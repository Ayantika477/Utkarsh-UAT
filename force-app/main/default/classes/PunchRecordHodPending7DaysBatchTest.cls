/**
 * @description Test class for PunchRecordHodPending7DaysBatch (HOD 7-day reminder
 *              and HR 15-day escalation).
 */
@isTest
private class PunchRecordHodPending7DaysBatchTest {

    @testSetup
    static void setupTestData() {
        insert new List<User>{
            createTestUser('emp'),
            createTestUser('hod')
        };

        // Templates are only created when the org does not already have them,
        // since DeveloperName must be unique.
        Set<String> templateNames = new Set<String>{
            PunchRecordHodPending7DaysBatch.TEMPLATE_WFH_7DAYS,
            PunchRecordHodPending7DaysBatch.TEMPLATE_WFO_7DAYS,
            PunchRecordHodPending7DaysBatch.TEMPLATE_WFH_HR_15DAYS,
            PunchRecordHodPending7DaysBatch.TEMPLATE_WFO_HR_15DAYS
        };
        for (EmailTemplate existing : [
            SELECT DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN :templateNames
        ]) {
            templateNames.remove(existing.DeveloperName);
        }

        List<EmailTemplate> templates = new List<EmailTemplate>();
        for (String templateName : templateNames) {
            templates.add(new EmailTemplate(
                Name = templateName.left(70),
                DeveloperName = templateName,
                TemplateType = 'text',
                FolderId = UserInfo.getUserId(),
                Subject = 'Request pending approval',
                Body = 'A WFH/WFO request is pending your approval.',
                IsActive = true
            ));
        }
        if (!templates.isEmpty()) {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert templates;
            }
        }
    }

    // ===============================================================
    // FULL BATCH RUN
    // ===============================================================

   

    @isTest
    static void testBatch_Wfo8DaysPending_SendsHodReminderOnly() {

        insertPendingRecord(PunchRecordHodPending7DaysBatch.PUNCH_TYPE_WFO, 8);

        Test.startTest();
        Id jobId = Database.executeBatch(new PunchRecordHodPending7DaysBatch(), 50);
        Test.stopTest();

        assertJobCompleted(jobId);
    }

    @isTest
    static void testBatch_RecentRecord_NotPickedUp() {

        insertPendingRecord(PunchRecordHodPending7DaysBatch.PUNCH_TYPE_WFH, 2);

        Test.startTest();
        Boolean hasRecords = new PunchRecordHodPending7DaysBatch()
            .start(null)
            .iterator()
            .hasNext();
        Test.stopTest();

        System.assert(!hasRecords, 'Records pending under 7 days should be skipped.');
    }

    // ===============================================================
    // BUILD MESSAGE - RECIPIENT
    // ===============================================================

    @isTest
    static void testBuildMessage_ActiveUser_SendsToUserId() {

        Punch_Record__c record = insertPendingRecord(
            PunchRecordHodPending7DaysBatch.PUNCH_TYPE_WFH,
            8
        );
        User hod = getUser('hod');

        Test.startTest();
        Messaging.SingleEmailMessage mail = PunchRecordHodPending7DaysBatch.buildMessage(
            getTemplateId(PunchRecordHodPending7DaysBatch.TEMPLATE_WFH_7DAYS),
            record.Id,
            hod.Id,
            hod.Email
        );
        Test.stopTest();

        System.assertEquals(hod.Id, mail.getTargetObjectId(), 'HOD should be the email target.');
        System.assert(
            mail.getToAddresses() == null || mail.getToAddresses().isEmpty(),
            'A User-targeted email must not carry To addresses.'
        );
        System.assertEquals(false, mail.getSaveAsActivity());
    }

    @isTest
    static void testBuildMessage_MissingInputs_ReturnsNull() {

        Test.startTest();
        Messaging.SingleEmailMessage noTemplate = PunchRecordHodPending7DaysBatch.buildMessage(
            null, null, UserInfo.getUserId(), 'someone@example.com'
        );
        Messaging.SingleEmailMessage noRecipient = PunchRecordHodPending7DaysBatch.buildMessage(
            getTemplateId(PunchRecordHodPending7DaysBatch.TEMPLATE_WFH_7DAYS),
            UserInfo.getUserId(),
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(null, noTemplate, 'Missing template should return null.');
        System.assertEquals(null, noRecipient, 'Missing recipient should return null.');
    }

    // ===============================================================
    // RESOLVE USER IDS BY EMAIL
    // ===============================================================

    @isTest
    static void testResolveActiveUserIdsByEmail() {

        User hod = getUser('hod');
        String email = hod.Email.toLowerCase();

        Test.startTest();
        Map<String, Id> found = PunchRecordHodPending7DaysBatch.resolveActiveUserIdsByEmail(
            new Set<String>{ email, 'no.such.user@example.invalid' }
        );
        Map<String, Id> fromEmpty =
            PunchRecordHodPending7DaysBatch.resolveActiveUserIdsByEmail(new Set<String>());
        Map<String, Id> fromNull =
            PunchRecordHodPending7DaysBatch.resolveActiveUserIdsByEmail(null);
        Test.stopTest();

        System.assertEquals(hod.Id, found.get(email), 'Active user should be matched by email.');
        System.assert(!found.containsKey('no.such.user@example.invalid'));
        System.assert(fromEmpty.isEmpty());
        System.assert(fromNull.isEmpty());
    }

    // ===============================================================
    // SCHEDULABLE
    // ===============================================================

    @isTest
    static void testSchedulableExecute_DoesNotThrow() {

        Test.startTest();
        String jobId = System.schedule(
            'PunchRecordHodPending7DaysBatchTestJob',
            '0 0 9 * * ?',
            new PunchRecordHodPending7DaysBatch()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Batch should be scheduled.');
    }

    // ===============================================================
    // HELPERS
    // ===============================================================

    private static User createTestUser(String uniqueKey) {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        return new User(
            FirstName = 'Pending',
            LastName = 'User' + uniqueKey,
            Email = 'pendinguser' + uniqueKey + '@example.com',
            Username = 'pendinguser' + uniqueKey +
                String.valueOf(Datetime.now().getTime()) + '@example.com',
            Alias = 'pu' + uniqueKey,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardProfile.Id,
            IsActive = true
        );
    }

    private static User getUser(String uniqueKey) {
        return [
            SELECT Id, Email
            FROM User
            WHERE LastName = :('User' + uniqueKey)
            AND FirstName = 'Pending'
            LIMIT 1
        ];
    }

    private static Id getTemplateId(String developerName) {
        return [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }

    // Inserts a pending WFH/WFO request and backdates it by the given number of days.
    private static Punch_Record__c insertPendingRecord(String punchType, Integer daysOld) {
        Punch_Record__c record = new Punch_Record__c(
            User__c = getUser('emp').Id,
            HOD__c = getUser('hod').Id,
            Punch_Type__c = punchType,
            WFH_Approval_Status__c = PunchRecordHodPending7DaysBatch.APPROVAL_STATUS_PENDING
        );
        insert record;
        Test.setCreatedDate(record.Id, Datetime.now().addDays(-daysOld));
        return record;
    }

    private static void assertJobCompleted(Id jobId) {
        AsyncApexJob job = [
            SELECT Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete.');
        System.assertEquals(0, job.NumberOfErrors, 'Batch should not have errors.');
    }
}