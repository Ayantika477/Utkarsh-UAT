/**
 * @description Sends WFH & WFO related emails:
 *              1. Employee - Approval Pending
 *              2. HOD - Submission
 *              3. Employee - Approved
 * @author Rani Mate
 * @date 2026-08-14
 */
public without sharing class PunchRecordWfhEmployeeEmailHandler {
  public static final String PUNCH_TYPE_WFH = 'WFH';
  public static final String PUNCH_TYPE_WFO = 'WFO';

  public static final String APPROVAL_STATUS_PENDING = 'Pending';
  public static final String APPROVAL_STATUS_APPROVED = 'Approved';

  public static final String TEMPLATE_WFH_EMPLOYEE_PENDING =
    'Employee_Approval_pending_1786604926046';
  public static final String TEMPLATE_WFH_HOD_SUBMISSION =
    'HOD_WFH_Submission_email_1786608000419';
  public static final String TEMPLATE_WFH_EMPLOYEE_APPROVED =
    'Employee_Approved_1786609772323';

  public static final String TEMPLATE_WFO_EMPLOYEE_PENDING =
    'WFO_Employee_Approval_pending_1786610200787';
  public static final String TEMPLATE_WFO_HOD_SUBMISSION =
    'HOD_WFO_Submission_email_1786610422083';
  public static final String TEMPLATE_WFO_EMPLOYEE_APPROVED =
    'WFO_Employee_Approved_1786611659696';

  public static final String PROFILE_NAME_UTKARSH_SALES = 'Utkarsh Sales';
  public static final String PROFILE_NAME_CRM_HEAD = 'CRM Head';
  public static final String APPROVAL_STATUS_REJECTED = 'Rejected';
  public static final String CUSTOM_NOTIFICATION_TYPE_NAME = 'WFH_WFO_Notification';

  public static final String TEMPLATE_WFH_EMPLOYEE_REJECTED = 'WFH_Employee_Rejected';
  public static final String TEMPLATE_WFO_EMPLOYEE_REJECTED = 'WFO_Employee_Rejected';

  public static final String ORG_WIDE_SENDER_EMAIL =
    'noreply@utkarshindialimited.in';

  // Department name (User.Department, uppercased) -> User.Departments__c picklist value
  private static final Map<String, String> DEPARTMENT_NORMALIZATION_MAP = new Map<String, String>{
    'HIGH MAST & POLYGONAL'             => 'High_Mast_Department',
    'CRASH BARRIER'                     => 'Crash_Barrier_Department',
    'HDPE'                              => 'HDPE_Pipe_Department',
    'STEEL TUBULAR POLES'               => 'Steel_Tubular_Pole_Department',
    'POLYMER'                           => 'PVC',
    'TRANSMISSION & TELECOM TOWER'      => 'Transmission_Tower_Department',
    'PRE ENGINEERING BUILDING'          => 'PEB',
    'SOLAR STRUCTURE'                   => 'Solar_Structure_Department',
    'RAILWAY ELECTRIFICATION STRUCTURE' => 'Core_Department',
    'STEEL PIPES'                       => 'Steel_Pipes_Department'
  };

  @TestVisible
  private static Id testTemplateIdOverride;

  @TestVisible
  private static Id testNotificationTypeIdOverride;

  public static void handleAfterInsert(List<Punch_Record__c> newRecords) {
    processRecords(newRecords, null);
  }

  public static void handleAfterUpdate(
    List<Punch_Record__c> newRecords,
    Map<Id, Punch_Record__c> oldRecordsById
  ) {
    processRecords(newRecords, oldRecordsById);
  }

  @TestVisible
  private static void processRecords(
    List<Punch_Record__c> newRecords,
    Map<Id, Punch_Record__c> oldRecordsById
  ) {
    if (newRecords == null || newRecords.isEmpty()) {
      return;
    }

    List<Punch_Record__c> pendingRecords = new List<Punch_Record__c>();
    List<Punch_Record__c> approvedRecords = new List<Punch_Record__c>();

    List<Punch_Record__c> rejectedRecords = new List<Punch_Record__c>();

    for (Punch_Record__c punchRecord : newRecords) {
      Punch_Record__c oldRecord = oldRecordsById == null
        ? null
        : oldRecordsById.get(punchRecord.Id);

      if (qualifiesAsPending(punchRecord, oldRecord)) {
        pendingRecords.add(punchRecord);
      }

      if (qualifiesAsApproved(punchRecord, oldRecord)) {
        approvedRecords.add(punchRecord);
      }

      // SEND CUSTOM NOTIFICATION FOR WFO/WFH REQUESTS   
      if (qualifiesAsRejected(punchRecord, oldRecord)) {
        rejectedRecords.add(punchRecord);
      }
    }

    if (!pendingRecords.isEmpty()) {
      sendPendingEmails(pendingRecords);
    }

    if (!approvedRecords.isEmpty()) {
      sendApprovedEmails(approvedRecords);
    }


    if (!pendingRecords.isEmpty()) {
      sendSalesHodNotifications(pendingRecords);
    }
    if (!approvedRecords.isEmpty()) {
      sendSalesUserNotifications(approvedRecords, 'Approved');
    }
    if (!rejectedRecords.isEmpty()) {
      sendSalesUserNotifications(rejectedRecords, 'Rejected');
      sendCrmHeadRejectedNotifications(rejectedRecords);
      sendRejectedEmails(rejectedRecords);
    }
  }

  @TestVisible
  private static Boolean qualifiesAsPending(
    Punch_Record__c punchRecord,
    Punch_Record__c oldRecord
  ) {
    if (punchRecord == null) {
      return false;
    }
    if (punchRecord.User__c == null) {
      return false;
    }
    if (punchRecord.WFH_Approval_Status__c != APPROVAL_STATUS_PENDING) {
      return false;
    }
    if (
      punchRecord.Punch_Type__c != PUNCH_TYPE_WFH &&
      punchRecord.Punch_Type__c != PUNCH_TYPE_WFO
    ) {
      return false;
    }
    if (oldRecord == null) {
      return true;
    }

    return punchRecord.Punch_Type__c != oldRecord.Punch_Type__c ||
      punchRecord.WFH_Approval_Status__c != oldRecord.WFH_Approval_Status__c;
  }

  @TestVisible
  private static Boolean qualifiesAsApproved(
    Punch_Record__c punchRecord,
    Punch_Record__c oldRecord
  ) {
    if (punchRecord == null || oldRecord == null) {
      return false;
    }
    if (punchRecord.User__c == null) {
      return false;
    }
    if (
      punchRecord.Punch_Type__c != PUNCH_TYPE_WFH &&
      punchRecord.Punch_Type__c != PUNCH_TYPE_WFO
    ) {
      return false;
    }

    return punchRecord.WFH_Approval_Status__c == APPROVAL_STATUS_APPROVED &&
      oldRecord.WFH_Approval_Status__c != APPROVAL_STATUS_APPROVED;
  }

  private static void sendPendingEmails(List<Punch_Record__c> punchRecords) {
    for (Punch_Record__c punchRecord : punchRecords) {
      String employeeTemplate;
      String hodTemplate;

      if (punchRecord.Punch_Type__c == PUNCH_TYPE_WFH) {
        employeeTemplate = TEMPLATE_WFH_EMPLOYEE_PENDING;
        hodTemplate = TEMPLATE_WFH_HOD_SUBMISSION;
      } else if (punchRecord.Punch_Type__c == PUNCH_TYPE_WFO) {
        employeeTemplate = TEMPLATE_WFO_EMPLOYEE_PENDING;
        hodTemplate = TEMPLATE_WFO_HOD_SUBMISSION;
      } else {
        continue;
      }

      sendEmailToUser(punchRecord, employeeTemplate, punchRecord.User__c);

      if (punchRecord.HOD__c != null) {
        sendEmailToUser(punchRecord, hodTemplate, punchRecord.HOD__c);
      }
    }
  }

  private static void sendApprovedEmails(List<Punch_Record__c> punchRecords) {
    for (Punch_Record__c punchRecord : punchRecords) {
      String templateName;
      if (punchRecord.Punch_Type__c == PUNCH_TYPE_WFH) {
        templateName = TEMPLATE_WFH_EMPLOYEE_APPROVED;
      } else if (punchRecord.Punch_Type__c == PUNCH_TYPE_WFO) {
        templateName = TEMPLATE_WFO_EMPLOYEE_APPROVED;
      } else {
        continue;
      }
      sendEmailToUser(punchRecord, templateName, punchRecord.User__c);
    }
  }

  private static void sendEmailToUser(
    Punch_Record__c punchRecord,
    String templateDeveloperName,
    Id userId
  ) {
    if (userId == null) {
      return;
    }

    Id templateId = resolveTemplateId(templateDeveloperName);
    if (templateId == null) {
      return;
    }

    List<User> recipients = [
      SELECT Id, Email, IsActive
      FROM User
      WHERE Id = :userId AND Email != NULL
      LIMIT 1
    ];
    if (recipients.isEmpty() || String.isBlank(recipients[0].Email)) {
      return;
    }

    Messaging.SingleEmailMessage message = buildMessage(
      templateId,
      punchRecord.Id,
      recipients[0].IsActive ? recipients[0].Id : null,
      recipients[0].Email.trim()
    );
    if (message != null) {
      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ message });
    }
  }

  // Sends to the User by Id so the email counts as internal (not against the
  // daily external email limit). A User recipient cannot take a WhatId, so the
  // template is rendered against the Punch Record first and its content copied
  // over. Without an active User no email is built (email address fallback disabled).
  @TestVisible
  private static Messaging.SingleEmailMessage buildMessage(
    Id templateId,
    Id punchRecordId,
    Id recipientUserId,
    String recipientEmail
  ) {
    if (
      templateId == null ||
      punchRecordId == null ||
      (recipientUserId == null && String.isBlank(recipientEmail))
    ) {
      return null;
    }

    Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
      templateId,
      null,
      punchRecordId
    );
    Messaging.SingleEmailMessage message;
    if (recipientUserId != null) {
      message = new Messaging.SingleEmailMessage();
      message.setTargetObjectId(recipientUserId);
      message.setSubject(rendered.getSubject());
      if (String.isNotBlank(rendered.getHtmlBody())) {
        message.setHtmlBody(rendered.getHtmlBody());
      }
      if (String.isNotBlank(rendered.getPlainTextBody())) {
        message.setPlainTextBody(rendered.getPlainTextBody());
      }
      if (rendered.getFileAttachments() != null && !rendered.getFileAttachments().isEmpty()) {
        message.setFileAttachments(rendered.getFileAttachments());
      }
      if (rendered.getEntityAttachments() != null && !rendered.getEntityAttachments().isEmpty()) {
        message.setEntityAttachments(rendered.getEntityAttachments());
      }
    } else {
      // Address-based fallback disabled for now - it counts as an external email.
      // message = rendered;
      // message.setToAddresses(new List<String>{ recipientEmail });
      // message.setTreatTargetObjectAsRecipient(false);
      System.debug(
        'PunchRecordWfhEmployeeEmailHandler: no active User Id for recipient ' + recipientEmail +
        ' - email address fallback is disabled, email not sent.'
      );
      return null;
    }
    message.setSaveAsActivity(false);
    applyOrgWideSender(message);
    return message;
  }

  private static Id resolveTemplateId(String templateDeveloperName) {
    if (Test.isRunningTest() && testTemplateIdOverride != null) {
      return testTemplateIdOverride;
    }

    List<EmailTemplate> templates = [
      SELECT Id
      FROM EmailTemplate
      WHERE DeveloperName = :templateDeveloperName
      LIMIT 1
    ];
    return templates.isEmpty() ? null : templates[0].Id;
  }

  private static void applyOrgWideSender(Messaging.SingleEmailMessage message) {
    List<OrgWideEmailAddress> orgWideAddresses = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE Address = :ORG_WIDE_SENDER_EMAIL
      LIMIT 1
    ];
    if (!orgWideAddresses.isEmpty()) {
      message.setOrgWideEmailAddressId(orgWideAddresses[0].Id);
    }
  }

  @TestVisible
  private static Boolean qualifiesAsRejected(Punch_Record__c punchRecord, Punch_Record__c oldRecord) {
    if (punchRecord == null || oldRecord == null || punchRecord.User__c == null) return false;
    if (punchRecord.Punch_Type__c != PUNCH_TYPE_WFH && punchRecord.Punch_Type__c != PUNCH_TYPE_WFO) return false;
    return punchRecord.WFH_Approval_Status__c == APPROVAL_STATUS_REJECTED &&
      oldRecord.WFH_Approval_Status__c != APPROVAL_STATUS_REJECTED;
  }

  private static void sendSalesHodNotifications(List<Punch_Record__c> punchRecords) {
    Map<Id, User> salesUsers = getSalesProfileUsers(collectUserIds(punchRecords));
    for (Punch_Record__c pr : punchRecords) {
      User salesUser = salesUsers.get(pr.User__c);
      if (salesUser == null || pr.HOD__c == null) continue;
      sendCustomNotification(
        new Set<String>{ pr.HOD__c }, 
        'New ' + pr.Punch_Type__c + ' Request',
        salesUser.Name + ' has submitted a ' + pr.Punch_Type__c + ' request for your approval.', 
        pr.Id
      );
    }
  }

  private static void sendSalesUserNotifications(List<Punch_Record__c> punchRecords, String statusLabel) {
    Map<Id, User> salesUsers = getSalesProfileUsers(collectUserIds(punchRecords));
    for (Punch_Record__c pr : punchRecords) {
      User salesUser = salesUsers.get(pr.User__c);
      if (salesUser == null) continue;
      sendCustomNotification(
        new Set<String>{ pr.User__c }, 
        pr.Punch_Type__c + ' Request ' + statusLabel,
        'Your ' + pr.Punch_Type__c + ' request has been ' + statusLabel.toLowerCase() + '.', pr.Id
      );
    }
  }

  private static void sendCrmHeadRejectedNotifications(List<Punch_Record__c> punchRecords) {
    Map<Id, User> employees = new Map<Id, User>(
      [SELECT Id, Name, Department FROM User WHERE Id IN :collectUserIds(punchRecords)]
    );
    List<User> crmHeads = [
      SELECT Id, Departments__c
      FROM User
      WHERE Profile.Name = :PROFILE_NAME_CRM_HEAD
      AND IsActive = true
      AND Departments__c != null
    ];

    for (Punch_Record__c pr : punchRecords) {
      User employee = employees.get(pr.User__c);
      if (employee == null || String.isBlank(employee.Department)) continue;
      String requestLabel = pr.Punch_Type__c == PUNCH_TYPE_WFH ? 'Work From Home' : 'Work From Office';
      sendCustomNotification(
        getCrmHeadRecipientIds(employee.Department, crmHeads),
        pr.Punch_Type__c + ' Request Rejected',
        employee.Name + '\'s ' + requestLabel + ' request has been rejected.',
        pr.User__c
      );
    }
  }

  // CRM Head: employee's Department belongs to one of the CRM Head's Departments__c
  @TestVisible
  private static Set<String> getCrmHeadRecipientIds(String department, List<User> crmHeads) {
    Set<String> recipientIds = new Set<String>();
    if (String.isBlank(department)) return recipientIds;
    String employeeDept = department.trim().toUpperCase();
    for (User crmHead : crmHeads) {
      for (String deptName : getCrmHeadDepartmentNames(crmHead.Departments__c)) {
        if (deptName.toUpperCase() == employeeDept) {
          recipientIds.add(crmHead.Id);
          break;
        }
      }
    }
    return recipientIds;
  }

  /**
   * Department values covered by a CRM Head: each of the CRM Head's Departments__c values
   * plus that department's name (e.g. 'Crash_Barrier_Department' and 'CRASH BARRIER').
   */
  private static Set<String> getCrmHeadDepartmentNames(String departmentsValue) {
    Set<String> deptNames = new Set<String>();
    if (String.isBlank(departmentsValue)) return deptNames;
    for (String rawDept : departmentsValue.split(';')) {
      if (String.isNotBlank(rawDept)) {
        deptNames.add(rawDept.trim());
      }
    }
    for (String deptName : DEPARTMENT_NORMALIZATION_MAP.keySet()) {
      if (deptNames.contains(DEPARTMENT_NORMALIZATION_MAP.get(deptName))) {
        deptNames.add(deptName);
      }
    }
    return deptNames;
  }

  private static Set<Id> collectUserIds(List<Punch_Record__c> punchRecords) {
    Set<Id> userIds = new Set<Id>();
    for (Punch_Record__c pr : punchRecords) {
      if (pr.User__c != null) userIds.add(pr.User__c);
    }
    return userIds;
  }

  /*private static Set<Id> getSalesProfileUserIds(Set<Id> userIds) {
    Set<Id> result = new Set<Id>();
    if (userIds.isEmpty()) return result;
    for (User u : [SELECT Id FROM User WHERE Id IN :userIds AND Profile.Name = :PROFILE_NAME_UTKARSH_SALES]) {
      result.add(u.Id);
    }
    return result;
  }*/
  private static Map<Id, User> getSalesProfileUsers(Set<Id> userIds) {
    Map<Id, User> result = new Map<Id, User>();
    if (userIds.isEmpty()) return result;
    for (User u : [SELECT Id, Name FROM User WHERE Id IN :userIds AND Profile.Name = :PROFILE_NAME_UTKARSH_SALES]) {
      result.put(u.Id, u);
    }
    return result;
  }

  @TestVisible
  private static void sendCustomNotification(Set<String> recipientIds, String title, String body, Id targetId) {
    if (recipientIds.isEmpty()) return;
    Id notificationTypeId = resolveCustomNotificationTypeId();
    if (notificationTypeId == null) return;
    Messaging.CustomNotification notification = new Messaging.CustomNotification();
    notification.setTitle(title);
    notification.setBody(body);
    notification.setNotificationTypeId(notificationTypeId);
    notification.setTargetId(targetId);
    try {
      notification.send(recipientIds);
    } catch (Exception e) {
      System.debug('Custom notification send failed: ' + e.getMessage());
    }
  }

  @TestVisible
  private static Id resolveCustomNotificationTypeId() {
    if (Test.isRunningTest() && testNotificationTypeIdOverride != null) {
      return testNotificationTypeIdOverride;
    }
    for (CustomNotificationType type : [SELECT Id FROM CustomNotificationType WHERE DeveloperName = :CUSTOM_NOTIFICATION_TYPE_NAME LIMIT 1]) {
      return type.Id;
    }
    return null;
  }

  private static void sendRejectedEmails(List<Punch_Record__c> punchRecords) {
    for (Punch_Record__c punchRecord : punchRecords) {
      String templateName;
      if (punchRecord.Punch_Type__c == PUNCH_TYPE_WFH) {
        templateName = TEMPLATE_WFH_EMPLOYEE_REJECTED;
      } else if (punchRecord.Punch_Type__c == PUNCH_TYPE_WFO) {
        templateName = TEMPLATE_WFO_EMPLOYEE_REJECTED;
      } else {
        continue;
      }
      sendEmailToUser(punchRecord, templateName, punchRecord.User__c);
    }
  }
}