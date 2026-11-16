/**
 * InternalTicketVisibilityController
 * Tells the internalTicketHighlightPanel LWC whether the running user is an L3 on any
 * Internal Ticket Matrix row. L3 users get all four ticket actions (status rules still apply).
 */
public with sharing class InternalTicketVisibilityController {

    @AuraEnabled(cacheable=true)
    public static Boolean isMatrixL3() {
        Id userId = UserInfo.getUserId();
        return [
            SELECT COUNT()
            FROM Internal_Ticket_Matrix__c
            WHERE L3__c = :userId
            WITH SYSTEM_MODE
        ] > 0;
    }
}
