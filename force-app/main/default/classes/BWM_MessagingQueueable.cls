/**
 * @description   Queueable job that processes messaging requests with HTTP callouts for
 *                WhatsApp/RCS/SMS journey sends.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
public without sharing class BWM_MessagingQueueable implements Queueable, Database.AllowsCallouts {
  // Each send uses many SOQL queries and callouts, so large request lists (bulk loads)
  // are processed in groups and the rest is chained to a new job.
  @TestVisible
  private static final Integer MAX_REQUESTS_PER_JOB = 10;

  // Minimum queries kept free for the next send and the final Message_Log__c insert;
  // raised to the heaviest send seen in the job plus SOQL_SAFETY_MARGIN.
  @TestVisible
  private static final Integer SOQL_HEADROOM = 40;

  private static final Integer SOQL_SAFETY_MARGIN = 15;

  // Minimum callouts kept free for the next send (WhatsApp, RCS and SMS nodes).
  private static final Integer CALLOUT_HEADROOM = 10;

  @TestVisible
  private static Integer lastProcessedCount = 0;

  @TestVisible
  private static Integer lastDeferredCount = 0;

  private final List<BWM_MessagingRequest> requests;

  public BWM_MessagingQueueable(List<BWM_MessagingRequest> requests) {
    this.requests = requests == null
      ? new List<BWM_MessagingRequest>()
      : new List<BWM_MessagingRequest>(requests);
  }

  public void execute(QueueableContext context) {
    enqueueDeferred(processRequests(requests));
  }

  /**
   * @description Sends as many requests as the transaction limits allow and returns the
   *              requests that were not processed, so the caller can chain them.
   */
  public static List<BWM_MessagingRequest> processRequests(List<BWM_MessagingRequest> requests) {
    List<BWM_MessagingRequest> deferredRequests = new List<BWM_MessagingRequest>();
    lastProcessedCount = 0;
    lastDeferredCount = 0;
    if (requests == null || requests.isEmpty()) {
      return deferredRequests;
    }

    List<Message_Log__c> logsToInsert = new List<Message_Log__c>();
    Integer processedCount = 0;
    Integer maxQueriesPerSend = 0;

    for (BWM_MessagingRequest requestItem : requests) {
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
        BWM_MessagingService.SendResult sendResult;
        if (
          requestItem.triggerPoint == BWM_MessagingConstants.TRIGGER_LEAD_CREATE
        ) {
          sendResult = BWM_MessagingService.sendForLeadCreate(
            requestItem.recordId
          );
        } else {
          sendResult = BWM_MessagingService.send(
            requestItem.recordId,
            requestItem.triggerPoint,
            requestItem.stageAtAction
          );
        }
        logsToInsert.addAll(sendResult.logs);
      } catch (Exception ex) {
        System.debug(
          LoggingLevel.ERROR,
          'BWM messaging failed for ' +
            requestItem.recordId +
            ' / ' +
            requestItem.triggerPoint +
            ': ' +
            ex.getMessage()
        );
        logsToInsert.add(buildFailedExceptionLog(requestItem, ex));
      }
      maxQueriesPerSend = Math.max(
        maxQueriesPerSend,
        Limits.getQueries() - queriesBeforeSend
      );
    }

    BWM_MessageLogService.insertLogs(logsToInsert);

    lastProcessedCount = processedCount;
    lastDeferredCount = deferredRequests.size();
    System.debug(
      'BWM_MessagingQueueable processed ' + processedCount + ', deferred ' +
        lastDeferredCount + ', SOQL used ' + Limits.getQueries() +
        ', heaviest send ' + maxQueriesPerSend
    );
    return deferredRequests;
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
      Limits.getCallouts() + CALLOUT_HEADROOM < Limits.getLimitCallouts();
  }

  /**
   * @description Chains the requests that did not fit in this transaction to a new job.
   */
  public static void enqueueDeferred(List<BWM_MessagingRequest> deferredRequests) {
    if (deferredRequests == null || deferredRequests.isEmpty() || Test.isRunningTest()) {
      return;
    }
    if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
      System.debug(
        LoggingLevel.ERROR,
        'BWM_MessagingQueueable could not chain ' + deferredRequests.size() +
          ' remaining messaging requests: queueable limit reached.'
      );
      return;
    }
    System.enqueueJob(new BWM_MessagingQueueable(deferredRequests));
  }

  /**
   * @description Builds a Failed Message_Log__c so Apex exceptions are visible in
   *              the UI instead of only debug logs.
   */
  @TestVisible
  private static Message_Log__c buildFailedExceptionLog(
    BWM_MessagingRequest requestItem,
    Exception ex
  ) {
    Message_Log__c failedLog = new Message_Log__c();
    failedLog.Related_Record_Id__c = String.valueOf(requestItem.recordId);
    failedLog.Trigger_Point__c = requestItem.triggerPoint;
    failedLog.Channel__c = BWM_MessagingConstants.LOG_CHANNEL_JOURNEY;
    failedLog.Template_Name__c = 'Apex exception';
    failedLog.Status__c = BWM_MessagingConstants.LOG_STATUS_FAILED;
    failedLog.Response_Message__c = formatExceptionMessage(ex);

    Schema.SObjectType recordType = requestItem.recordId.getSObjectType();
    if (recordType == Lead.SObjectType) {
      failedLog.Lead__c = requestItem.recordId;
    } else if (recordType == Opportunity.SObjectType) {
      failedLog.Opportunity__c = requestItem.recordId;
    }

    return failedLog;
  }

  private static String formatExceptionMessage(Exception ex) {
    if (ex == null) {
      return 'Apex exception with no message.';
    }

    String message =
      'Apex exception: ' +
      ex.getTypeName() +
      ': ' +
      ex.getMessage();
    String stackTrace = ex.getStackTraceString();
    if (String.isNotBlank(stackTrace)) {
      message += '\n' + stackTrace;
    }
    if (message.length() > 32000) {
      return message.substring(0, 32000);
    }
    return message;
  }
}