public with sharing class LeadProspectingActivityHandler {

    public static void updateProspectingActivityDate(
        List<Lead> newLeads,
        Map<Id, Lead> oldMap
    ){

        System.debug('===== START LeadProspectingActivityHandler =====');
        System.debug('Total Leads Received: ' + newLeads.size());
        System.debug('Old Map Is Null: ' + (oldMap == null));

        for(Lead ld : newLeads){

            System.debug('----------------------------------------');
            System.debug('Processing Lead Id: ' + ld.Id);
            System.debug('Lead Name: ' + ld.Name);
            System.debug('Current Status: ' + ld.Status);

            if(oldMap == null){

                System.debug('INSERT Operation Detected');

                if(ld.Status == 'Prospecting'){

                    System.debug('Lead inserted with Prospecting status');
                    System.debug('Setting Last_Prospecting_Activity__c to current datetime');

                    ld.Last_Prospecting_Activity__c = System.now();

                    System.debug('Last_Prospecting_Activity__c Updated To: '
                        + ld.Last_Prospecting_Activity__c);
                }
                else{

                    System.debug('Lead inserted but status is not Prospecting');
                    System.debug('No update required');
                }

                continue;
            }

            Lead oldLead = oldMap.get(ld.Id);

            System.debug('UPDATE Operation Detected');
            System.debug('Old Status: ' + oldLead.Status);
            System.debug('New Status: ' + ld.Status);

            if(
                oldLead.Status != 'Prospecting'
                &&
                ld.Status == 'Prospecting'
            ){

                System.debug('Lead moved INTO Prospecting status');

                ld.Last_Prospecting_Activity__c = System.now();

                System.debug('Updated Last_Prospecting_Activity__c: '
                    + ld.Last_Prospecting_Activity__c);

                ld.Prospecting_Escalation_24_Sent__c = false;
                System.debug('Reset Prospecting_Escalation_24_Sent__c to FALSE');

                ld.Prospecting_Escalation_48_Sent__c = false;
                System.debug('Reset Prospecting_Escalation_48_Sent__c to FALSE');

                ld.Prospecting_Escalation_72_Sent__c = false;
                System.debug('Reset Prospecting_Escalation_72_Sent__c to FALSE');
            }

            else if(
                oldLead.Status == 'Prospecting'
                &&
                ld.Status == 'Prospecting'
                &&
                !hasOnlyEscalationChanges(ld, oldLead)
            ){

                System.debug('Lead remains in Prospecting status');
                System.debug('Updating Last_Prospecting_Activity__c');

                ld.Last_Prospecting_Activity__c = System.now();

                System.debug('New Last_Prospecting_Activity__c Value: '
                    + ld.Last_Prospecting_Activity__c);
            }
            else{

                System.debug('No Prospecting status change detected');
                System.debug('No field updates performed');
            }
        }

        System.debug('===== END LeadProspectingActivityHandler =====');
    }

    // Fields written by the escalation / overdue batches. A save that changes only these
    // is not prospecting activity and must not restart the no-activity clock.
    private static final Set<String> ESCALATION_FIELDS = new Set<String>{
        'last_prospecting_activity__c',
        'prospecting_escalation_24_sent__c',
        'prospecting_escalation_48_sent__c',
        'prospecting_escalation_72_sent__c',
        'firstoverduetaskdate__c',
        'leadoverdueesc36sent__c',
        'leadoverdueesc96sent__c',
        'escalation_24_sent__c',
        'escalation_48_sent__c',
        'escalation_72_sent__c',
        'escalation_120_sent__c'
    };

    // Maintained by Salesforce on every save; never a user change.
    private static final Set<String> SYSTEM_FIELDS = new Set<String>{
        'id',
        'isdeleted',
        'name',
        'createddate',
        'createdbyid',
        'lastmodifieddate',
        'lastmodifiedbyid',
        'systemmodstamp',
        'lastactivitydate',
        'lastvieweddate',
        'lastreferenceddate',
        'isunreadbyowner',
        'photourl'
    };

    private static List<String> comparableFieldNames;

    private static List<String> getComparableFieldNames(){
        if(comparableFieldNames == null){
            comparableFieldNames = new List<String>();
            for(Schema.SObjectField field :
                Schema.SObjectType.Lead.fields.getMap().values()){

                // Not based on isUpdateable(): that follows the running user's field-level
                // security, and system-mode automation can change fields the user cannot see.
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                String fieldName = fieldDescribe.getName().toLowerCase();
                Schema.DisplayType fieldType = fieldDescribe.getType();
                if(
                    !fieldDescribe.isCalculated()
                    &&
                    !fieldDescribe.isAutoNumber()
                    &&
                    fieldType != Schema.DisplayType.ADDRESS
                    &&
                    fieldType != Schema.DisplayType.LOCATION
                    &&
                    !SYSTEM_FIELDS.contains(fieldName)
                    &&
                    !ESCALATION_FIELDS.contains(fieldName)
                ){
                    comparableFieldNames.add(fieldName);
                }
            }
        }
        return comparableFieldNames;
    }

    @TestVisible
    private static Boolean hasOnlyEscalationChanges(Lead newLead, Lead oldLead){
        // Read from the populated-field maps: Lead.get() throws for fields that were not loaded.
        Map<String, Object> newValues = toLowerCaseKeys(newLead.getPopulatedFieldsAsMap());
        Map<String, Object> oldValues = toLowerCaseKeys(oldLead.getPopulatedFieldsAsMap());
        for(String fieldName : getComparableFieldNames()){
            if(newValues.get(fieldName) != oldValues.get(fieldName)){
                System.debug('Prospecting activity field changed: ' + fieldName);
                return false;
            }
        }
        System.debug('Only escalation fields changed - Last_Prospecting_Activity__c kept');
        return true;
    }

    private static Map<String, Object> toLowerCaseKeys(Map<String, Object> values){
        Map<String, Object> lowerCased = new Map<String, Object>();
        for(String key : values.keySet()){
            lowerCased.put(key.toLowerCase(), values.get(key));
        }
        return lowerCased;
    }
}