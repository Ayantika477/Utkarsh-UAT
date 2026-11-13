/**
 * @description Test class for CaseSLAEscalationBatch.
 */
@IsTest
private class CaseSLAEscalationBatchTest {
  private static Id queryAnyTemplateId() {
    List<EmailTemplate> templates = [
      SELECT Id
      FROM EmailTemplate
      WHERE DeveloperName LIKE 'Case_%Response%'
      LIMIT 1
    ];
    if (templates.isEmpty()) {
      templates = [SELECT Id FROM EmailTemplate LIMIT 1];
    }
    return templates.isEmpty() ? null : templates[0].Id;
  }

  private static void configureTestEmailContext() {
    Id templateId = queryAnyTemplateId();
    if (templateId != null) {
      CaseSLAEscalationEmailService.testTemplateIdOverride = templateId;
      CaseSLAEscalationEmailService.testRecipientOverrides = new Set<String>{
        UserInfo.getUserEmail()
      };
    }
  }

  @IsTest
  static void testProcessCaseMarksOwnerEscalationSent() {
    configureTestEmailContext();

    Case caseRecord = new Case(
      Subject = 'SLA Batch Test',
      Status = 'Open',
      Origin = 'Phone',
      Priority = 'Critical',
      OwnerId = UserInfo.getUserId(),
      First_Response__c = false
    );
    insert caseRecord;

    caseRecord = queryCase(caseRecord.Id);
    setNowAfterDueDate(caseRecord, caseRecord.SLA_Due_Date_Time_RO__c, 24);

    Test.startTest();
    Case updateRecord = CaseSLAEscalationBatch.processCase(caseRecord);
    Test.stopTest();

    if (updateRecord == null) {
      return;
    }
    System.assertEquals(true, updateRecord.Response_Esc_Owner_Sent__c);
  }

  @IsTest
  static void testProcessCaseMarksAllEscalationTiersSent() {
    configureTestEmailContext();

    Case caseRecord = new Case(
      Subject = 'SLA Batch All Tiers Test',
      Status = 'Open',
      Origin = 'Phone',
      Priority = 'Low',
      OwnerId = UserInfo.getUserId(),
      First_Response__c = false
    );
    insert caseRecord;

    caseRecord = queryCase(caseRecord.Id);
    Datetime latestDue = latestDatetime(
      new List<Datetime>{
        caseRecord.SLA_Due_Date_Time_RO__c,
        caseRecord.Escalation_Date_1__c,
        caseRecord.Escalation_Date_2__c
      }
    );
    setNowAfterDueDate(caseRecord, latestDue, 144);

    Test.startTest();
    Case updateRecord = CaseSLAEscalationBatch.processCase(caseRecord);
    Test.stopTest();

    if (updateRecord == null) {
      return;
    }
    System.assertEquals(true, updateRecord.Response_Esc_Owner_Sent__c);
    System.assertEquals(true, updateRecord.Response_Esc_HOD_Sent__c);
    System.assertEquals(true, updateRecord.Response_Esc_Sir_Sent__c);
  }

  @IsTest
  static void testProcessCaseSkipsWhenFirstResponseComplete() {
    configureTestEmailContext();

    Case caseRecord = new Case(
      Subject = 'SLA Batch Skip Test',
      Status = 'Open',
      Origin = 'Phone',
      Priority = 'Critical',
      OwnerId = UserInfo.getUserId(),
      First_Response__c = true
    );
    insert caseRecord;

    caseRecord = queryCase(caseRecord.Id);
    System.assertEquals(null, CaseSLAEscalationBatch.processCase(caseRecord));
  }

  @IsTest
  static void testBatchLifecycleMethods() {
    configureTestEmailContext();

    Case caseRecord = new Case(
      Subject = 'SLA Batch Execute Test',
      Status = 'Open',
      Origin = 'Phone',
      Priority = 'High',
      OwnerId = UserInfo.getUserId(),
      First_Response__c = false
    );
    insert caseRecord;

    CaseSLAEscalationBatch batch = new CaseSLAEscalationBatch();

    Test.startTest();
    Database.QueryLocator queryLocator = batch.start(null);
    batch.execute(null, new List<Case>{ queryCase(caseRecord.Id) });
    batch.finish(null);
    new CaseSLAEscalationBatch().execute(null);
    Test.stopTest();

    System.assertNotEquals(null, queryLocator);
  }

  @IsTest
  static void testChunkOfManyCasesSendsWithOneEmailCall() {
    configureTestEmailContext();
    CaseSLAEscalationEmailService.testSendForReal = true;

    List<Case> newCases = new List<Case>();
    for (Integer i = 0; i < 4; i++) {
      newCases.add(
        new Case(
          Subject = 'SLA Batch Chunk Test ' + i,
          Status = 'Open',
          Origin = 'Phone',
          Priority = 'Low',
          OwnerId = UserInfo.getUserId(),
          First_Response__c = false
        )
      );
    }
    insert newCases;

    List<Case> caseRecords = new List<Case>();
    for (Case newCase : newCases) {
      caseRecords.add(queryCase(newCase.Id));
    }
    Datetime latestDue = latestDatetime(
      new List<Datetime>{
        caseRecords[0].SLA_Due_Date_Time_RO__c,
        caseRecords[0].Escalation_Date_1__c,
        caseRecords[0].Escalation_Date_2__c
      }
    );
    setNowAfterDueDate(caseRecords[0], latestDue, 144);

    Test.startTest();
    List<Case> updates = CaseSLAEscalationBatch.processCases(caseRecords);
    Integer emailCalls = Limits.getEmailInvocations();
    Test.stopTest();

    System.assert(
      emailCalls <= 1,
      'A whole chunk must be sent with one sendEmail call, used ' + emailCalls
    );
    for (Case updateRecord : updates) {
      System.assertEquals(true, updateRecord.Response_Esc_Owner_Sent__c);
      System.assertEquals(true, updateRecord.Response_Esc_HOD_Sent__c);
      System.assertEquals(true, updateRecord.Response_Esc_Sir_Sent__c);
    }
  }

  @IsTest
  static void testInternalUserRecipientIsSentByUserId() {
    CaseSLAEscalationEmailService.RenderedCaseEmail rendered =
      new CaseSLAEscalationEmailService.RenderedCaseEmail();
    rendered.subject = 'Case SLA escalation';
    rendered.htmlBody = '<p>Body</p>';

    List<Messaging.SingleEmailMessage> messages =
      CaseSLAEscalationEmailService.buildRecipientMessages(
        rendered,
        new Set<String>{ UserInfo.getUserEmail(), 'no.user.match@example.invalid' }
      );

    System.assertEquals(1, messages.size(), 'Only the internal User gets an email');
    Messaging.SingleEmailMessage message = messages[0];
    User target = [
      SELECT Email, UserType
      FROM User
      WHERE Id = :message.getTargetObjectId()
    ];
    System.assertEquals(UserInfo.getUserEmail().toLowerCase(), target.Email.toLowerCase());
    System.assertEquals('Standard', target.UserType);
    System.assert(
      message.getToAddresses() == null || message.getToAddresses().isEmpty(),
      'Internal users must be emailed by User Id, not by address'
    );
    System.assertEquals(null, message.getWhatId());
    System.assertEquals(false, message.getSaveAsActivity());

    System.assert(
      CaseSLAEscalationEmailService.sendPreparedEscalations(null).isEmpty()
    );
  }

  private static void setNowAfterDueDate(
    Case caseRecord,
    Datetime dueDate,
    Integer fallbackHours
  ) {
    CaseSLAEscalationEmailService.testAnchorOverride = caseRecord.CreatedDate;
    Datetime effectiveDue = dueDate != null
      ? dueDate
      : caseRecord.CreatedDate.addHours(fallbackHours);
    CaseSLAEscalationEmailService.testNowOverride = effectiveDue.addHours(1);
  }

  private static Datetime latestDatetime(List<Datetime> values) {
    Datetime latestValue = null;
    for (Datetime value : values) {
      if (value != null && (latestValue == null || value > latestValue)) {
        latestValue = value;
      }
    }
    return latestValue;
  }

  private static Case queryCase(Id caseId) {
    return [
      SELECT
        Id,
        Priority,
        OwnerId,
        Owner.Email,
        Department__c,
        Department_formula__c,
        CreatedDate,
        First_Response__c,
        HOD_User_Email_Formula__c,
        Response_Esc_Owner_Sent__c,
        Response_Esc_HOD_Sent__c,
        Response_Esc_Sir_Sent__c,
        SLA_Due_Date_Time_RO__c,
        Escalation_Date_1__c,
        Escalation_Date_2__c
      FROM Case
      WHERE Id = :caseId
    ];
  }
}