/**
 * Handler for ProjectBidderNotificationTrigger (Bidders__c, after insert / after update).
 * Owns the kill-switch check and delegates to ProjectNotificationService.
 */
public without sharing class ProjectBidderNotificationTriggerHandler {
  /**
   * The website/tender integration inserts bidders with Name blank (the platform
   * then stores the record Id as the Name) and puts the real name only in
   * Bidder_Name__c. Copy it over so related lists never show a bare Id.
   * Runs regardless of the notification kill switch: name population must stay
   * on even when pushes are silenced for data loads.
   */
  public static void handleBeforeInsert(List<Bidders__c> newList) {
    for (Bidders__c b : newList) {
      if (String.isBlank(b.Name) && String.isNotBlank(b.Bidder_Name__c)) {
        b.Name = b.Bidder_Name__c.abbreviate(80);
      }
    }
  }

  public static void handleBeforeUpdate(List<Bidders__c> newList) {
    for (Bidders__c b : newList) {
      Boolean nameIsOwnId = b.Name == null ||
        b.Name == String.valueOf(b.Id) ||
        b.Name == String.valueOf(b.Id).left(15);
      if (nameIsOwnId && String.isNotBlank(b.Bidder_Name__c)) {
        b.Name = b.Bidder_Name__c.abbreviate(80);
      }
    }
  }

  public static void handleAfterInsert(List<Bidders__c> newList) {
    run(newList, null);
  }

  public static void handleAfterUpdate(
    List<Bidders__c> newList,
    Map<Id, Bidders__c> oldMap
  ) {
    run(newList, oldMap);
  }

  private static void run(List<Bidders__c> newList, Map<Id, Bidders__c> oldMap) {
    if (!TriggerEnableService.isEnabled(ProjectNotificationService.BIDDER_TRIGGER_SWITCH)) {
      return;
    }
    ProjectNotificationService.notifyNewBidders(newList, oldMap);
  }
}