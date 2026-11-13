/**
 * @description   Tests for OpportunityActivityHandler (Nurture escalation flag reset on activity).
 * @author        Anshita Chanda
 * @date          2026-11-05
 */
@IsTest
private class OpportunityActivityHandlerTest {
  @IsTest
  static void openTaskAndTaskRemovalResetNurtureEscalationFlags() {
    EscalationMatrixTestUtil.prepareTestContext();
    Opportunity opportunityRecord = createNurtureOpportunity('Activity Handler Opp');
    opportunityRecord.Active_Task_Escalation_60_Sent__c = true;
    opportunityRecord.Active_Task_Escalation_72_Sent__c = true;
    update opportunityRecord;

    Test.startTest();
    Task openTask = new Task(
      WhatId = opportunityRecord.Id,
      Subject = 'Follow up',
      Status = 'Open',
      ActivityDate = Date.today().addDays(2)
    );
    insert openTask;
    OpportunityActivityHandler.processTasks(new List<Task>{ openTask });

    Opportunity afterOpenTask = [
      SELECT StageName, Active_Task_Escalation_60_Sent__c, Active_Task_Escalation_72_Sent__c, Last_Open_Task_Activity__c
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    // The 60h flag is reset together with the existing 72/96/120h flags.
    System.assertEquals(
      afterOpenTask.Active_Task_Escalation_72_Sent__c,
      afterOpenTask.Active_Task_Escalation_60_Sent__c,
      '60h flag must follow the same reset as the 72h flag'
    );

    update new Opportunity(
      Id = opportunityRecord.Id,
      Active_Task_Escalation_60_Sent__c = true,
      Active_Task_Escalation_72_Sent__c = true
    );
    delete [SELECT Id FROM Task WHERE WhatId = :opportunityRecord.Id];
    OpportunityActivityHandler.processTasks(new List<Task>{ openTask });
    Test.stopTest();

    Opportunity afterRemoval = [
      SELECT Active_Task_Escalation_60_Sent__c, Active_Task_Escalation_72_Sent__c
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    System.assertEquals(
      afterRemoval.Active_Task_Escalation_72_Sent__c,
      afterRemoval.Active_Task_Escalation_60_Sent__c,
      '60h flag must follow the same reset as the 72h flag'
    );
  }

  @IsTest
  static void futureEventAndRecordlessActivitiesAreHandled() {
    EscalationMatrixTestUtil.prepareTestContext();
    Opportunity opportunityRecord = EscalationMatrixTestUtil.createOpportunity(
      'Nurture',
      'Activity Handler Event Opp',
      false,
      null
    );

    Test.startTest();
    OpportunityActivityHandler.processEvents(
      new List<Event>{
        new Event(WhatId = opportunityRecord.Id, EndDateTime = System.now().addDays(1)),
        new Event(WhatId = opportunityRecord.Id, EndDateTime = System.now().addDays(-1)),
        new Event()
      }
    );
    OpportunityActivityHandler.processTasks(new List<Task>{ new Task(Subject = 'No record') });
    Test.stopTest();

    System.assertEquals(1, [SELECT COUNT() FROM Opportunity WHERE Id = :opportunityRecord.Id]);
  }

  private static Opportunity createNurtureOpportunity(String name) {
    Account accountRecord = new Account(Name = name + ' Account', Phone = '9000000001');
    insert accountRecord;
    Opportunity opportunityRecord = new Opportunity(
      Name = name,
      AccountId = accountRecord.Id,
      StageName = 'Nurture',
      CloseDate = Date.today().addDays(30),
      Budget_Confirmed__c = false,
      Department_Name__c = 'Polymer',
      Customer_Journey__c = 'Direct Business'
    );
    insert opportunityRecord;
    return opportunityRecord;
  }
}