/**
 * @description Sends emails to the Opportunity Owner (Employee/Sales User) when
 *              an Opportunity is assigned, or when L1 Bidder is declared.
 *              Department_*_Person__mdt is not used. When the formula email is
 *              blank, the department role (<Department> HOD / <Department> CRM User) is used.
 *              Owner emails are INTERNAL (target = User) for active Standard owners;
 *              inactive or non-Standard owners fall back to an external To address.
 * @author Rani Mate
 * @date 2026-08-14
 *
 */
public without sharing class OpportunityAssignmentEmailHandler {
    // ===== Stage value for L1 Bidder Declared (adjust if this is a custom field instead) =====
    // COMMENTED OUT (not required): L1 Bidder Declared
    // public static final String STAGE_L1_BIDDER_DECLARED = 'L1 Bidder Declared';
    // ===== Templates (DeveloperName) =====
    public static final String TEMPLATE_NEW_OPPORTUNITY_ASSIGNED =
        'New_Project_Opportunity_Assigned_1786616028589';
    // COMMENTED OUT (not required): Owner L1 Bidder Declared template
    // public static final String TEMPLATE_L1_BIDDER_DECLARED =
    //     'L1_Bidder_Declared_1786616437038';
    public static final String ORG_WIDE_SENDER_EMAIL = 'noreply@utkarshindialimited.in';
    // ===== ADDED: Department CRM Head templates (DeveloperName) =====
    // "Created" now goes out ONCE A DAY (digest), see ProjectOpportunityCreatedDigestBatch.
    public static final String TEMPLATE_CRM_HEAD_OPPORTUNITY_CREATED =
        'Project_Opportunity_Created_1786620843232';
    // COMMENTED OUT (not required): CRM Head L1 Bidder Declared template
    // public static final String TEMPLATE_CRM_HEAD_L1_BIDDER_DECLARED =
    //     'L1_Bidder_Declared_Confirmed_Opportunity_1786621328010';
    // "Created" now goes out ONCE A DAY (digest), see ProjectOpportunityCreatedDigestBatch.
    public static final String TEMPLATE_HOD_PROJECT_CREATED =
        'New_Project_Opportunity_Created_1786620185112';
    // COMMENTED OUT (not required): HOD L1 Bidder Declared template
    // public static final String TEMPLATE_HOD_L1_BIDDER_DECLARED =
    //     'L1_Bidder_Declared_1786620559286';
    public static final String PROJECT_RECORD_TYPE_DEVELOPER_NAME = 'Project_Opportunity';

    // true => if the recipient email matches no active User, try the department role
    // (<Department> HOD / <Department> CRM User). Set false to disable the role fallback.
    private static final Boolean USE_ROLE_FALLBACK = true;

    private static Id projectRecordTypeId;
    // role name -> email of the first active Standard user in that role (null = none)
    private static Map<String, String> roleEmailCache = new Map<String, String>();
    @TestVisible
    private static Id testTemplateIdOverride;
    public static void handleAfterInsert(List<Opportunity> newRecords) {
        processRecords(newRecords, null);
    }
    public static void handleAfterUpdate(
        List<Opportunity> newRecords,
        Map<Id, Opportunity> oldRecordsById
    ) {
        processRecords(newRecords, oldRecordsById);
    }
    @TestVisible
    private static void processRecords(
        List<Opportunity> newRecords,
        Map<Id, Opportunity> oldRecordsById
    ) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }
        Boolean isInsert = oldRecordsById == null;
        Map<String, List<Opportunity>> oppsByTemplate = new Map<String, List<Opportunity>>();
        for (Opportunity opp : newRecords) {
            // Only Project Opportunity
            if (!isProjectOpportunity(opp)) {
                continue;
            }
            Opportunity oldOpp = isInsert ? null : oldRecordsById.get(opp.Id);
            String templateName = getTemplateForChange(opp, oldOpp, isInsert);
            if (templateName == null) {
                continue;
            }
            if (!oppsByTemplate.containsKey(templateName)) {
                oppsByTemplate.put(templateName, new List<Opportunity>());
            }
            oppsByTemplate.get(templateName).add(opp);
        }
        List<EmailSendRequest> emailSendRequests = new List<EmailSendRequest>();
        for (String templateName : oppsByTemplate.keySet()) {
            emailSendRequests.add(
                new EmailSendRequest('OWNER', oppsByTemplate.get(templateName), templateName)
            );
        }
        // COMMENTED OUT: CRM Head and HOD notifications from the trigger.
        //  - "Project Opportunity Created" (CRM Head + HOD): now sent ONCE A DAY, one
        //    consolidated email per recipient, by ProjectOpportunityCreatedDigestBatch.
        //  - "L1 Bidder Declared" (CRM Head + HOD): not required.
        /*
        // ADDED: parallel notification to the Department CRM Head.
        // Detected separately (not reused from oppsByTemplate) because
        // "Created" must exclude reassignments, which share
        // TEMPLATE_NEW_OPPORTUNITY_ASSIGNED with inserts in the branch above.
        List<Opportunity> createdOpportunities = new List<Opportunity>();
        List<Opportunity> l1BidderDeclaredOpportunities = new List<Opportunity>();
        for (Opportunity opp : newRecords) {
            // Only Project Opportunity
            if (!isProjectOpportunity(opp)) {
                continue;
            }
            Opportunity oldOpp = isInsert ? null : oldRecordsById.get(opp.Id);
            if (isInsert && opp.OwnerId != null) {
                createdOpportunities.add(opp);
            }
            if (qualifiesAsL1BidderDeclared(opp, oldOpp)) {
                l1BidderDeclaredOpportunities.add(opp);
            }
        }
        if (!createdOpportunities.isEmpty()) {
            emailSendRequests.add(
                new EmailSendRequest(
                    'CRM_HEAD',
                    createdOpportunities,
                    TEMPLATE_CRM_HEAD_OPPORTUNITY_CREATED
                )
            );
        }
        if (!l1BidderDeclaredOpportunities.isEmpty()) {
            emailSendRequests.add(
                new EmailSendRequest(
                    'CRM_HEAD',
                    l1BidderDeclaredOpportunities,
                    TEMPLATE_CRM_HEAD_L1_BIDDER_DECLARED
                )
            );
        }
        // ADDED: parallel notification to the Department HOD (Project record type only).
        List<Opportunity> projectCreatedOpportunities = filterProjectOpportunities(
            createdOpportunities
        );
        List<Opportunity> projectL1Opportunities = filterProjectOpportunities(
            l1BidderDeclaredOpportunities
        );
        if (!projectCreatedOpportunities.isEmpty()) {
            emailSendRequests.add(
                new EmailSendRequest(
                    'HOD',
                    projectCreatedOpportunities,
                    TEMPLATE_HOD_PROJECT_CREATED
                )
            );
        }
        if (!projectL1Opportunities.isEmpty()) {
            emailSendRequests.add(
                new EmailSendRequest(
                    'HOD',
                    projectL1Opportunities,
                    TEMPLATE_HOD_L1_BIDDER_DECLARED
                )
            );
        }
        */
        enqueueEmailSends(emailSendRequests);
    }
    private static void enqueueEmailSends(List<EmailSendRequest> emailSendRequests) {
        if (emailSendRequests == null || emailSendRequests.isEmpty()) {
            return;
        }
        System.enqueueJob(new EmailSendQueueable(emailSendRequests));
    }
    private class EmailSendRequest {
        private String recipientType;
        private String templateDeveloperName;
        private List<Id> opportunityIds;
        private EmailSendRequest(
            String recipientType,
            List<Opportunity> opps,
            String templateDeveloperName
        ) {
            this.recipientType = recipientType;
            this.templateDeveloperName = templateDeveloperName;
            this.opportunityIds = new List<Id>();
            if (opps == null) {
                return;
            }
            for (Opportunity opp : opps) {
                if (opp != null && opp.Id != null) {
                    this.opportunityIds.add(opp.Id);
                }
            }
        }
        private List<Opportunity> toOpportunityStubs() {
            List<Opportunity> stubs = new List<Opportunity>();
            for (Id opportunityId : opportunityIds) {
                stubs.add(new Opportunity(Id = opportunityId));
            }
            return stubs;
        }
    }
    private class EmailSendQueueable implements Queueable {
        private List<EmailSendRequest> emailSendRequests;
        private EmailSendQueueable(List<EmailSendRequest> emailSendRequests) {
            this.emailSendRequests = emailSendRequests;
        }
        public void execute(QueueableContext context) {
            if (emailSendRequests == null || emailSendRequests.isEmpty()) {
                return;
            }
            for (EmailSendRequest request : emailSendRequests) {
                if (request == null || String.isBlank(request.templateDeveloperName)) {
                    continue;
                }
                List<Opportunity> opps = request.toOpportunityStubs();
                if (opps.isEmpty()) {
                    continue;
                }
                if (request.recipientType == 'OWNER') {
                    sendEmails(opps, request.templateDeveloperName);
                } else if (request.recipientType == 'CRM_HEAD') {
                    sendCrmHeadEmails(opps, request.templateDeveloperName);
                } else if (request.recipientType == 'HOD') {
                    sendHodEmails(opps, request.templateDeveloperName);
                }
            }
        }
    }
    // COMMENTED OUT (not required): L1 Bidder Declared detection
    /*
    // ADDED: mirrors branch 3 of getTemplateForChange(), extracted so it can be
    // reused here without altering the existing method.
    @TestVisible
    private static Boolean qualifiesAsL1BidderDeclared(Opportunity opp, Opportunity oldOpp) {
        if (opp == null || oldOpp == null) {
            return false;
        }
        return opp.StageName == STAGE_L1_BIDDER_DECLARED
            && oldOpp.StageName != STAGE_L1_BIDDER_DECLARED;
    }
    */
    // ADDED
    @TestVisible
    private static List<Opportunity> filterProjectOpportunities(List<Opportunity> opps) {
        List<Opportunity> filtered = new List<Opportunity>();
        Id projectRtId = getProjectRecordTypeId();
        if (projectRtId == null) {
            return filtered;
        }
        for (Opportunity opp : opps) {
            if (opp.RecordTypeId == projectRtId) {
                filtered.add(opp);
            }
        }
        return filtered;
    }
    // ADDED: true only for Project Opportunity record type
    @TestVisible
    private static Boolean isProjectOpportunity(Opportunity opp) {
        if (opp == null) {
            return false;
        }
        Id projectRtId = getProjectRecordTypeId();
        return projectRtId != null && opp.RecordTypeId == projectRtId;
    }
    // ADDED
    private static Id getProjectRecordTypeId() {
        if (projectRecordTypeId != null) {
            return projectRecordTypeId;
        }
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Opportunity'
            AND DeveloperName = :PROJECT_RECORD_TYPE_DEVELOPER_NAME
            AND IsActive = TRUE
            LIMIT 1
        ];
        projectRecordTypeId = recordTypes.isEmpty() ? null : recordTypes[0].Id;
        return projectRecordTypeId;
    }
    @TestVisible
    private static String getTemplateForChange(Opportunity opp, Opportunity oldOpp, Boolean isInsert) {
        if (opp == null || opp.OwnerId == null) {
            return null;
        }
        // 1) New Opportunity Assigned - on insert
        if (isInsert) {
            return TEMPLATE_NEW_OPPORTUNITY_ASSIGNED;
        }
        if (oldOpp == null) {
            return null;
        }
        // 2) Re-assignment - OwnerId changed
        if (opp.OwnerId != oldOpp.OwnerId) {
            return TEMPLATE_NEW_OPPORTUNITY_ASSIGNED;
        }
        // 3) COMMENTED OUT (not required): L1 Bidder Declared (Owner)
        /*
        // 3) L1 Bidder Declared - StageName transitioned into the L1 Bidder stage
        if (opp.StageName == STAGE_L1_BIDDER_DECLARED
            && oldOpp.StageName != STAGE_L1_BIDDER_DECLARED) {
            return TEMPLATE_L1_BIDDER_DECLARED;
        }
        */
        return null;
    }
    private static void sendEmails(List<Opportunity> opps, String templateDeveloperName) {
        Id templateId = resolveTemplateId(templateDeveloperName);
        if (templateId == null) {
            System.debug('Template not found: ' + templateDeveloperName);
            return;
        }
        Id oweaId = getOrgWideEmailAddressId();
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity opp : opps) {
            oppIds.add(opp.Id);
        }
        // Also query Owner.IsActive and Owner.UserType (no extra SOQL query)
        List<Opportunity> oppsWithDetails = [
            SELECT Id, OwnerId, Owner.Email, Owner.IsActive, Owner.UserType
            FROM Opportunity
            WHERE Id IN :oppIds
            AND Owner.Email != null
        ];
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Opportunity opp : oppsWithDetails) {
            // Salesforce does not allow WhatId when TargetObjectId is a User.
            // Render the Opportunity template, then send to the Owner.
            // Active Standard owners are sent as INTERNAL (target = User);
            // anyone else falls back to the external To address.
            Messaging.SingleEmailMessage mail = buildFormulaRecipientMessage(
                templateId,
                opp.Id,
                opp.Owner.Email.trim(),
                oweaId,
                (opp.Owner.IsActive && opp.Owner.UserType == 'Standard') ? opp.OwnerId : null
            );
            if (mail != null) {
                messages.add(mail);
            }
        }
        sendMessageBatch(messages, 'Opportunity Owner');
    }
    // ADDED: sends to the Department CRM Head (formula email, else department role).
    // NOTE: no longer called by the trigger flow ("Created" is now a daily digest).
    private static void sendCrmHeadEmails(List<Opportunity> opps, String templateDeveloperName) {
        Id templateId = resolveTemplateId(templateDeveloperName);
        if (templateId == null) {
            System.debug('CRM Head template not found: ' + templateDeveloperName);
            return;
        }
        Id oweaId = getOrgWideEmailAddressId();
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity opp : opps) {
            oppIds.add(opp.Id);
        }
        List<Opportunity> oppsWithDetails = [
            SELECT Id, Department_Name__c, CRM_User_Email_Formula__c
            FROM Opportunity
            WHERE Id IN :oppIds
        ];
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Opportunity opp : oppsWithDetails) {
            String crmHeadEmail = resolveCrmHeadEmail(opp);
            if (String.isBlank(crmHeadEmail)) {
                System.debug(
                    'CRM Head email not resolved for Opportunity ' +
                    opp.Id +
                    ' (Department_Name__c=' +
                    opp.Department_Name__c +
                    ')'
                );
                continue;
            }
            Messaging.SingleEmailMessage mail = buildFormulaRecipientMessage(
                templateId,
                opp.Id,
                crmHeadEmail.trim(),
                oweaId
            );
            if (mail != null) {
                messages.add(mail);
            }
        }
        sendMessageBatch(messages, 'Opportunity CRM Head');
    }
    // ADDED: sends to the Department HOD (formula email, else department role).
    // NOTE: no longer called by the trigger flow ("Created" is now a daily digest).
    private static void sendHodEmails(List<Opportunity> opps, String templateDeveloperName) {
        Id templateId = resolveTemplateId(templateDeveloperName);
        if (templateId == null) {
            System.debug('HOD template not found: ' + templateDeveloperName);
            return;
        }
        Id oweaId = getOrgWideEmailAddressId();
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity opp : opps) {
            oppIds.add(opp.Id);
        }
        List<Opportunity> oppsWithDetails = [
            SELECT Id, Department_Name__c, HOD_User_Email_Formula__c
            FROM Opportunity
            WHERE Id IN :oppIds
        ];
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Opportunity opp : oppsWithDetails) {
            String hodEmail = resolveHodEmail(opp);
            if (String.isBlank(hodEmail)) {
                System.debug(
                    'HOD email not resolved for Opportunity ' +
                    opp.Id +
                    ' (Department_Name__c=' +
                    opp.Department_Name__c +
                    ')'
                );
                continue;
            }
            Messaging.SingleEmailMessage mail = buildFormulaRecipientMessage(
                templateId,
                opp.Id,
                hodEmail.trim(),
                oweaId
            );
            if (mail != null) {
                messages.add(mail);
            }
        }
        sendMessageBatch(messages, 'Opportunity HOD');
    }

    // Formula email first; otherwise the department role (no metadata).
    @TestVisible
    private static String resolveCrmHeadEmail(Opportunity opp) {
        if (opp == null) {
            return null;
        }
        if (String.isNotBlank(opp.CRM_User_Email_Formula__c)) {
            return opp.CRM_User_Email_Formula__c.trim();
        }
        return lookupRoleEmail(opp.Department_Name__c, false);
    }
    // Formula email first; otherwise the department role (no metadata).
    @TestVisible
    private static String resolveHodEmail(Opportunity opp) {
        if (opp == null) {
            return null;
        }
        if (String.isNotBlank(opp.HOD_User_Email_Formula__c)) {
            return opp.HOD_User_Email_Formula__c.trim();
        }
        return lookupRoleEmail(opp.Department_Name__c, true);
    }

    // Role name used in this org: "<Department> HOD" / "<Department> CRM User".
    private static String roleNameFor(String department, Boolean forHod) {
        if (String.isBlank(department)) {
            return null;
        }
        String dept = department.trim();
        if (dept == 'Transmission & Telecom Tower') {
            dept = 'Transmission Tower';
        }
        return dept + (forHod ? ' HOD' : ' CRM User');
    }

    // Email of the first active Standard user (by email) holding the department role.
    // Cached per role, so the same role is queried only once per transaction.
    private static String lookupRoleEmail(String departmentName, Boolean forHod) {
        String roleName = roleNameFor(departmentName, forHod);
        if (roleName == null) {
            return null;
        }
        if (!roleEmailCache.containsKey(roleName)) {
            List<User> roleUsers = [
                SELECT Email
                FROM User
                WHERE IsActive = TRUE
                AND UserType = 'Standard'
                AND Email != NULL
                AND UserRole.Name = :roleName
                ORDER BY Email
                LIMIT 1
            ];
            roleEmailCache.put(
                roleName,
                roleUsers.isEmpty() ? null : roleUsers[0].Email.trim()
            );
        }
        return roleEmailCache.get(roleName);
    }

    private static void sendMessageBatch(
        List<Messaging.SingleEmailMessage> messages,
        String recipientLabel
    ) {
        if (messages == null || messages.isEmpty()) {
            return;
        }
        try {
            Messaging.sendEmail(messages, false);
        } catch (Exception e) {
            System.debug('Error sending ' + recipientLabel + ' emails: ' + e.getMessage());
        }
    }
    // ADDED: original 4-parameter version kept as a wrapper (always EXTERNAL),
    // so the CRM Head / HOD paths behave exactly as before.
    private static Messaging.SingleEmailMessage buildFormulaRecipientMessage(
        Id templateId,
        Id opportunityId,
        String recipientEmail,
        Id oweaId
    ) {
        return buildFormulaRecipientMessage(templateId, opportunityId, recipientEmail, oweaId, null);
    }
    // 5-parameter version. recipientUserId != null => INTERNAL send
    // (target = User, no To address). null => EXTERNAL fallback to recipientEmail.
    private static Messaging.SingleEmailMessage buildFormulaRecipientMessage(
        Id templateId,
        Id opportunityId,
        String recipientEmail,
        Id oweaId,
        Id recipientUserId
    ) {
        if (templateId == null || opportunityId == null) {
            return null;
        }
        if (recipientUserId == null && String.isBlank(recipientEmail)) {
            return null;
        }
        Messaging.SingleEmailMessage mail;
        try {
            // Always render against the Opportunity so its merge fields resolve.
            mail = Messaging.renderStoredEmailTemplate(templateId, null, opportunityId);
        } catch (Exception e) {
            System.debug('Formula recipient template render failed: ' + e.getMessage());
            return null;
        }
        if (recipientUserId != null) {
            // INTERNAL: target is the User; WhatId is not allowed with a User target.
            mail.setTargetObjectId(recipientUserId);
            mail.setWhatId(null);
            mail.setTreatTargetObjectAsRecipient(true);
        } else {
            // EXTERNAL fallback.
            System.debug(
                LoggingLevel.WARN,
                'FALLBACK external ' + recipientEmail + ' opp=' + opportunityId
            );
            mail.setTargetObjectId(null);
            mail.setToAddresses(new List<String>{ recipientEmail });
            mail.setTreatTargetObjectAsRecipient(false);
        }
        mail.setSaveAsActivity(false);
        if (oweaId != null) {
            mail.setOrgWideEmailAddressId(oweaId);
        }
        return mail;
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

    /**
     * Groups opportunities by the HOD email (resolveHodEmail: HOD_User_Email_Formula__c,
     * else the department HOD role). Opportunities with no resolvable email are skipped.
     */
    public static Map<String, List<Opportunity>> groupByHodEmail(List<Opportunity> opps) {
        return groupByRecipientEmail(opps, true);
    }

    /**
     * Same for the CRM Head (resolveCrmHeadEmail: CRM_User_Email_Formula__c,
     * else the department CRM User role).
     */
    public static Map<String, List<Opportunity>> groupByCrmHeadEmail(List<Opportunity> opps) {
        return groupByRecipientEmail(opps, false);
    }

    private static Map<String, List<Opportunity>> groupByRecipientEmail(
        List<Opportunity> opps,
        Boolean forHod
    ) {
        Map<String, List<Opportunity>> oppsByEmail = new Map<String, List<Opportunity>>();
        if (opps == null) {
            return oppsByEmail;
        }
        for (Opportunity opp : opps) {
            String email = forHod ? resolveHodEmail(opp) : resolveCrmHeadEmail(opp);
            if (String.isBlank(email)) {
                System.debug(
                    (forHod ? 'HOD' : 'CRM Head') +
                    ' email not resolved for Opportunity ' +
                    opp.Id +
                    ' (Department_Name__c=' +
                    opp.Department_Name__c +
                    ')'
                );
                continue;
            }
            String key = email.trim().toLowerCase();
            if (!oppsByEmail.containsKey(key)) {
                oppsByEmail.put(key, new List<Opportunity>());
            }
            oppsByEmail.get(key).add(opp);
        }
        return oppsByEmail;
    }

    /**
     * Sends ONE email to one recipient (HOD or CRM Head) listing all the new Project
     * Opportunities.
     * Sent INTERNAL (target = User) when a User Id is found by email or by role.
     */
    public static Boolean sendCreatedDigest(
        List<Opportunity> opps,
        String recipientEmail,
        String templateDeveloperName
    ) {
        if (
            opps == null ||
            opps.isEmpty() ||
            String.isBlank(recipientEmail) ||
            String.isBlank(templateDeveloperName)
        ) {
            return false;
        }
        Id templateId = resolveTemplateId(templateDeveloperName);
        if (templateId == null) {
            System.debug('Digest template not found: ' + templateDeveloperName);
            return false;
        }

        Boolean forHod = templateDeveloperName == TEMPLATE_HOD_PROJECT_CREATED;
        Messaging.SingleEmailMessage mail = buildFormulaRecipientMessage(
            templateId,
            opps[0].Id,
            recipientEmail.trim(),
            getOrgWideEmailAddressId(),
            resolveInternalUserId(recipientEmail, opps[0].Department_Name__c, forHod)
        );
        if (mail == null) {
            return false;
        }

        String baseSubject = String.isBlank(mail.getSubject())
            ? 'Project Opportunity Created'
            : mail.getSubject();
        mail.setSubject(baseSubject + ' (' + opps.size() + ' Opportunities)');

        String introHtml = String.isNotBlank(mail.getHtmlBody())
            ? mail.getHtmlBody()
            : (String.isNotBlank(mail.getPlainTextBody())
                ? mail.getPlainTextBody().replace('\n', '<br/>')
                : '');
        mail.setHtmlBody(
            introHtml +
            '<br/><p><b>New Project Opportunities (' + opps.size() + '):</b></p>' +
            buildCreatedDigestHtml(opps)
        );
        mail.setPlainTextBody(
            (String.isNotBlank(mail.getPlainTextBody()) ? mail.getPlainTextBody() : '') +
            '\n\nNew Project Opportunities (' + opps.size() + '):\n' +
            buildCreatedDigestText(opps)
        );

        try {
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ mail },
                false
            );
            if (!results[0].isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Digest send failed: ' + results[0].getErrors());
            }
            return results[0].isSuccess();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Digest send error: ' + e.getMessage());
            return false;
        }
    }

    /**
     * email -> active Standard User Id. If none matches and USE_ROLE_FALLBACK is true,
     * the department role is used, but only when exactly one active Standard user holds it.
     * Returns null => the caller keeps the external send.
     */
    @TestVisible
    private static Id resolveInternalUserId(String email, String department, Boolean forHod) {
        if (String.isBlank(email)) {
            return null;
        }
        List<User> byEmail = [
            SELECT Id
            FROM User
            WHERE IsActive = TRUE AND UserType = 'Standard' AND Email = :email.trim()
            LIMIT 1
        ];
        if (!byEmail.isEmpty()) {
            return byEmail[0].Id;
        }
        String roleName = roleNameFor(department, forHod);
        if (!USE_ROLE_FALLBACK || roleName == null) {
            return null;
        }
        List<User> byRole = [
            SELECT Id
            FROM User
            WHERE IsActive = TRUE AND UserType = 'Standard' AND UserRole.Name = :roleName
            LIMIT 2
        ];
        return byRole.size() == 1 ? byRole[0].Id : null;
    }

    // HTML table listing every opportunity of the digest.
    private static String buildCreatedDigestHtml(List<Opportunity> opps) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        String html =
            '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;font-size:13px;">' +
            '<tr style="background:#f3f3f3;">' +
            '<th>#</th><th>Opportunity</th><th>Department</th><th>Assigned To</th><th>Created</th>' +
            '</tr>';
        Integer rowNumber = 1;
        for (Opportunity opp : opps) {
            String oppName = String.isBlank(opp.Name) ? String.valueOf(opp.Id) : opp.Name;
            String department = opp.Department_Name__c != null ? opp.Department_Name__c : '';
            String ownerName = opp.Owner != null && opp.Owner.Name != null ? opp.Owner.Name : '';
            String createdOn = opp.CreatedDate != null ? opp.CreatedDate.format('dd MMM yyyy HH:mm') : '';
            html +=
                '<tr>' +
                '<td>' + rowNumber + '</td>' +
                '<td><a href="' + baseUrl + '/' + opp.Id + '">' + oppName.escapeHtml4() + '</a></td>' +
                '<td>' + department.escapeHtml4() + '</td>' +
                '<td>' + ownerName.escapeHtml4() + '</td>' +
                '<td>' + createdOn + '</td>' +
                '</tr>';
            rowNumber++;
        }
        return html + '</table>';
    }

    // Plain-text version of the same list.
    private static String buildCreatedDigestText(List<Opportunity> opps) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        List<String> lines = new List<String>();
        Integer rowNumber = 1;
        for (Opportunity opp : opps) {
            lines.add(
                rowNumber + '. ' + opp.Name + ' | ' +
                (opp.Department_Name__c != null ? opp.Department_Name__c : '') + ' | assigned to ' +
                (opp.Owner != null ? opp.Owner.Name : '') + ' | ' +
                (opp.CreatedDate != null ? opp.CreatedDate.format('dd MMM yyyy HH:mm') : '') + ' | ' +
                baseUrl + '/' + opp.Id
            );
            rowNumber++;
        }
        return String.join(lines, '\n');
    }
}