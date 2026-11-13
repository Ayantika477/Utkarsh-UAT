/**
 * @description Batch that sends SLA-breached Case push notifications to CRM Head.
 * @author Anshita Chanda
 * @date 2026-08-17
 */
public without sharing class CaseCrmHeadSlaBreachedPushBatch
  implements Database.Batchable<SObject>, Schedulable {
  private static final Integer BATCH_SIZE = 1;

  // Cases that breached their SLA before this batch was scheduled (30 Oct 2026, 11:15 IST)
  // are not notified, so CRM Heads do not receive a one-off backlog.
  @TestVisible
  private static Datetime notifyBreachesFrom = Datetime.newInstanceGmt(2026, 10, 30, 5, 45, 0);

  public void execute(SchedulableContext context) {
    Database.executeBatch(new CaseCrmHeadSlaBreachedPushBatch(), BATCH_SIZE);
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          CaseNumber,
          Priority,
          CreatedDate,
          First_Response__c,
          IsClosed,
          Department__c,
          Department_formula__c,
          CRM_User_Email_Formula__c,
          SLA_Breached_CRM_Head_Push_Sent__c,
          SLA_Due_Date_Time_RO__c,
          Escalation_Date_1__c,
          Escalation_Date_2__c
        FROM Case
        WHERE
          IsClosed = FALSE
          AND RecordType.DeveloperName = 'Case'
          AND First_Response__c = FALSE
          AND SLA_Breached_CRM_Head_Push_Sent__c = FALSE
          AND Priority IN ('Critical', 'High', 'Medium', 'Low')
          AND (Department__c != NULL OR Department_formula__c != NULL)
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<Case> scope) {
    CaseCrmHeadPushService.processSlaBreached(filterBreachedAfterGoLive(scope));
  }

  @TestVisible
  private static List<Case> filterBreachedAfterGoLive(List<Case> scope) {
    List<Case> eligible = new List<Case>();
    if (scope == null) {
      return eligible;
    }
    for (Case caseRecord : scope) {
      Datetime breachAt = resolveOwnerBreachTime(caseRecord);
      if (breachAt != null && breachAt >= notifyBreachesFrom) {
        eligible.add(caseRecord);
      }
    }
    return eligible;
  }

  // Mirrors CaseSLAEscalationEmailService.isTierDue for the OWNER tier.
  @TestVisible
  private static Datetime resolveOwnerBreachTime(Case caseRecord) {
    if (caseRecord == null) {
      return null;
    }
    if (caseRecord.SLA_Due_Date_Time_RO__c != null) {
      return caseRecord.SLA_Due_Date_Time_RO__c;
    }
    if (caseRecord.CreatedDate == null) {
      return null;
    }
    Integer thresholdHours = CaseSLAEscalationEmailService.getOwnerThresholdHours(caseRecord.Priority);
    return thresholdHours == null ? null : caseRecord.CreatedDate.addHours(thresholdHours);
  }

  public void finish(Database.BatchableContext context) {
  }
}