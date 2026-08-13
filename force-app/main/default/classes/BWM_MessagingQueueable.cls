public without sharing class BWM_MessagingQueueable implements Queueable, Database.AllowsCallouts {
  private final List<BWM_MessagingRequest> requests;

  public BWM_MessagingQueueable(List<BWM_MessagingRequest> requests) {
    this.requests = requests == null
      ? new List<BWM_MessagingRequest>()
      : new List<BWM_MessagingRequest>(requests);
  }

  public void execute(QueueableContext context) {
    processRequests(requests);
  }

  public static void processRequests(List<BWM_MessagingRequest> requests) {
    if (requests == null || requests.isEmpty()) {
      return;
    }

    List<Message_Log__c> logsToInsert = new List<Message_Log__c>();

    for (BWM_MessagingRequest requestItem : requests) {
      if (requestItem == null || requestItem.recordId == null) {
        continue;
      }

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
      }
    }

    BWM_MessageLogService.insertLogs(logsToInsert);
  }
}