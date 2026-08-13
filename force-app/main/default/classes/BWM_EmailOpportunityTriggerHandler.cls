public without sharing class BWM_EmailOpportunityTriggerHandler {
  private static Set<Id> processedInsertIds = new Set<Id>();

  public static void handleAfterInsert(List<Opportunity> newOpportunities) {
    if (newOpportunities == null || newOpportunities.isEmpty()) {
      return;
    }

    BWM_Email_Settings__mdt settings = BWM_EmailSettingsService.getSettings();
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

    List<BWM_EmailRequest> requests = new List<BWM_EmailRequest>();

    for (Opportunity opportunityRecord : eligible) {
      if (opportunityRecord.StageName == BWM_EmailConstants.STAGE_NURTURE) {
        requests.add(
          new BWM_EmailRequest(
            opportunityRecord.Id,
            BWM_EmailConstants.TRIGGER_OPPORTUNITY_QUALIFY_NURTURE
          )
        );
      }

      if (isDealerEnquiryOpportunity(opportunityRecord)) {
        requests.add(
          new BWM_EmailRequest(
            opportunityRecord.Id,
            BWM_EmailConstants.TRIGGER_OPPORTUNITY_DEALER_ENQUIRY
          )
        );
      }

      if (
        opportunityRecord.Customer_Journey__c ==
        BWM_EmailConstants.CUSTOMER_JOURNEY_REFER_DEALER
      ) {
        requests.add(
          new BWM_EmailRequest(
            opportunityRecord.Id,
            BWM_EmailConstants.TRIGGER_OPPORTUNITY_REFER_TO_DEALER
          )
        );
      }
    }

    if (!requests.isEmpty()) {
      BWM_EmailEnqueueService.enqueue(requests);
    }
  }

  public static void handleAfterUpdate(
    List<Opportunity> newOpportunities,
    Map<Id, Opportunity> oldMap
  ) {
    if (newOpportunities == null || newOpportunities.isEmpty()) {
      return;
    }

    BWM_Email_Settings__mdt settings = BWM_EmailSettingsService.getSettings();
    if (settings == null || settings.Is_Enabled__c != true) {
      return;
    }

    List<BWM_EmailRequest> requests = new List<BWM_EmailRequest>();

    for (Opportunity opportunityRecord : newOpportunities) {
      Opportunity oldRecord = oldMap.get(opportunityRecord.Id);
      if (oldRecord == null) {
        continue;
      }

      addLostReasonChangeRequests(
        requests,
        opportunityRecord,
        oldRecord
      );
      addReferToDealerRequests(requests, opportunityRecord, oldRecord);
    }

    if (!requests.isEmpty()) {
      BWM_EmailEnqueueService.enqueue(requests);
    }
  }

  private static void addLostReasonChangeRequests(
    List<BWM_EmailRequest> requests,
    Opportunity opportunityRecord,
    Opportunity oldRecord
  ) {
    if (opportunityRecord.Lost_Reason__c == oldRecord.Lost_Reason__c) {
      return;
    }
    if (String.isBlank(opportunityRecord.Lost_Reason__c)) {
      return;
    }

    String triggerPoint = BWM_EmailOpportunityLostReasonRouter.resolveTriggerPoint(
      opportunityRecord.StageName,
      oldRecord.StageName,
      opportunityRecord.Lost_Reason__c
    );
    if (String.isNotBlank(triggerPoint)) {
      requests.add(new BWM_EmailRequest(opportunityRecord.Id, triggerPoint));
    }
  }

  private static void addReferToDealerRequests(
    List<BWM_EmailRequest> requests,
    Opportunity opportunityRecord,
    Opportunity oldRecord
  ) {
    if (
      opportunityRecord.Customer_Journey__c == oldRecord.Customer_Journey__c
    ) {
      return;
    }
    if (
      opportunityRecord.Customer_Journey__c !=
      BWM_EmailConstants.CUSTOMER_JOURNEY_REFER_DEALER
    ) {
      return;
    }

    requests.add(
      new BWM_EmailRequest(
        opportunityRecord.Id,
        BWM_EmailConstants.TRIGGER_OPPORTUNITY_REFER_TO_DEALER
      )
    );
  }

  @TestVisible
  private static Boolean isDealerEnquiryOpportunity(Opportunity opportunityRecord) {
    if (opportunityRecord == null) {
      return false;
    }

    if (
      opportunityRecord.Department_Name__c != BWM_EmailConstants.DEPT_ENQUIRY &&
      !BWM_EmailConstants.GEN_TOWER_DEPARTMENTS.contains(
        opportunityRecord.Department_Name__c
      )
    ) {
      return false;
    }

    return BWM_EmailConstants.PHONE_OPPORTUNITY_SOURCES.contains(
        opportunityRecord.LeadSource
      ) ||
      opportunityRecord.LeadSource ==
      BWM_EmailConstants.OPP_SOURCE_INBOUND_EMAIL;
  }
}