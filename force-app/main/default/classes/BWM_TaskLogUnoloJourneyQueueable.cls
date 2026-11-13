/**
 * @description   Queueable job that sends the Unolo client visit journey for Task Logs.
 * @author        Anshita Chanda
 * @date          2026-08-13
 */
public without sharing class BWM_TaskLogUnoloJourneyQueueable implements Queueable, Database.AllowsCallouts {
  // The journey makes one callout per Task Log (limit 100 per transaction), so bulk
  // inserts are sent in groups and the rest is chained to a new job.
  @TestVisible
  private static final Integer MAX_TASK_LOGS_PER_JOB = 50;

  @TestVisible
  private static Integer lastDeferredCount = 0;

  private final List<Id> taskLogIds;

  public BWM_TaskLogUnoloJourneyQueueable(List<Id> taskLogIds) {
    this.taskLogIds = taskLogIds == null
      ? new List<Id>()
      : new List<Id>(taskLogIds);
  }

  public void execute(QueueableContext context) {
    List<Id> currentIds = new List<Id>();
    List<Id> remainingIds = new List<Id>();
    for (Id taskLogId : taskLogIds) {
      if (currentIds.size() < MAX_TASK_LOGS_PER_JOB) {
        currentIds.add(taskLogId);
      } else {
        remainingIds.add(taskLogId);
      }
    }
    lastDeferredCount = remainingIds.size();

    // Journey callout must run before email DML in the same transaction.
    BWM_TaskLogUnoloJourneyService.sendForTaskLogIds(currentIds);
    // Email is independent of WhatsApp/journey success.
    BWM_TaskLogUnoloEmailService.sendForTaskLogIds(currentIds);

    if (!remainingIds.isEmpty() && !Test.isRunningTest()) {
      System.enqueueJob(new BWM_TaskLogUnoloJourneyQueueable(remainingIds));
    }
  }
}