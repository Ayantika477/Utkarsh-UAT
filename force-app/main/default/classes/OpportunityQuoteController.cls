public with sharing class OpportunityQuoteController {
    @AuraEnabled
    public static DealerOpportunityWhatsAppService.SendWhatsAppResult sendQuoteToCustomer(
        Id opportunityId
    ) {
        DealerOpportunityWhatsAppService.SendWhatsAppResult result =
            OpportunityQuoteJourneyService.sendQuoteToCustomer(opportunityId);

        if (result.sentCount == 0) {
            String message = result.messages.isEmpty()
                ? 'WhatsApp message could not be sent.'
                : String.join(result.messages, ' ');
            throw new AuraHandledException(message);
        }

        return result;
    }
}