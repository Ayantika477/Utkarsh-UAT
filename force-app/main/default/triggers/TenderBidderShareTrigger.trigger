trigger TenderBidderShareTrigger on Bidders__c (after insert, after update) {
    // Independent toggle - new field on the same mdt type used by the other share triggers.
    Tender_Trigger_Controll__mdt setting =
        Tender_Trigger_Controll__mdt.getInstance('Tender_Share_Trigger');

    if (Trigger.isInsert) {
    // Push notification: Tender User, Dept HOD, CRM Head — "Possible Bidders Identified"
    if (setting != null && setting.Push_Notification_For_Bidder__c) {
        TenderBidderNotificationHandler.notifyNewBidders(Trigger.new);
    }
    
    if (setting != null && setting.Is_Bidder_Share_Active__c) {
        TenderBidderSharingHandler.shareBidders(Trigger.new);
    }
    }

    // L1 Bidder Declared email to Department HOD and CRM Head
    if (Trigger.isInsert) {
        TenderBidderL1EmailHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isUpdate) {
        TenderBidderL1EmailHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}