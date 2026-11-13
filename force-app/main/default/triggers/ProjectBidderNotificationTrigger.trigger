/**
 * Pushes "new bidder added" to the project owner when a Bidders__c record is
 * created on (or re-linked to) a Project__c.
 * Logic in ProjectBidderNotificationTriggerHandler / ProjectNotificationService.
 * Off switch: Trigger_Enable__mdt.ProjectBidderNotificationTrigger (IsEnable__c).
 */
trigger ProjectBidderNotificationTrigger on Bidders__c(
  before insert,
  before update,
  after insert,
  after update
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    ProjectBidderNotificationTriggerHandler.handleBeforeInsert(Trigger.new);
  } else if (Trigger.isBefore && Trigger.isUpdate) {
    ProjectBidderNotificationTriggerHandler.handleBeforeUpdate(Trigger.new);
  } else if (Trigger.isAfter && Trigger.isInsert) {
    ProjectBidderNotificationTriggerHandler.handleAfterInsert(Trigger.new);
  } else if (Trigger.isAfter && Trigger.isUpdate) {
    ProjectBidderNotificationTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
  }
}