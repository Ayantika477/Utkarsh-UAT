/**
 * @description   Future method fallback dispatcher used when Queueable slots are
 *                exhausted for messaging callouts.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
public without sharing class BWM_MessagingFutureDispatcher {
  @future(callout=true)
  public static void process(String payloadJson) {
    if (String.isBlank(payloadJson)) {
      return;
    }

    List<BWM_MessagingRequest> requests = (List<BWM_MessagingRequest>) JSON.deserialize(
      payloadJson,
      List<BWM_MessagingRequest>.class
    );
    BWM_MessagingQueueable.enqueueDeferred(
      BWM_MessagingQueueable.processRequests(requests)
    );
  }

  public static void dispatch(List<BWM_MessagingRequest> requests) {
    if (requests == null || requests.isEmpty()) {
      return;
    }

    process(JSON.serialize(requests));
  }
}