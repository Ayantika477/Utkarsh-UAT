/**
 * @description   Sends the daily consolidated "Project Opportunity Created" emails
 *                to HODs and CRM Heads (one email per recipient, listing all
 *                their new Project Opportunities).
 *
 *                Recipients:
 *                 1) Users first, always INTERNAL (target = User):
 *                      HOD       => active users with profile "Utkarsh HOD" whose
 *                                   User.Department includes the Opportunity department
 *                      CRM Head  => active Standard users with role "<Department> CRM User"
 *                 2) FALLBACK when no such user exists: the formula email
 *                    (HOD_User_Email_Formula__c / CRM_User_Email_Formula__c).
 *                      - matches an active Standard User => INTERNAL
 *                      - matches no User                 => skipped (no external email)
 *                 3) Neither role user nor formula email => skipped, retried next run.
 *
 * REQUIRES two checkbox fields on Opportunity (default unchecked):
 *   Project_Created_HOD_Sent_c__c
 *   Project_Created_CRM_Sent_c__c
 */
public without sharing class ProjectOpportunityCreatedDigestBatch implements Database.Batchable<ProjectOpportunityCreatedDigestBatch.WorkItem> {

  private static final Integer LOOKBACK_DAYS = 2;

  public class WorkItem {
    public Id recipientUserId; // null => external fallback
    public String recipientEmail;
    public String templateName;
    public Boolean isHod;
    public List<Opportunity> opps;
  }

  // ===========================================================================
  // BATCH
  // ===========================================================================
  public Iterable<WorkItem> start(Database.BatchableContext context) {
    Datetime cutoff = System.now().addDays(-LOOKBACK_DAYS);
    String projectRecordType = OpportunityAssignmentEmailHandler.PROJECT_RECORD_TYPE_DEVELOPER_NAME;

    List<Opportunity> candidates = [
      SELECT
        Id,
        Name,
        OwnerId,
        Owner.Name,
        CreatedDate,
        Department_Name__c,
        CRM_User_Email_Formula__c,
        HOD_User_Email_Formula__c,
        Project_Created_HOD_Sent_c__c,
        Project_Created_CRM_Sent_c__c
      FROM Opportunity
      WHERE
        RecordType.DeveloperName = :projectRecordType
        AND CreatedDate >= :cutoff
        AND (
          Project_Created_HOD_Sent_c__c = FALSE
          OR Project_Created_CRM_Sent_c__c = FALSE
        )
      ORDER BY CreatedDate
    ];

    // Collect role names and fallback formula emails once => one User query in total.
    Set<String> roleNames = new Set<String>();
    Set<String> formulaEmails = new Set<String>();
    Set<String> departments = new Set<String>();
    for (Opportunity opp : candidates) {
      departments.add(opp.Department_Name__c);
      String crmRole = roleNameFor(opp.Department_Name__c, false);
      if (crmRole != null) {
        roleNames.add(crmRole);
      }
      if (String.isNotBlank(opp.HOD_User_Email_Formula__c)) {
        formulaEmails.add(opp.HOD_User_Email_Formula__c.trim().toLowerCase());
      }
      if (String.isNotBlank(opp.CRM_User_Email_Formula__c)) {
        formulaEmails.add(opp.CRM_User_Email_Formula__c.trim().toLowerCase());
      }
    }

    Map<String, List<User>> usersByRole = new Map<String, List<User>>();
    Map<String, User> userByEmail = new Map<String, User>();
    if (!roleNames.isEmpty() || !formulaEmails.isEmpty()) {
      for (User u : [
        SELECT Id, Email, UserRole.Name
        FROM User
        WHERE
          IsActive = TRUE
          AND UserType = 'Standard'
          AND (UserRole.Name IN :roleNames OR Email IN :formulaEmails)
        ORDER BY Email
      ]) {
        if (u.UserRole != null && roleNames.contains(u.UserRole.Name)) {
          if (!usersByRole.containsKey(u.UserRole.Name)) {
            usersByRole.put(u.UserRole.Name, new List<User>());
          }
          usersByRole.get(u.UserRole.Name).add(u);
        }
        if (u.Email != null) {
          String key = u.Email.trim().toLowerCase();
          if (formulaEmails.contains(key) && !userByEmail.containsKey(key)) {
            userByEmail.put(key, u);
          }
        }
      }
    }

    // HOD = profile "Utkarsh HOD" + User.Department (not role).
    Map<String, List<User>> hodUsersByDepartment = TenderEmailRecipientService.resolveUsersByProfileDepartment(
      TenderEmailRecipientService.PROFILE_HOD,
      departments
    );

    // One work item per (template, recipient).
    List<WorkItem> items = new List<WorkItem>();
    Map<String, WorkItem> itemByKey = new Map<String, WorkItem>();
    for (Opportunity opp : candidates) {
      if (!opp.Project_Created_HOD_Sent_c__c) {
        addRecipients(
          items,
          itemByKey,
          opp,
          true,
          OpportunityAssignmentEmailHandler.TEMPLATE_HOD_PROJECT_CREATED,
          usersByRole,
          userByEmail,
          hodUsersByDepartment
        );
      }
      if (!opp.Project_Created_CRM_Sent_c__c) {
        addRecipients(
          items,
          itemByKey,
          opp,
          false,
          OpportunityAssignmentEmailHandler.TEMPLATE_CRM_HEAD_OPPORTUNITY_CREATED,
          usersByRole,
          userByEmail,
          hodUsersByDepartment
        );
      }
    }

    return items;
  }

  public void execute(Database.BatchableContext context, List<WorkItem> scope) {
    Id oweaId = getOrgWideEmailAddressId();
    Map<String, Id> templateIdByName = new Map<String, Id>();
    Map<Id, Opportunity> updatesById = new Map<Id, Opportunity>();

    for (WorkItem item : scope) {
      if (!templateIdByName.containsKey(item.templateName)) {
        templateIdByName.put(item.templateName, getTemplateId(item.templateName));
      }

      Boolean sent = false;
      try {
        sent = sendDigest(item, templateIdByName.get(item.templateName), oweaId);
      } catch (Exception ex) {
        System.debug(
          LoggingLevel.ERROR,
          'Created digest failed for ' + item.recipientEmail + ': ' + ex.getMessage()
        );
      }

      if (!sent) {
        continue; // flag stays false => retried on the next run
      }

      // Flag is set when at least one recipient received the digest.
      for (Opportunity opp : item.opps) {
        Opportunity updateRecord = updatesById.containsKey(opp.Id)
          ? updatesById.get(opp.Id)
          : new Opportunity(Id = opp.Id);

        if (item.isHod) {
          updateRecord.Project_Created_HOD_Sent_c__c = true;
        } else {
          updateRecord.Project_Created_CRM_Sent_c__c = true;
        }
        updatesById.put(opp.Id, updateRecord);
      }
    }

    if (!updatesById.isEmpty()) {
      List<Opportunity> toUpdate = updatesById.values();
      List<Database.SaveResult> results = Database.update(toUpdate, false);
      for (Integer i = 0; i < results.size(); i++) {
        if (!results[i].isSuccess()) {
          System.debug(
            LoggingLevel.ERROR,
            'FLAG UPDATE FAILED opp=' + toUpdate[i].Id + ' errors=' + results[i].getErrors()
          );
        }
      }
    }
  }

  public void finish(Database.BatchableContext context) {
  }

  // ===========================================================================
  // RECIPIENTS (roles first, formula email as fallback)
  // ===========================================================================

  // Role name used in this org: "<Department> HOD" / "<Department> CRM User".
  private static String roleNameFor(String department, Boolean forHod) {
    if (String.isBlank(department)) {
      return null;
    }
    String dept = department.trim();
    if (dept == 'Transmission & Telecom Tower') {
      dept = 'Transmission Tower';
    }
    return dept + (forHod ? ' HOD' : ' CRM User');
  }

  private static void addRecipients(
    List<WorkItem> items,
    Map<String, WorkItem> itemByKey,
    Opportunity opp,
    Boolean forHod,
    String templateName,
    Map<String, List<User>> usersByRole,
    Map<String, User> userByEmail,
    Map<String, List<User>> hodUsersByDepartment
  ) {
    String roleName;
    List<User> roleUsers;
    if (forHod) {
      roleName = 'profile ' + TenderEmailRecipientService.PROFILE_HOD;
      roleUsers = TenderEmailRecipientService.findUsersForDepartment(
        hodUsersByDepartment,
        opp.Department_Name__c
      );
    } else {
      roleName = roleNameFor(opp.Department_Name__c, forHod);
      roleUsers = roleName == null ? null : usersByRole.get(roleName);
    }

    // 1) HOD by profile + department / CRM by role: every matching active user (INTERNAL).
    if (roleUsers != null && !roleUsers.isEmpty()) {
      for (User u : roleUsers) {
        addToItem(items, itemByKey, opp, forHod, templateName, u.Id, u.Email);
      }
      return;
    }

    // 2) Fallback: formula email (no active role user).
    String formulaEmail = forHod ? opp.HOD_User_Email_Formula__c : opp.CRM_User_Email_Formula__c;
    if (String.isBlank(formulaEmail)) {
      System.debug(
        'SKIPPED (no active user in role "' + roleName + '" and no formula email) opp=' + opp.Id
      );
      return; // flag stays false => retried on the next run
    }
    String email = formulaEmail.trim().toLowerCase();
    User matched = userByEmail.get(email);
    // Department setting (custom metadata) emails go only to active Users, by User Id.
    if (matched == null) {
      System.debug(
        'SKIPPED (formula email is not an active User) opp=' + opp.Id + ' role="' + roleName +
        '" email=' + email
      );
      return; // flag stays false => retried on the next run
    }
    System.debug(
      'FALLBACK used for opp=' + opp.Id + ' role="' + roleName + '" email=' + email + ' (internal user)'
    );
    addToItem(
      items,
      itemByKey,
      opp,
      forHod,
      templateName,
      matched.Id,
      email
    );
  }

  private static void addToItem(
    List<WorkItem> items,
    Map<String, WorkItem> itemByKey,
    Opportunity opp,
    Boolean forHod,
    String templateName,
    Id userId,
    String email
  ) {
    String key = templateName + '|' + (userId != null ? String.valueOf(userId) : email);
    WorkItem item = itemByKey.get(key);
    if (item == null) {
      item = new WorkItem();
      item.recipientUserId = userId;
      item.recipientEmail = email;
      item.templateName = templateName;
      item.isHod = forHod;
      item.opps = new List<Opportunity>();
      itemByKey.put(key, item);
      items.add(item);
    }
    item.opps.add(opp);
  }

  // ===========================================================================
  // SENDING
  // ===========================================================================
  private static Id getTemplateId(String developerName) {
    List<EmailTemplate> templates = [
      SELECT Id
      FROM EmailTemplate
      WHERE DeveloperName = :developerName
      LIMIT 1
    ];
    return templates.isEmpty() ? null : templates[0].Id;
  }

  private static Id getOrgWideEmailAddressId() {
    List<OrgWideEmailAddress> owea = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE Address = :OpportunityAssignmentEmailHandler.ORG_WIDE_SENDER_EMAIL
      LIMIT 1
    ];
    return owea.isEmpty() ? null : owea[0].Id;
  }

  private static Boolean sendDigest(WorkItem item, Id templateId, Id oweaId) {
    if (
      item == null ||
      item.opps == null ||
      item.opps.isEmpty() ||
      (item.recipientUserId == null && String.isBlank(item.recipientEmail)) ||
      templateId == null
    ) {
      System.debug('Digest skipped (missing data or template) for ' + (item == null ? null : item.recipientEmail));
      return false;
    }

    Messaging.SingleEmailMessage mail;
    try {
      // Always render against the Opportunity so its merge fields resolve.
      mail = Messaging.renderStoredEmailTemplate(templateId, null, item.opps[0].Id);

      if (item.recipientUserId != null) {
        // INTERNAL: target is the User and is the recipient.
        mail.setTargetObjectId(item.recipientUserId);
        mail.setWhatId(null); // WhatId is not allowed when the target is a User
        mail.setTreatTargetObjectAsRecipient(true);
      } else {
        // FALLBACK: formula email that is not an active User.
        mail.setTargetObjectId(null);
        mail.setToAddresses(new List<String>{ item.recipientEmail.trim() });
        mail.setTreatTargetObjectAsRecipient(false);
      }
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Digest template render failed: ' + e.getMessage());
      return false;
    }

    mail.setSaveAsActivity(false);
    if (oweaId != null) {
      mail.setOrgWideEmailAddressId(oweaId);
    }

    Integer total = item.opps.size();
    String baseSubject = String.isBlank(mail.getSubject())
      ? 'Project Opportunity Created'
      : mail.getSubject();
    mail.setSubject(baseSubject + ' (' + total + ' Opportunities)');

    String rawHtml = String.isNotBlank(mail.getHtmlBody())
      ? mail.getHtmlBody()
      : (String.isNotBlank(mail.getPlainTextBody())
          ? mail.getPlainTextBody().replace('\n', '<br/>')
          : '');

    List<String> htmlParts = splitClosingHtml(rawHtml);
    mail.setHtmlBody(
      htmlParts[0] +
      '<br/><p><b>New Project Opportunities (' + total + '):</b></p>' +
      buildHtmlTable(item.opps) +
      '<br/>' + htmlParts[1]
    );

    List<String> textParts = splitClosingText(mail.getPlainTextBody());
    mail.setPlainTextBody(
      textParts[0] +
      '\n\nNew Project Opportunities (' + total + '):\n' +
      buildText(item.opps) +
      '\n\n' + textParts[1]
    );

    try {
      List<Messaging.SendEmailResult> results = Messaging.sendEmail(
        new List<Messaging.SingleEmailMessage>{ mail },
        false
      );
      if (!results[0].isSuccess()) {
        System.debug(LoggingLevel.ERROR, 'Digest send failed: ' + results[0].getErrors());
      }
      return results[0].isSuccess();
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Digest send error: ' + e.getMessage());
      return false;
    }
  }

  // Splits a rendered HTML body into [intro, closing] at the last "Regards".
  private static List<String> splitClosingHtml(String html) {
    if (String.isBlank(html)) {
      return new List<String>{ '', '' };
    }
    String lower = html.toLowerCase();
    Integer idx = lower.lastIndexOf('regards');
    if (idx < 0) {
      return new List<String>{ html, '' };
    }
    Integer blockStart = Math.max(lower.lastIndexOf('<p', idx), lower.lastIndexOf('<div', idx));
    Integer lastClose = Math.max(lower.lastIndexOf('</p>', idx), lower.lastIndexOf('</div>', idx));
    Integer cut = (blockStart >= 0 && blockStart > lastClose) ? blockStart : idx;
    return new List<String>{ html.substring(0, cut), html.substring(cut) };
  }

  private static List<String> splitClosingText(String text) {
    if (String.isBlank(text)) {
      return new List<String>{ '', '' };
    }
    Integer idx = text.toLowerCase().lastIndexOf('regards');
    if (idx < 0) {
      return new List<String>{ text, '' };
    }
    return new List<String>{ text.substring(0, idx), text.substring(idx) };
  }

  private static String buildHtmlTable(List<Opportunity> opps) {
    String baseUrl = URL.getOrgDomainUrl().toExternalForm();
    String html =
      '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;font-size:13px;">' +
      '<tr style="background:#f3f3f3;">' +
      '<th>#</th><th>Opportunity</th><th>Department</th><th>Assigned To</th><th>Created</th>' +
      '</tr>';
    Integer rowNumber = 1;
    for (Opportunity opp : opps) {
      String oppName = String.isBlank(opp.Name) ? String.valueOf(opp.Id) : opp.Name;
      String department = opp.Department_Name__c != null ? opp.Department_Name__c : '';
      String ownerName = opp.Owner != null && opp.Owner.Name != null ? opp.Owner.Name : '';
      String createdOn = opp.CreatedDate != null
        ? opp.CreatedDate.format('dd MMM yyyy HH:mm')
        : '';
      html +=
        '<tr>' +
        '<td>' + rowNumber + '</td>' +
        '<td><a href="' + baseUrl + '/' + opp.Id + '">' + oppName.escapeHtml4() + '</a></td>' +
        '<td>' + department.escapeHtml4() + '</td>' +
        '<td>' + ownerName.escapeHtml4() + '</td>' +
        '<td>' + createdOn + '</td>' +
        '</tr>';
      rowNumber++;
    }
    return html + '</table>';
  }

  private static String buildText(List<Opportunity> opps) {
    String baseUrl = URL.getOrgDomainUrl().toExternalForm();
    List<String> lines = new List<String>();
    Integer rowNumber = 1;
    for (Opportunity opp : opps) {
      lines.add(
        rowNumber + '. ' + opp.Name + ' | ' +
        (opp.Department_Name__c != null ? opp.Department_Name__c : '') + ' | assigned to ' +
        (opp.Owner != null ? opp.Owner.Name : '') + ' | ' +
        (opp.CreatedDate != null ? opp.CreatedDate.format('dd MMM yyyy HH:mm') : '') + ' | ' +
        baseUrl + '/' + opp.Id
      );
      rowNumber++;
    }
    return String.join(lines, '\n');
  }
}