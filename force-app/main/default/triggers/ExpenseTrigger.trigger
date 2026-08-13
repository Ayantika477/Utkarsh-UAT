/**
 * @description Trigger for Expense__c object
 * Delegates logic to ExpenseTriggerHandler
 * @author Salesforce
 * @date 2026
 */
trigger ExpenseTrigger on Expense__c (before insert, before update, before delete, 
                                      after insert, after update, after delete, after undelete) {
    
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            ExpenseTriggerHandler.beforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            ExpenseTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            ExpenseTriggerHandler.beforeDelete(Trigger.old);
        }
    } else if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            ExpenseTriggerHandler.afterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            ExpenseTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}