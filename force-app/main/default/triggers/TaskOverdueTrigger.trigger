trigger TaskOverdueTrigger on Task (after insert, after update) {
    TaskOverdueHandler.handleOverdueTasks(Trigger.new, Trigger.oldMap);
}