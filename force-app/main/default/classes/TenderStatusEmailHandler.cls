/**
 * Bulkified, fail-safe email handler for Tender__c.
 *
 * IMPORTANT:
 * - Trigger transaction ONLY determines which emails are required.
 * - Actual email processing is moved to Queueable Apex.
 * - This prevents the Tender email logic from consuming the SOQL limits
 *   of the Tender integration transaction.
 * - Queueable processes maximum 40 Tenders per transaction.
 * - No SOQL/DML in record loops.
 * - EmailTemplate lookup is bulkified.
 * - Org-Wide Email Address is queried once.
 * - Messaging.renderStoredEmailTemplate is limited by the Queueable chunk size.
 *
 */
public without sharing class TenderStatusEmailHandler {

    // ========================================================================
    // Picklist values
    // ========================================================================

    public static final String CHOICE_DIRECT_PARTICIPATION =
        'Accept and participate';

    public static final String CHOICE_DIRECT_PARTICIPATION_REJECTION =
        'Reject and Create Project';

    public static final String HOD_APPROVED =
        'Accept for participation';

    public static final String HOD_REJECTED =
        'Reject and Close';

    public static final String HOD_REJECT_AND_CREATE_PROJECT =
        'Reject and Create Project';

    public static final String HOD_SEND_BACK =
        'Review and resend for participation';

    // Tender User rejection request can be either value (TenderAcceptanceController).
    public static final Set<String> USER_REJECTION_CHOICES =
        new Set<String>{
            CHOICE_DIRECT_PARTICIPATION_REJECTION,
            'Reject and Close'
        };

    // HOD screen saves one of these when the tender is not taken forward.
    public static final Set<String> HOD_REJECTION_CHOICES =
        new Set<String>{
            HOD_REJECTED,
            HOD_REJECT_AND_CREATE_PROJECT
        };


    // ========================================================================
    // Tender User templates
    // ========================================================================

    public static final String TEMPLATE_NEW_TENDER_ALERT =
        'New_Tender_Alert_A_new_tender_relevant_1786621926967';

    public static final String TEMPLATE_PARTICIPATION_SUBMITTED =
        'TendeDirect_Participation_approval_submission_1786622243328';

    public static final String TEMPLATE_REJECTION_REQUEST_SUBMITTED =
        'Tender_Direct_Participation_Rejection_1786622679452';

    public static final String TEMPLATE_PARTICIPATION_ACCEPTED =
        'Direct_Participation_Accepted_1786628138227';

    public static final String TEMPLATE_REJECTION_REQUEST_APPROVED =
        'Direct_Participation_Rejection_request_approved_1786624395212';

    public static final String TEMPLATE_PARTICIPATION_REQUEST_REJECTED =
        'Direct_Participation_request_rejected_1786624627244';

    public static final String TEMPLATE_REJECTION_REQUEST_REJECTED =
        'Direct_Participation_Rejection_request_rejected_1786624972141';


  

    public static final String ORG_WIDE_SENDER_EMAIL =
        'noreply@utkarshindialimited.in';


    // ========================================================================
    // CRM Head templates
    // ========================================================================

    public static final String TEMPLATE_CRM_HEAD_NEW_TENDER_ALERT =
        'New_Tender_Alert_A_new_tender_relevant_to_your_department_has_b_1786778850618';

    // COMMENTED OUT (not required): CRM Head Direct Participation Accepted
    // public static final String TEMPLATE_CRM_HEAD_PARTICIPATION_ACCEPTED =
    //     'Direct_Participation_Accepted_1786623262023';

    // COMMENTED OUT (not required): CRM Head Direct Participation Rejection accepted
    // public static final String TEMPLATE_CRM_HEAD_REJECTION_REQUEST_APPROVED =
    //     'Direct_Participation_Rejection_accepted_CRM_Head_1786779740569';


    // ========================================================================
    // HOD templates
    // ========================================================================

    public static final String TEMPLATE_HOD_NEW_TENDER_ALERT =
        'New_Tender_Alert_A_new_tender_relevant_to_your_department_1786625246055';

    public static final String TEMPLATE_HOD_PARTICIPATION_AWAITING =
        'Tender_Direct_Participation_Awaiting_Approval_1786625465484';

    public static final String TEMPLATE_HOD_REJECTION_AWAITING =
        'Tender_Direct_Participation_Rejection_Awaiting_Approval_1786625682691';



    @TestVisible
    private static Map<String, Id> templateIdByDeveloperName =
        new Map<String, Id>();

    @TestVisible
    private static Id orgWideEmailAddressId;

    @TestVisible
    private static Boolean orgWideEmailAddressQueried = false;

    @TestVisible
    private static Id testTemplateIdOverride;


    // ========================================================================
    // Queueable chunk size
    // ========================================================================
    //
    // CRM/HOD emails use renderStoredEmailTemplate().
    // That method consumes SOQL.
    //
    // Maximum 40 Tenders:
    //
    //   40 Tender queries
    //   1 EmailTemplate query
    //   1 OrgWideEmailAddress query
    //   up to 80 renderStoredEmailTemplate calls
    //
    // Total remains comfortably below the async SOQL limit.
    //
    private static final Integer QUEUEABLE_CHUNK_SIZE = 40;


    // ========================================================================
    // Entry points
    // ========================================================================

    public static void handleAfterInsert(List<Tender__c> newRecords) {
        processRecords(newRecords, null);
    }


    /**
     * Sends New Tender Alert emails in the current transaction instead of
     * enqueueing TenderStatusEmailQueueable. Call only from async code that
     * passes at most QUEUEABLE_CHUNK_SIZE records, so the caller keeps its
     * single child-job slot for its own chaining.
     */
    public static void sendAfterInsertNow(List<Tender__c> newRecords) {
        processRecords(newRecords, null, true);
    }


    public static void handleAfterUpdate(
        List<Tender__c> newRecords,
        Map<Id, Tender__c> oldRecordsById
    ) {
        processRecords(newRecords, oldRecordsById);
    }


    // ========================================================================
    // Determine which emails are required
    // ========================================================================

    @TestVisible
    private static void processRecords(
        List<Tender__c> newRecords,
        Map<Id, Tender__c> oldRecordsById
    ) {
        processRecords(newRecords, oldRecordsById, false);
    }


    private static void processRecords(
        List<Tender__c> newRecords,
        Map<Id, Tender__c> oldRecordsById,
        Boolean sendInline
    ) {
        try {

            if (newRecords == null || newRecords.isEmpty()) {
                return;
            }

            Boolean isInsert = (oldRecordsById == null);

          

            Map<Id, String> userTemplateByTender =
                new Map<Id, String>();

            Map<Id, String> crmTemplateByTender =
                new Map<Id, String>();

            Map<Id, String> hodTemplateByTender =
                new Map<Id, String>();


            // ---------------------------------------------------------------
            // Determine email requirements
            // ---------------------------------------------------------------

            for (Tender__c t : newRecords) {

                if (t == null || t.Id == null) {
                    continue;
                }

                Tender__c oldT =
                    isInsert
                        ? null
                        : oldRecordsById.get(t.Id);


                // ===========================================================
                // Tender User email
                // ===========================================================

                String userTemplate =
                    getTemplateForChange(
                        t,
                        oldT,
                        isInsert
                    );

                if (userTemplate != null) {

                    userTemplateByTender.put(
                        t.Id,
                        userTemplate
                    );


                    // -------------------------------------------------------
                    // CRM Head emails
                    // -------------------------------------------------------

                    if (userTemplate == TEMPLATE_NEW_TENDER_ALERT) {

                        crmTemplateByTender.put(
                            t.Id,
                            TEMPLATE_CRM_HEAD_NEW_TENDER_ALERT
                        );

                    }
                    // COMMENTED OUT (not required): CRM Head Direct Participation
                    // Accepted / Rejection accepted emails.
                    /*
                    else if (
                        userTemplate ==
                        TEMPLATE_PARTICIPATION_ACCEPTED
                    ) {

                        crmTemplateByTender.put(
                            t.Id,
                            TEMPLATE_CRM_HEAD_PARTICIPATION_ACCEPTED
                        );

                    }
                    else if (
                        userTemplate ==
                        TEMPLATE_REJECTION_REQUEST_APPROVED
                    ) {

                        crmTemplateByTender.put(
                            t.Id,
                            TEMPLATE_CRM_HEAD_REJECTION_REQUEST_APPROVED
                        );
                    }
                    */
                }


                // ===========================================================
                // HOD emails
                // ===========================================================

                if (
                    isInsert &&
                    shouldSendNewTenderAlert(t)
                ) {

                    hodTemplateByTender.put(
                        t.Id,
                        TEMPLATE_HOD_NEW_TENDER_ALERT
                    );
                }


                if (
                    qualifiesForHodParticipationAwaiting(
                        t,
                        oldT
                    )
                ) {

                    hodTemplateByTender.put(
                        t.Id,
                        TEMPLATE_HOD_PARTICIPATION_AWAITING
                    );
                }


                if (
                    qualifiesForHodRejectionAwaiting(
                        t,
                        oldT
                    )
                ) {

                    hodTemplateByTender.put(
                        t.Id,
                        TEMPLATE_HOD_REJECTION_AWAITING
                    );
                }
            }


            // ---------------------------------------------------------------
            // Nothing to process
            // ---------------------------------------------------------------

            if (
                userTemplateByTender.isEmpty() &&
                crmTemplateByTender.isEmpty() &&
                hodTemplateByTender.isEmpty()
            ) {
                return;
            }


            // ---------------------------------------------------------------
            // Collect all Tender IDs
            // ---------------------------------------------------------------

            Set<Id> allTenderIds =
                new Set<Id>();

            allTenderIds.addAll(
                userTemplateByTender.keySet()
            );

            allTenderIds.addAll(
                crmTemplateByTender.keySet()
            );

            allTenderIds.addAll(
                hodTemplateByTender.keySet()
            );


            if (allTenderIds.isEmpty()) {
                return;
            }


            // ---------------------------------------------------------------
            // Enqueue ONE Queueable
            //
            // Important for Batch/Async integration:
            // only one Queueable is added from this transaction.
            // The Queueable chains the next one if necessary.
            // ---------------------------------------------------------------

            TenderStatusEmailQueueable emailJob =
                new TenderStatusEmailQueueable(
                    new List<Id>(allTenderIds),
                    userTemplateByTender,
                    crmTemplateByTender,
                    hodTemplateByTender,
                    0
                );

            if (sendInline == true) {
                emailJob.execute(null);
            }
            else {
                System.enqueueJob(emailJob);
            }

        }
        catch (Exception e) {

            System.debug(
                LoggingLevel.ERROR,
                'TenderStatusEmailHandler.processRecords failed: '
                + e.getMessage()
                + ' | '
                + e.getStackTraceString()
            );
        }
    }


    // ========================================================================
    // Qualification
    // ========================================================================

    @TestVisible
    private static Boolean qualifiesForHodParticipationAwaiting(
        Tender__c t,
        Tender__c oldT
    ) {

        if (t == null || oldT == null) {
            return false;
        }

        return
            t.Tender_User_Choice__c ==
                CHOICE_DIRECT_PARTICIPATION
            &&
            t.Tender_User_Choice__c !=
                oldT.Tender_User_Choice__c;
    }


    @TestVisible
    private static Boolean qualifiesForHodRejectionAwaiting(
        Tender__c t,
        Tender__c oldT
    ) {

        if (t == null || oldT == null) {
            return false;
        }

        return
            t.Tender_User_Choice__c ==
                CHOICE_DIRECT_PARTICIPATION_REJECTION
            &&
            t.Tender_User_Choice__c !=
                oldT.Tender_User_Choice__c;
    }


    // ========================================================================
    // Determine Tender User template
    // ========================================================================

    @TestVisible
    private static String getTemplateForChange(
        Tender__c t,
        Tender__c oldT,
        Boolean isInsert
    ) {

        if (t == null) {
            return null;
        }


        // ---------------------------------------------------------------
        // Insert — New Tender Alert (Tender User = Tender Owner)
        // ---------------------------------------------------------------

        if (isInsert) {

            return
                shouldSendNewTenderAlert(t)
                    ? TEMPLATE_NEW_TENDER_ALERT
                    : null;
        }


        if (oldT == null) {
            return null;
        }


        String newUserChoice =
            t.Tender_User_Choice__c;

        String oldUserChoice =
            oldT.Tender_User_Choice__c;

        String newHodChoice =
            t.HOD_Choice__c;

        String oldHodChoice =
            oldT.HOD_Choice__c;


        // ===============================================================
        // HOD Choice changed (checked first: the HOD screen can set the
        // Tender User Choice in the same save)
        // ===============================================================

        if (newHodChoice != oldHodChoice) {

            // TenderHODController blanks Tender_User_Choice__c in the same
            // update as the HOD decision, so fall back to the prior value.
            String requestedChoice =
                String.isBlank(newUserChoice)
                    ? oldUserChoice
                    : newUserChoice;

            // -----------------------------------------------------------
            // Direct Participation
            // -----------------------------------------------------------

            if (
                requestedChoice ==
                CHOICE_DIRECT_PARTICIPATION
            ) {

                if (
                    newHodChoice ==
                    HOD_APPROVED
                ) {

                    return TEMPLATE_PARTICIPATION_ACCEPTED;
                }


                if (
                    HOD_REJECTION_CHOICES.contains(newHodChoice)
                ) {

                    return TEMPLATE_PARTICIPATION_REQUEST_REJECTED;
                }
            }


            // -----------------------------------------------------------
            // Direct Participation Rejection
            // -----------------------------------------------------------

            if (
                USER_REJECTION_CHOICES.contains(requestedChoice)
            ) {

                if (
                    HOD_REJECTION_CHOICES.contains(newHodChoice)
                ) {

                    return TEMPLATE_REJECTION_REQUEST_APPROVED;
                }


                if (
                    newHodChoice ==
                    HOD_SEND_BACK
                ) {

                    return TEMPLATE_REJECTION_REQUEST_REJECTED;
                }
            }
        }


        // ===============================================================
        // Tender User Choice changed
        // ===============================================================

        if (newUserChoice != oldUserChoice) {

            if (
                newUserChoice ==
                CHOICE_DIRECT_PARTICIPATION
            ) {

                return TEMPLATE_PARTICIPATION_SUBMITTED;
            }


            if (
                newUserChoice ==
                CHOICE_DIRECT_PARTICIPATION_REJECTION
            ) {

                return TEMPLATE_REJECTION_REQUEST_SUBMITTED;
            }
        }


        return null;
    }


    // ========================================================================
    // New Tender condition
    // ========================================================================

    private static Boolean shouldSendNewTenderAlert(
        Tender__c t
    ) {

        return true;
    }


    // ========================================================================
    // Queueable
    // ========================================================================

    public class TenderStatusEmailQueueable
        implements Queueable {

        private List<Id> tenderIds;

        private Map<Id, String> userTemplateByTender;

        private Map<Id, String> crmTemplateByTender;

        private Map<Id, String> hodTemplateByTender;

        private Integer startIndex;


        public TenderStatusEmailQueueable(
            List<Id> tenderIds,
            Map<Id, String> userTemplateByTender,
            Map<Id, String> crmTemplateByTender,
            Map<Id, String> hodTemplateByTender,
            Integer startIndex
        ) {

            this.tenderIds =
                tenderIds == null
                    ? new List<Id>()
                    : tenderIds;

            this.userTemplateByTender =
                userTemplateByTender == null
                    ? new Map<Id, String>()
                    : userTemplateByTender;

            this.crmTemplateByTender =
                crmTemplateByTender == null
                    ? new Map<Id, String>()
                    : crmTemplateByTender;

            this.hodTemplateByTender =
                hodTemplateByTender == null
                    ? new Map<Id, String>()
                    : hodTemplateByTender;

            this.startIndex =
                startIndex == null
                    ? 0
                    : startIndex;
        }


        public void execute(
            QueueableContext context
        ) {

            try {

                if (
                    tenderIds == null ||
                    tenderIds.isEmpty() ||
                    startIndex >= tenderIds.size()
                ) {
                    return;
                }


                // ===========================================================
                // Determine chunk
                // ===========================================================

                Integer endIndex =
                    Math.min(
                        startIndex + QUEUEABLE_CHUNK_SIZE,
                        tenderIds.size()
                    );


                List<Id> chunkIds =
                    new List<Id>();


                for (
                    Integer i = startIndex;
                    i < endIndex;
                    i++
                ) {

                    chunkIds.add(
                        tenderIds[i]
                    );
                }


                Set<Id> chunkIdSet =
                    new Set<Id>(
                        chunkIds
                    );


                // ===========================================================
                // Determine required template names
                // ===========================================================

                Set<String> requiredTemplateNames =
                    new Set<String>();


                for (Id tenderId : chunkIds) {

                    if (
                        userTemplateByTender.containsKey(
                            tenderId
                        )
                    ) {

                        requiredTemplateNames.add(
                            userTemplateByTender.get(
                                tenderId
                            )
                        );
                    }


                    if (
                        crmTemplateByTender.containsKey(
                            tenderId
                        )
                    ) {

                        requiredTemplateNames.add(
                            crmTemplateByTender.get(
                                tenderId
                            )
                        );
                    }


                    if (
                        hodTemplateByTender.containsKey(
                            tenderId
                        )
                    ) {

                        requiredTemplateNames.add(
                            hodTemplateByTender.get(
                                tenderId
                            )
                        );
                    }
                }


                // ===========================================================
                // Resolve ALL templates with ONE SOQL
                // ===========================================================

                Map<String, Id> templateIds =
                    resolveTemplateIds(
                        requiredTemplateNames
                    );


                // ===========================================================
                // Query Org Wide Email once
                // ===========================================================

                Id oweaId =
                    getOrgWideEmailAddressId();


                // ===========================================================
                // Query ALL Tender data once
                // ===========================================================

                List<Tender__c> rows = [

                    SELECT
                        Id,
                        OwnerId,
                        Owner.Email,
                        Owner.Type,
                        Contact__c,
                        Contact__r.Email,
                        Department_Name__c,
                        CRM_User_Email_Formula__c,
                        HOD_User_Email_Formula__c

                    FROM Tender__c

                    WHERE Id IN :chunkIdSet
                ];


                // ===========================================================
                // Resolve internal Users so emails go by User Id
                // ===========================================================

                Set<String> formulaRecipientEmails =
                    new Set<String>();
                Set<Id> ownerIds =
                    new Set<Id>();
                Set<String> tenderDepartments =
                    new Set<String>();

                for (Tender__c t : rows) {

                    tenderDepartments.add(
                        t.Department_Name__c
                    );
                    formulaRecipientEmails.add(
                        t.CRM_User_Email_Formula__c
                    );
                    formulaRecipientEmails.add(
                        t.HOD_User_Email_Formula__c
                    );

                    if (t.OwnerId != null) {
                        ownerIds.add(t.OwnerId);
                    }
                }

                Map<String, Id> userIdByEmail =
                    TenderEmailRecipientService.resolveActiveUserIdsByEmail(
                        formulaRecipientEmails
                    );
                Set<Id> activeOwnerIds =
                    TenderEmailRecipientService.resolveActiveUserIds(
                        ownerIds
                    );
                Map<String, List<User>> crmHeadsByDepartment =
                    TenderEmailRecipientService.resolveUsersByProfileDepartment(
                        TenderEmailRecipientService.PROFILE_CRM_HEAD,
                        tenderDepartments
                    );


                // ===========================================================
                // Build email messages
                // ===========================================================

                List<Messaging.SingleEmailMessage> messages =
                    new List<Messaging.SingleEmailMessage>();


                for (Tender__c t : rows) {

                    // -------------------------------------------------------
                    // Tender User
                    // -------------------------------------------------------

                    if (
                        userTemplateByTender.containsKey(t.Id)
                    ) {

                        String developerName =
                            userTemplateByTender.get(
                                t.Id
                            );

                        Id templateId =
                            templateIds.get(
                                developerName
                            );


                        Boolean canSendToOwner =
                            t.OwnerId != null &&
                            t.OwnerId.getSObjectType() == User.SObjectType &&
                            !String.isBlank(t.Owner.Email);

                        if (
                            templateId != null &&
                            canSendToOwner
                        ) {

                            // Active Owners are emailed by User Id; others keep Owner.Email.
                            Messaging.SingleEmailMessage mail =
                                buildFormulaRecipientMessage(
                                    templateId,
                                    t.Id,
                                    t.Owner.Email.trim(),
                                    activeOwnerIds.contains(t.OwnerId)
                                        ? t.OwnerId
                                        : null,
                                    oweaId
                                );

                            if (mail != null) {

                                messages.add(mail);
                            }
                        }
                    }


                    // -------------------------------------------------------
                    // CRM Head
                    // -------------------------------------------------------

                    if (
                        crmTemplateByTender.containsKey(t.Id)
                    ) {

                        String developerName =
                            crmTemplateByTender.get(
                                t.Id
                            );

                        Id templateId =
                            templateIds.get(
                                developerName
                            );

                        // CRM Head = profile "CRM Head" + User.Department; the department
                        // setting email below is only the fallback when nobody matches.
                        List<User> crmHeads =
                            TenderEmailRecipientService.findUsersForDepartment(
                                crmHeadsByDepartment,
                                t.Department_Name__c
                            );

                        if (
                            templateId != null &&
                            !crmHeads.isEmpty()
                        ) {

                            for (User crmHead : crmHeads) {

                                Messaging.SingleEmailMessage mail =
                                    buildFormulaRecipientMessage(
                                        templateId,
                                        t.Id,
                                        crmHead.Email,
                                        crmHead.Id,
                                        oweaId
                                    );

                                if (mail != null) {

                                    messages.add(mail);
                                }
                            }
                        }
                        else if (
                            templateId != null &&
                            !String.isBlank(
                                t.CRM_User_Email_Formula__c
                            ) &&
                            isActiveUserEmail(
                                userIdByEmail,
                                t.CRM_User_Email_Formula__c,
                                'CRM Head',
                                t.Id
                            )
                        ) {

                            Messaging.SingleEmailMessage mail =
                                buildFormulaRecipientMessage(
                                    templateId,
                                    t.Id,
                                    t.CRM_User_Email_Formula__c.trim(),
                                    TenderEmailRecipientService.findUserIdByEmail(
                                        userIdByEmail,
                                        t.CRM_User_Email_Formula__c
                                    ),
                                    oweaId
                                );


                            if (mail != null) {

                                messages.add(mail);
                            }
                        }
                    }


                    // -------------------------------------------------------
                    // HOD
                    // -------------------------------------------------------

                    if (
                        hodTemplateByTender.containsKey(t.Id)
                    ) {

                        String developerName =
                            hodTemplateByTender.get(
                                t.Id
                            );

                        Id templateId =
                            templateIds.get(
                                developerName
                            );


                        if (
                            templateId != null &&
                            !String.isBlank(
                                t.HOD_User_Email_Formula__c
                            ) &&
                            isActiveUserEmail(
                                userIdByEmail,
                                t.HOD_User_Email_Formula__c,
                                'HOD',
                                t.Id
                            )
                        ) {

                            Messaging.SingleEmailMessage mail =
                                buildFormulaRecipientMessage(
                                    templateId,
                                    t.Id,
                                    t.HOD_User_Email_Formula__c.trim(),
                                    TenderEmailRecipientService.findUserIdByEmail(
                                        userIdByEmail,
                                        t.HOD_User_Email_Formula__c
                                    ),
                                    oweaId
                                );


                            if (mail != null) {

                                messages.add(mail);
                            }
                        }
                    }
                }


                // ===========================================================
                // ONE sendEmail invocation per Queueable
                // ===========================================================

                sendMessageList(
                    messages,
                    'Tender Status Emails'
                );


                // ===========================================================
                // Chain next Queueable
                // ===========================================================

                if (endIndex < tenderIds.size()) {

                    System.enqueueJob(
                        new TenderStatusEmailQueueable(
                            tenderIds,
                            userTemplateByTender,
                            crmTemplateByTender,
                            hodTemplateByTender,
                            endIndex
                        )
                    );
                }

            }
            catch (Exception e) {

                System.debug(
                    LoggingLevel.ERROR,
                    'TenderStatusEmailQueueable failed: '
                    + e.getMessage()
                    + ' | '
                    + e.getStackTraceString()
                );
            }
        }
    }


    // ========================================================================
    // Department setting (custom metadata) emails are sent only to active
    // Users, by User Id; an address with no active User is skipped.
    // ========================================================================

    @TestVisible
    private static Boolean isActiveUserEmail(
        Map<String, Id> userIdByEmail,
        String recipientEmail,
        String recipientLabel,
        Id tenderId
    ) {

        if (
            TenderEmailRecipientService.findUserIdByEmail(
                userIdByEmail,
                recipientEmail
            ) != null
        ) {
            return true;
        }

        System.debug(
            LoggingLevel.WARN,
            'Tender ' + recipientLabel + ' email skipped (no active User): '
            + recipientEmail + ' tender=' + tenderId
        );

        return false;
    }


    // ========================================================================
    // Build formula recipient email
    // ========================================================================

    @TestVisible
    private static Messaging.SingleEmailMessage
        buildFormulaRecipientMessage(
            Id templateId,
            Id tenderId,
            String recipientEmail,
            Id oweaId
        ) {

        return buildFormulaRecipientMessage(
            templateId,
            tenderId,
            recipientEmail,
            null,
            oweaId
        );
    }


    @TestVisible
    private static Messaging.SingleEmailMessage
        buildFormulaRecipientMessage(
            Id templateId,
            Id tenderId,
            String recipientEmail,
            Id recipientUserId,
            Id oweaId
        ) {

        if (
            templateId == null ||
            tenderId == null ||
            String.isBlank(recipientEmail)
        ) {
            return null;
        }


        try {

            /*
             * This method consumes one SOQL query.
             *
             * It is deliberately NOT called from the trigger transaction.
             * It is called only inside the Queueable.
             *
             * Queueable chunk = 40 records.
             * Therefore this remains safely below the async query limit.
             */

            Messaging.SingleEmailMessage mail =
                Messaging.renderStoredEmailTemplate(
                    templateId,
                    null,
                    tenderId
                );


            if (recipientUserId != null) {

                return TenderEmailRecipientService.buildUserMessage(
                    mail,
                    recipientUserId,
                    oweaId
                );
            }


            mail.setTargetObjectId(
                null
            );

            mail.setToAddresses(
                new List<String>{
                    recipientEmail
                }
            );

            mail.setSaveAsActivity(
                false
            );

            mail.setTreatTargetObjectAsRecipient(
                false
            );


            if (oweaId != null) {

                mail.setOrgWideEmailAddressId(
                    oweaId
                );
            }


            return mail;

        }
        catch (Exception e) {

            System.debug(
                LoggingLevel.ERROR,
                'renderStoredEmailTemplate failed: '
                + e.getMessage()
            );

            return null;
        }
    }


    // ========================================================================
    // Send messages
    // ========================================================================

    @TestVisible
    private static void sendMessageList(
        List<Messaging.SingleEmailMessage> messages,
        String label
    ) {

        if (
            messages == null ||
            messages.isEmpty()
        ) {
            return;
        }


        try {

            /*
             * ONE Messaging.sendEmail invocation.
             */
            Messaging.sendEmail(
                messages,
                false
            );

        }
        catch (Exception e) {

            System.debug(
                LoggingLevel.ERROR,
                'sendEmail ('
                + label
                + ') failed: '
                + e.getMessage()
            );
        }
    }


    // ========================================================================
    // Bulk template lookup
    // ========================================================================

    private static Map<String, Id> resolveTemplateIds(
        Set<String> developerNames
    ) {

        Map<String, Id> result =
            new Map<String, Id>();


        if (
            developerNames == null ||
            developerNames.isEmpty()
        ) {
            return result;
        }


        Set<String> namesToQuery =
            new Set<String>();


        for (String developerName : developerNames) {

            if (String.isBlank(developerName)) {
                continue;
            }


            if (
                Test.isRunningTest() &&
                testTemplateIdOverride != null
            ) {

                result.put(
                    developerName,
                    testTemplateIdOverride
                );

                continue;
            }


            if (
                templateIdByDeveloperName.containsKey(
                    developerName
                )
            ) {

                result.put(
                    developerName,
                    templateIdByDeveloperName.get(
                        developerName
                    )
                );

            }
            else {

                namesToQuery.add(
                    developerName
                );
            }
        }


        // ---------------------------------------------------------------
        // ONE EmailTemplate SOQL
        // ---------------------------------------------------------------

        if (!namesToQuery.isEmpty()) {

            try {

                List<EmailTemplate> templates = [

                    SELECT
                        Id,
                        DeveloperName

                    FROM EmailTemplate

                    WHERE DeveloperName IN :namesToQuery
                ];


                for (EmailTemplate template : templates) {

                    templateIdByDeveloperName.put(
                        template.DeveloperName,
                        template.Id
                    );

                    result.put(
                        template.DeveloperName,
                        template.Id
                    );
                }


                // -------------------------------------------------------
                // Cache templates that do not exist
                // -------------------------------------------------------

                for (String developerName : namesToQuery) {

                    if (
                        !templateIdByDeveloperName.containsKey(
                            developerName
                        )
                    ) {

                        templateIdByDeveloperName.put(
                            developerName,
                            null
                        );

                        result.put(
                            developerName,
                            null
                        );
                    }
                }

            }
            catch (Exception e) {

                System.debug(
                    LoggingLevel.ERROR,
                    'resolveTemplateIds failed: '
                    + e.getMessage()
                );


                for (String developerName : namesToQuery) {

                    templateIdByDeveloperName.put(
                        developerName,
                        null
                    );

                    result.put(
                        developerName,
                        null
                    );
                }
            }
        }


        return result;
    }


    // ========================================================================
    // Backward-compatible single template resolver
    // ========================================================================

    @TestVisible
    private static Id resolveTemplateId(
        String developerName
    ) {

        if (
            String.isBlank(developerName)
        ) {
            return null;
        }


        if (
            Test.isRunningTest() &&
            testTemplateIdOverride != null
        ) {

            return testTemplateIdOverride;
        }


        if (
            templateIdByDeveloperName.containsKey(
                developerName
            )
        ) {

            return templateIdByDeveloperName.get(
                developerName
            );
        }


        Map<String, Id> resolved =
            resolveTemplateIds(
                new Set<String>{
                    developerName
                }
            );


        return resolved.get(
            developerName
        );
    }


    // ========================================================================
    // Org Wide Email Address
    // ========================================================================

    private static Id getOrgWideEmailAddressId() {

        if (
            orgWideEmailAddressQueried
        ) {
            return orgWideEmailAddressId;
        }


        orgWideEmailAddressQueried = true;


        try {

            List<OrgWideEmailAddress> owea = [

                SELECT
                    Id

                FROM OrgWideEmailAddress

                WHERE Address = :ORG_WIDE_SENDER_EMAIL

                LIMIT 1
            ];


            orgWideEmailAddressId =
                owea.isEmpty()
                    ? null
                    : owea[0].Id;

        }
        catch (Exception e) {

            System.debug(
                LoggingLevel.ERROR,
                'getOrgWideEmailAddressId failed: '
                + e.getMessage()
            );

            orgWideEmailAddressId = null;
        }


        return orgWideEmailAddressId;
    }
}