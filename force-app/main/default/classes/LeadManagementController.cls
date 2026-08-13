public with sharing class LeadManagementController {
    private static final String LEAD_MANAGEMENT_ORG_WIDE_EMAIL =
        'noreply@utkarshindialimited.in';

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getLeadStatusOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (
            Schema.PicklistEntry entry : Lead.Status.getDescribe().getPicklistValues()
        ) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getLeadLostReasonOptions() {
        return getPicklistOptions(Lead.Lost_Reason__c);
    }

    @AuraEnabled
    public static List<Lead> searchLeads(
        String searchTerm,
        List<String> stages,
        String departmentFilter,
        String campaignFilter,
        List<String> lostReasons,
        Date fromDate,
        Date toDate
    ) {
        String namePattern = String.isNotBlank(searchTerm)
            ? '%' + searchTerm.trim() + '%'
            : null;
        String departmentPattern = String.isNotBlank(departmentFilter)
            ? '%' + departmentFilter.trim() + '%'
            : null;
        String campaignPattern = String.isNotBlank(campaignFilter)
            ? '%' + campaignFilter.trim() + '%'
            : null;
        Datetime toDateTime = toDate == null
            ? null
            : Datetime.newInstance(
                  toDate.year(),
                  toDate.month(),
                  toDate.day(),
                  23,
                  59,
                  59
              );

        String soql =
            'SELECT Id, Name, Status, Email, Phone, Department_Name__c, Lost_Reason__c, Campaign_Name__c, CreatedDate' +
            ' FROM Lead WHERE Id != null AND Status != \'Qualified\'';

        if (namePattern != null) {
            soql += ' AND Name LIKE :namePattern';
        }
        if (stages != null && !stages.isEmpty()) {
            soql += ' AND Status IN :stages';
        }
        if (departmentPattern != null) {
            soql += ' AND Department_Name__c LIKE :departmentPattern';
        }
        if (campaignPattern != null) {
            soql += ' AND Campaign_Name__c LIKE :campaignPattern';
        }
        if (lostReasons != null && !lostReasons.isEmpty()) {
            soql += ' AND Lost_Reason__c IN :lostReasons';
        }
        if (fromDate != null) {
            soql += ' AND CreatedDate >= :fromDate';
        }
        if (toDateTime != null) {
            soql += ' AND CreatedDate <= :toDateTime';
        }

        soql += ' ORDER BY CreatedDate DESC LIMIT 5000';
        return Database.query(soql);
    }

    @AuraEnabled(cacheable=true)
    public static List<Lead> getLeads() {
        return [
            SELECT Id, Name, Status, Email, Phone, Department_Name__c, Lost_Reason__c, Campaign_Name__c, CreatedDate
            FROM Lead
            WHERE Status != 'Qualified'
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled
    public static BWM_CampaignEmailService.SendCampaignEmailResult sendLeadCampaignEmail(
        List<Id> leadIds,
        String infobipTemplateId
    ) {
        try {
            return BWM_CampaignEmailService.sendToLeads(leadIds, infobipTemplateId);
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
    public static BWM_JourneyDefinitionService.SendJourneyResult sendLeadJourney(
        List<Id> leadIds,
        String journeyName
    ) {
        return BWM_CampaignJourneyService.sendToLeads(leadIds, journeyName);
    }

    @AuraEnabled(cacheable=true)
    public static List<EmailTemplateOption> getEmailTemplates() {
        List<EmailTemplateOption> options = new List<EmailTemplateOption>();
        for (EmailTemplate templateRecord : [
            SELECT Id, Name, FolderName
            FROM EmailTemplate
            WHERE IsActive = true
              AND TemplateType = 'custom'
              AND UiType = 'SFX'
            ORDER BY FolderName, Name
        ]) {
            options.add(
                new EmailTemplateOption(
                    templateRecord.Id,
                    templateRecord.Name,
                    templateRecord.FolderName
                )
            );
        }
        return options;
    }

    @AuraEnabled
    public static List<LeadManagementWhatsAppService.WhatsAppTemplateOption> getWhatsAppTemplates() {
        return LeadManagementWhatsAppService.fetchApprovedTemplates();
    }

    @AuraEnabled
    public static LeadManagementWhatsAppService.SendWhatsAppResult sendLeadWhatsApp(
        List<Id> leadIds,
        String templateName
    ) {
        return LeadManagementWhatsAppService.sendToLeads(leadIds, templateName);
    }

    @AuraEnabled
    public static List<LeadManagementRcsService.RcsTemplateOption> getRcsTemplates() {
        return LeadManagementRcsService.fetchApprovedTemplates();
    }

    @AuraEnabled
    public static LeadManagementRcsService.SendRcsResult sendLeadRcs(
        List<Id> leadIds,
        String templateName
    ) {
        return LeadManagementRcsService.sendToLeads(leadIds, templateName);
    }

    @AuraEnabled
    public static List<BWM_SmsTemplateService.SmsTemplateOption> getSmsTemplates() {
        return BWM_SmsTemplateService.fetchApprovedTemplates();
    }

    @AuraEnabled
    public static LeadManagementSmsService.SendSmsResult sendLeadSms(
        List<Id> leadIds,
        String templateName
    ) {
        return LeadManagementSmsService.sendToLeads(leadIds, templateName);
    }

    @AuraEnabled
    public static SendEmailResult sendLeadEmails(List<Id> leadIds, Id templateId) {
        SendEmailResult result = new SendEmailResult();

        if (leadIds == null || leadIds.isEmpty()) {
            throw new AuraHandledException('Select at least one lead.');
        }
        if (templateId == null) {
            throw new AuraHandledException('Select an email template.');
        }

        List<EmailTemplate> selectedTemplates = [
            SELECT Name
            FROM EmailTemplate
            WHERE Id = :templateId
            LIMIT 1
        ];
        String templateName = selectedTemplates.isEmpty() ? null : selectedTemplates[0].Name;

        List<Lead> leads = [
            SELECT Id, Name, Email, OwnerId, Department_Name__c, Product_Category__c
            FROM Lead
            WHERE Id IN :leadIds
        ];

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<String> leadNames = new List<String>();

        for (Lead leadRecord : leads) {
            if (String.isBlank(leadRecord.Email)) {
                result.skippedCount++;
                result.messages.add(leadRecord.Name + ': No email address found on the lead.');
                continue;
            }

            LeadManagementEmailService.RenderedEmail renderedEmail =
                LeadManagementEmailService.renderTemplate(templateId, leadRecord);
            if (renderedEmail == null) {
                result.skippedCount++;
                result.messages.add(
                    leadRecord.Name + ': Could not render the selected email template.'
                );
                continue;
            }

            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setSaveAsActivity(true);
            message.setUseSignature(false);
            message.setToAddresses(new List<String>{ leadRecord.Email.trim() });
            message.setSubject(renderedEmail.subject);
            if (String.isNotBlank(renderedEmail.htmlBody)) {
                message.setHtmlBody(renderedEmail.htmlBody);
            }
            if (String.isNotBlank(renderedEmail.plainTextBody)) {
                message.setPlainTextBody(renderedEmail.plainTextBody);
            }

            List<Messaging.EmailFileAttachment> brochureAttachments =
                LeadManagementEmailService.buildBrochureAttachments(templateName, leadRecord);
            if (!brochureAttachments.isEmpty()) {
                message.setFileAttachments(brochureAttachments);
            }

            message.setTargetObjectId(leadRecord.Id);
            message.setTreatTargetObjectAsRecipient(false);

            applyOrgWideEmail(message);
            messages.add(message);
            leadNames.add(leadRecord.Name);
        }

        if (!messages.isEmpty()) {
            Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(messages, false);
            for (Integer index = 0; index < sendResults.size(); index++) {
                if (sendResults[index].isSuccess()) {
                    result.sentCount++;
                } else {
                    result.skippedCount++;
                    String errorMessage = sendResults[index].getErrors().isEmpty()
                        ? 'Email send failed.'
                        : sendResults[index].getErrors()[0].getMessage();
                    result.messages.add(leadNames[index] + ': ' + errorMessage);
                }
            }
        }

        return result;
    }

    private static void applyOrgWideEmail(Messaging.SingleEmailMessage message) {
        List<OrgWideEmailAddress> rows = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :LEAD_MANAGEMENT_ORG_WIDE_EMAIL
            LIMIT 1
        ];
        if (!rows.isEmpty()) {
            message.setOrgWideEmailAddressId(rows[0].Id);
        }
    }

    private static List<PicklistOption> getPicklistOptions(Schema.SObjectField fieldToken) {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    public class EmailTemplateOption {
        @AuraEnabled
        public Id value;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String folderName;

        public EmailTemplateOption(Id templateId, String templateName, String folder) {
            value = templateId;
            label = templateName;
            folderName = folder;
        }
    }

    public class SendEmailResult {
        @AuraEnabled
        public Integer sentCount = 0;
        @AuraEnabled
        public Integer skippedCount = 0;
        @AuraEnabled
        public List<String> messages = new List<String>();
    }

    public class PicklistOption {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;

        public PicklistOption(String optionLabel, String optionValue) {
            label = optionLabel;
            value = optionValue;
        }
    }
}