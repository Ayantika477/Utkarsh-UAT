/**
 * @description   Task overdue escalation emails for owner, 36h HOD, and 96h CRM HOD.
 * @author        Anshita Chanda
 * @date          2026-08-10
 */
public without sharing class TaskOverdueEscalationMatrixBatch implements Database.Batchable<SObject> {
  private static final String TEMPLATE_OWNER = 'Task Overdue Owner';
  private static final String TEMPLATE_36H = 'Task Overdue 36h HOD';
  private static final String TEMPLATE_96H = 'Task Overdue 96h CRM HOD';

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT Id, Subject, Status, ActivityDate, WhatId, WhoId
        FROM Task
        WHERE
          Status != 'Completed'
          AND ActivityDate != NULL
          AND ActivityDate < TODAY
          AND (WhatId != NULL OR WhoId != NULL)
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<Task> scope) {
    Set<Id> opportunityIds = new Set<Id>();
    Set<Id> leadIds = new Set<Id>();

    for (Task taskRecord : scope) {
      if (taskRecord.WhatId != null && String.valueOf(taskRecord.WhatId).startsWith('006')) {
        opportunityIds.add(taskRecord.WhatId);
      }
      if (taskRecord.WhoId != null && String.valueOf(taskRecord.WhoId).startsWith('00Q')) {
        leadIds.add(taskRecord.WhoId);
      }
    }

    Map<Id, Opportunity> opportunityById = queryOpportunities(opportunityIds);
    Map<Id, Lead> leadById = queryLeads(leadIds);
    List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
    List<Lead> leadsToUpdate = new List<Lead>();

    for (Task taskRecord : scope) {
      if (taskRecord.WhatId != null && opportunityById.containsKey(taskRecord.WhatId)) {
        processOpportunityTask(
          taskRecord,
          opportunityById.get(taskRecord.WhatId),
          opportunitiesToUpdate
        );
      } else if (taskRecord.WhoId != null && leadById.containsKey(taskRecord.WhoId)) {
        processLeadTask(taskRecord, leadById.get(taskRecord.WhoId), leadsToUpdate);
      }
    }

    if (!opportunitiesToUpdate.isEmpty()) {
      update opportunitiesToUpdate;
    }
    if (!leadsToUpdate.isEmpty()) {
      update leadsToUpdate;
    }
  }

  public void finish(Database.BatchableContext context) {
  }

  private static void processOpportunityTask(
    Task taskRecord,
    Opportunity opportunityRecord,
    List<Opportunity> opportunitiesToUpdate
  ) {
    Opportunity updateRecord = new Opportunity(Id = opportunityRecord.Id);
    Boolean changed = false;

    if (opportunityRecord.FirstOverdueTaskDate__c == null) {
      updateRecord.FirstOverdueTaskDate__c = System.now();
      updateRecord.OppOverdueEsc36Sent__c = false;
      updateRecord.OppOverdueEsc96Sent__c = false;
      changed = true;

      EscalationMatrixEmailService.sendOpportunityEmail(
        opportunityRecord,
        TEMPLATE_OWNER,
        EscalationMatrixEmailService.RecipientGroup.OWNER
      );
    }

    Datetime firstOverdueDate = changed
      ? updateRecord.FirstOverdueTaskDate__c
      : opportunityRecord.FirstOverdueTaskDate__c;
    Long hoursSinceFirstOverdue = EscalationMatrixEmailService.hoursSince(firstOverdueDate);

    if (
      !opportunityRecord.OppOverdueEsc36Sent__c &&
      hoursSinceFirstOverdue >= 36 &&
      EscalationMatrixEmailService.sendOpportunityEmail(
        opportunityRecord,
        TEMPLATE_36H,
        EscalationMatrixEmailService.RecipientGroup.HOD_ONLY
      )
    ) {
      updateRecord.OppOverdueEsc36Sent__c = true;
      changed = true;
    }

    if (
      !opportunityRecord.OppOverdueEsc96Sent__c &&
      hoursSinceFirstOverdue >= 96 &&
      EscalationMatrixEmailService.sendOpportunityEmail(
        opportunityRecord,
        TEMPLATE_96H,
        EscalationMatrixEmailService.RecipientGroup.CRM_HEAD_ONLY
      )
    ) {
      updateRecord.OppOverdueEsc96Sent__c = true;
      changed = true;
    }

    if (changed) {
      opportunitiesToUpdate.add(updateRecord);
    }
  }

  private static void processLeadTask(
    Task taskRecord,
    Lead leadRecord,
    List<Lead> leadsToUpdate
  ) {
    Lead updateRecord = new Lead(Id = leadRecord.Id);
    Boolean changed = false;

    if (leadRecord.FirstOverdueTaskDate__c == null) {
      updateRecord.FirstOverdueTaskDate__c = System.now();
      updateRecord.LeadOverdueEsc36Sent__c = false;
      updateRecord.LeadOverdueEsc96Sent__c = false;
      changed = true;

      EscalationMatrixEmailService.sendLeadEmail(
        leadRecord,
        TEMPLATE_OWNER,
        EscalationMatrixEmailService.RecipientGroup.OWNER
      );
    }

    Datetime firstOverdueDate = changed
      ? updateRecord.FirstOverdueTaskDate__c
      : leadRecord.FirstOverdueTaskDate__c;
    Long hoursSinceFirstOverdue = EscalationMatrixEmailService.hoursSince(firstOverdueDate);

    if (
      !leadRecord.LeadOverdueEsc36Sent__c &&
      hoursSinceFirstOverdue >= 36 &&
      EscalationMatrixEmailService.sendLeadEmail(
        leadRecord,
        TEMPLATE_36H,
        EscalationMatrixEmailService.RecipientGroup.HOD_ONLY
      )
    ) {
      updateRecord.LeadOverdueEsc36Sent__c = true;
      changed = true;
    }

    if (
      !leadRecord.LeadOverdueEsc96Sent__c &&
      hoursSinceFirstOverdue >= 96 &&
      EscalationMatrixEmailService.sendLeadEmail(
        leadRecord,
        TEMPLATE_96H,
        EscalationMatrixEmailService.RecipientGroup.CRM_HEAD_ONLY
      )
    ) {
      updateRecord.LeadOverdueEsc96Sent__c = true;
      changed = true;
    }

    if (changed) {
      leadsToUpdate.add(updateRecord);
    }
  }

  private static Map<Id, Opportunity> queryOpportunities(Set<Id> opportunityIds) {
    Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>();
    if (opportunityIds.isEmpty()) {
      return opportunityById;
    }

    for (Opportunity opportunityRecord : [
      SELECT
        Id,
        Name,
        OwnerId,
        Owner.Name,
        Owner.Email,
        Department_Name__c,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c,
        FirstOverdueTaskDate__c,
        OppOverdueEsc36Sent__c,
        OppOverdueEsc96Sent__c
      FROM Opportunity
      WHERE Id IN :opportunityIds
    ]) {
      opportunityById.put(opportunityRecord.Id, opportunityRecord);
    }
    return opportunityById;
  }

  private static Map<Id, Lead> queryLeads(Set<Id> leadIds) {
    Map<Id, Lead> leadById = new Map<Id, Lead>();
    if (leadIds.isEmpty()) {
      return leadById;
    }

    for (Lead leadRecord : [
      SELECT
        Id,
        Name,
        OwnerId,
        Owner.Name,
        Owner.Email,
        Department_Name__c,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c,
        FirstOverdueTaskDate__c,
        LeadOverdueEsc36Sent__c,
        LeadOverdueEsc96Sent__c
      FROM Lead
      WHERE Id IN :leadIds
    ]) {
      leadById.put(leadRecord.Id, leadRecord);
    }
    return leadById;
  }
}