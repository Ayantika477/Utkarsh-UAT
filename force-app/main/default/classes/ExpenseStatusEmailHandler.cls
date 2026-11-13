/**
 * @description Sends emails to Employee when Expense status changes
 * (Submitted / Approved by HOD / Rejected by HOD / Approved by HR / Rejected by HR /
 * Approved by ED / Rejected by ED)
 * @author Rani Mate
 * @date 2026-08-14
 */
public without sharing class ExpenseStatusEmailHandler {
    // ===== Status Values (Adjust these according to your org) =====
    // Approval by a stage is represented by the move to the next stage's pending status.
    public static final String STATUS_SUBMITTED = 'Pending HOD Approval';
    public static final String STATUS_APPROVED_BY_HOD = 'Pending HR Approval';
    public static final String STATUS_REJECTED_BY_HOD = 'Rejected by HOD';
    public static final String STATUS_APPROVED_BY_HR = 'Pending ED Approval';
    public static final String STATUS_REJECTED_BY_HR = 'Rejected by HR';
    public static final String STATUS_APPROVED_BY_ED = 'Approved by ED';
    public static final String STATUS_REJECTED_BY_ED = 'Rejected by ED';
    // ===== Templates =====
    public static final String TEMPLATE_SUBMITTED =
        'Expense_submitted_Your_expense_claim_has_been_submitte_1786634065001';
    public static final String TEMPLATE_APPROVED_HOD =
        'Expense_approved_by_HOD_Your_expense_claim_has_been_approved_1786634230389';
    public static final String TEMPLATE_REJECTED_HOD =
        'Expense_rejected_by_HOD_Your_expense_claim_has_been_rejected_by_y_1786634318658';
    public static final String TEMPLATE_APPROVED_HR =
        'Expense_approved_by_HR_Your_expense_claim_has_been_approve_1786634464645';
    public static final String TEMPLATE_REJECTED_HR =
        'Expense_rejected_by_HR_Your_expense_claim_has_been_rejected_1786636244825';
    public static final String TEMPLATE_APPROVED_ED =
        'Expense_approved_by_ED_Your_expense_claim_has_been_approved_1791441794563';
    public static final String TEMPLATE_REJECTED_ED =
        'Expense_rejected_by_ED_Your_expense_claim_has_been_rejected_1791441954052';
    // ===== ADDED: HOD / HR approver templates =====
    public static final String TEMPLATE_HOD_NEW_SUBMITTED =
        'New_expense_submitted_Expense_claim_submitted_by_Employee_1786636633300';
    public static final String TEMPLATE_HR_AWAITING_APPROVAL =
        'New_expense_approved_by_HOD_Awaiting_HR_approval_1786637047775';
    public static final String HR_PROFILE_NAME = 'Utkarsh HR';
    // ===== ADDED: ED approver email =====
    public static final String TEMPLATE_ED_AWAITING_APPROVAL =
        'New_expense_approved_by_HR_Awaiting_ED_approval_1793877385710';
    public static final String ED_PROFILE_NAME = 'System Administrator';
    public static final String ED_ROLE_NAME = 'Utkarsh ED';
    public static final String ORG_WIDE_SENDER_EMAIL = 'noreply@utkarshindialimited.in';
    @TestVisible
    private static Id testTemplateIdOverride;
    public static void handleAfterInsert(List<Expense__c> newRecords) {
        processRecords(newRecords, null);
    }
    public static void handleAfterUpdate(
        List<Expense__c> newRecords,
        Map<Id, Expense__c> oldRecordsById
    ) {
        processRecords(newRecords, oldRecordsById);
    }
    @TestVisible
    private static void processRecords(
        List<Expense__c> newRecords,
        Map<Id, Expense__c> oldRecordsById
    ) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }
        Map<String, List<Expense__c>> expensesByTemplate = new Map<String, List<Expense__c>>();
        for (Expense__c exp : newRecords) {
            Expense__c oldExp = oldRecordsById == null ? null : oldRecordsById.get(exp.Id);
            String templateName = getTemplateForStatusChange(exp, oldExp);
            if (templateName == null) {
                continue;
            }
            if (!expensesByTemplate.containsKey(templateName)) {
                expensesByTemplate.put(templateName, new List<Expense__c>());
            }
            expensesByTemplate.get(templateName).add(exp);
        }
        for (String templateName : expensesByTemplate.keySet()) {
            sendEmails(expensesByTemplate.get(templateName), templateName);
        }
        // ADDED: parallel notifications to HOD / HR (employee emails above are untouched).
        sendHodAndHrEmails(newRecords, oldRecordsById);
        // ADDED: separate path - ED approver email on move to Pending ED Approval.
        sendEdEmails(newRecords, oldRecordsById);
    }
    @TestVisible
    private static String getTemplateForStatusChange(Expense__c exp, Expense__c oldExp) {
        if (exp == null || exp.Employee__c == null) {
            return null;
        }
        String newStatus = exp.Status__c;
        String oldStatus = oldExp == null ? null : oldExp.Status__c;
        // Only fire when Status actually changes
        if (newStatus == oldStatus) {
            return null;
        }
        if (newStatus == STATUS_SUBMITTED) {
            return TEMPLATE_SUBMITTED;
        }
        if (newStatus == STATUS_APPROVED_BY_HOD) {
            return TEMPLATE_APPROVED_HOD;
        }
        if (newStatus == STATUS_REJECTED_BY_HOD) {
            return TEMPLATE_REJECTED_HOD;
        }
        if (newStatus == STATUS_APPROVED_BY_HR) {
            return TEMPLATE_APPROVED_HR;
        }
        if (newStatus == STATUS_REJECTED_BY_HR) {
            return TEMPLATE_REJECTED_HR;
        }
        if (newStatus == STATUS_APPROVED_BY_ED) {
            return TEMPLATE_APPROVED_ED;
        }
        if (newStatus == STATUS_REJECTED_BY_ED) {
            return TEMPLATE_REJECTED_ED;
        }
        return null;
    }
    // ADDED
    @TestVisible
    private static void sendHodAndHrEmails(
        List<Expense__c> newRecords,
        Map<Id, Expense__c> oldRecordsById
    ) {
        List<Expense__c> submittedForHod = new List<Expense__c>();
        List<Expense__c> approvedByHodForHr = new List<Expense__c>();
        for (Expense__c exp : newRecords) {
            Expense__c oldExp = oldRecordsById == null ? null : oldRecordsById.get(exp.Id);
            if (qualifiesForHodSubmittedNotification(exp, oldExp)) {
                submittedForHod.add(exp);
            }
            if (qualifiesForHrAwaitingApprovalNotification(exp, oldExp)) {
                approvedByHodForHr.add(exp);
            }
        }
        if (!submittedForHod.isEmpty()) {
            sendFormulaRecipientEmails(
                submittedForHod,
                TEMPLATE_HOD_NEW_SUBMITTED,
                'HOD_User_Email_Formula__c'
            );
        }
        if (!approvedByHodForHr.isEmpty()) {
            sendHrAwaitingApprovalEmails(approvedByHodForHr);
        }
    }
    // ADDED
    @TestVisible
    private static Boolean qualifiesForHodSubmittedNotification(
        Expense__c exp,
        Expense__c oldExp
    ) {
        if (exp == null || exp.Employee__c == null) {
            return false;
        }
        String oldStatus = oldExp == null ? null : oldExp.Status__c;
        return exp.Status__c == STATUS_SUBMITTED && exp.Status__c != oldStatus;
    }
    // ADDED
    @TestVisible
    private static Boolean qualifiesForHrAwaitingApprovalNotification(
        Expense__c exp,
        Expense__c oldExp
    ) {
        if (exp == null || exp.Employee__c == null) {
            return false;
        }
        String oldStatus = oldExp == null ? null : oldExp.Status__c;
        return exp.Status__c == STATUS_APPROVED_BY_HOD && exp.Status__c != oldStatus;
    }
    // ADDED
    private static void sendFormulaRecipientEmails(
        List<Expense__c> expenses,
        String templateDeveloperName,
        String emailFieldApiName
    ) {
        Id templateId = resolveTemplateId(templateDeveloperName);
        if (templateId == null) {
            System.debug('Template not found: ' + templateDeveloperName);
            return;
        }
        Id oweaId = getOrgWideEmailAddressId();
        Set<Id> expenseIds = new Set<Id>();
        for (Expense__c exp : expenses) {
            expenseIds.add(exp.Id);
        }
        String query =
            'SELECT Id, ' +
            emailFieldApiName +
            ' FROM Expense__c WHERE Id IN :expenseIds';
        List<Expense__c> expensesWithDetails = Database.query(query);
        Set<String> recipientEmails = new Set<String>();
        for (Expense__c exp : expensesWithDetails) {
            String recipientEmail = (String) exp.get(emailFieldApiName);
            if (String.isNotBlank(recipientEmail)) {
                recipientEmails.add(recipientEmail.trim().toLowerCase());
            }
        }
        Map<String, Id> userIdByEmail = resolveActiveUserIdsByEmail(recipientEmails);
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Expense__c exp : expensesWithDetails) {
            String recipientEmail = (String) exp.get(emailFieldApiName);
            if (String.isBlank(recipientEmail)) {
                System.debug('Recipient email not resolved for Expense ' + exp.Id);
                continue;
            }
            Messaging.SingleEmailMessage mail = buildFormulaRecipientMessage(
                templateId,
                exp.Id,
                userIdByEmail.get(recipientEmail.trim().toLowerCase()),
                recipientEmail.trim(),
                oweaId
            );
            if (mail != null) {
                messages.add(mail);
            }
        }
        sendMessageBatch(messages, 'Expense HOD');
    }
    // ADDED
    private static void sendHrAwaitingApprovalEmails(List<Expense__c> expenses) {
        Id templateId = resolveTemplateId(TEMPLATE_HR_AWAITING_APPROVAL);
        if (templateId == null) {
            System.debug('HR template not found: ' + TEMPLATE_HR_AWAITING_APPROVAL);
            return;
        }
        List<User> hrUsers = resolveHrRecipients();
        if (hrUsers.isEmpty()) {
            System.debug('No active HR recipients found for profile ' + HR_PROFILE_NAME);
            return;
        }
        Id oweaId = getOrgWideEmailAddressId();
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Expense__c exp : expenses) {
            for (User hrUser : hrUsers) {
                Messaging.SingleEmailMessage mail = buildFormulaRecipientMessage(
                    templateId,
                    exp.Id,
                    hrUser.Id,
                    hrUser.Email.trim(),
                    oweaId
                );
                if (mail != null) {
                    messages.add(mail);
                }
            }
        }
        sendMessageBatch(messages, 'Expense HR');
    }
    // ADDED
    private static List<User> resolveHrRecipients() {
        return [
            SELECT Id, Email
            FROM User
            WHERE IsActive = TRUE
            AND Email != NULL
            AND Profile.Name = :HR_PROFILE_NAME
        ];
    }
    // ADDED
    @TestVisible
    private static void sendEdEmails(
        List<Expense__c> newRecords,
        Map<Id, Expense__c> oldRecordsById
    ) {
        List<Expense__c> approvedByHrForEd = new List<Expense__c>();
        for (Expense__c exp : newRecords) {
            Expense__c oldExp = oldRecordsById == null ? null : oldRecordsById.get(exp.Id);
            if (qualifiesForEdAwaitingApprovalNotification(exp, oldExp)) {
                approvedByHrForEd.add(exp);
            }
        }
        if (!approvedByHrForEd.isEmpty()) {
            sendEdAwaitingApprovalEmails(approvedByHrForEd);
        }
    }
    // ADDED
    @TestVisible
    private static Boolean qualifiesForEdAwaitingApprovalNotification(
        Expense__c exp,
        Expense__c oldExp
    ) {
        if (exp == null || exp.Employee__c == null) {
            return false;
        }
        String oldStatus = oldExp == null ? null : oldExp.Status__c;
        return exp.Status__c == STATUS_APPROVED_BY_HR && exp.Status__c != oldStatus;
    }
    // ADDED
    private static void sendEdAwaitingApprovalEmails(List<Expense__c> expenses) {
        Id templateId = resolveTemplateId(TEMPLATE_ED_AWAITING_APPROVAL);
        if (templateId == null) {
            System.debug('ED template not found: ' + TEMPLATE_ED_AWAITING_APPROVAL);
            return;
        }
        List<User> edUsers = resolveEdRecipients();
        if (edUsers.isEmpty()) {
            System.debug(
                'No active ED recipients found for profile ' + ED_PROFILE_NAME +
                ' with role ' + ED_ROLE_NAME
            );
            return;
        }
        Id oweaId = getOrgWideEmailAddressId();
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Expense__c exp : expenses) {
            for (User edUser : edUsers) {
                Messaging.SingleEmailMessage mail = buildFormulaRecipientMessage(
                    templateId,
                    exp.Id,
                    edUser.Id,
                    edUser.Email.trim(),
                    oweaId
                );
                if (mail != null) {
                    messages.add(mail);
                }
            }
        }
        sendMessageBatch(messages, 'Expense ED');
    }
    // ADDED
    private static List<User> resolveEdRecipients() {
        return [
            SELECT Id, Email
            FROM User
            WHERE IsActive = TRUE
            AND Email != NULL
            AND Profile.Name = :ED_PROFILE_NAME
            AND UserRole.Name = :ED_ROLE_NAME
        ];
    }
    // The HOD email comes from a formula over Department_HOD_Person__mdt, so the
    // Expense has no HOD User Id - match the address to an active User instead.
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
    // ADDED
    private static Messaging.SingleEmailMessage buildFormulaRecipientMessage(
        Id templateId,
        Id expenseId,
        Id recipientUserId,
        String recipientEmail,
        Id oweaId
    ) {
        if (
            templateId == null ||
            expenseId == null ||
            (recipientUserId == null && String.isBlank(recipientEmail))
        ) {
            return null;
        }
        Messaging.SingleEmailMessage rendered;
        try {
            rendered = Messaging.renderStoredEmailTemplate(templateId, null, expenseId);
        } catch (Exception e) {
            System.debug('Template render failed: ' + e.getMessage());
            return null;
        }
        return buildRecipientMessage(rendered, recipientUserId, recipientEmail, oweaId);
    }
    // Sends to the User by Id so the email counts as internal (not against the
    // daily external email limit). A User recipient cannot take a WhatId, so the
    // template is rendered against the Expense first and its content copied over.
    // Without an active User no email is built (email address fallback disabled).
    @TestVisible
    private static Messaging.SingleEmailMessage buildRecipientMessage(
        Messaging.SingleEmailMessage rendered,
        Id recipientUserId,
        String recipientEmail,
        Id oweaId
    ) {
        Messaging.SingleEmailMessage mail;
        if (recipientUserId != null) {
            mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(recipientUserId);
            mail.setSubject(rendered.getSubject());
            if (String.isNotBlank(rendered.getHtmlBody())) {
                mail.setHtmlBody(rendered.getHtmlBody());
            }
            if (String.isNotBlank(rendered.getPlainTextBody())) {
                mail.setPlainTextBody(rendered.getPlainTextBody());
            }
            if (rendered.getFileAttachments() != null && !rendered.getFileAttachments().isEmpty()) {
                mail.setFileAttachments(rendered.getFileAttachments());
            }
            if (rendered.getEntityAttachments() != null && !rendered.getEntityAttachments().isEmpty()) {
                mail.setEntityAttachments(rendered.getEntityAttachments());
            }
        } else {
            // Address-based fallback disabled for now - it counts as an external email.
            // mail = rendered;
            // mail.setTargetObjectId(null);
            // mail.setToAddresses(new List<String>{ recipientEmail });
            // mail.setTreatTargetObjectAsRecipient(false);
            System.debug(
                'ExpenseStatusEmailHandler: no active User Id for recipient ' + recipientEmail +
                ' - email address fallback is disabled, email not sent.'
            );
            return null;
        }
        mail.setSaveAsActivity(false);
        if (oweaId != null) {
            mail.setOrgWideEmailAddressId(oweaId);
        }
        return mail;
    }
    private static void sendEmails(List<Expense__c> expenses, String templateDeveloperName) {
    Id templateId = resolveTemplateId(templateDeveloperName);
    if (templateId == null) {
        System.debug('Template not found: ' + templateDeveloperName);
        return;
    }
    Set<Id> expenseIds = new Set<Id>();
    for (Expense__c exp : expenses) {
        expenseIds.add(exp.Id);
    }
    List<Expense__c> expensesWithDetails = [
        SELECT Id, Employee__c, Employee__r.Email, Employee__r.IsActive, Remark__c
        FROM Expense__c
        WHERE Id IN :expenseIds
        AND Employee__r.Email != null
    ];
    Id oweaId = getOrgWideEmailAddressId();
    List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
    for (Expense__c exp : expensesWithDetails) {
        Messaging.SingleEmailMessage rendered;
        try {
            rendered = Messaging.renderStoredEmailTemplate(
                templateId,
                null, // whoId
                exp.Id // whatId = Expense
            );
        } catch (Exception e) {
            System.debug('Employee template render failed: ' + e.getMessage());
            continue;
        }
        // Inactive users cannot be email targets, so no email is built for them.
        Id employeeUserId = exp.Employee__r.IsActive ? exp.Employee__c : null;
        Messaging.SingleEmailMessage mail =
            buildRecipientMessage(rendered, employeeUserId, exp.Employee__r.Email, oweaId);
        if (mail != null) {
            messages.add(mail);
        }
    }
    sendMessageBatch(messages, 'Expense employee');
}
    // ADDED
    private static void sendMessageBatch(
        List<Messaging.SingleEmailMessage> messages,
        String contextLabel
    ) {
        if (messages.isEmpty()) {
            return;
        }
        try {
            Messaging.sendEmail(messages);
        } catch (Exception e) {
            System.debug('Error sending ' + contextLabel + ' emails: ' + e.getMessage());
        }
    }
    private static Id resolveTemplateId(String developerName) {
        if (Test.isRunningTest() && testTemplateIdOverride != null) {
            return testTemplateIdOverride;
        }
        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0].Id;
    }
    private static Id getOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_SENDER_EMAIL
            LIMIT 1
        ];
        return owea.isEmpty() ? null : owea[0].Id;
    }
}