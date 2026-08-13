trigger LeadProspectingActivityTrigger on Lead (before insert, before update) {

    if(Trigger.isBefore){

        LeadProspectingActivityHandler.updateProspectingActivityDate(Trigger.new,Trigger.oldMap);
    }
}