/**
 * @description Sends Case 1st-response SLA escalation emails to Owner, HOD, and CRM Head / ED Sir.
 * @author Anshita Chanda
 * @date 2026-08-16
 */
public without sharing class CaseSLAEscalationEmailService {
  public static final String ROLE_UTKARSH_ED = 'Utkarsh ED';
  public static final String ROLE_UTKARSH_CRM_HEAD = 'Utkarsh CRM Head';
  public static final String ORG_WIDE_SENDER_EMAIL = 'noreply@utkarshindialimited.in';

  public enum EscalationTier {
    OWNER,
    HOD,
    SIR
  }

  @TestVisible
  private static Id testTemplateIdOverride;

  @TestVisible
  private static Set<String> testRecipientOverrides;

  @TestVisible
  private static Datetime testNowOverride;

  @TestVisible
  private static Datetime testAnchorOverride;

  // Lets tests exercise the real Messaging.sendEmail path (test emails are never delivered).
  @TestVisible
  private static Boolean testSendForReal = false;

  private static Map<String, EmailTemplate> templateByDeveloperName = new Map<String, EmailTemplate>();
  private static Map<Id, String> ownerEmailById = new Map<Id, String>();
  private static Map<String, List<String>> roleEmailsByRoleName = new Map<String, List<String>>();
  private static Map<String, Id> hodUserIdByRoleName = new Map<String, Id>();
  private static Id cachedOrgWideEmailAddressId;
  private static Boolean orgWideEmailResolved = false;

  // Messages per Messaging.sendEmail call. A transaction allows only 10 calls, so a
  // whole batch chunk is sent together instead of one call per Case and tier.
  @TestVisible
  private static final Integer SEND_CHUNK_SIZE = 100;

  public class PreparedEscalation {
    public Id caseId;
    public EscalationTier tier;
    public List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();

    public PreparedEscalation(Id caseId, EscalationTier tier) {
      this.caseId = caseId;
      this.tier = tier;
    }
  }

  public static Boolean sendEscalationEmail(Case caseRecord, EscalationTier tier) {
    if (caseRecord == null || tier == null) {
      return false;
    }
    PreparedEscalation prepared = new PreparedEscalation(caseRecord.Id, tier);
    prepared.messages = prepareEscalationEmail(caseRecord, tier);
    return sendPreparedEscalations(new List<PreparedEscalation>{ prepared })
      .contains(buildEscalationKey(caseRecord.Id, tier));
  }

  /**
   * @description Builds the escalation emails for one Case and tier without sending them.
   * @return One internal (User Id) message per active internal User recipient; empty when
   *         nothing can be sent.
   */
  public static List<Messaging.SingleEmailMessage> prepareEscalationEmail(
    Case caseRecord,
    EscalationTier tier
  ) {
    List<Messaging.SingleEmailMessage> noMessages = new List<Messaging.SingleEmailMessage>();
    if (caseRecord == null || tier == null) {
      return noMessages;
    }

    String templateDeveloperName = resolveTemplateDeveloperName(
      caseRecord.Priority,
      tier
    );
    if (String.isBlank(templateDeveloperName)) {
      return noMessages;
    }

    EmailTemplate templateRecord = resolveTemplate(templateDeveloperName);
    if (templateRecord == null) {
      return noMessages;
    }

    Id renderWhoId = resolveRenderWhoId(caseRecord, tier);
    if (renderWhoId == null) {
      return noMessages;
    }

    RenderedCaseEmail rendered = renderTemplate(
      templateRecord,
      caseRecord.Id,
      renderWhoId
    );
    if (rendered == null) {
      return noMessages;
    }

    Set<String> recipients = resolveRecipients(caseRecord, tier);
    if (recipients.isEmpty()) {
      return noMessages;
    }

    return buildRecipientMessages(rendered, recipients);
  }

  /**
   * @description Sends all prepared escalations with as few Messaging.sendEmail calls as
   *              possible (up to SEND_CHUNK_SIZE messages per call, never more calls than
   *              the transaction has left).
   * @return Keys (see buildEscalationKey) of the Case/tier escalations where at least one
   *         message was sent. Escalations not sent stay unmarked and are retried next run.
   */
  public static Set<String> sendPreparedEscalations(List<PreparedEscalation> escalations) {
    Set<String> sentKeys = new Set<String>();
    if (escalations == null || escalations.isEmpty()) {
      return sentKeys;
    }

    List<Messaging.SingleEmailMessage> allMessages = new List<Messaging.SingleEmailMessage>();
    List<String> keyByMessageIndex = new List<String>();
    for (PreparedEscalation escalation : escalations) {
      if (escalation == null || escalation.messages == null) {
        continue;
      }
      String key = buildEscalationKey(escalation.caseId, escalation.tier);
      for (Messaging.SingleEmailMessage message : escalation.messages) {
        allMessages.add(message);
        keyByMessageIndex.add(key);
      }
    }
    if (allMessages.isEmpty()) {
      return sentKeys;
    }

    if (Test.isRunningTest() && !testSendForReal) {
      sentKeys.addAll(keyByMessageIndex);
      return sentKeys;
    }

    Integer index = 0;
    while (index < allMessages.size()) {
      if (Limits.getEmailInvocations() >= Limits.getLimitEmailInvocations()) {
        System.debug(
          LoggingLevel.WARN,
          'CaseSLAEscalationEmailService: no sendEmail calls left; ' +
            (allMessages.size() - index) + ' message(s) will be retried next run.'
        );
        break;
      }

      List<Messaging.SingleEmailMessage> chunk = new List<Messaging.SingleEmailMessage>();
      Integer chunkStart = index;
      while (index < allMessages.size() && chunk.size() < SEND_CHUNK_SIZE) {
        chunk.add(allMessages[index]);
        index++;
      }

      try {
        Messaging.SendEmailResult[] results = Messaging.sendEmail(chunk, false);
        for (Integer i = 0; i < results.size(); i++) {
          if (results[i].isSuccess()) {
            sentKeys.add(keyByMessageIndex[chunkStart + i]);
          }
        }
      } catch (Exception ex) {
        // Org daily Single Email quota exhausted — stop without failing the batch chunk.
        if (isEmailLimitExceeded(ex)) {
          break;
        }
        throw ex;
      }
    }
    return sentKeys;
  }

  public static String buildEscalationKey(Id caseId, EscalationTier tier) {
    return String.valueOf(caseId) + ':' + String.valueOf(tier);
  }

  // One email per active User, sent by User Id so it counts as internal (not
  // against the daily external email limit) - a SingleEmailMessage can only
  // target one User. Addresses with no active User (e.g. a formula email that
  // matches nobody) still go together in one address-based email.
  @TestVisible
  private static List<Messaging.SingleEmailMessage> buildRecipientMessages(
    RenderedCaseEmail rendered,
    Set<String> recipients
  ) {
    List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
    Map<String, Id> userIdByEmail = resolveActiveUserIdsByEmail(recipients);
    Set<Id> targetedUserIds = new Set<Id>();
    List<String> addressOnlyRecipients = new List<String>();

    for (String email : recipients) {
      Id userId = userIdByEmail.get(email.trim().toLowerCase());
      if (userId == null) {
        addressOnlyRecipients.add(email);
        continue;
      }
      if (targetedUserIds.add(userId)) {
        Messaging.SingleEmailMessage message = buildMessage(rendered);
        message.setTargetObjectId(userId);
        messages.add(message);
      }
    }

    if (!addressOnlyRecipients.isEmpty()) {
      // Address-based fallback disabled for now - it counts as an external email.
      // Messaging.SingleEmailMessage message = buildMessage(rendered);
      // message.setToAddresses(addressOnlyRecipients);
      // message.setTreatTargetObjectAsRecipient(false);
      // messages.add(message);
      System.debug(
        'CaseSLAEscalationEmailService: no active User Id for recipients ' + addressOnlyRecipients +
        ' - email address fallback is disabled, email not sent.'
      );
    }
    return messages;
  }

  private static Messaging.SingleEmailMessage buildMessage(RenderedCaseEmail rendered) {
    Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
    message.setSubject(rendered.subject);
    message.setSaveAsActivity(false);
    if (String.isNotBlank(rendered.htmlBody)) {
      message.setHtmlBody(rendered.htmlBody);
    }
    if (String.isNotBlank(rendered.plainTextBody)) {
      message.setPlainTextBody(rendered.plainTextBody);
    }
    applyOrgWideSender(message);
    return message;
  }

  @TestVisible
  private static Map<String, Id> resolveActiveUserIdsByEmail(Set<String> emails) {
    Map<String, Id> userIdByEmail = new Map<String, Id>();
    if (emails == null || emails.isEmpty()) {
      return userIdByEmail;
    }
    Set<String> normalizedEmails = new Set<String>();
    for (String email : emails) {
      if (String.isNotBlank(email)) {
        normalizedEmails.add(email.trim().toLowerCase());
      }
    }
    for (User u : [
      SELECT Id, Email
      FROM User
      WHERE IsActive = TRUE AND UserType = 'Standard' AND Email IN :normalizedEmails
      ORDER BY CreatedDate
    ]) {
      String key = u.Email.trim().toLowerCase();
      if (!userIdByEmail.containsKey(key)) {
        userIdByEmail.put(key, u.Id);
      }
    }
    return userIdByEmail;
  }

  private static Boolean isEmailLimitExceeded(Exception ex) {
    if (ex == null || String.isBlank(ex.getMessage())) {
      return false;
    }
    String message = ex.getMessage().toUpperCase();
    return message.contains('SINGLE_EMAIL_LIMIT_EXCEEDED') ||
      message.contains('EMAIL LIMIT EXCEEDED');
  }

  @TestVisible
  public static String resolveTemplateDeveloperName(
    String priority,
    EscalationTier tier
  ) {
    if (String.isBlank(priority) || tier == null) {
      return null;
    }

    Map<String, Map<EscalationTier, String>> templatesByPriority = new Map<String, Map<EscalationTier, String>>{
      'Critical' => new Map<EscalationTier, String>{
        EscalationTier.OWNER => 'Case_Critical_Response_24h_Owner',
        EscalationTier.HOD => 'Case_Critical_Response_48h_HOD',
        EscalationTier.SIR => 'Case_Critical_Response_72h_Sir'
      },
      'High' => new Map<EscalationTier, String>{
        EscalationTier.OWNER => 'Case_High_Response_24h_Owner',
        EscalationTier.HOD => 'Case_High_Response_48h_HOD',
        EscalationTier.SIR => 'Case_High_Response_72h_Sir'
      },
      'Medium' => new Map<EscalationTier, String>{
        EscalationTier.OWNER => 'Case_Medium_Response_48h_Owner',
        EscalationTier.HOD => 'Case_Medium_Response_72h_HOD',
        EscalationTier.SIR => 'Case_Medium_Response_144h_Sir'
      },
      'Low' => new Map<EscalationTier, String>{
        EscalationTier.OWNER => 'Case_Low_Response_72h_Owner',
        EscalationTier.HOD => 'Case_Low_Response_120h_HOD',
        EscalationTier.SIR => 'Case_Low_Response_144h_Sir'
      }
    };

    Map<EscalationTier, String> tierTemplates = templatesByPriority.get(priority);
    return tierTemplates == null ? null : tierTemplates.get(tier);
  }

  @TestVisible
  public static Boolean isTierDue(Case caseRecord, EscalationTier tier) {
    Datetime anchorDate = resolveAnchorDate(caseRecord);
    if (caseRecord == null || tier == null || anchorDate == null) {
      return false;
    }

    Datetime ownerDue = caseRecord.SLA_Due_Date_Time_RO__c;
    Datetime hodDue = caseRecord.Escalation_Date_1__c;
    Datetime sirDue = caseRecord.Escalation_Date_2__c;

    if (tier == EscalationTier.OWNER) {
      return ownerDue != null
        ? getNow() >= ownerDue
        : hoursSince(anchorDate) >= getOwnerThresholdHours(caseRecord.Priority);
    }
    if (tier == EscalationTier.HOD) {
      return hodDue != null
        ? getNow() >= hodDue
        : hoursSince(anchorDate) >= getHodThresholdHours(caseRecord.Priority);
    }
    return sirDue != null
      ? getNow() >= sirDue
      : hoursSince(anchorDate) >= getSirThresholdHours(caseRecord.Priority);
  }

  @TestVisible
  private static Datetime resolveAnchorDate(Case caseRecord) {
    if (Test.isRunningTest() && testAnchorOverride != null) {
      return testAnchorOverride;
    }
    return caseRecord == null ? null : caseRecord.CreatedDate;
  }

  @TestVisible
  private static Datetime getNow() {
    if (Test.isRunningTest() && testNowOverride != null) {
      return testNowOverride;
    }
    return System.now();
  }

  @TestVisible
  public static Integer getOwnerThresholdHours(String priority) {
    if (priority == 'Medium') {
      return 48;
    }
    if (priority == 'Low') {
      return 72;
    }
    return 24;
  }

  @TestVisible
  public static Integer getHodThresholdHours(String priority) {
    if (priority == 'Medium') {
      return 72;
    }
    if (priority == 'Low') {
      return 120;
    }
    return 48;
  }

  @TestVisible
  public static Integer getSirThresholdHours(String priority) {
    if (priority == 'Medium') {
      return 120;
    }
    if (priority == 'Low') {
      return 144;
    }
    return 72;
  }

  private static Long hoursSince(Datetime anchorDate) {
    return (getNow().getTime() - anchorDate.getTime()) / (1000 * 60 * 60);
  }

  private static Id resolveRenderWhoId(Case caseRecord, EscalationTier tier) {
    if (tier == EscalationTier.OWNER) {
      return caseRecord.OwnerId;
    }
    if (tier == EscalationTier.HOD) {
      Id hodUserId = resolveDepartmentHodUserId(caseRecord);
      return hodUserId != null ? hodUserId : caseRecord.OwnerId;
    }
    return caseRecord.OwnerId;
  }

  private static Set<String> resolveRecipients(Case caseRecord, EscalationTier tier) {
    if (
      Test.isRunningTest() &&
      testRecipientOverrides != null &&
      !testRecipientOverrides.isEmpty()
    ) {
      return new Set<String>(testRecipientOverrides);
    }

    Set<String> recipients = new Set<String>();

    if (tier == EscalationTier.OWNER) {
      addOwnerEmail(caseRecord.OwnerId, recipients);
      return recipients;
    }

    if (tier == EscalationTier.HOD) {
      addDepartmentHodEmails(caseRecord, recipients);
      return recipients;
    }

    // CRM Head = profile "CRM Head" + User.Department (not role); ED Sir stays role-based.
    recipients.addAll(
      EscalationMatrixEmailService.resolveProfileDepartmentEmails(
        EscalationMatrixEmailService.PROFILE_CRM_HEAD,
        resolveRawDepartmentName(caseRecord)
      )
    );
    addRoleEmails(ROLE_UTKARSH_ED, recipients);
    return recipients;
  }

  private static void addOwnerEmail(Id ownerId, Set<String> recipients) {
    if (ownerId == null) {
      return;
    }

    if (!ownerEmailById.containsKey(ownerId)) {
      String ownerEmail = null;
      for (User ownerRecord : [
        SELECT Email
        FROM User
        WHERE Id = :ownerId AND Email != NULL
        LIMIT 1
      ]) {
        ownerEmail = ownerRecord.Email.trim().toLowerCase();
      }
      ownerEmailById.put(ownerId, ownerEmail);
    }

    if (String.isNotBlank(ownerEmailById.get(ownerId))) {
      recipients.add(ownerEmailById.get(ownerId));
    }
  }

  private static void addDepartmentHodEmails(Case caseRecord, Set<String> recipients) {
    if (String.isNotBlank(caseRecord.HOD_User_Email_Formula__c)) {
      recipients.add(caseRecord.HOD_User_Email_Formula__c.trim().toLowerCase());
    }

    // HOD = profile "Utkarsh HOD" + User.Department (not role).
    recipients.addAll(
      EscalationMatrixEmailService.resolveProfileDepartmentEmails(
        EscalationMatrixEmailService.PROFILE_HOD,
        resolveRawDepartmentName(caseRecord)
      )
    );
  }

  private static Id resolveDepartmentHodUserId(Case caseRecord) {
    String department = resolveRawDepartmentName(caseRecord);
    if (String.isBlank(department)) {
      return null;
    }

    String cacheKey = department.trim().toLowerCase();
    if (!hodUserIdByRoleName.containsKey(cacheKey)) {
      List<User> hodUsers = TenderEmailRecipientService.findUsersForDepartment(
        TenderEmailRecipientService.resolveUsersByProfileDepartment(
          EscalationMatrixEmailService.PROFILE_HOD,
          new Set<String>{ department }
        ),
        department
      );
      hodUserIdByRoleName.put(cacheKey, hodUsers.isEmpty() ? null : hodUsers[0].Id);
    }
    return hodUserIdByRoleName.get(cacheKey);
  }

  // Raw Case department (User.Department holds the full name, e.g. "Transmission & Telecom Tower").
  private static String resolveRawDepartmentName(Case caseRecord) {
    if (caseRecord == null) {
      return null;
    }
    return String.isNotBlank(caseRecord.Department_formula__c)
      ? caseRecord.Department_formula__c
      : caseRecord.Department__c;
  }

  private static String resolveDepartmentName(Case caseRecord) {
    if (String.isNotBlank(caseRecord.Department_formula__c)) {
      return EscalationMatrixEmailService.getRoleDepartmentName(
        caseRecord.Department_formula__c
      );
    }
    if (String.isNotBlank(caseRecord.Department__c)) {
      return EscalationMatrixEmailService.getRoleDepartmentName(
        caseRecord.Department__c
      );
    }
    return null;
  }

  private static void addRoleEmails(String roleName, Set<String> recipients) {
    if (String.isBlank(roleName)) {
      return;
    }

    if (!roleEmailsByRoleName.containsKey(roleName)) {
      List<String> emails = new List<String>();
      for (User userRecord : [
        SELECT Email
        FROM User
        WHERE IsActive = TRUE AND UserRole.Name = :roleName AND Email != NULL
      ]) {
        emails.add(userRecord.Email.trim().toLowerCase());
      }
      roleEmailsByRoleName.put(roleName, emails);
    }

    recipients.addAll(roleEmailsByRoleName.get(roleName));
  }

  private static RenderedCaseEmail renderTemplate(
    EmailTemplate templateRecord,
    Id caseId,
    Id whoId
  ) {
    if (templateRecord == null || caseId == null || whoId == null) {
      return null;
    }

    if (isLightningTemplate(templateRecord)) {
      return renderLightningTemplate(templateRecord, caseId, whoId);
    }

    try {
      Messaging.SingleEmailMessage renderedMessage = Messaging.renderStoredEmailTemplate(
        templateRecord.Id,
        whoId,
        caseId
      );
      RenderedCaseEmail rendered = new RenderedCaseEmail();
      rendered.subject = renderedMessage.getSubject();
      rendered.plainTextBody = renderedMessage.getPlainTextBody();
      rendered.htmlBody = renderedMessage.getHtmlBody();
      return hasContent(rendered) ? rendered : null;
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.ERROR,
        'CaseSLAEscalationEmailService classic render failed: ' + ex.getMessage()
      );
      return null;
    }
  }

  private static RenderedCaseEmail renderLightningTemplate(
    EmailTemplate templateRecord,
    Id caseId,
    Id whoId
  ) {
    String subject = convertLightningMergeSyntax(templateRecord.Subject);
    String html = convertLightningMergeSyntax(templateRecord.HtmlValue);
    List<String> bodies = new List<String>();
    Boolean hasSubject = String.isNotBlank(subject);
    Boolean hasHtml = String.isNotBlank(html);

    if (hasSubject) {
      bodies.add(subject);
    }
    if (hasHtml) {
      bodies.add(html);
    }
    if (bodies.isEmpty()) {
      return null;
    }

    List<Messaging.RenderEmailTemplateBodyResult> results = Messaging.renderEmailTemplate(
      String.valueOf(whoId),
      String.valueOf(caseId),
      bodies
    );

    RenderedCaseEmail rendered = new RenderedCaseEmail();
    Integer resultIndex = 0;
    if (hasSubject) {
      if (results[resultIndex].getSuccess()) {
        rendered.subject = results[resultIndex].getMergedBody();
      } else {
        return null;
      }
      resultIndex++;
    }
    if (hasHtml && results.size() > resultIndex) {
      if (results[resultIndex].getSuccess()) {
        rendered.htmlBody = results[resultIndex].getMergedBody();
      } else {
        return null;
      }
    }

    return hasContent(rendered) ? rendered : null;
  }

  private static Boolean isLightningTemplate(EmailTemplate templateRecord) {
    return templateRecord.UiType == 'SFX' ||
      (String.isNotBlank(templateRecord.HtmlValue) &&
      templateRecord.HtmlValue.contains('{{{'));
  }

  private static String convertLightningMergeSyntax(String value) {
    if (String.isBlank(value)) {
      return value;
    }
    return value.replaceAll('\\{\\{\\{', '{!').replaceAll('\\}\\}\\}', '}');
  }

  private static Boolean hasContent(RenderedCaseEmail rendered) {
    return rendered != null &&
      (String.isNotBlank(rendered.subject) ||
      String.isNotBlank(rendered.htmlBody) ||
      String.isNotBlank(rendered.plainTextBody));
  }

  private static EmailTemplate resolveTemplate(String developerName) {
    if (Test.isRunningTest() && testTemplateIdOverride != null) {
      List<EmailTemplate> testTemplates = [
        SELECT Id, Subject, HtmlValue, Body, UiType
        FROM EmailTemplate
        WHERE Id = :testTemplateIdOverride
        LIMIT 1
      ];
      return testTemplates.isEmpty() ? null : testTemplates[0];
    }

    if (templateByDeveloperName.containsKey(developerName)) {
      return templateByDeveloperName.get(developerName);
    }

    List<EmailTemplate> templates = [
      SELECT Id, DeveloperName, Subject, HtmlValue, Body, UiType
      FROM EmailTemplate
      WHERE DeveloperName = :developerName
      LIMIT 1
    ];
    EmailTemplate templateRecord = templates.isEmpty() ? null : templates[0];
    templateByDeveloperName.put(developerName, templateRecord);
    return templateRecord;
  }

  private static void applyOrgWideSender(Messaging.SingleEmailMessage message) {
    if (!orgWideEmailResolved) {
      List<OrgWideEmailAddress> orgWideAddresses = [
        SELECT Id
        FROM OrgWideEmailAddress
        WHERE Address = :ORG_WIDE_SENDER_EMAIL
        LIMIT 1
      ];
      cachedOrgWideEmailAddressId = orgWideAddresses.isEmpty()
        ? null
        : orgWideAddresses[0].Id;
      orgWideEmailResolved = true;
    }

    if (cachedOrgWideEmailAddressId != null) {
      message.setOrgWideEmailAddressId(cachedOrgWideEmailAddressId);
    }
  }

  @TestVisible
  private class RenderedCaseEmail {
    public String subject;
    public String plainTextBody;
    public String htmlBody;
  }
}