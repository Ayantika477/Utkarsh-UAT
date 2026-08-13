public with sharing class DealerOpportunityManagementController {
    private static final String DEALER_OPPORTUNITY_ORG_WIDE_EMAIL =
        'noreply@utkarshindialimited.in';

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getOpportunityStageOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (
            Schema.PicklistEntry entry : Opportunity.StageName.getDescribe()
                .getPicklistValues()
        ) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getOpportunityLostReasonOptions() {
        return getPicklistOptions(Opportunity.Lost_Reason__c);
    }

    @AuraEnabled
    public static List<OpportunityListItem> searchDealerOpportunities(
        String searchTerm,
        String dealerAccountFilter,
        List<String> stages,
        String departmentFilter,
        List<String> lostReasons,
        Date fromDate,
        Date toDate
    ) {
        String namePattern = String.isNotBlank(searchTerm)
            ? '%' + searchTerm.trim() + '%'
            : null;
        String dealerPattern = String.isNotBlank(dealerAccountFilter)
            ? '%' + dealerAccountFilter.trim() + '%'
            : null;
        String departmentPattern = String.isNotBlank(departmentFilter)
            ? '%' + departmentFilter.trim() + '%'
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
            'SELECT Id, Name, StageName, Amount, CloseDate, CreatedDate,' +
            ' Department_Name__c, Lost_Reason__c, DealerAccount__r.Name' +
            ' FROM Opportunity WHERE Id != null';

        if (namePattern != null) {
            soql += ' AND Name LIKE :namePattern';
        }
        if (dealerPattern != null) {
            soql += ' AND DealerAccount__r.Name LIKE :dealerPattern';
        }
        if (stages != null && !stages.isEmpty()) {
            soql += ' AND StageName IN :stages';
        }
        if (departmentPattern != null) {
            soql += ' AND Department_Name__c LIKE :departmentPattern';
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
        List<Opportunity> opportunities = Database.query(soql);
        return buildOpportunityListItems(opportunities);
    }

    @AuraEnabled(cacheable=true)
    public static List<OpportunityListItem> getDealerOpportunities() {
        List<Opportunity> opportunities = [
            SELECT
                Id,
                Name,
                StageName,
                Amount,
                CloseDate,
                CreatedDate,
                Department_Name__c,
                Lost_Reason__c,
                DealerAccount__r.Name
            FROM Opportunity
            ORDER BY CreatedDate DESC
        ];

        return buildOpportunityListItems(opportunities);
    }

    private static List<OpportunityListItem> buildOpportunityListItems(
        List<Opportunity> opportunities
    ) {
        Set<Id> opportunityIds = new Set<Id>();
        for (Opportunity opportunityRecord : opportunities) {
            opportunityIds.add(opportunityRecord.Id);
        }

        Map<Id, OpportunityContactRole> primaryContactByOpportunityId =
            queryPrimaryContactsByOpportunityId(opportunityIds);

        List<OpportunityListItem> rows = new List<OpportunityListItem>();
        for (Opportunity opportunityRecord : opportunities) {
            OpportunityListItem row = new OpportunityListItem();
            row.Id = opportunityRecord.Id;
            row.Name = opportunityRecord.Name;
            row.StageName = opportunityRecord.StageName;
            row.Amount = opportunityRecord.Amount;
            row.CloseDate = opportunityRecord.CloseDate;
            row.CreatedDate = opportunityRecord.CreatedDate;
            row.DepartmentName = opportunityRecord.Department_Name__c;
            row.LostReason = opportunityRecord.Lost_Reason__c;
            row.DealerAccountName = opportunityRecord.DealerAccount__r == null
                ? null
                : opportunityRecord.DealerAccount__r.Name;

            OpportunityContactRole primaryContactRole =
                primaryContactByOpportunityId.get(opportunityRecord.Id);
            if (primaryContactRole != null && primaryContactRole.Contact != null) {
                row.PrimaryContactName = primaryContactRole.Contact.Name;
                row.PrimaryContactEmail = primaryContactRole.Contact.Email;
                row.PrimaryContactPhone = String.isNotBlank(
                        primaryContactRole.Contact.Phone
                    )
                    ? primaryContactRole.Contact.Phone
                    : primaryContactRole.Contact.MobilePhone;
            }

            rows.add(row);
        }

        return rows;
    }

    private static Map<Id, OpportunityContactRole> queryPrimaryContactsByOpportunityId(
        Set<Id> opportunityIds
    ) {
        Map<Id, OpportunityContactRole> primaryContactByOpportunityId =
            new Map<Id, OpportunityContactRole>();

        if (opportunityIds.isEmpty()) {
            return primaryContactByOpportunityId;
        }

        for (OpportunityContactRole contactRole : [
            SELECT
                OpportunityId,
                Contact.Name,
                Contact.Email,
                Contact.Phone,
                Contact.MobilePhone
            FROM OpportunityContactRole
            WHERE OpportunityId IN :opportunityIds AND IsPrimary = TRUE
        ]) {
            primaryContactByOpportunityId.put(contactRole.OpportunityId, contactRole);
        }

        return primaryContactByOpportunityId;
    }

    @AuraEnabled
    public static BWM_CampaignEmailService.SendCampaignEmailResult sendOpportunityCampaignEmail(
        List<Id> opportunityIds,
        String infobipTemplateId
    ) {
        try {
            return BWM_CampaignEmailService.sendToOpportunities(
                opportunityIds,
                infobipTemplateId
            );
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
    public static BWM_JourneyDefinitionService.SendJourneyResult sendOpportunityJourney(
        List<Id> opportunityIds,
        String journeyName
    ) {
        return BWM_CampaignJourneyService.sendToOpportunities(
            opportunityIds,
            journeyName
        );
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
    public static List<DealerOpportunityWhatsAppService.WhatsAppTemplateOption> getWhatsAppTemplates() {
        return DealerOpportunityWhatsAppService.fetchApprovedTemplates();
    }

    @AuraEnabled
    public static DealerOpportunityWhatsAppService.SendWhatsAppResult sendOpportunityWhatsApp(
        List<Id> opportunityIds,
        String templateName
    ) {
        return DealerOpportunityWhatsAppService.sendToOpportunities(
            opportunityIds,
            templateName
        );
    }

    @AuraEnabled
    public static List<DealerOpportunityRcsService.RcsTemplateOption> getRcsTemplates() {
        return DealerOpportunityRcsService.fetchApprovedTemplates();
    }

    @AuraEnabled
    public static DealerOpportunityRcsService.SendRcsResult sendOpportunityRcs(
        List<Id> opportunityIds,
        String templateName
    ) {
        return DealerOpportunityRcsService.sendToOpportunities(
            opportunityIds,
            templateName
        );
    }

    @AuraEnabled
    public static List<BWM_SmsTemplateService.SmsTemplateOption> getSmsTemplates() {
        return BWM_SmsTemplateService.fetchApprovedTemplates();
    }

    @AuraEnabled
    public static DealerOpportunitySmsService.SendSmsResult sendOpportunitySms(
        List<Id> opportunityIds,
        String templateName
    ) {
        return DealerOpportunitySmsService.sendToOpportunities(
            opportunityIds,
            templateName
        );
    }

    @AuraEnabled
    public static SendEmailResult sendOpportunityEmails(
        List<Id> opportunityIds,
        Id templateId
    ) {
        SendEmailResult result = new SendEmailResult();

        if (opportunityIds == null || opportunityIds.isEmpty()) {
            throw new AuraHandledException('Select at least one opportunity.');
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

        List<Opportunity> opportunities = [
            SELECT Id, Name, Email__c, ContactId, OwnerId, Department_Name__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];

        Map<Id, List<OpportunityContactRole>> contactRolesByOpportunityId =
            queryContactRolesByOpportunityId(opportunityIds);

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<String> opportunityNames = new List<String>();

        for (Opportunity opportunityRecord : opportunities) {
            List<OpportunityContactRole> contactRoles =
                contactRolesByOpportunityId.get(opportunityRecord.Id);
            List<String> recipientEmails = collectContactRoleEmails(contactRoles);
            if (recipientEmails.isEmpty()) {
                result.skippedCount++;
                result.messages.add(
                    opportunityRecord.Name +
                        ': No email address found on related contact roles.'
                );
                continue;
            }

            Id contactIdForTemplate = resolveContactIdForTemplate(
                contactRoles,
                opportunityRecord
            );

            DealerOpportunityEmailService.RenderedEmail renderedEmail =
                DealerOpportunityEmailService.renderTemplate(
                    templateId,
                    opportunityRecord,
                    contactIdForTemplate
                );
            if (renderedEmail == null) {
                result.skippedCount++;
                result.messages.add(
                    opportunityRecord.Name + ': Could not render the selected email template.'
                );
                continue;
            }

            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setSaveAsActivity(true);
            message.setUseSignature(false);
            message.setToAddresses(recipientEmails);
            message.setSubject(renderedEmail.subject);
            if (String.isNotBlank(renderedEmail.htmlBody)) {
                message.setHtmlBody(renderedEmail.htmlBody);
            }
            if (String.isNotBlank(renderedEmail.plainTextBody)) {
                message.setPlainTextBody(renderedEmail.plainTextBody);
            }

            List<Messaging.EmailFileAttachment> brochureAttachments =
                DealerOpportunityEmailService.buildBrochureAttachments(
                    templateName,
                    opportunityRecord
                );
            if (!brochureAttachments.isEmpty()) {
                message.setFileAttachments(brochureAttachments);
            }

            Id whoId = contactIdForTemplate != null
                ? contactIdForTemplate
                : BWM_EmailTemplateRenderer.resolveWhoId(opportunityRecord);
            if (whoId != null) {
                message.setTargetObjectId(whoId);
                message.setTreatTargetObjectAsRecipient(false);
            }

            Id whatId = BWM_EmailTemplateRenderer.resolveWhatId(opportunityRecord);
            if (whatId != null) {
                message.setWhatId(whatId);
            }

            applyDealerOrgWideEmail(message);
            messages.add(message);
            opportunityNames.add(opportunityRecord.Name);
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
                    result.messages.add(opportunityNames[index] + ': ' + errorMessage);
                }
            }
        }

        return result;
    }

    private static Map<Id, List<OpportunityContactRole>> queryContactRolesByOpportunityId(
        List<Id> opportunityIds
    ) {
        Map<Id, List<OpportunityContactRole>> contactRolesByOpportunityId =
            new Map<Id, List<OpportunityContactRole>>();

        for (OpportunityContactRole contactRole : [
            SELECT OpportunityId, ContactId, IsPrimary, Contact.Email
            FROM OpportunityContactRole
            WHERE OpportunityId IN :opportunityIds
            ORDER BY IsPrimary DESC, CreatedDate ASC
        ]) {
            if (!contactRolesByOpportunityId.containsKey(contactRole.OpportunityId)) {
                contactRolesByOpportunityId.put(
                    contactRole.OpportunityId,
                    new List<OpportunityContactRole>()
                );
            }
            contactRolesByOpportunityId.get(contactRole.OpportunityId).add(contactRole);
        }

        return contactRolesByOpportunityId;
    }

    private static List<String> collectContactRoleEmails(
        List<OpportunityContactRole> contactRoles
    ) {
        List<String> recipientEmails = new List<String>();
        Set<String> uniqueEmails = new Set<String>();

        if (contactRoles == null) {
            return recipientEmails;
        }

        for (OpportunityContactRole contactRole : contactRoles) {
            String emailAddress = contactRole.Contact == null
                ? null
                : contactRole.Contact.Email;
            if (String.isBlank(emailAddress)) {
                continue;
            }

            String normalizedEmail = emailAddress.trim().toLowerCase();
            if (!uniqueEmails.contains(normalizedEmail)) {
                uniqueEmails.add(normalizedEmail);
                recipientEmails.add(emailAddress.trim());
            }
        }

        return recipientEmails;
    }

    private static Id resolveContactIdForTemplate(
        List<OpportunityContactRole> contactRoles,
        Opportunity opportunityRecord
    ) {
        if (contactRoles != null) {
            for (OpportunityContactRole contactRole : contactRoles) {
                if (contactRole.IsPrimary == true && contactRole.ContactId != null) {
                    return contactRole.ContactId;
                }
            }
            for (OpportunityContactRole contactRole : contactRoles) {
                if (
                    contactRole.ContactId != null &&
                    contactRole.Contact != null &&
                    String.isNotBlank(contactRole.Contact.Email)
                ) {
                    return contactRole.ContactId;
                }
            }
        }

        return opportunityRecord.ContactId;
    }

    private static void applyDealerOrgWideEmail(Messaging.SingleEmailMessage message) {
        List<OrgWideEmailAddress> rows = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :DEALER_OPPORTUNITY_ORG_WIDE_EMAIL
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

    public class OpportunityListItem {
        @AuraEnabled
        public Id Id;
        @AuraEnabled
        public String Name;
        @AuraEnabled
        public String StageName;
        @AuraEnabled
        public Decimal Amount;
        @AuraEnabled
        public Date CloseDate;
        @AuraEnabled
        public Datetime CreatedDate;
        @AuraEnabled
        public String DepartmentName;
        @AuraEnabled
        public String LostReason;
        @AuraEnabled
        public String DealerAccountName;
        @AuraEnabled
        public String PrimaryContactName;
        @AuraEnabled
        public String PrimaryContactEmail;
        @AuraEnabled
        public String PrimaryContactPhone;
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