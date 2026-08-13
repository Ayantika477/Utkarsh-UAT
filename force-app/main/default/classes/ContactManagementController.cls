public with sharing class ContactManagementController {
    @AuraEnabled
    public static List<Contact> searchContacts(
        String searchTerm,
        String phoneFilter,
        String emailFilter
    ) {
        String namePattern = String.isNotBlank(searchTerm)
            ? '%' + searchTerm.trim() + '%'
            : null;
        String phonePattern = String.isNotBlank(phoneFilter)
            ? '%' + phoneFilter.trim() + '%'
            : null;
        String emailPattern = String.isNotBlank(emailFilter)
            ? '%' + emailFilter.trim() + '%'
            : null;

        String soql =
            'SELECT Id, Name, Email, Phone, MobilePhone, Account.Name, CreatedDate FROM Contact WHERE Id != null';
        if (namePattern != null) {
            soql += ' AND Name LIKE :namePattern';
        }
        if (phonePattern != null) {
            soql += ' AND (Phone LIKE :phonePattern OR MobilePhone LIKE :phonePattern)';
        }
        if (emailPattern != null) {
            soql += ' AND Email LIKE :emailPattern';
        }
        soql += ' ORDER BY CreatedDate DESC LIMIT 5000';
        return Database.query(soql);
    }

    @AuraEnabled
    public static BWM_CampaignEmailService.SendCampaignEmailResult sendContactCampaignEmail(
        List<Id> contactIds,
        String infobipTemplateId
    ) {
        try {
            return BWM_CampaignEmailService.sendToContacts(contactIds, infobipTemplateId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static List<BWM_InfobipEmailTemplateService.TemplateOption> getBluewaveEmailTemplates() {
        try {
            return BWM_InfobipEmailTemplateService.fetchTemplates();
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static List<BWM_JourneyDefinitionService.JourneyOption> getCampaignJourneys() {
        return BWM_JourneyDefinitionService.fetchActiveJourneys();
    }

    @AuraEnabled
    public static BWM_JourneyDefinitionService.SendJourneyResult sendContactJourney(
        List<Id> contactIds,
        String journeyName
    ) {
        return BWM_CampaignJourneyService.sendToContacts(contactIds, journeyName);
    }

    @AuraEnabled
    public static List<LeadManagementWhatsAppService.WhatsAppTemplateOption> getWhatsAppTemplates() {
        return LeadManagementWhatsAppService.fetchApprovedTemplates();
    }

    @AuraEnabled
    public static LeadManagementWhatsAppService.SendWhatsAppResult sendContactWhatsApp(
        List<Id> contactIds,
        String templateName
    ) {
        return ContactManagementWhatsAppService.sendToContacts(contactIds, templateName);
    }

    @AuraEnabled
    public static List<LeadManagementRcsService.RcsTemplateOption> getRcsTemplates() {
        return LeadManagementRcsService.fetchApprovedTemplates();
    }

    @AuraEnabled
    public static ContactManagementRcsService.SendRcsResult sendContactRcs(
        List<Id> contactIds,
        String templateName
    ) {
        return ContactManagementRcsService.sendToContacts(contactIds, templateName);
    }

    @AuraEnabled
    public static List<BWM_SmsTemplateService.SmsTemplateOption> getSmsTemplates() {
        return BWM_SmsTemplateService.fetchApprovedTemplates();
    }

    @AuraEnabled
    public static ContactManagementSmsService.SendSmsResult sendContactSms(
        List<Id> contactIds,
        String templateName
    ) {
        return ContactManagementSmsService.sendToContacts(contactIds, templateName);
    }
}