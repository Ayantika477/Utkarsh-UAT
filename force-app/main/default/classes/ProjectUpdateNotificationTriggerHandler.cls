/**
 * Handler for ProjectUpdateNotificationTrigger (Project__c, after update).
 * Owns the kill-switch check and delegates to ProjectNotificationService.
 */
public without sharing class ProjectUpdateNotificationTriggerHandler {
  public static void handleAfterUpdate(
    List<Project__c> newList,
    Map<Id, Project__c> oldMap
  ) {
    if (!TriggerEnableService.isEnabled(ProjectNotificationService.PROJECT_TRIGGER_SWITCH)) {
      return;
    }
    ProjectNotificationService.notifyFieldChanges(newList, oldMap);
  }
}