trigger CaseTrigger on Case (after insert, after update) {
    List<CaseShare> sharesToInsert = new List<CaseShare>();
    for (Case c : Trigger.new) {
        if (Trigger.isInsert || (Trigger.isUpdate && c.OwnerId != Trigger.oldMap.get(c.Id).OwnerId)) {
            if (c.CreatedById != c.OwnerId) {
                sharesToInsert.add(new CaseShare(
                    CaseId = c.Id,
                    UserOrGroupId = c.CreatedById,
                    CaseAccessLevel = 'Edit',
                    RowCause = 'Manual'
                ));
            }
        }
    }
    if (!sharesToInsert.isEmpty()) {
        Database.insert(sharesToInsert, false);
    }
}