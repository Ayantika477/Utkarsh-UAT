/**
 * @description   Queueable job that processes email send requests with callouts via
 *                BWM_EmailService.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
public without sharing class BWM_EmailQueueable implements Queueable, Database.AllowsCallouts {
  // Each send uses several SOQL queries and one sendEmail call (limit 10 per transaction),
  // so large requests lists are processed in groups and the rest is chained to a new job.
  @TestVisible
  private static final Integer MAX_REQUESTS_PER_JOB = 10;

  // Minimum queries kept free for the next send and the final Email_Log__c insert;
  // raised to the heaviest send seen in the job plus SOQL_SAFETY_MARGIN.
  @TestVisible
  private static final Integer SOQL_HEADROOM = 40;

  private static final Integer SOQL_SAFETY_MARGIN = 15;

  @TestVisible
  private static Integer lastProcessedCount = 0;

  @TestVisible
  private static Integer lastDeferredCount = 0;

  @TestVisible
  private static Integer lastQueriesUsed = 0;

  private final List<BWM_EmailRequest> requests;

  public BWM_EmailQueueable(List<BWM_EmailRequest> requests) {
    this.requests = requests == null
      ? new List<BWM_EmailRequest>()
      : new List<BWM_EmailRequest>(requests);
  }

  public void execute(QueueableContext context) {
    List<Email_Log__c> logsToInsert = new List<Email_Log__c>();
    List<BWM_EmailRequest> deferredRequests = new List<BWM_EmailRequest>();
    Integer processedCount = 0;
    Integer maxQueriesPerSend = 0;

    for (BWM_EmailRequest requestItem : requests) {
      if (requestItem == null || requestItem.recordId == null) {
        continue;
      }

      if (
        !deferredRequests.isEmpty() ||
        (processedCount > 0 && !hasCapacityForAnotherSend(processedCount, maxQueriesPerSend))
      ) {
        deferredRequests.add(requestItem);
        continue;
      }
      processedCount++;
      Integer queriesBeforeSend = Limits.getQueries();

      try {
        BWM_EmailService.SendResult sendResult;
        if (
          requestItem.triggerPoint == BWM_EmailConstants.TRIGGER_LEAD_CREATE
        ) {
          sendResult = BWM_EmailService.sendForLeadCreate(requestItem.recordId);
        } else {
          sendResult = BWM_EmailService.send(
            requestItem.recordId,
            requestItem.triggerPoint,
            requestItem.stageAtAction
          );
        }
        if (sendResult != null && sendResult.logs != null) {
          logsToInsert.addAll(sendResult.logs);
        }
      } catch (Exception ex) {
        System.debug(
          LoggingLevel.ERROR,
          'BWM_EmailQueueable failed for ' +
            requestItem.recordId +
            ' / ' +
            requestItem.triggerPoint +
            ': ' +
            ex.getMessage()
        );
        Email_Log__c failLog = new Email_Log__c();
        failLog.Related_Record_Id__c = String.valueOf(requestItem.recordId);
        failLog.Trigger_Point__c = requestItem.triggerPoint;
        failLog.Status__c = BWM_EmailConstants.LOG_STATUS_FAILED;
        failLog.Response_Message__c = ex.getMessage();
        if (requestItem.recordId.getSObjectType() == Lead.SObjectType) {
          failLog.Lead__c = requestItem.recordId;
        } else if (
          requestItem.recordId.getSObjectType() == Opportunity.SObjectType
        ) {
          failLog.Opportunity__c = requestItem.recordId;
        }
        logsToInsert.add(failLog);
      }
      maxQueriesPerSend = Math.max(
        maxQueriesPerSend,
        Limits.getQueries() - queriesBeforeSend
      );
    }

    BWM_EmailLogService.insertLogs(logsToInsert);

    lastProcessedCount = processedCount;
    lastDeferredCount = deferredRequests.size();
    lastQueriesUsed = Limits.getQueries();
    System.debug(
      'BWM_EmailQueueable processed ' + processedCount + ', deferred ' +
        lastDeferredCount + ', SOQL used ' + lastQueriesUsed +
        ', heaviest send ' + maxQueriesPerSend
    );
    enqueueDeferred(deferredRequests);
  }

  private static Boolean hasCapacityForAnotherSend(
    Integer processedCount,
    Integer maxQueriesPerSend
  ) {
    Integer queriesNeeded = Math.max(
      SOQL_HEADROOM,
      maxQueriesPerSend + SOQL_SAFETY_MARGIN
    );
    return processedCount < MAX_REQUESTS_PER_JOB &&
      Limits.getQueries() + queriesNeeded < Limits.getLimitQueries() &&
      Limits.getEmailInvocations() < Limits.getLimitEmailInvocations();
  }

  private static void enqueueDeferred(List<BWM_EmailRequest> deferredRequests) {
    if (deferredRequests.isEmpty() || Test.isRunningTest()) {
      return;
    }
    if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
      System.debug(
        LoggingLevel.ERROR,
        'BWM_EmailQueueable could not chain ' + deferredRequests.size() +
          ' remaining email requests: queueable limit reached.'
      );
      return;
    }
    System.enqueueJob(new BWM_EmailQueueable(deferredRequests));
  }
}