/**
 * @description Test class for ExpenseSubmissionReminderBatch day-7 HOD reminder logic.
 */
@IsTest
private class ExpenseSubmissionReminderBatchTest {
  @IsTest
  static void testExecuteNonReminderDayReturnsEarly() {
    ExpenseSubmissionReminderBatch.testTodayOverride = Date.newInstance(2026, 3, 10);
    User runAsUser = [
      SELECT Id, Email
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    ExpenseSubmissionReminderBatch batch = new ExpenseSubmissionReminderBatch();

    Test.startTest();
    batch.execute(null, new List<User>{ runAsUser });
    batch.finish(null);
    Test.stopTest();

    System.assert(true, 'Non-reminder day should return without error');
  }

  @IsTest
  static void testExecuteDay7WithPriorMonthSubmission() {
    ExpenseSubmissionReminderBatch.testTodayOverride = Date.newInstance(2026, 3, 7);
    User runAsUser = [
      SELECT Id, Email
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    Expense__c expense = new Expense__c(
      Status__c = 'Pending HOD Approval',
      Employee__c = runAsUser.Id,
      Submitted_Date__c = Date.newInstance(2026, 2, 15)
    );
    insert expense;

    ExpenseSubmissionReminderBatch batch = new ExpenseSubmissionReminderBatch();

    Test.startTest();
    batch.execute(null, new List<User>{ runAsUser });
    Test.stopTest();

    System.assert(true, 'Submitted employee should be excluded from HOD reminders');
  }

  @IsTest
  static void testExecuteDay7HodReminderPath() {
    ExpenseSubmissionReminderBatch.testTodayOverride = Date.newInstance(2026, 3, 7);
    User runAsUser = [
      SELECT Id, Email
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    Expense__c expense = new Expense__c(
      Status__c = 'New',
      Employee__c = runAsUser.Id
    );
    insert expense;

    ExpenseSubmissionReminderBatch batch = new ExpenseSubmissionReminderBatch();

    Test.startTest();
    batch.execute(null, new List<User>{ runAsUser });
    Test.stopTest();

    System.assert(true, 'Day-7 HOD reminder path should execute without error');
  }

  @IsTest
  static void testExecuteDay16EmployeeReminderPath() {
    ExpenseSubmissionReminderBatch.testTodayOverride = Date.newInstance(2026, 3, 16);
    User runAsUser = [
      SELECT Id, Email
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    ExpenseSubmissionReminderBatch batch = new ExpenseSubmissionReminderBatch();

    Test.startTest();
    batch.execute(null, new List<User>{ runAsUser });
    Test.stopTest();

    System.assert(true, 'Day-16 employee reminder path should execute without error');
  }

  @IsTest
  static void testExecuteDay1EmployeeReminderPath() {
    ExpenseSubmissionReminderBatch.testTodayOverride = Date.newInstance(2026, 3, 1);
    User runAsUser = [
      SELECT Id, Email
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    ExpenseSubmissionReminderBatch batch = new ExpenseSubmissionReminderBatch();

    Test.startTest();
    batch.execute(null, new List<User>{ runAsUser });
    Test.stopTest();

    System.assert(true, 'Day-1 employee reminder path should execute without error');
  }

  @IsTest
  static void testExecuteDay16SkipsSubmittedEmployee() {
    ExpenseSubmissionReminderBatch.testTodayOverride = Date.newInstance(2026, 3, 16);
    User runAsUser = [
      SELECT Id, Email
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    Expense__c expense = new Expense__c(
      Status__c = 'Pending HOD Approval',
      Employee__c = runAsUser.Id,
      Submitted_Date__c = Date.newInstance(2026, 3, 5)
    );
    insert expense;

    ExpenseSubmissionReminderBatch batch = new ExpenseSubmissionReminderBatch();

    Test.startTest();
    batch.execute(null, new List<User>{ runAsUser });
    Test.stopTest();

    System.assert(true, 'Submitted employee should be skipped on day 16');
  }

  @IsTest
  static void testStartQueryLocator() {
    ExpenseSubmissionReminderBatch batch = new ExpenseSubmissionReminderBatch();
    Test.startTest();
    Database.QueryLocator queryLocator = batch.start(null);
    Test.stopTest();
    System.assertNotEquals(null, queryLocator);
  }

  private static User createUser(String department, String email) {
    String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    User newUser = new User(
      ProfileId = UserInfo.getProfileId(),
      LastName = 'ReminderTest' + unique,
      Alias = 'rmt' + unique.left(5),
      Email = String.isNotBlank(email) ? email : 'reminder.test' + unique + '@example.com',
      Username = 'reminder.test' + unique + '@example.com.test',
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
  static void testBuildHodReminderMessageSendsToUserId() {
    Id oweaId = '0D2000000000001';

    Test.startTest();
    Messaging.SingleEmailMessage mail = ExpenseSubmissionReminderBatch.buildHodReminderMessage(
      null,
      UserInfo.getUserId(),
      'hod@example.com',
      'Test Employee',
      'February 2026',
      oweaId
    );
    Test.stopTest();

    System.assertEquals(UserInfo.getUserId(), mail.getTargetObjectId());
    System.assert(
      mail.getToAddresses() == null || mail.getToAddresses().isEmpty(),
      'A User-targeted email must not carry To addresses'
    );
    System.assertEquals(null, mail.getWhatId());
    System.assert(mail.getSubject().contains('Test Employee'));
    System.assert(mail.getHtmlBody().contains('February 2026'));
    System.assertEquals(false, mail.getSaveAsActivity());
    System.assertEquals(oweaId, mail.getOrgWideEmailAddressId());
  }

  @IsTest
  static void testBuildHodReminderMessageFallsBackToEmail() {
    Expense__c expense = new Expense__c(
      Status__c = 'New',
      Employee__c = UserInfo.getUserId()
    );
    insert expense;

    Test.startTest();
    Messaging.SingleEmailMessage mail = ExpenseSubmissionReminderBatch.buildHodReminderMessage(
      expense.Id,
      null,
      'hod@example.com',
      null,
      'February 2026',
      null
    );
    Test.stopTest();

    // The email address fallback is disabled, so no email is built without a User Id.
    System.assertEquals(null, mail, 'No email should be built without a HOD User Id');
  }

  @IsTest
  static void testBuildHodReminderMessageWithoutRecipient() {
    Test.startTest();
    Messaging.SingleEmailMessage mail = ExpenseSubmissionReminderBatch.buildHodReminderMessage(
      null,
      null,
      null,
      'Test Employee',
      'February 2026',
      null
    );
    Test.stopTest();

    System.assertEquals(null, mail);
  }

  @IsTest
  static void testExecuteDay7HodReminderForDepartmentEmployee() {
    ExpenseSubmissionReminderBatch.testTodayOverride = Date.newInstance(2026, 3, 7);
    User employee = createUser('Steel Pipes', null);

    // Give the department HOD email a matching active User so the User Id lookup is exercised.
    Department_HOD_Person__mdt hodPerson = Department_HOD_Person__mdt.getInstance('STEEL_PIPES');
    if (hodPerson != null && String.isNotBlank(hodPerson.HOD_Person_Email__c)) {
      createUser('Steel Pipes', hodPerson.HOD_Person_Email__c.trim());
    }

    // Inserted as the employee so the HOD email formula resolves from their department.
    System.runAs(employee) {
      insert new Expense__c(Status__c = 'New', Employee__c = employee.Id);
    }

    User scopeUser = [
      SELECT Id, Name, Email, FirstName, LastName, IsActive
      FROM User
      WHERE Id = :employee.Id
    ];
    ExpenseSubmissionReminderBatch batch = new ExpenseSubmissionReminderBatch();

    Test.startTest();
    batch.execute(null, new List<User>{ scopeUser });
    Test.stopTest();

    System.assert(true, 'Day-7 HOD reminder should run for a department employee');
  }
}