/**
 * @description Sends reminder email to HOD when WFH or WFO request 
 *              is pending for more than 7 days, and escalates to HR
 *              when still pending after 15 days.
 * @author Rani Mate
 * @date 2026-08-14
 */
public without sharing class PunchRecordHodPending7DaysBatch 
    implements Database.Batchable<SObject>, Schedulable {

    public static final String PUNCH_TYPE_WFH = 'WFH';
    public static final String PUNCH_TYPE_WFO = 'WFO';
    public static final String APPROVAL_STATUS_PENDING = 'Pending';

    // Templates
    public static final String TEMPLATE_WFH_7DAYS = 'WFH_HOD_Pending_7_Days_1786610858509';
    public static final String TEMPLATE_WFO_7DAYS = 'HOD_Pending_7_Days_1786608257389';

    // ADDED: HR escalation templates (15+ days pending)
    public static final String TEMPLATE_WFH_HR_15DAYS = 'HR_Pending_15_Days_1786608951229';
    public static final String TEMPLATE_WFO_HR_15DAYS = 'WFO_HR_Pending_15_Days_1786611238112';

    // ADDED: 15-day threshold for HR escalation, alongside the existing 7-day HOD threshold
    public static final Integer HR_ESCALATION_DAYS = 15;

    public static final String ORG_WIDE_SENDER_EMAIL = 'noreply@utkarshindialimited.in';

    // ========== Schedulable ==========
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new PunchRecordHodPending7DaysBatch(), 50);
    }

    // ========== Batch Start ==========
    public Database.QueryLocator start(Database.BatchableContext bc) {
        DateTime cutoffDate = System.now().addDays(-7);

        // ADDED: HR_Email_Formula__c selected so the 15-day HR escalation
        // below can read the recipient email directly off the record.
        return Database.getQueryLocator([
            SELECT Id, Punch_Type__c, HOD__c, User__c, CreatedDate, HR_Email_Formula__c
            FROM Punch_Record__c
            WHERE Punch_Type__c IN :new List<String>{ PUNCH_TYPE_WFH, PUNCH_TYPE_WFO }
            AND WFH_Approval_Status__c = :APPROVAL_STATUS_PENDING
            AND HOD__c != null
            AND CreatedDate <= :cutoffDate
        ]);
    }

    // ========== Batch Execute ==========
    public void execute(Database.BatchableContext bc, List<Punch_Record__c> scope) {

        // Collect HOD Ids
        Set<Id> hodIds = new Set<Id>();
        for (Punch_Record__c pr : scope) {
            hodIds.add(pr.HOD__c);
        }

        Map<Id, User> hodsById = new Map<Id, User>([
            SELECT Id, Email, IsActive
            FROM User
            WHERE Id IN :hodIds AND Email != null
        ]);

        // The HR email comes from a formula over HR_Config__mdt, so the record has
        // no HR User Id - match the address to an active User instead.
        Set<String> hrEmails = new Set<String>();
        for (Punch_Record__c pr : scope) {
            if (String.isNotBlank(pr.HR_Email_Formula__c)) {
                hrEmails.add(pr.HR_Email_Formula__c.trim().toLowerCase());
            }
        }
        Map<String, Id> hrUserIdByEmail = resolveActiveUserIdsByEmail(hrEmails);

        // ADDED: cutoff for the 15-day HR escalation, evaluated per record below
        DateTime hrCutoffDate = System.now().addDays(-HR_ESCALATION_DAYS);

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();

        for (Punch_Record__c pr : scope) {

            String templateName;
            if (pr.Punch_Type__c == PUNCH_TYPE_WFH) {
                templateName = TEMPLATE_WFH_7DAYS;
            } else if (pr.Punch_Type__c == PUNCH_TYPE_WFO) {
                templateName = TEMPLATE_WFO_7DAYS;
            } else {
                continue;
            }

            Id templateId = resolveTemplateId(templateName);
            if (templateId == null) continue;

            User hod = hodsById.get(pr.HOD__c);
            if (hod == null || String.isBlank(hod.Email)) continue;

            Messaging.SingleEmailMessage message = buildMessage(
                templateId,
                pr.Id,
                hod.IsActive ? hod.Id : null,
                hod.Email.trim()
            );

            if (message != null) {
                messages.add(message);
            }

            // ADDED: HR escalation once the same record has been pending 15+ days.
            // Independent of the HOD email above - HOD keeps getting notified
            // via the existing logic untouched, HR is an additional recipient.
            if (pr.CreatedDate <= hrCutoffDate) {
                String hrTemplateName;
                if (pr.Punch_Type__c == PUNCH_TYPE_WFH) {
                    hrTemplateName = TEMPLATE_WFH_HR_15DAYS;
                } else {
                    hrTemplateName = TEMPLATE_WFO_HR_15DAYS;
                }

                Id hrTemplateId = resolveTemplateId(hrTemplateName);
                if (hrTemplateId != null && String.isNotBlank(pr.HR_Email_Formula__c)) {
                    Messaging.SingleEmailMessage hrMessage = buildMessage(
                        hrTemplateId,
                        pr.Id,
                        hrUserIdByEmail.get(pr.HR_Email_Formula__c.trim().toLowerCase()),
                        pr.HR_Email_Formula__c.trim()
                    );
                    if (hrMessage != null) {
                        messages.add(hrMessage);
                    }
                }
            }
        }

        if (!messages.isEmpty()) {
            Messaging.sendEmail(messages);
        }
    }

    public void finish(Database.BatchableContext bc) {}

    // ========== Helper Methods ==========
    private static Id resolveTemplateId(String templateDeveloperName) {
        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :templateDeveloperName
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0].Id;
    }

    @TestVisible
    private static Map<String, Id> resolveActiveUserIdsByEmail(Set<String> emails) {
        Map<String, Id> userIdByEmail = new Map<String, Id>();
        if (emails == null || emails.isEmpty()) {
            return userIdByEmail;
        }
        for (User u : [
            SELECT Id, Email
            FROM User
            WHERE IsActive = TRUE
            AND Email IN :emails
            ORDER BY CreatedDate
        ]) {
            String key = u.Email.trim().toLowerCase();
            if (!userIdByEmail.containsKey(key)) {
                userIdByEmail.put(key, u.Id);
            }
        }
        return userIdByEmail;
    }

    // Sends to the User by Id so the email counts as internal (not against the
    // daily external email limit). A User recipient cannot take a WhatId, so the
    // template is rendered against the Punch Record first and its content copied
    // over. Without an active User no email is built (email address fallback disabled).
    @TestVisible
    private static Messaging.SingleEmailMessage buildMessage(
        Id templateId,
        Id punchRecordId,
        Id recipientUserId,
        String recipientEmail
    ) {
        if (
            templateId == null ||
            punchRecordId == null ||
            (recipientUserId == null && String.isBlank(recipientEmail))
        ) {
            return null;
        }

        Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
            templateId,
            null,
            punchRecordId
        );
        Messaging.SingleEmailMessage message;
        if (recipientUserId != null) {
            message = new Messaging.SingleEmailMessage();
            message.setTargetObjectId(recipientUserId);
            message.setSubject(rendered.getSubject());
            if (String.isNotBlank(rendered.getHtmlBody())) {
                message.setHtmlBody(rendered.getHtmlBody());
            }
            if (String.isNotBlank(rendered.getPlainTextBody())) {
                message.setPlainTextBody(rendered.getPlainTextBody());
            }
            if (rendered.getFileAttachments() != null && !rendered.getFileAttachments().isEmpty()) {
                message.setFileAttachments(rendered.getFileAttachments());
            }
            if (rendered.getEntityAttachments() != null && !rendered.getEntityAttachments().isEmpty()) {
                message.setEntityAttachments(rendered.getEntityAttachments());
            }
        } else {
            // Address-based fallback disabled for now - it counts as an external email.
            // message = rendered;
            // message.setToAddresses(new List<String>{ recipientEmail });
            // message.setTreatTargetObjectAsRecipient(false);
            System.debug(
                'PunchRecordHodPending7DaysBatch: no active User Id for recipient ' + recipientEmail +
                ' - email address fallback is disabled, email not sent.'
            );
            return null;
        }
        message.setSaveAsActivity(false);
        applyOrgWideSender(message);
        return message;
    }

    private static void applyOrgWideSender(Messaging.SingleEmailMessage message) {
        List<OrgWideEmailAddress> orgWideAddresses = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_SENDER_EMAIL
            LIMIT 1
        ];
        if (!orgWideAddresses.isEmpty()) {
            message.setOrgWideEmailAddressId(orgWideAddresses[0].Id);
        }
    }
}