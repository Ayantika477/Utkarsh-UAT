/**
 * @description   Shared Lightning email template render/send helpers for the
 *                Utkarsh Escalation Matrix automations.
 * @author        Anshita Chanda
 * @date          2026-08-10
 */
public without sharing class EscalationMatrixEmailService {
  public enum RecipientGroup {
    OWNER,
    OWNER_AND_CRM,
    HOD_ONLY,
    CRM_HEAD_ONLY,
    HOD_AND_CRM_HEAD,
    ED_SIR
  }

  private static Map<String, Id> templateIdByName;

  @TestVisible
  private static Map<String, Id> testTemplateIdOverrides;

  @TestVisible
  private static Set<String> testRecipientOverrides;

  @TestVisible
  private static LeadManagementEmailService.RenderedEmail testLeadRenderedOverride;

  @TestVisible
  private static DealerOpportunityEmailService.RenderedEmail testOppRenderedOverride;

  @TestVisible
  private static Boolean testSimulateSuccessfulSend = false;

  /**
   * @description Sends a rendered Lead escalation email to the requested recipient group.
   */
  public static Boolean sendLeadEmail(
    Lead leadRecord,
    String templateName,
    RecipientGroup recipientType
  ) {
    if (leadRecord == null || String.isBlank(templateName)) {
      return false;
    }

    LeadManagementEmailService.RenderedEmail rendered = renderLeadTemplate(
      leadRecord,
      templateName
    );
    if (rendered == null) {
      return false;
    }

    Set<String> recipients = resolveLeadRecipients(leadRecord, recipientType);
    return sendRenderedEmail(leadRecord.Id, rendered, recipients);
  }

  /**
   * @description Sends a rendered Opportunity escalation email to the requested recipient group.
   */
  public static Boolean sendOpportunityEmail(
    Opportunity opportunityRecord,
    String templateName,
    RecipientGroup recipientType
  ) {
    if (opportunityRecord == null || String.isBlank(templateName)) {
      return false;
    }

    DealerOpportunityEmailService.RenderedEmail rendered = renderOpportunityTemplate(
      opportunityRecord,
      templateName
    );
    if (rendered == null) {
      return false;
    }

    Set<String> recipients = resolveOpportunityRecipients(
      opportunityRecord,
      recipientType
    );
    return sendRenderedEmail(
      resolveOpportunityTargetObjectId(opportunityRecord),
      rendered,
      recipients
    );
  }

  /**
   * @description Sends a task overdue email to the Lead or Opportunity owner.
   */
  public static Boolean sendTaskOverdueOwnerEmail(
    Task taskRecord,
    String templateName,
    Id targetObjectId,
    String ownerEmail
  ) {
    if (taskRecord == null || String.isBlank(templateName) || String.isBlank(ownerEmail)) {
      return false;
    }

    Id templateId = resolveTemplateId(templateName);
    if (templateId == null || targetObjectId == null) {
      return false;
    }

    SObject targetRecord = targetObjectId.getSobjectType() == Lead.SObjectType
      ? (SObject) queryLeadForRender(targetObjectId)
      : (SObject) queryOpportunityForRender(targetObjectId);

    if (targetRecord == null) {
      return false;
    }

    LeadManagementEmailService.RenderedEmail leadRendered;
    DealerOpportunityEmailService.RenderedEmail oppRendered;

    if (targetRecord instanceof Lead) {
      leadRendered = renderLeadTemplate((Lead) targetRecord, templateName);
      if (leadRendered == null) {
        return false;
      }
      return sendRenderedEmail(targetObjectId, leadRendered, new Set<String>{ ownerEmail.trim().toLowerCase() });
    }

    oppRendered = renderOpportunityTemplate((Opportunity) targetRecord, templateName);
    if (oppRendered == null) {
      return false;
    }
    return sendRenderedEmail(
      targetObjectId,
      oppRendered,
      new Set<String>{ ownerEmail.trim().toLowerCase() }
    );
  }

  public static String getRoleDepartmentName(String department) {
    Map<String, String> departmentMap = new Map<String, String>{
      'Transmission & Telecom Tower' => 'Transmission Tower'
    };
    return departmentMap.containsKey(department) ? departmentMap.get(department) : department;
  }

  public static Set<String> resolveLeadRecipients(
    Lead leadRecord,
    RecipientGroup recipientType
  ) {
    if (
      Test.isRunningTest() &&
      testRecipientOverrides != null &&
      !testRecipientOverrides.isEmpty()
    ) {
      return new Set<String>(testRecipientOverrides);
    }

    Set<String> recipients = new Set<String>();
    String department = getRoleDepartmentName(leadRecord.Department_NameFormula__c);

    if (
      recipientType == RecipientGroup.OWNER ||
      recipientType == RecipientGroup.OWNER_AND_CRM
    ) {
      addOwnerEmail(leadRecord.OwnerId, recipients);
    }

    if (recipientType == RecipientGroup.OWNER_AND_CRM) {
      addCrmHeadEmails(leadRecord.CRM_User_Email_Formula__c, department, recipients);
    }

    if (recipientType == RecipientGroup.HOD_ONLY) {
      addRoleEmails(department + ' HOD', recipients);
    }

    if (recipientType == RecipientGroup.CRM_HEAD_ONLY) {
      addRoleEmails('Utkarsh CRM Head', recipients);
    }

    if (recipientType == RecipientGroup.HOD_AND_CRM_HEAD) {
      addRoleEmails(department + ' HOD', recipients);
      addRoleEmails('Utkarsh CRM Head', recipients);
      addCrmHeadEmails(leadRecord.CRM_User_Email_Formula__c, department, recipients);
    }

    if (recipientType == RecipientGroup.ED_SIR) {
      addRoleEmails('Utkarsh ED', recipients);
    }

    return recipients;
  }

  public static Set<String> resolveOpportunityRecipients(
    Opportunity opportunityRecord,
    RecipientGroup recipientType
  ) {
    if (
      Test.isRunningTest() &&
      testRecipientOverrides != null &&
      !testRecipientOverrides.isEmpty()
    ) {
      return new Set<String>(testRecipientOverrides);
    }

    Set<String> recipients = new Set<String>();
    String department = getRoleDepartmentName(
      String.isNotBlank(opportunityRecord.Department_NameFormula__c)
        ? opportunityRecord.Department_NameFormula__c
        : opportunityRecord.Department_Name__c
    );

    if (
      recipientType == RecipientGroup.OWNER ||
      recipientType == RecipientGroup.OWNER_AND_CRM
    ) {
      addOwnerEmail(opportunityRecord.OwnerId, recipients);
    }

    if (recipientType == RecipientGroup.OWNER_AND_CRM) {
      addCrmHeadEmails(
        opportunityRecord.CRM_User_Email_Formula__c,
        department,
        recipients
      );
    }

    if (recipientType == RecipientGroup.HOD_ONLY) {
      addRoleEmails(department + ' HOD', recipients);
    }

    if (recipientType == RecipientGroup.CRM_HEAD_ONLY) {
      addRoleEmails('Utkarsh CRM Head', recipients);
    }

    if (recipientType == RecipientGroup.HOD_AND_CRM_HEAD) {
      addRoleEmails(department + ' HOD', recipients);
      addRoleEmails('Utkarsh CRM Head', recipients);
      addCrmHeadEmails(
        opportunityRecord.CRM_User_Email_Formula__c,
        department,
        recipients
      );
    }

    if (recipientType == RecipientGroup.ED_SIR) {
      addRoleEmails('Utkarsh ED', recipients);
    }

    return recipients;
  }

  public static Boolean hasNoActivitySince(Datetime anchorDate, Date lastActivityDate) {
    if (anchorDate == null) {
      return false;
    }
    if (lastActivityDate == null) {
      return true;
    }
    return lastActivityDate <= anchorDate.date();
  }

  public static Long hoursSince(Datetime anchorDate) {
    if (anchorDate == null) {
      return 0;
    }
    return (System.now().getTime() - anchorDate.getTime()) / (1000 * 60 * 60);
  }

  public static Long daysSince(Datetime anchorDate) {
    if (anchorDate == null) {
      return 0;
    }
    return anchorDate.date().daysBetween(Date.today());
  }

  public static Long daysSince(Date anchorDate) {
    if (anchorDate == null) {
      return 0;
    }
    return anchorDate.daysBetween(Date.today());
  }

  @TestVisible
  static void setTestTemplateId(String templateName, Id templateId) {
    if (testTemplateIdOverrides == null) {
      testTemplateIdOverrides = new Map<String, Id>();
    }
    testTemplateIdOverrides.put(templateName, templateId);
  }

  @TestVisible
  static void clearTestTemplateIds() {
    clearTestState();
  }

  @TestVisible
  static void clearTestState() {
    testTemplateIdOverrides = null;
    templateIdByName = null;
    testRecipientOverrides = null;
    testLeadRenderedOverride = null;
    testOppRenderedOverride = null;
    testSimulateSuccessfulSend = false;
  }

  private static LeadManagementEmailService.RenderedEmail renderLeadTemplate(
    Lead leadRecord,
    String templateName
  ) {
    if (Test.isRunningTest() && testLeadRenderedOverride != null) {
      return testLeadRenderedOverride;
    }

    Id templateId = resolveTemplateId(templateName);
    if (templateId == null) {
      return null;
    }
    return LeadManagementEmailService.renderTemplate(templateId, leadRecord);
  }

  private static DealerOpportunityEmailService.RenderedEmail renderOpportunityTemplate(
    Opportunity opportunityRecord,
    String templateName
  ) {
    if (Test.isRunningTest() && testOppRenderedOverride != null) {
      return testOppRenderedOverride;
    }

    Id templateId = resolveTemplateId(templateName);
    if (templateId == null) {
      return null;
    }

    Opportunity renderRecord = queryOpportunityForRender(opportunityRecord.Id);
    if (renderRecord == null) {
      return null;
    }

    return DealerOpportunityEmailService.renderTemplate(
      templateId,
      renderRecord,
      null
    );
  }

  private static Boolean sendRenderedEmail(
    Id targetObjectId,
    LeadManagementEmailService.RenderedEmail rendered,
    Set<String> recipients
  ) {
    if (rendered == null || recipients == null || recipients.isEmpty()) {
      return false;
    }

    if (Test.isRunningTest() && testSimulateSuccessfulSend) {
      return true;
    }

    Messaging.SingleEmailMessage message = buildMessage(
      targetObjectId,
      rendered.subject,
      rendered.htmlBody,
      rendered.plainTextBody,
      new List<String>(recipients)
    );
    Messaging.SendEmailResult[] results = Messaging.sendEmail(
      new List<Messaging.SingleEmailMessage>{ message }
    );
    return !results.isEmpty() && results[0].isSuccess();
  }

  private static Boolean sendRenderedEmail(
    Id targetObjectId,
    DealerOpportunityEmailService.RenderedEmail rendered,
    Set<String> recipients
  ) {
    if (rendered == null || recipients == null || recipients.isEmpty()) {
      return false;
    }

    if (Test.isRunningTest() && testSimulateSuccessfulSend) {
      return true;
    }

    Messaging.SingleEmailMessage message = buildMessage(
      targetObjectId,
      rendered.subject,
      rendered.htmlBody,
      rendered.plainTextBody,
      new List<String>(recipients)
    );
    Messaging.SendEmailResult[] results = Messaging.sendEmail(
      new List<Messaging.SingleEmailMessage>{ message }
    );
    return !results.isEmpty() && results[0].isSuccess();
  }

  private static Messaging.SingleEmailMessage buildMessage(
    Id targetObjectId,
    String subject,
    String htmlBody,
    String plainTextBody,
    List<String> toAddresses
  ) {
    Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
    message.setToAddresses(toAddresses);
    message.setSubject(subject);
    message.setSaveAsActivity(false);
    message.setTargetObjectId(targetObjectId);
    message.setTreatTargetObjectAsRecipient(false);

    if (String.isNotBlank(htmlBody)) {
      message.setHtmlBody(htmlBody);
    }
    if (String.isNotBlank(plainTextBody)) {
      message.setPlainTextBody(plainTextBody);
    }

    applyOrgWideSender(message);
    return message;
  }

  private static Id resolveTemplateId(String templateName) {
    if (Test.isRunningTest() && testTemplateIdOverrides != null) {
      return testTemplateIdOverrides.get(templateName);
    }

    if (templateIdByName == null) {
      templateIdByName = new Map<String, Id>();
      for (EmailTemplate templateRecord : [
        SELECT Id, Name
        FROM EmailTemplate
        WHERE Folder.Name = 'Utkarsh Escalation Matrix Template'
      ]) {
        templateIdByName.put(templateRecord.Name, templateRecord.Id);
      }
    }

    return templateIdByName.get(templateName);
  }

  private static void addOwnerEmail(Id ownerId, Set<String> recipients) {
    if (ownerId == null) {
      return;
    }

    List<User> owners = [
      SELECT Email
      FROM User
      WHERE Id = :ownerId AND Email != NULL
      LIMIT 1
    ];
    if (!owners.isEmpty()) {
      recipients.add(owners[0].Email.trim().toLowerCase());
    }
  }

  private static void addCrmHeadEmails(
    String crmFormulaEmail,
    String department,
    Set<String> recipients
  ) {
    if (String.isNotBlank(crmFormulaEmail)) {
      recipients.add(crmFormulaEmail.trim().toLowerCase());
    }
    addRoleEmails(department + ' CRM User', recipients);
  }

  private static void addRoleEmails(String roleName, Set<String> recipients) {
    if (String.isBlank(roleName)) {
      return;
    }

    for (User userRecord : [
      SELECT Email
      FROM User
      WHERE IsActive = TRUE AND UserRole.Name = :roleName AND Email != NULL
    ]) {
      recipients.add(userRecord.Email.trim().toLowerCase());
    }
  }

  private static void applyOrgWideSender(Messaging.SingleEmailMessage message) {
    BWM_Email_Settings__mdt settings = BWM_EmailSettingsService.getSettings();
    if (settings == null || String.isBlank(settings.Central_Sender_Email__c)) {
      return;
    }

    List<OrgWideEmailAddress> orgWideAddresses = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE Address = :settings.Central_Sender_Email__c.trim()
      LIMIT 1
    ];
    if (!orgWideAddresses.isEmpty()) {
      message.setOrgWideEmailAddressId(orgWideAddresses[0].Id);
    }
  }

  private static Id resolveOpportunityTargetObjectId(Opportunity opportunityRecord) {
    Opportunity renderRecord = queryOpportunityForRender(opportunityRecord.Id);
    if (renderRecord == null) {
      return opportunityRecord.OwnerId;
    }

    if (renderRecord.ContactId != null) {
      return renderRecord.ContactId;
    }

    return renderRecord.OwnerId;
  }

  private static Lead queryLeadForRender(Id leadId) {
    List<Lead> rows = [
      SELECT
        Id,
        Name,
        OwnerId,
        Owner.Name,
        Owner.Email,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c
      FROM Lead
      WHERE Id = :leadId
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  private static Opportunity queryOpportunityForRender(Id opportunityId) {
    List<Opportunity> rows = [
      SELECT
        Id,
        Name,
        OwnerId,
        Owner.Name,
        Owner.Email,
        ContactId,
        Department_Name__c,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c
      FROM Opportunity
      WHERE Id = :opportunityId
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }
}