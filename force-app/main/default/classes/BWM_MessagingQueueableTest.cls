/**
 * @description   Tests for BWM_MessagingQueueable chunking (bulk loads must not hit the SOQL limit).
 * @author        Anshita Chanda
 * @date          2026-11-11
 */
@IsTest
private class BWM_MessagingQueueableTest {
  private static final Integer BULK_SIZE = 15;

  private static void setCalloutMock() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );
  }

  private static List<BWM_MessagingRequest> createBulkRequests() {
    BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = true;
    List<Lead> leads = new List<Lead>();
    for (Integer index = 0; index < BULK_SIZE; index++) {
      String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger())) + index;
      leads.add(
        new Lead(
          LastName = 'Bulk Messaging ' + suffix,
          Company = 'Bulk Co ' + suffix,
          Company_Name__c = 'Bulk Co ' + suffix,
          LeadSource = 'INBOUND EMAIL',
          Status = 'Prospect',
          Department_Name__c = 'Polymer',
          Phone = ('9' + suffix + '123456789').left(10),
          Email = 'bulk+' + suffix + '@example.com'
        )
      );
    }
    Database.DMLOptions dmlOptions = new Database.DMLOptions();
    dmlOptions.DuplicateRuleHeader.AllowSave = true;
    dmlOptions.optAllOrNone = true;
    Database.insert(leads, dmlOptions);
    BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = false;

    List<BWM_MessagingRequest> requests = new List<BWM_MessagingRequest>();
    for (Lead leadRecord : leads) {
      requests.add(
        new BWM_MessagingRequest(
          leadRecord.Id,
          BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT
        )
      );
    }
    return requests;
  }

  private static Integer countLogs() {
    return [
      SELECT COUNT()
      FROM Message_Log__c
      WHERE Trigger_Point__c = :BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT
    ];
  }

  @IsTest
  static void bulkJobProcessesAtMostTenAndDefersTheRest() {
    setCalloutMock();
    List<BWM_MessagingRequest> requests = createBulkRequests();

    Test.startTest();
    List<BWM_MessagingRequest> deferred = BWM_MessagingQueueable.processRequests(requests);
    Test.stopTest();

    Integer processed = BWM_MessagingQueueable.lastProcessedCount;
    System.assert(processed >= 1, 'At least one request must be processed');
    System.assert(processed <= BWM_MessagingQueueable.MAX_REQUESTS_PER_JOB, 'Never more than 10 per job');
    System.assertEquals(BULK_SIZE - processed, deferred.size(), 'Everything not processed is deferred');
    System.assertEquals(deferred.size(), BWM_MessagingQueueable.lastDeferredCount);
    System.assertEquals(processed, countLogs(), 'One Message_Log__c per processed request');
  }

  @IsTest
  static void queuedBulkJobDoesNotHitSoqlLimit() {
    setCalloutMock();
    List<BWM_MessagingRequest> requests = createBulkRequests();

    Test.startTest();
    System.enqueueJob(new BWM_MessagingQueueable(requests));
    Test.stopTest();

    Integer logs = countLogs();
    System.assert(logs >= 1 && logs <= BWM_MessagingQueueable.MAX_REQUESTS_PER_JOB, 'Logs: ' + logs);
  }

  @IsTest
  static void futureFallbackAlsoProcessesInGroups() {
    setCalloutMock();
    List<BWM_MessagingRequest> requests = createBulkRequests();

    Test.startTest();
    BWM_MessagingFutureDispatcher.dispatch(requests);
    Test.stopTest();

    Integer logs = countLogs();
    System.assert(logs >= 1 && logs <= BWM_MessagingQueueable.MAX_REQUESTS_PER_JOB, 'Logs: ' + logs);
  }

  @IsTest
  static void emptyAndNullRequestsReturnNothingDeferred() {
    System.assertEquals(0, BWM_MessagingQueueable.processRequests(null).size());
    System.assertEquals(0, BWM_MessagingQueueable.processRequests(new List<BWM_MessagingRequest>()).size());
    BWM_MessagingQueueable.enqueueDeferred(new List<BWM_MessagingRequest>());
    System.assertEquals(0, BWM_MessagingQueueable.lastProcessedCount);
  }
}