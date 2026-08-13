/**
 * @description   Master schedulable that runs all Escalation Matrix batch jobs hourly.
 * @author        Anshita Chanda
 * @date          2026-08-10
 */
public without sharing class EscalationMatrixScheduler implements Schedulable {
  public void execute(SchedulableContext context) {
    Database.executeBatch(new LeadProspectNotContacted48_96Batch(), 50);
    Database.executeBatch(new LeadProspectingNoActivityBatch(), 50);
    Database.executeBatch(new OpportunityQuotationPendingMatrixBatch(), 50);
    Database.executeBatch(new OpportunityNurtureActiveMatrixBatch(), 50);
    Database.executeBatch(new OpportunityNurtureTenderMatrixBatch(), 50);
    Database.executeBatch(new OpportunityNurtureBudgetaryMatrixBatch(), 50);
    Database.executeBatch(new OpportunityNegotiationActiveMatrixBatch(), 50);
    Database.executeBatch(new OpportunityNegotiationTenderMatrixBatch(), 50);
    Database.executeBatch(new OppNegoBudgetaryMatrixBatch(), 50);
    Database.executeBatch(new TaskOverdueEscalationMatrixBatch(), 50);
  }
}