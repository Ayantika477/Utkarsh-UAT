/**
 * @description Sends reminder emails when Planned Visit is not completed.
 *              1. 1 Day After Planned Visit → Employee
 *              2. 7 Days After Planned Visit → HOD
 * @author Rani Mate
 * @date 2026-08-17
 */
public without sharing class TaskLogPlannedVisitReminderBatch
    implements Database.Batchable<SObject>{

    public static final String TEMPLATE_EMPLOYEE_1DAY =
        'Planned_Visit_Not_Completed_1786603471519';
    public static final String TEMPLATE_HOD_7DAYS =
        'HOD_7_Days_After_Planned_Visit_1786603879278';
    public static final String ORG_WIDE_SENDER_EMAIL = 'noreply@utkarshindialimited.in';

    // ========== Schedulable ==========
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new TaskLogPlannedVisitReminderBatch(), 50);
    }

    // ========== Batch Start ==========
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date today = Date.today();
        Date oneDayAgo = today.addDays(-1);

        return Database.getQueryLocator([
            SELECT Id, Schedule_Date__c, Visit_Status__c, IsCheckout__c,
                   Punch_Record__c,
                   Punch_Record__r.User__c,
                   Punch_Record__r.User__r.Email,
                   Punch_Record__r.User__r.IsActive,
                   Punch_Record__r.HOD__c,
                   Punch_Record__r.HOD__r.Email,
                   Punch_Record__r.HOD__r.IsActive,
                   OwnerId, Owner.Email, Owner.IsActive
            FROM Task_Log__c
            WHERE Schedule_Date__c != null
            AND Schedule_Date__c <= :oneDayAgo
            AND (Visit_Status__c != 'Completed' OR IsCheckout__c = false)
        ]);
    }

    // ========== Batch Execute ==========
    public void execute(Database.BatchableContext bc, List<Task_Log__c> scope) {
        Date today = Date.today();
        Date oneDayAgo = today.addDays(-1);
        Date sevenDaysAgo = today.addDays(-7);

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();

        System.debug('Total records in scope: ' + scope.size());

        for (Task_Log__c taskLog : scope) {

            // Skip if already completed
            if (taskLog.Visit_Status__c == 'Completed' || taskLog.IsCheckout__c == true) {
                System.debug('Skipping completed record: ' + taskLog.Id);
                continue;
            }

            // ========== 1. 1 Day or more After → Employee ==========
            // Changed from == to <= so old records are also picked
            if (taskLog.Schedule_Date__c <= oneDayAgo) {

                String employeeEmail = null;
                Id employeeUserId = null;

                if (taskLog.Punch_Record__r != null &&
                    taskLog.Punch_Record__r.User__r != null &&
                    String.isNotBlank(taskLog.Punch_Record__r.User__r.Email)) {

                    employeeEmail = taskLog.Punch_Record__r.User__r.Email;
                    if (taskLog.Punch_Record__r.User__r.IsActive == true) {
                        employeeUserId = taskLog.Punch_Record__r.User__c;
                    }
                }
                else if (taskLog.Owner != null && String.isNotBlank(taskLog.Owner.Email)) {
                    employeeEmail = taskLog.Owner.Email;
                    // The owner can be a Queue, which cannot be an email target.
                    if (taskLog.OwnerId.getSObjectType() == User.SObjectType &&
                        taskLog.Owner.IsActive == true) {
                        employeeUserId = taskLog.OwnerId;
                    }
                }

                System.debug('Employee Email for ' + taskLog.Id + ' → ' + employeeEmail);

                if (String.isNotBlank(employeeEmail)) {
                    Messaging.SingleEmailMessage mail = buildMessage(
                        TEMPLATE_EMPLOYEE_1DAY,
                        taskLog.Id,
                        employeeUserId,
                        employeeEmail
                    );
                    if (mail != null) {
                        messages.add(mail);
                    }
                }
            }

            // ========== 2. 7 Days or more After → HOD ==========
            if (taskLog.Schedule_Date__c <= sevenDaysAgo) {

                String hodEmail = null;
                Id hodUserId = null;

                if (taskLog.Punch_Record__r != null &&
                    taskLog.Punch_Record__r.HOD__r != null &&
                    String.isNotBlank(taskLog.Punch_Record__r.HOD__r.Email)) {

                    hodEmail = taskLog.Punch_Record__r.HOD__r.Email;
                    if (taskLog.Punch_Record__r.HOD__r.IsActive == true) {
                        hodUserId = taskLog.Punch_Record__r.HOD__c;
                    }
                }

                System.debug('HOD Email for ' + taskLog.Id + ' → ' + hodEmail);

                if (String.isNotBlank(hodEmail)) {
                    Messaging.SingleEmailMessage mail = buildMessage(
                        TEMPLATE_HOD_7DAYS,
                        taskLog.Id,
                        hodUserId,
                        hodEmail
                    );
                    if (mail != null) {
                        messages.add(mail);
                    }
                }
            }
        }

        System.debug('Total emails to send: ' + messages.size());

        if (!messages.isEmpty()) {
            try {
                Messaging.sendEmail(messages);
                System.debug('Emails sent successfully');
            } catch (Exception e) {
                System.debug('Error while sending emails: ' + e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {}

    // ========== Helper Methods ==========
    // Sends to the User by Id so the email counts as internal (not against the
    // daily external email limit). A User recipient cannot take a WhatId, so the
    // template is rendered against the Task Log first and its content copied over.
    // Without an active User no email is built (email address fallback disabled).
    @TestVisible
    private static Messaging.SingleEmailMessage buildMessage(
        String templateDeveloperName,
        Id recordId,
        Id recipientUserId,
        String recipientEmail
    ) {
        Id templateId = resolveTemplateId(templateDeveloperName);
        if (templateId == null || (recipientUserId == null && String.isBlank(recipientEmail))) {
            System.debug('Template or Email missing. Template: ' + templateDeveloperName);
            return null;
        }

        Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
            templateId,
            null,
            recordId
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
                'TaskLogPlannedVisitReminderBatch: no active User Id for recipient ' + recipientEmail +
                ' - email address fallback is disabled, email not sent.'
            );
            return null;
        }
        message.setSaveAsActivity(false);
        applyOrgWideSender(message);
        return message;
    }

    private static Id resolveTemplateId(String templateDeveloperName) {
        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :templateDeveloperName
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            System.debug('ERROR: Template not found → ' + templateDeveloperName);
            return null;
        }
        return templates[0].Id;
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
        } else {
            System.debug('WARNING: Org-Wide Email not found');
        }
    }
}