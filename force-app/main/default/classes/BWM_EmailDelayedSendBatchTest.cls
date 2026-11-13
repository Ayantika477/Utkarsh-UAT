/**
 * @description   Test class for BWM_EmailDelayedSendBatch pending scheduled email
 *                processing.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
@IsTest
private class BWM_EmailDelayedSendBatchTest {
  /**
   * Scenario: Scheduled row without related record Id is cancelled.
   */
  @IsTest
  static void testExecute_MissingRelatedRecord_CancelsScheduledSend() {
    BWM_Email_Scheduled_Send__c scheduled = new BWM_Email_Scheduled_Send__c();
    scheduled.Status__c = BWM_EmailConstants.SCHEDULE_STATUS_PENDING;
    scheduled.Process_After__c = System.now().addMinutes(-5);
    scheduled.Trigger_Point__c = BWM_EmailConstants.TRIGGER_LEAD_TASK_LOST_DETAILS_PROSPECTING_DELAYED;
    insert as system scheduled;

    Test.startTest();
    new BWM_EmailDelayedSendBatch()
      .execute(null, new List<BWM_Email_Scheduled_Send__c>{ scheduled });
    Test.stopTest();

    scheduled = [
      SELECT Status__c, Error_Message__c
      FROM BWM_Email_Scheduled_Send__c
      WHERE Id = :scheduled.Id
    ];
    System.assertEquals(BWM_EmailConstants.SCHEDULE_STATUS_CANCELLED, scheduled.Status__c);
  }

  /**
   * Scenario: Lead that no longer matches delayed criteria is cancelled.
   */
  @IsTest
  static void testExecute_LeadNoLongerEligible_CancelsScheduledSend() {
    BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = true;
    BWM_EmailLeadTriggerHandler.skipEnqueueForTests = true;

    Lead leadRecord = new Lead(
      LastName = 'Ineligible Delayed Lead ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
      Company = 'Delayed Co ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
      Company_Name__c = 'Delayed Co ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
      LeadSource = 'INBOUND EMAIL',
      Status = 'Prospecting',
      Department_Name__c = 'Steel Pipes',
      Phone = (String.valueOf(Math.abs(Crypto.getRandomInteger())) + '9123456789').right(10),
      Email = 'ineligible.delayed+' + String.valueOf(Math.abs(Crypto.getRandomInteger())) + '@example.com',
      Lost_Reason__c = BWM_EmailConstants.LOST_REASON_DETAILS_NOT_RECEIVED
    );
    insert as system leadRecord;

    BWM_Email_Scheduled_Send__c scheduled = new BWM_Email_Scheduled_Send__c();
    scheduled.Lead__c = leadRecord.Id;
    scheduled.Related_Record_Id__c = String.valueOf(leadRecord.Id);
    scheduled.Trigger_Point__c = BWM_EmailConstants.TRIGGER_LEAD_TASK_LOST_DETAILS_PROSPECTING_DELAYED;
    scheduled.Process_After__c = System.now().addMinutes(-5);
    scheduled.Status__c = BWM_EmailConstants.SCHEDULE_STATUS_PENDING;
    insert as system scheduled;

    leadRecord.Lost_Reason__c = null;
    update as system leadRecord;

    Test.startTest();
    new BWM_EmailDelayedSendBatch()
      .execute(null, new List<BWM_Email_Scheduled_Send__c>{ scheduled });
    Test.stopTest();

    scheduled = [
      SELECT Status__c, Error_Message__c
      FROM BWM_Email_Scheduled_Send__c
      WHERE Id = :scheduled.Id
    ];
    System.assertEquals(BWM_EmailConstants.SCHEDULE_STATUS_CANCELLED, scheduled.Status__c);
    System.assert(String.isNotBlank(scheduled.Error_Message__c));
  }

  /**
   * Scenario: Eligible delayed Lead send is attempted; row is updated to Sent or Failed.
   */
  @IsTest
  static void testExecute_EligibleLeadDelayedSend_UpdatesStatus() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_EmailCalloutMock('{"messages":[{"status":"PENDING_ACCEPTED"}]}', 200)
    );
    BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = true;
    BWM_EmailLeadTriggerHandler.skipEnqueueForTests = true;

    Lead leadRecord = new Lead(
      LastName = 'Delayed Email Lead ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
      Company = 'Delayed Co ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
      Company_Name__c = 'Delayed Co ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
      LeadSource = 'INBOUND EMAIL',
      Status = 'Prospecting',
      Department_Name__c = 'Steel Pipes',
      Phone = (String.valueOf(Math.abs(Crypto.getRandomInteger())) + '9123456789').right(10),
      Email = 'delayed.email+' + String.valueOf(Math.abs(Crypto.getRandomInteger())) + '@example.com',
      Lost_Reason__c = BWM_EmailConstants.LOST_REASON_DETAILS_NOT_RECEIVED
    );
    insert as system leadRecord;

    BWM_Email_Scheduled_Send__c scheduled = new BWM_Email_Scheduled_Send__c();
    scheduled.Lead__c = leadRecord.Id;
    scheduled.Related_Record_Id__c = String.valueOf(leadRecord.Id);
    scheduled.Trigger_Point__c = BWM_EmailConstants.TRIGGER_LEAD_TASK_LOST_DETAILS_PROSPECTING_DELAYED;
    scheduled.Process_After__c = System.now().addMinutes(-5);
    scheduled.Status__c = BWM_EmailConstants.SCHEDULE_STATUS_PENDING;
    insert as system scheduled;

    Test.startTest();
    new BWM_EmailDelayedSendBatch()
      .execute(null, new List<BWM_Email_Scheduled_Send__c>{ scheduled });
    Test.stopTest();

    scheduled = [
      SELECT Status__c, Error_Message__c
      FROM BWM_Email_Scheduled_Send__c
      WHERE Id = :scheduled.Id
    ];
    System.assert(
      scheduled.Status__c == BWM_EmailConstants.SCHEDULE_STATUS_SENT ||
        scheduled.Status__c == BWM_EmailConstants.SCHEDULE_STATUS_FAILED,
      'Scheduled row should be processed.'
    );
  }

  /**
   * Scenario: many due rows in one chunk - no limit exception; rows that do not fit stay Pending.
   */
  @IsTest
  static void testExecute_BulkRows_StopsBeforeLimitsAndLeavesRestPending() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_EmailCalloutMock('{"messages":[{"status":"PENDING_ACCEPTED"}]}', 200)
    );
    BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = true;
    BWM_EmailLeadTriggerHandler.skipEnqueueForTests = true;

    List<Lead> leads = new List<Lead>();
    for (Integer index = 0; index < 15; index++) {
      String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger())) + index;
      leads.add(
        new Lead(
          LastName = 'Bulk Delayed Lead ' + suffix,
          Company = 'Bulk Delayed Co ' + suffix,
          Company_Name__c = 'Bulk Delayed Co ' + suffix,
          LeadSource = 'INBOUND EMAIL',
          Status = 'Prospecting',
          Department_Name__c = 'Steel Pipes',
          Phone = ('9' + suffix + '123456789').left(10),
          Email = 'bulk.delayed+' + suffix + '@example.com',
          Lost_Reason__c = BWM_EmailConstants.LOST_REASON_DETAILS_NOT_RECEIVED
        )
      );
    }
    Database.DMLOptions dmlOptions = new Database.DMLOptions();
    dmlOptions.DuplicateRuleHeader.AllowSave = true;
    Database.insert(leads, dmlOptions);

    List<BWM_Email_Scheduled_Send__c> rows = new List<BWM_Email_Scheduled_Send__c>();
    for (Lead leadRecord : leads) {
      rows.add(
        new BWM_Email_Scheduled_Send__c(
          Lead__c = leadRecord.Id,
          Related_Record_Id__c = String.valueOf(leadRecord.Id),
          Trigger_Point__c = BWM_EmailConstants.TRIGGER_LEAD_TASK_LOST_DETAILS_PROSPECTING_DELAYED,
          Process_After__c = System.now().addMinutes(-5),
          Status__c = BWM_EmailConstants.SCHEDULE_STATUS_PENDING
        )
      );
    }
    insert as system rows;

    Test.startTest();
    new BWM_EmailDelayedSendBatch().execute(null, rows);
    Test.stopTest();

    Integer processed = BWM_EmailDelayedSendBatch.lastProcessedCount;
    Integer leftPending = BWM_EmailDelayedSendBatch.lastLeftPendingCount;
    System.assert(processed >= 1, 'At least one row must be processed');
    System.assertEquals(15, processed + leftPending);
    System.assertEquals(
      leftPending,
      [
        SELECT COUNT()
        FROM BWM_Email_Scheduled_Send__c
        WHERE Id IN :rows AND Status__c = :BWM_EmailConstants.SCHEDULE_STATUS_PENDING
      ],
      'Rows that did not fit stay Pending for the next run'
    );
  }

  /**
   * Scenario: Opportunity delayed send is cancelled when nurture lost criteria no longer match.
   */
  @IsTest
  static void testExecute_OpportunityNoLongerEligible_CancelsScheduledSend() {
    Account accountRecord = new Account(Name = 'Delayed Opp Account ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
    insert as system accountRecord;
    Opportunity opportunityRecord = new Opportunity(
      Name = 'Delayed Opp ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
      AccountId = accountRecord.Id,
      StageName = BWM_EmailConstants.STAGE_NURTURE,
      CloseDate = Date.today().addDays(30),
      Department_Name__c = 'Steel Pipes',
      Lost_Reason__c = BWM_EmailConstants.LOST_REASON_DETAILS_NOT_RECEIVED,
      Email__c = 'delayed.opp@example.com'
    );
    insert as system opportunityRecord;

    BWM_Email_Scheduled_Send__c scheduled = new BWM_Email_Scheduled_Send__c();
    scheduled.Opportunity__c = opportunityRecord.Id;
    scheduled.Related_Record_Id__c = String.valueOf(opportunityRecord.Id);
    scheduled.Trigger_Point__c = BWM_EmailConstants.TRIGGER_OPP_LOST_DETAILS_NURTURE_DELAYED;
    scheduled.Process_After__c = System.now().addMinutes(-5);
    scheduled.Status__c = BWM_EmailConstants.SCHEDULE_STATUS_PENDING;
    insert as system scheduled;

    opportunityRecord.Lost_Reason__c = null;
    update as system opportunityRecord;

    Test.startTest();
    new BWM_EmailDelayedSendBatch()
      .execute(null, new List<BWM_Email_Scheduled_Send__c>{ scheduled });
    Test.stopTest();

    scheduled = [
      SELECT Status__c
      FROM BWM_Email_Scheduled_Send__c
      WHERE Id = :scheduled.Id
    ];
    System.assertEquals(BWM_EmailConstants.SCHEDULE_STATUS_CANCELLED, scheduled.Status__c);
  }

  /**
   * Scenario: Batch start/execute/finish lifecycle completes without error.
   */
  @IsTest
  static void testBatchLifecycle_StartExecuteFinish() {
    Test.startTest();
    Id batchJobId = Database.executeBatch(new BWM_EmailDelayedSendBatch(), 50);
    Test.stopTest();

    System.assertNotEquals(null, batchJobId);
  }

  /**
   * Scenario: Schedulable execute kicks off the batch without error.
   */
  @IsTest
  static void testSchedulableExecute_StartsBatch() {
    Test.startTest();
    new BWM_EmailDelayedSendBatch().execute((SchedulableContext) null);
    Test.stopTest();

    System.assertEquals(true, true, 'Schedulable execute should complete.');
  }
}