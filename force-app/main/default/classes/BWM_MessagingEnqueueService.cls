public without sharing class BWM_MessagingEnqueueService {
  public static void enqueue(List<BWM_MessagingRequest> requests) {
    if (requests == null || requests.isEmpty()) {
      return;
    }

    if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
      System.enqueueJob(new BWM_MessagingQueueable(requests));
      return;
    }

    BWM_MessagingFutureDispatcher.dispatch(requests);
  }

  public static void enqueueLeadCreate(List<Id> leadIds) {
    List<BWM_MessagingRequest> requests = new List<BWM_MessagingRequest>();
    for (Id leadId : leadIds) {
      requests.add(
        new BWM_MessagingRequest(leadId, BWM_MessagingConstants.TRIGGER_LEAD_CREATE)
      );
    }
    enqueue(requests);
  }

  public static void enqueue(Id recordId, String triggerPoint) {
    enqueue(
      new List<BWM_MessagingRequest>{
        new BWM_MessagingRequest(recordId, triggerPoint)
      }
    );
  }
}