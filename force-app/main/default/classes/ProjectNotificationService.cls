/**
 * Push notifications to the Project owner:
 *  - notifyFieldChanges: "<Field(s)> has been updated for '<Project>'" on any field change.
 *  - notifyNewBidders:   "New bidder '<Bidder>' has been added for '<Project>'" when a
 *    Bidders__c record is created on (or re-linked to) a project.
 * Kill switches: Trigger_Enable__mdt records ProjectUpdateNotificationTrigger /
 * ProjectBidderNotificationTrigger via TriggerEnableService (missing record = ON).
 */
public without sharing class ProjectNotificationService {
  public static final String PROJECT_TRIGGER_SWITCH = 'ProjectUpdateNotificationTrigger';
  public static final String BIDDER_TRIGGER_SWITCH = 'ProjectBidderNotificationTrigger';
  private static final String NOTIF_TYPE_DEV_NAME = 'Project_Update_Notification';
  // Custom notification bodies are capped at 750 characters.
  private static final Integer MAX_BODY_LENGTH = 750;

  private static Id notifTypeId;

  private static Id getNotifTypeId() {
    if (notifTypeId == null) {
      List<CustomNotificationType> types = [
        SELECT Id
        FROM CustomNotificationType
        WHERE DeveloperName = :NOTIF_TYPE_DEV_NAME
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!types.isEmpty()) {
        notifTypeId = types[0].Id;
      }
    }
    return notifTypeId;
  }

  /** After update on Project__c: one push per record listing every changed field label. */
  public static void notifyFieldChanges(
    List<Project__c> newList,
    Map<Id, Project__c> oldMap
  ) {
    Id typeId = getNotifTypeId();
    if (typeId == null) {
      return;
    }
    Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Project__c.fields.getMap();

    for (Project__c newRec : newList) {
      Project__c oldRec = oldMap.get(newRec.Id);
      List<String> changedLabels = new List<String>();
      for (String fieldName : fieldMap.keySet()) {
        Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
        // Only user-editable fields: skips formulas, autonumber, and system
        // fields (LastModifiedDate etc.) that change on every save.
        if (!dfr.isUpdateable() || dfr.isCalculated()) {
          continue;
        }
        if (newRec.get(fieldName) != oldRec.get(fieldName)) {
          changedLabels.add(dfr.getLabel());
        }
      }
      if (changedLabels.isEmpty() || newRec.OwnerId == null) {
        continue;
      }
      // Queues/groups cannot receive custom notifications.
      if (String.valueOf(newRec.OwnerId).startsWith('00G')) {
        continue;
      }
      // Don't notify the owner about their own edit.
      if (newRec.OwnerId == UserInfo.getUserId()) {
        continue;
      }
      String fieldList = String.join(changedLabels, ', ');
      String verb = changedLabels.size() == 1 ? 'has been updated' : 'have been updated';
      String body = fieldList + ' ' + verb + ' for \'' + newRec.Name + '\'';
      sendNotification(typeId, 'Project Updated', body, newRec.OwnerId, newRec.Id);
    }
  }

  /**
   * After insert / after update on Bidders__c: push to the project owner when a bidder
   * is added to a project (insert with Project__c set, or Project__c newly set/changed).
   */
  public static void notifyNewBidders(
    List<Bidders__c> newList,
    Map<Id, Bidders__c> oldMap
  ) {
    Id typeId = getNotifTypeId();
    if (typeId == null) {
      return;
    }

    List<Bidders__c> relevant = new List<Bidders__c>();
    Set<Id> projectIds = new Set<Id>();
    for (Bidders__c b : newList) {
      if (b.Project__c == null) {
        continue;
      }
      Boolean isNewLink = oldMap == null ||
        oldMap.get(b.Id).Project__c != b.Project__c;
      if (isNewLink) {
        relevant.add(b);
        projectIds.add(b.Project__c);
      }
    }
    if (relevant.isEmpty()) {
      return;
    }

    Map<Id, Project__c> projects = new Map<Id, Project__c>(
      [SELECT Id, Name, OwnerId FROM Project__c WHERE Id IN :projectIds WITH SYSTEM_MODE]
    );

    for (Bidders__c b : relevant) {
      Project__c proj = projects.get(b.Project__c);
      if (proj == null || proj.OwnerId == null) {
        continue;
      }
      if (String.valueOf(proj.OwnerId).startsWith('00G')) {
        continue;
      }
      String bidderName = String.isBlank(b.Bidder_Name__c) ? b.Name : b.Bidder_Name__c;
      String body = 'New bidder \'' + bidderName + '\' has been added for \'' + proj.Name + '\'';
      // Target the bidder record so the push opens the bidder, not the project.
      sendNotification(typeId, 'New Bidder Added', body, proj.OwnerId, b.Id);
    }
  }

  private static void sendNotification(
    Id typeId,
    String title,
    String body,
    Id recipientId,
    Id targetId
  ) {
    if (body.length() > MAX_BODY_LENGTH) {
      body = body.substring(0, MAX_BODY_LENGTH - 3) + '...';
    }
    try {
      Messaging.CustomNotification notification = new Messaging.CustomNotification();
      notification.setNotificationTypeId(typeId);
      notification.setTitle(title);
      notification.setBody(body);
      notification.setTargetId(targetId);
      notification.send(new Set<String>{ String.valueOf(recipientId) });
    } catch (Exception e) {
      // A notification failure must never block the save.
      System.debug(LoggingLevel.ERROR, 'ProjectNotificationService send failed: ' + e.getMessage());
    }
  }
}