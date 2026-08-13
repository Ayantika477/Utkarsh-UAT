public without sharing class ParentProjectOpportunityTriggerHandler {

    private static final String PROJECT_RECORD_TYPE = 'Project_Opportunity';
    private static final String CLOSED_LOST = 'Closed Lost';

    // Fields allowed to change even when the record is locked
    private static final Set<String> ALLOWED_FIELDS = new Set<String>{
        'stagename',
        'probability', 
        'isclosed',
        'lost_reason__c',
        'stage__c',
        'lost_reason_formula__c',
        'forecastcategory',       
        'forecastcategoryname',
        'LastModifiedDate',
        'LastModifiedById',
        'SystemModstamp'
    };

    public static void validateParentProjectOpportunity(
        List<Opportunity> newList,
        Map<Id, Opportunity> oldMap
    ) {
        
        //metadata_check 
        Trigger_Enable__mdt config = Trigger_Enable__mdt.getInstance('ParentProjectOpportunityTrigger');
        if (config == null || !config.IsEnable__c) {
             System.debug('OpportunityTriggerHandler: trigger disabled via metadata - skipping.');
            return;
        }
        
        
        Id projectRecordTypeId = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(PROJECT_RECORD_TYPE)
            .getRecordTypeId();

        Map<String, Schema.SObjectField> fieldMap =
            Opportunity.SObjectType.getDescribe().fields.getMap();
        
        System.debug('Contains StageName (mixed case)? ' + fieldMap.containsKey('StageName'));
		System.debug('Contains stagename (lowercase)? ' + fieldMap.containsKey('stagename'));

        for (Opportunity opp : newList) {
            Opportunity oldOpp = oldMap.get(opp.Id);

            // Only applies to locked Parent Project Opportunities
            if (oldOpp.RecordTypeId != projectRecordTypeId || !oldOpp.isParent__c) {
                continue;
            }

            // Rule 1: block if any non-allowed field changed
            Boolean otherFieldChanged = false;
            for (String fieldName : fieldMap.keySet()) {
                if (ALLOWED_FIELDS.contains(fieldName.toLowerCase())) {
                    continue;
                }

                Object oldValue = oldOpp.get(fieldName);
                Object newValue = opp.get(fieldName);

                Boolean changed = (oldValue == null)
                    ? newValue != null
                    : !oldValue.equals(newValue);

                if (changed) {
                    otherFieldChanged = true;
                    System.debug('OpportunityTriggerHandler: blocking ' + opp.Id + ' - field changed: ' + fieldName + ' (old: ' + oldValue + ', new: ' + newValue + ')');
                    break;
                }
            }

            if (otherFieldChanged) {
                opp.addError('This Parent Project Opportunity is locked. Only Stage can be changed, and it must be changed to Closed Lost.');
                continue;
            }

            // Rule 2: if Stage changed, it must be to Closed Lost
            if (opp.StageName != oldOpp.StageName && opp.StageName != CLOSED_LOST) {
                System.debug('OpportunityTriggerHandler: blocking ' + opp.Id + ' - Stage changed to "' + opp.StageName + '" instead of Closed Lost');
                opp.addError('This Parent Project Opportunity is locked. Stage can only be changed to Closed Lost.');
            }
        }
    }
}