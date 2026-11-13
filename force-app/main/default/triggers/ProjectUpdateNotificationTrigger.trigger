/**
 * Pushes "field X has been updated for project Y" to the project owner.
 * Logic in ProjectUpdateNotificationTriggerHandler / ProjectNotificationService.
 * Off switch: Trigger_Enable__mdt.ProjectUpdateNotificationTrigger (IsEnable__c).
 */
trigger ProjectUpdateNotificationTrigger on Project__c(after update) {
  ProjectUpdateNotificationTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
}