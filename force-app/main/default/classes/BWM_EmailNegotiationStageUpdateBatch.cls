public without sharing class BWM_EmailNegotiationStageUpdateBatch implements Database.Batchable<SObject>, Schedulable {
  private static final Integer STALE_DAYS = 30;
  private static final Integer DEDUP_DAYS = 28;

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM Opportunity
        WHERE
          IsClosed = FALSE
          AND StageName = :BWM_EmailConstants.STAGE_NEGOTIATION
          AND Sub_Stage__c IN (
            :BWM_EmailConstants.SUB_STAGE_ACTIVE,
            :BWM_EmailConstants.SUB_STAGE_BUDGETARY
          )
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<Opportunity> scope) {
    Set<Id> opportunityIds = new Map<Id, Opportunity>(scope).keySet();
    Map<Id, Boolean> staleById = BWM_EmailOpportunityFieldHistoryService.buildStageStaleMap(
      opportunityIds,
      STALE_DAYS
    );

    List<BWM_EmailRequest> requests = new List<BWM_EmailRequest>();
    for (Opportunity opportunityRecord : scope) {
      if (staleById.get(opportunityRecord.Id) != true) {
        continue;
      }

      if (
        BWM_EmailLogService.hasRecentSentLog(
          opportunityRecord.Id,
          BWM_EmailConstants.TRIGGER_OPPORTUNITY_NEGOTIATION_STALE_30_DAYS,
          DEDUP_DAYS
        )
      ) {
        continue;
      }

      requests.add(
        new BWM_EmailRequest(
          opportunityRecord.Id,
          BWM_EmailConstants.TRIGGER_OPPORTUNITY_NEGOTIATION_STALE_30_DAYS
        )
      );
    }

    if (!requests.isEmpty()) {
      BWM_EmailEnqueueService.enqueue(requests);
    }
  }

  public void finish(Database.BatchableContext context) {
  }

  public void execute(SchedulableContext context) {
    Database.executeBatch(new BWM_EmailNegotiationStageUpdateBatch(), 50);
  }
}