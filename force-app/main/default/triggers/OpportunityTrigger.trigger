trigger OpportunityTrigger on Opportunity (
    before update,
    after insert,
    after update
) {

    try {

        // BEFORE UPDATE
        if (Trigger.isBefore && Trigger.isUpdate) {
            for (Opportunity opp : Trigger.new) {
                if (opp.isFirstUpdate__c) {
                    opp.isFirstUpdate__c = true;
                }
            }
            //parentopportunitycheck
            ParentProjectOpportunityTriggerHandler.validateParentProjectOpportunity(
                Trigger.new,
                Trigger.oldMap
            );
        }

        // AFTER INSERT
        if (Trigger.isAfter && Trigger.isInsert) {

            BWM_EmailOpportunityTriggerHandler.handleAfterInsert(
                Trigger.new
            );

            BWM_OpportunityMessagingTriggerHandler.handleAfterInsert(
                Trigger.new
            );
        }

        // AFTER UPDATE
        if (Trigger.isAfter && Trigger.isUpdate) {

            BWM_EmailOpportunityTriggerHandler.handleAfterUpdate(
                Trigger.new,
                Trigger.oldMap
            );

            BWM_OpportunityMessagingTriggerHandler.handleAfterUpdate(
                Trigger.new,
                Trigger.oldMap
            );
            
            //For creating notes records //Nasir - 19/07/2026
            OpportunityNotesTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }

    } catch (Exception ex) {
        System.debug(
            LoggingLevel.ERROR,
            'OpportunityTrigger failed: ' + ex.getMessage() +
            '\nStack Trace: ' + ex.getStackTraceString()
        );
    }
}