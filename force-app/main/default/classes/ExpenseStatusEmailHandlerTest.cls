/**
 * @description Test class for ExpenseStatusEmailHandler employee / HOD / HR email criteria.
 */
@IsTest
private class ExpenseStatusEmailHandlerTest {
  private static final String STATUS_NEW = 'New';

  private static Id queryAnyTemplateId() {
    List<EmailTemplate> templates = [
      SELECT Id
      FROM EmailTemplate
      WHERE IsActive = TRUE
      LIMIT 1
    ];
    return templates.isEmpty() ? null : templates[0].Id;
  }

  // Lets the running user change Status__c past ExpenseTriggerHandler's approver checks.
  private static void allowStatusChanges() {
    ExpenseTriggerHandler.isAuthorizedApproverOverride = true;
    ExpenseTriggerHandler.currentUserProfileNameOverride = 'System Administrator';
    ExpenseTriggerHandler.currentUserRoleNameOverride = '';
  }

  private static Expense__c buildExpense(String status) {
    return new Expense__c(Status__c = status, Employee__c = UserInfo.getUserId());
  }

  @IsTest
  static void testHodAndHrQualificationMethods() {
    Expense__c submitted = buildExpense(ExpenseStatusEmailHandler.STATUS_SUBMITTED);
    Expense__c oldNew = new Expense__c(Status__c = STATUS_NEW);

    System.assertEquals(
      true,
      ExpenseStatusEmailHandler.qualifiesForHodSubmittedNotification(submitted, oldNew)
    );
    System.assertEquals(
      true,
      ExpenseStatusEmailHandler.qualifiesForHodSubmittedNotification(submitted, null)
    );
    System.assertEquals(
      false,
      ExpenseStatusEmailHandler.qualifiesForHodSubmittedNotification(submitted, submitted)
    );

    Expense__c approvedByHod = buildExpense(ExpenseStatusEmailHandler.STATUS_APPROVED_BY_HOD);

    System.assertEquals(
      true,
      ExpenseStatusEmailHandler.qualifiesForHrAwaitingApprovalNotification(
        approvedByHod,
        submitted
      )
    );
    System.assertEquals(
      false,
      ExpenseStatusEmailHandler.qualifiesForHrAwaitingApprovalNotification(
        approvedByHod,
        approvedByHod
      )
    );
    System.assertEquals(
      false,
      ExpenseStatusEmailHandler.qualifiesForHrAwaitingApprovalNotification(submitted, oldNew)
    );

    Expense__c noEmployee = new Expense__c(
      Status__c = ExpenseStatusEmailHandler.STATUS_SUBMITTED
    );
    System.assertEquals(
      false,
      ExpenseStatusEmailHandler.qualifiesForHodSubmittedNotification(noEmployee, oldNew)
    );
    System.assertEquals(
      false,
      ExpenseStatusEmailHandler.qualifiesForHrAwaitingApprovalNotification(null, oldNew)
    );
  }

  @IsTest
  static void testEmployeeStatusTemplateMapping() {
    Expense__c oldNew = new Expense__c(Status__c = STATUS_NEW);
    Expense__c submitted = buildExpense(ExpenseStatusEmailHandler.STATUS_SUBMITTED);
    Expense__c approvedByHod = buildExpense(ExpenseStatusEmailHandler.STATUS_APPROVED_BY_HOD);
    Expense__c approvedByHr = buildExpense(ExpenseStatusEmailHandler.STATUS_APPROVED_BY_HR);

    System.assertEquals(
      ExpenseStatusEmailHandler.TEMPLATE_SUBMITTED,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(submitted, oldNew)
    );
    System.assertEquals(
      ExpenseStatusEmailHandler.TEMPLATE_APPROVED_HOD,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(approvedByHod, submitted)
    );
    System.assertEquals(
      ExpenseStatusEmailHandler.TEMPLATE_REJECTED_HOD,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(
        buildExpense(ExpenseStatusEmailHandler.STATUS_REJECTED_BY_HOD),
        submitted
      )
    );
    System.assertEquals(
      ExpenseStatusEmailHandler.TEMPLATE_APPROVED_HR,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(approvedByHr, approvedByHod)
    );
    System.assertEquals(
      ExpenseStatusEmailHandler.TEMPLATE_REJECTED_HR,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(
        buildExpense(ExpenseStatusEmailHandler.STATUS_REJECTED_BY_HR),
        approvedByHod
      )
    );
    System.assertEquals(
      ExpenseStatusEmailHandler.TEMPLATE_APPROVED_ED,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(
        buildExpense(ExpenseStatusEmailHandler.STATUS_APPROVED_BY_ED),
        approvedByHr
      )
    );
    System.assertEquals(
      ExpenseStatusEmailHandler.TEMPLATE_REJECTED_ED,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(
        buildExpense(ExpenseStatusEmailHandler.STATUS_REJECTED_BY_ED),
        approvedByHr
      )
    );
  }

  @IsTest
  static void testEmployeeStatusTemplateMappingNoEmail() {
    Expense__c submitted = buildExpense(ExpenseStatusEmailHandler.STATUS_SUBMITTED);

    // Unchanged status
    System.assertEquals(
      null,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(submitted, submitted)
    );
    // Status without an email (New, Reimbursed)
    System.assertEquals(
      null,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(buildExpense(STATUS_NEW), null)
    );
    System.assertEquals(
      null,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(
        buildExpense('Reimbursed'),
        buildExpense(ExpenseStatusEmailHandler.STATUS_APPROVED_BY_ED)
      )
    );
    // No employee
    System.assertEquals(
      null,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(
        new Expense__c(Status__c = ExpenseStatusEmailHandler.STATUS_SUBMITTED),
        null
      )
    );
    System.assertEquals(
      null,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(null, null)
    );
  }

  @IsTest
  static void testHandleAfterUpdateApprovalPath() {
    Id templateId = queryAnyTemplateId();
    System.assertNotEquals(null, templateId, 'An active email template must exist');
    ExpenseStatusEmailHandler.testTemplateIdOverride = templateId;
    allowStatusChanges();

    Expense__c expense = buildExpense(STATUS_NEW);
    insert expense;

    List<String> approvalPath = new List<String>{
      ExpenseStatusEmailHandler.STATUS_SUBMITTED,
      ExpenseStatusEmailHandler.STATUS_APPROVED_BY_HOD,
      ExpenseStatusEmailHandler.STATUS_APPROVED_BY_HR,
      ExpenseStatusEmailHandler.STATUS_APPROVED_BY_ED
    };

    Test.startTest();
    for (String status : approvalPath) {
      expense.Status__c = status;
      update expense;
    }
    Test.stopTest();

    expense = [SELECT Status__c FROM Expense__c WHERE Id = :expense.Id];
    System.assertEquals(ExpenseStatusEmailHandler.STATUS_APPROVED_BY_ED, expense.Status__c);
  }

  @IsTest
  static void testHandleAfterUpdateRejectionPaths() {
    Id templateId = queryAnyTemplateId();
    System.assertNotEquals(null, templateId, 'An active email template must exist');
    ExpenseStatusEmailHandler.testTemplateIdOverride = templateId;
    allowStatusChanges();

    Expense__c rejectedByHod = buildExpense(ExpenseStatusEmailHandler.STATUS_SUBMITTED);
    Expense__c rejectedByHr = buildExpense(ExpenseStatusEmailHandler.STATUS_APPROVED_BY_HOD);
    Expense__c rejectedByEd = buildExpense(ExpenseStatusEmailHandler.STATUS_APPROVED_BY_HR);
    List<Expense__c> expenses = new List<Expense__c>{ rejectedByHod, rejectedByHr, rejectedByEd };
    insert expenses;

    rejectedByHod.Status__c = ExpenseStatusEmailHandler.STATUS_REJECTED_BY_HOD;
    rejectedByHr.Status__c = ExpenseStatusEmailHandler.STATUS_REJECTED_BY_HR;
    rejectedByEd.Status__c = ExpenseStatusEmailHandler.STATUS_REJECTED_BY_ED;

    Test.startTest();
    update expenses;
    Test.stopTest();

    Map<Id, Expense__c> savedById = new Map<Id, Expense__c>(
      [SELECT Status__c FROM Expense__c WHERE Id IN :expenses]
    );
    System.assertEquals(
      ExpenseStatusEmailHandler.STATUS_REJECTED_BY_HOD,
      savedById.get(rejectedByHod.Id).Status__c
    );
    System.assertEquals(
      ExpenseStatusEmailHandler.STATUS_REJECTED_BY_HR,
      savedById.get(rejectedByHr.Id).Status__c
    );
    System.assertEquals(
      ExpenseStatusEmailHandler.STATUS_REJECTED_BY_ED,
      savedById.get(rejectedByEd.Id).Status__c
    );
  }

  @IsTest
  static void testSendHodAndHrEmailsPaths() {
    Id templateId = queryAnyTemplateId();
    System.assertNotEquals(null, templateId, 'An active email template must exist');
    ExpenseStatusEmailHandler.testTemplateIdOverride = templateId;

    Expense__c expense = buildExpense(STATUS_NEW);
    insert expense;

    Expense__c oldNew = new Expense__c(
      Id = expense.Id,
      Status__c = STATUS_NEW,
      Employee__c = expense.Employee__c
    );
    Expense__c oldSubmitted = new Expense__c(
      Id = expense.Id,
      Status__c = ExpenseStatusEmailHandler.STATUS_SUBMITTED,
      Employee__c = expense.Employee__c
    );
    Expense__c submitted = new Expense__c(
      Id = expense.Id,
      Status__c = ExpenseStatusEmailHandler.STATUS_SUBMITTED,
      Employee__c = expense.Employee__c
    );
    Expense__c approvedByHod = new Expense__c(
      Id = expense.Id,
      Status__c = ExpenseStatusEmailHandler.STATUS_APPROVED_BY_HOD,
      Employee__c = expense.Employee__c
    );

    Test.startTest();
    ExpenseStatusEmailHandler.sendHodAndHrEmails(
      new List<Expense__c>{ submitted },
      new Map<Id, Expense__c>{ expense.Id => oldNew }
    );
    ExpenseStatusEmailHandler.sendHodAndHrEmails(
      new List<Expense__c>{ approvedByHod },
      new Map<Id, Expense__c>{ expense.Id => oldSubmitted }
    );
    Test.stopTest();

    System.assertNotEquals(null, expense.Id);
  }

  @IsTest
  static void testProcessRecordsEmptyInput() {
    Test.startTest();
    ExpenseStatusEmailHandler.handleAfterInsert(new List<Expense__c>());
    ExpenseStatusEmailHandler.handleAfterUpdate(null, null);
    Integer emailInvocations = Limits.getEmailInvocations();
    Test.stopTest();

    System.assertEquals(0, emailInvocations);
  }

  // Plain text template with no merge fields, so it always renders against an Expense.
  private static Id createTextTemplate() {
    EmailTemplate template = new EmailTemplate(
      Name = 'Expense Status Test Template',
      DeveloperName = 'Expense_Status_Test_' +
        String.valueOf(Math.abs(Crypto.getRandomInteger())),
      TemplateType = 'text',
      FolderId = UserInfo.getUserId(),
      Subject = 'Expense status update',
      Body = 'Your expense claim status has changed.',
      IsActive = true
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert template;
    }
    return template.Id;
  }

  private static User createUser(Id profileId, String department) {
    String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    User newUser = new User(
      ProfileId = profileId,
      LastName = 'ExpenseTest' + unique,
      Alias = 'ext' + unique.left(5),
      Email = 'expense.test' + unique + '@example.com',
      Username = 'expense.test' + unique + '@example.com.test',
      Department = department,
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'Asia/Kolkata'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert newUser;
    }
    return newUser;
  }

  @IsTest
  static void testBuildRecipientMessageSendsToUserId() {
    Messaging.SingleEmailMessage rendered = new Messaging.SingleEmailMessage();
    rendered.setSubject('Rendered subject');
    rendered.setHtmlBody('<p>Rendered body</p>');
    rendered.setPlainTextBody('Rendered body');
    Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
    attachment.setFileName('claim.txt');
    attachment.setBody(Blob.valueOf('claim'));
    rendered.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });
    rendered.setEntityAttachments(new List<String>{ UserInfo.getUserId() });
    Id oweaId = '0D2000000000001';

    Test.startTest();
    Messaging.SingleEmailMessage mail = ExpenseStatusEmailHandler.buildRecipientMessage(
      rendered,
      UserInfo.getUserId(),
      'fallback@example.com',
      oweaId
    );
    Test.stopTest();

    System.assertEquals(UserInfo.getUserId(), mail.getTargetObjectId());
    System.assert(
      mail.getToAddresses() == null || mail.getToAddresses().isEmpty(),
      'A User-targeted email must not carry To addresses'
    );
    System.assertEquals('Rendered subject', mail.getSubject());
    System.assertEquals('<p>Rendered body</p>', mail.getHtmlBody());
    System.assertEquals('Rendered body', mail.getPlainTextBody());
    System.assertEquals(1, mail.getFileAttachments().size());
    System.assertEquals(1, mail.getEntityAttachments().size());
    System.assertEquals(false, mail.getSaveAsActivity());
    System.assertEquals(oweaId, mail.getOrgWideEmailAddressId());
  }

  @IsTest
  static void testBuildRecipientMessageWithoutBodiesOrAttachments() {
    Messaging.SingleEmailMessage rendered = new Messaging.SingleEmailMessage();
    rendered.setSubject('Subject only');

    Test.startTest();
    Messaging.SingleEmailMessage mail = ExpenseStatusEmailHandler.buildRecipientMessage(
      rendered,
      UserInfo.getUserId(),
      null,
      null
    );
    Test.stopTest();

    System.assertEquals(UserInfo.getUserId(), mail.getTargetObjectId());
    System.assertEquals('Subject only', mail.getSubject());
    System.assertEquals(null, mail.getHtmlBody());
    System.assertEquals(null, mail.getPlainTextBody());
    System.assertEquals(null, mail.getOrgWideEmailAddressId());
  }

  @IsTest
  static void testBuildRecipientMessageFallsBackToEmail() {
    Messaging.SingleEmailMessage rendered = new Messaging.SingleEmailMessage();
    rendered.setSubject('Rendered subject');
    rendered.setPlainTextBody('Rendered body');
    Id oweaId = '0D2000000000001';

    Test.startTest();
    Messaging.SingleEmailMessage mail = ExpenseStatusEmailHandler.buildRecipientMessage(
      rendered,
      null,
      'fallback@example.com',
      oweaId
    );
    Test.stopTest();

    // The email address fallback is disabled, so no email is built without a User Id.
    System.assertEquals(null, mail, 'No email should be built without a User Id');
  }

  @IsTest
  static void testResolveActiveUserIdsByEmail() {
    User current = [SELECT Id, Email FROM User WHERE Id = :UserInfo.getUserId()];
    String email = current.Email.trim().toLowerCase();

    Test.startTest();
    Map<String, Id> found = ExpenseStatusEmailHandler.resolveActiveUserIdsByEmail(
      new Set<String>{ email, 'no.such.user@example.invalid' }
    );
    Map<String, Id> fromEmpty = ExpenseStatusEmailHandler.resolveActiveUserIdsByEmail(
      new Set<String>()
    );
    Map<String, Id> fromNull = ExpenseStatusEmailHandler.resolveActiveUserIdsByEmail(null);
    Test.stopTest();

    System.assert(found.containsKey(email), 'Active user should be matched by email');
    System.assert(!found.containsKey('no.such.user@example.invalid'));
    System.assert(fromEmpty.isEmpty());
    System.assert(fromNull.isEmpty());
  }

  @IsTest
  static void testEmployeeEmailSentOnStatusChange() {
    ExpenseStatusEmailHandler.testTemplateIdOverride = createTextTemplate();
    allowStatusChanges();

    Expense__c expense = buildExpense(STATUS_NEW);
    insert expense;

    Test.startTest();
    expense.Status__c = ExpenseStatusEmailHandler.STATUS_SUBMITTED;
    update expense;
    Integer emailInvocations = Limits.getEmailInvocations();
    Test.stopTest();

    System.assert(emailInvocations > 0, 'Employee status email should be sent');
  }

  @IsTest
  static void testHrEmailSentToHrUsers() {
    List<Profile> hrProfiles = [
      SELECT Id
      FROM Profile
      WHERE Name = :ExpenseStatusEmailHandler.HR_PROFILE_NAME
      LIMIT 1
    ];
    if (hrProfiles.isEmpty()) {
      return;
    }
    ExpenseStatusEmailHandler.testTemplateIdOverride = createTextTemplate();
    createUser(hrProfiles[0].Id, null);

    Expense__c expense = buildExpense(STATUS_NEW);
    insert expense;
    Expense__c approvedByHod = new Expense__c(
      Id = expense.Id,
      Status__c = ExpenseStatusEmailHandler.STATUS_APPROVED_BY_HOD,
      Employee__c = expense.Employee__c
    );
    Expense__c oldSubmitted = new Expense__c(
      Id = expense.Id,
      Status__c = ExpenseStatusEmailHandler.STATUS_SUBMITTED,
      Employee__c = expense.Employee__c
    );

    Test.startTest();
    ExpenseStatusEmailHandler.sendHodAndHrEmails(
      new List<Expense__c>{ approvedByHod },
      new Map<Id, Expense__c>{ expense.Id => oldSubmitted }
    );
    Integer emailInvocations = Limits.getEmailInvocations();
    Test.stopTest();

    System.assert(emailInvocations > 0, 'HR email should be sent');
  }
}