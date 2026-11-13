/**
 * @description Batch that sends Case 1st-response SLA escalation emails by priority tier.
 * @author Anshita Chanda
 * @date 2026-08-16
 */
public without sharing class CaseSLAEscalationBatch
  implements Database.Batchable<SObject>, Schedulable {
  private static final Integer BATCH_SIZE = 10;

  // Preparing one Case (template render + recipient lookups) uses several SOQL queries;
  // stop preparing when fewer than this many are left. Unprepared Cases are retried next run.
  @TestVisible
  private static final Integer SOQL_HEADROOM_PER_CASE = 25;

  public void execute(SchedulableContext context) {
    Database.executeBatch(new CaseSLAEscalationBatch(), BATCH_SIZE);
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          CaseNumber,
          Priority,
          OwnerId,
          Owner.Email,
          Department__c,
          Department_formula__c,
          CreatedDate,
          First_Response__c,
          IsClosed,
          HOD_User_Email_Formula__c,
          Response_Esc_Owner_Sent__c,
          Response_Esc_HOD_Sent__c,
          Response_Esc_Sir_Sent__c,
          SLA_Due_Date_Time_RO__c,
          Escalation_Date_1__c,
          Escalation_Date_2__c
        FROM Case
        WHERE
          IsClosed = FALSE
          AND RecordType.DeveloperName = 'Case'
          AND First_Response__c = FALSE
          AND Priority IN ('Critical', 'High', 'Medium', 'Low')
          AND (
            Response_Esc_Owner_Sent__c = FALSE
            OR Response_Esc_HOD_Sent__c = FALSE
            OR Response_Esc_Sir_Sent__c = FALSE
          )
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<Case> scope) {
    List<Case> casesToUpdate = processCases(scope);

    if (!casesToUpdate.isEmpty()) {
      // Partial update: one Case with invalid ContactId must not fail the chunk.
      Database.update(casesToUpdate, false);
    }
  }

  public void finish(Database.BatchableContext context) {
  }

  @TestVisible
  private static Case processCase(Case caseRecord) {
    List<Case> updates = processCases(new List<Case>{ caseRecord });
    return updates.isEmpty() ? null : updates[0];
  }

  /**
   * @description Prepares every due escalation in the chunk, sends them together, and
   *              returns the Cases whose sent flags must be set (only for tiers that went out).
   */
  @TestVisible
  private static List<Case> processCases(List<Case> caseRecords) {
    List<CaseSLAEscalationEmailService.PreparedEscalation> escalations =
      new List<CaseSLAEscalationEmailService.PreparedEscalation>();

    for (Case caseRecord : caseRecords) {
      if (caseRecord == null || caseRecord.First_Response__c == true) {
        continue;
      }
      if (Limits.getQueries() + SOQL_HEADROOM_PER_CASE >= Limits.getLimitQueries()) {
        break;
      }
      for (CaseSLAEscalationEmailService.EscalationTier tier : dueUnsentTiers(caseRecord)) {
        CaseSLAEscalationEmailService.PreparedEscalation escalation =
          new CaseSLAEscalationEmailService.PreparedEscalation(caseRecord.Id, tier);
        escalation.messages = CaseSLAEscalationEmailService.prepareEscalationEmail(
          caseRecord,
          tier
        );
        if (!escalation.messages.isEmpty()) {
          escalations.add(escalation);
        }
      }
    }

    Set<String> sentKeys = CaseSLAEscalationEmailService.sendPreparedEscalations(
      escalations
    );

    List<Case> casesToUpdate = new List<Case>();
    for (Case caseRecord : caseRecords) {
      if (caseRecord == null) {
        continue;
      }
      Case updateRecord = new Case(Id = caseRecord.Id);
      Boolean changed = false;
      if (isSent(sentKeys, caseRecord, CaseSLAEscalationEmailService.EscalationTier.OWNER)) {
        updateRecord.Response_Esc_Owner_Sent__c = true;
        changed = true;
      }
      if (isSent(sentKeys, caseRecord, CaseSLAEscalationEmailService.EscalationTier.HOD)) {
        updateRecord.Response_Esc_HOD_Sent__c = true;
        changed = true;
      }
      if (isSent(sentKeys, caseRecord, CaseSLAEscalationEmailService.EscalationTier.SIR)) {
        updateRecord.Response_Esc_Sir_Sent__c = true;
        changed = true;
      }
      if (changed) {
        casesToUpdate.add(updateRecord);
      }
    }
    return casesToUpdate;
  }

  private static List<CaseSLAEscalationEmailService.EscalationTier> dueUnsentTiers(
    Case caseRecord
  ) {
    List<CaseSLAEscalationEmailService.EscalationTier> tiers =
      new List<CaseSLAEscalationEmailService.EscalationTier>();
    if (
      caseRecord.Response_Esc_Owner_Sent__c != true &&
      CaseSLAEscalationEmailService.isTierDue(
        caseRecord,
        CaseSLAEscalationEmailService.EscalationTier.OWNER
      )
    ) {
      tiers.add(CaseSLAEscalationEmailService.EscalationTier.OWNER);
    }
    if (
      caseRecord.Response_Esc_HOD_Sent__c != true &&
      CaseSLAEscalationEmailService.isTierDue(
        caseRecord,
        CaseSLAEscalationEmailService.EscalationTier.HOD
      )
    ) {
      tiers.add(CaseSLAEscalationEmailService.EscalationTier.HOD);
    }
    if (
      caseRecord.Response_Esc_Sir_Sent__c != true &&
      CaseSLAEscalationEmailService.isTierDue(
        caseRecord,
        CaseSLAEscalationEmailService.EscalationTier.SIR
      )
    ) {
      tiers.add(CaseSLAEscalationEmailService.EscalationTier.SIR);
    }
    return tiers;
  }

  private static Boolean isSent(
    Set<String> sentKeys,
    Case caseRecord,
    CaseSLAEscalationEmailService.EscalationTier tier
  ) {
    return sentKeys.contains(
      CaseSLAEscalationEmailService.buildEscalationKey(caseRecord.Id, tier)
    );
  }
}