trigger TenderShareTrigger on Tender__c (after insert, after update) {

    // Check if trigger is enabled in Custom Metadata
    Tender_Trigger_Controll__mdt  setting = Tender_Trigger_Controll__mdt.getInstance('Tender_Share_Trigger');
    // If metadata exists and trigger is disabled, exit
    if (setting != null && !setting.Is_Active__c) {
        return;
    }

    if (Trigger.isAfter) {

        // On Insert → share all records
        if (Trigger.isInsert) {
            TenderSharingHandler.shareTenders(Trigger.new);
        }

        // On Update → only process records where Department or Owner changed
        if (Trigger.isUpdate) {

            List<Tender__c> tendersToProcess = new List<Tender__c>();

            for (Tender__c newRec : Trigger.new) {
                Tender__c oldRec = Trigger.oldMap.get(newRec.Id);

                if (
                    newRec.Department_Name__c != oldRec.Department_Name__c ||
                    newRec.OwnerId != oldRec.OwnerId
                ) {
                    tendersToProcess.add(newRec);
                }
            }

            if (!tendersToProcess.isEmpty()) {
                TenderSharingHandler.shareTenders(tendersToProcess);
            }
        }
    }
}