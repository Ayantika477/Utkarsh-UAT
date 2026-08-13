public without sharing class DealerOpportunityEmailService {
    private static final Set<String> CORPORATE_BROCHURE_TEMPLATES = new Set<String>{
        'prospect_enq_gen',
        'prospect_not_responding',
        'prospecting_not_responding'
    };

    private static final Set<String> DEPARTMENT_BROCHURE_TEMPLATES = new Set<String>{
        'dealer_enq_dept',
        'u_nurt_not_resp'
    };

    public class RenderedEmail {
        public String subject;
        public String plainTextBody;
        public String htmlBody;
    }

    public static RenderedEmail renderTemplate(
        Id templateId,
        Opportunity opportunityRecord,
        Id whoIdOverride
    ) {
        if (templateId == null || opportunityRecord == null) {
            return null;
        }

        List<EmailTemplate> templates = [
            SELECT Id, Subject, HtmlValue, Body, UiType
            FROM EmailTemplate
            WHERE Id = :templateId
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            return null;
        }

        EmailTemplate templateRecord = templates[0];
        Id whoId = whoIdOverride != null
            ? whoIdOverride
            : BWM_EmailTemplateRenderer.resolveWhoId(opportunityRecord);
        if (whoId == null) {
            return null;
        }

        if (isLightningTemplate(templateRecord)) {
            return renderLightningTemplate(templateRecord, opportunityRecord, whoId);
        }

        try {
            Messaging.SingleEmailMessage renderedMessage = Messaging.renderStoredEmailTemplate(
                templateId,
                whoId,
                BWM_EmailTemplateRenderer.resolveWhatId(opportunityRecord)
            );

            RenderedEmail rendered = new RenderedEmail();
            rendered.subject = renderedMessage.getSubject();
            rendered.plainTextBody = renderedMessage.getPlainTextBody();
            rendered.htmlBody = renderedMessage.getHtmlBody();
            return hasContent(rendered) ? rendered : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Boolean isLightningTemplate(EmailTemplate templateRecord) {
        return templateRecord.UiType == 'SFX' ||
            (String.isNotBlank(templateRecord.HtmlValue) &&
            templateRecord.HtmlValue.contains('{{{'));
    }

    private static RenderedEmail renderLightningTemplate(
        EmailTemplate templateRecord,
        Opportunity opportunityRecord,
        Id whoId
    ) {
        Id whatId = opportunityRecord.Id;
        String subject = convertLightningMergeSyntax(templateRecord.Subject);
        String html = convertLightningMergeSyntax(templateRecord.HtmlValue);
        List<String> bodies = new List<String>();
        Boolean hasSubject = String.isNotBlank(subject);
        Boolean hasHtml = String.isNotBlank(html);

        if (hasSubject) {
            bodies.add(subject);
        }
        if (hasHtml) {
            bodies.add(html);
        }
        if (bodies.isEmpty()) {
            return null;
        }

        List<Messaging.RenderEmailTemplateBodyResult> results = Messaging.renderEmailTemplate(
            String.valueOf(whoId),
            String.valueOf(whatId),
            bodies
        );

        RenderedEmail rendered = new RenderedEmail();
        Integer resultIndex = 0;
        if (hasSubject) {
            if (results[resultIndex].getSuccess()) {
                rendered.subject = results[resultIndex].getMergedBody();
            }
            resultIndex++;
        }
        if (hasHtml && results.size() > resultIndex && results[resultIndex].getSuccess()) {
            rendered.htmlBody = results[resultIndex].getMergedBody();
        }

        return hasContent(rendered) ? rendered : null;
    }

    private static String convertLightningMergeSyntax(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        return value.replaceAll('\\{\\{\\{', '{!').replaceAll('\\}\\}\\}', '}');
    }

    private static Boolean hasContent(RenderedEmail rendered) {
        return rendered != null &&
            (String.isNotBlank(rendered.subject) ||
            String.isNotBlank(rendered.htmlBody) ||
            String.isNotBlank(rendered.plainTextBody));
    }

    public static List<Messaging.EmailFileAttachment> buildBrochureAttachments(
        String templateName,
        Opportunity opportunityRecord
    ) {
        String attachmentMode = resolveBrochureAttachmentMode(templateName);
        if (attachmentMode == null || opportunityRecord == null) {
            return new List<Messaging.EmailFileAttachment>();
        }

        BWM_Email_Template_Mapping__mdt mapping = new BWM_Email_Template_Mapping__mdt(
            Brochure_Attachment_Mode__c = attachmentMode
        );
        return BWM_EmailBrochureAttachmentService.buildAttachments(
            BWM_EmailSettingsService.getSettings(),
            mapping,
            opportunityRecord
        );
    }

    private static String resolveBrochureAttachmentMode(String templateName) {
        if (String.isBlank(templateName)) {
            return null;
        }

        String normalizedName = templateName.trim().toLowerCase();
        if (CORPORATE_BROCHURE_TEMPLATES.contains(normalizedName)) {
            return BWM_EmailConstants.BROCHURE_ATTACH_CORPORATE;
        }
        if (DEPARTMENT_BROCHURE_TEMPLATES.contains(normalizedName)) {
            return BWM_EmailConstants.BROCHURE_ATTACH_DEPARTMENT;
        }
        return null;
    }
}