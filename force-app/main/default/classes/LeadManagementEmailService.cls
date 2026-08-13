public with sharing class LeadManagementEmailService {
    public class RenderedEmail {
        public String subject;
        public String plainTextBody;
        public String htmlBody;
    }

    public static RenderedEmail renderTemplate(Id templateId, Lead leadRecord) {
        if (templateId == null || leadRecord == null) {
            return null;
        }

        List<EmailTemplate> templates = [
            SELECT Id, Name
            FROM EmailTemplate
            WHERE Id = :templateId
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            return null;
        }

        BWM_Email_Template_Mapping__mdt mapping = resolveEmailMapping(
            templates[0].Name,
            templateId
        );
        BWM_EmailTemplateRenderer.RenderedEmail rendered = BWM_EmailTemplateRenderer.render(
            mapping,
            leadRecord
        );
        if (rendered == null || !rendered.fromSalesforceTemplate) {
            return null;
        }

        injectProductBrief(rendered, leadRecord);

        RenderedEmail result = new RenderedEmail();
        result.subject = rendered.subject;
        result.plainTextBody = rendered.plainTextBody;
        result.htmlBody = rendered.htmlBody;
        return hasContent(result) ? result : null;
    }

    public static List<Messaging.EmailFileAttachment> buildBrochureAttachments(
        String templateName,
        Lead leadRecord
    ) {
        if (leadRecord == null || String.isBlank(templateName)) {
            return new List<Messaging.EmailFileAttachment>();
        }

        BWM_Email_Template_Mapping__mdt mapping = findEmailMappingByTemplateName(
            templateName
        );
        if (mapping == null) {
            return new List<Messaging.EmailFileAttachment>();
        }

        return BWM_EmailBrochureAttachmentService.buildAttachments(
            BWM_EmailSettingsService.getSettings(),
            mapping,
            leadRecord
        );
    }

    private static BWM_Email_Template_Mapping__mdt resolveEmailMapping(
        String templateName,
        Id templateId
    ) {
        BWM_Email_Template_Mapping__mdt mapping = findEmailMappingByTemplateName(
            templateName
        );
        if (mapping != null) {
            return mapping;
        }

        mapping = new BWM_Email_Template_Mapping__mdt();
        mapping.Template_Id__c = String.valueOf(templateId);
        mapping.Template_Name__c = templateName;
        return mapping;
    }

    private static BWM_Email_Template_Mapping__mdt findEmailMappingByTemplateName(
        String templateName
    ) {
        if (String.isBlank(templateName)) {
            return null;
        }

        String normalizedTarget = normalizeTemplateName(templateName);
        for (BWM_Email_Template_Mapping__mdt row : [
            SELECT
                Template_Name__c,
                Template_Id__c,
                Brochure_Attachment_Mode__c,
                Subject_Template__c,
                Body_Template__c,
                Sender_Type__c,
                Recipient_Type__c,
                Param1_Field__c,
                Param2_Field__c,
                Param3_Field__c,
                Param4_Field__c,
                Param5_Field__c,
                Param6_Field__c
            FROM BWM_Email_Template_Mapping__mdt
            WHERE Is_Active__c = TRUE
        ]) {
            if (normalizeTemplateName(row.Template_Name__c) == normalizedTarget) {
                return row;
            }
        }
        return null;
    }

    private static String normalizeTemplateName(String templateName) {
        return templateName == null
            ? ''
            : templateName.trim().toLowerCase().replace(' ', '_');
    }

    private static void injectProductBrief(
        BWM_EmailTemplateRenderer.RenderedEmail rendered,
        Lead leadRecord
    ) {
        String plainBrief = BWM_EmailProductBriefService.resolvePlainText(leadRecord);
        if (String.isBlank(plainBrief)) {
            return;
        }

        String htmlBrief = BWM_EmailProductBriefService.resolveHtml(leadRecord);
        if (String.isNotBlank(rendered.htmlBody)) {
            rendered.htmlBody = BWM_EmailProductBriefService.injectIntoContent(
                rendered.htmlBody,
                plainBrief,
                htmlBrief,
                leadRecord
            );
        }
        if (String.isNotBlank(rendered.plainTextBody)) {
            rendered.plainTextBody = BWM_EmailProductBriefService.injectIntoContent(
                rendered.plainTextBody,
                plainBrief,
                htmlBrief,
                leadRecord
            );
        }
    }

    private static Boolean hasContent(RenderedEmail rendered) {
        return rendered != null &&
            (String.isNotBlank(rendered.subject) ||
            String.isNotBlank(rendered.htmlBody) ||
            String.isNotBlank(rendered.plainTextBody));
    }
}