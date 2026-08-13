public without sharing class BWM_OpportunityMessagingTriggerHandler {
  private static Set<Id> processedInsertIds = new Set<Id>();

  public static void handleAfterInsert(List<Opportunity> newOpportunities) {
    if (newOpportunities == null || newOpportunities.isEmpty()) {
      return;
    }

    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    if (settings == null || settings.Is_Enabled__c != true) {
      return;
    }

    List<Opportunity> eligible = new List<Opportunity>();
    for (Opportunity opportunityRecord : newOpportunities) {
      if (opportunityRecord == null || opportunityRecord.Id == null) {
        continue;
      }
      if (processedInsertIds.contains(opportunityRecord.Id)) {
        continue;
      }
      processedInsertIds.add(opportunityRecord.Id);
      eligible.add(opportunityRecord);
    }

    if (eligible.isEmpty()) {
      return;
    }

    List<BWM_MessagingRequest> requests = new List<BWM_MessagingRequest>();

    for (Opportunity opportunityRecord : eligible) {
      if (opportunityRecord.StageName == BWM_MessagingConstants.STAGE_NURTURE) {
        requests.add(
          new BWM_MessagingRequest(
            opportunityRecord.Id,
            BWM_MessagingConstants.TRIGGER_OPPORTUNITY_QUALIFY_NURTURE
          )
        );
      }

      if (isDealerEnquiryOpportunity(opportunityRecord)) {
        requests.add(
          new BWM_MessagingRequest(
            opportunityRecord.Id,
            BWM_MessagingConstants.TRIGGER_OPPORTUNITY_DEALER_ENQUIRY
          )
        );
      }

      if (
        opportunityRecord.Customer_Journey__c ==
        BWM_MessagingConstants.CUSTOMER_JOURNEY_REFER_DEALER
      ) {
        requests.add(
          new BWM_MessagingRequest(
            opportunityRecord.Id,
            BWM_MessagingConstants.TRIGGER_OPPORTUNITY_REFER_TO_DEALER
          )
        );
      }
    }

    if (!requests.isEmpty()) {
      BWM_MessagingEnqueueService.enqueue(requests);
    }
  }

  public static void handleAfterUpdate(
    List<Opportunity> newOpportunities,
    Map<Id, Opportunity> oldMap
  ) {
    if (newOpportunities == null || newOpportunities.isEmpty()) {
      return;
    }

    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    if (settings == null || settings.Is_Enabled__c != true) {
      return;
    }

    List<BWM_MessagingRequest> requests = new List<BWM_MessagingRequest>();

    for (Opportunity opportunityRecord : newOpportunities) {
      Opportunity oldRecord = oldMap.get(opportunityRecord.Id);
      if (oldRecord == null) {
        continue;
      }

      if (opportunityRecord.Lost_Reason__c != oldRecord.Lost_Reason__c) {
        String lostTrigger = BWM_MessagingOpportunityLostReasonRouter.resolveTriggerPoint(
          opportunityRecord.StageName,
          oldRecord.StageName,
          opportunityRecord.Lost_Reason__c
        );
        if (String.isNotBlank(lostTrigger)) {
          requests.add(new BWM_MessagingRequest(opportunityRecord.Id, lostTrigger));
        }
      }

      if (
        opportunityRecord.Customer_Journey__c != oldRecord.Customer_Journey__c &&
        opportunityRecord.Customer_Journey__c ==
        BWM_MessagingConstants.CUSTOMER_JOURNEY_REFER_DEALER
      ) {
        requests.add(
          new BWM_MessagingRequest(
            opportunityRecord.Id,
            BWM_MessagingConstants.TRIGGER_OPPORTUNITY_REFER_TO_DEALER
          )
        );
      }
    }

    if (!requests.isEmpty()) {
      BWM_MessagingEnqueueService.enqueue(requests);
    }
  }

  @TestVisible
  private static Boolean isDealerEnquiryOpportunity(Opportunity opportunityRecord) {
    if (opportunityRecord == null) {
      return false;
    }

    if (isDealerRecordType(opportunityRecord.RecordTypeId)) {
      return true;
    }

    if (
      opportunityRecord.Department_Name__c != BWM_MessagingConstants.DEPT_ENQUIRY &&
      !BWM_MessagingConstants.GEN_TOWER_DEPARTMENTS.contains(
        opportunityRecord.Department_Name__c
      )
    ) {
      return false;
    }

    return BWM_MessagingConstants.PHONE_OPPORTUNITY_SOURCES.contains(
        opportunityRecord.LeadSource
      ) ||
      opportunityRecord.LeadSource ==
      BWM_MessagingConstants.OPP_SOURCE_INBOUND_EMAIL;
  }

  @TestVisible
  private static Boolean isDealerRecordType(Id recordTypeId) {
    if (recordTypeId == null) {
      return false;
    }

    Map<Id, Schema.RecordTypeInfo> infos = Schema.SObjectType.Opportunity.getRecordTypeInfosById();
    Schema.RecordTypeInfo info = infos.get(recordTypeId);
    if (info == null) {
      return false;
    }

    String developerName = info.getDeveloperName();
    return String.isNotBlank(developerName) &&
      developerName.toLowerCase().contains('dealer');
  }
}