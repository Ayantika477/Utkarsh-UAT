public with sharing class AccountManagementController {
    @AuraEnabled
    public static List<Account> searchAccounts(
        String searchTerm,
        String phoneFilter,
        String emailFilter,
        String departmentFilter
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
        String departmentPattern = String.isNotBlank(departmentFilter)
            ? '%' + departmentFilter.trim() + '%'
            : null;

        String soql =
            'SELECT Id, Name, Phone, Email__c, Department_Name__c, CreatedDate FROM Account WHERE Id != null';
        if (namePattern != null) {
            soql += ' AND Name LIKE :namePattern';
        }
        if (phonePattern != null) {
            soql += ' AND Phone LIKE :phonePattern';
        }
        if (emailPattern != null) {
            soql += ' AND Email__c LIKE :emailPattern';
        }
        if (departmentPattern != null) {
            soql += ' AND Department_Name__c LIKE :departmentPattern';
        }
        soql += ' ORDER BY CreatedDate DESC LIMIT 5000';
        return Database.query(soql);
    }

    @AuraEnabled
    public static BWM_CampaignEmailService.SendCampaignEmailResult sendAccountCampaignEmail(
        List<Id> accountIds,
        String infobipTemplateId
    ) {
        try {
            return BWM_CampaignEmailService.sendToAccounts(accountIds, infobipTemplateId);
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
    public static BWM_JourneyDefinitionService.SendJourneyResult sendAccountJourney(
        List<Id> accountIds,
        String journeyName
    ) {
        return BWM_CampaignJourneyService.sendToAccounts(accountIds, journeyName);
    }

    @AuraEnabled
    public static List<LeadManagementWhatsAppService.WhatsAppTemplateOption> getWhatsAppTemplates() {
        return LeadManagementWhatsAppService.fetchApprovedTemplates();
    }

    @AuraEnabled
    public static LeadManagementWhatsAppService.SendWhatsAppResult sendAccountWhatsApp(
        List<Id> accountIds,
        String templateName
    ) {
        return AccountManagementWhatsAppService.sendToAccounts(accountIds, templateName);
    }

    @AuraEnabled
    public static List<LeadManagementRcsService.RcsTemplateOption> getRcsTemplates() {
        return LeadManagementRcsService.fetchApprovedTemplates();
    }

    @AuraEnabled
    public static AccountManagementRcsService.SendRcsResult sendAccountRcs(
        List<Id> accountIds,
        String templateName
    ) {
        return AccountManagementRcsService.sendToAccounts(accountIds, templateName);
    }

    @AuraEnabled
    public static List<BWM_SmsTemplateService.SmsTemplateOption> getSmsTemplates() {
        return BWM_SmsTemplateService.fetchApprovedTemplates();
    }

    @AuraEnabled
    public static AccountManagementSmsService.SendSmsResult sendAccountSms(
        List<Id> accountIds,
        String templateName
    ) {
        return AccountManagementSmsService.sendToAccounts(accountIds, templateName);
    }
}