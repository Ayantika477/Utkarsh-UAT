public without sharing class BWM_EmailMonthlyScheduler implements Schedulable {
  public void execute(SchedulableContext context) {
    if (System.today().day() != 1) {
      return;
    }

    Database.executeBatch(new BWM_EmailDealerMonthlyBatch(), 50);
    Database.executeBatch(new BWM_EmailNegotiationTenderMonthlyBatch(), 50);
    Database.executeBatch(new BWM_EmailNegotiationStageUpdateBatch(), 50);
  }
}