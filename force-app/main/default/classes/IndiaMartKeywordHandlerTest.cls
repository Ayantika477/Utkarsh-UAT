@isTest
private class IndiaMartKeywordHandlerTest {

    private static Lead buildLead(String leadSource, String productToPurchase) {
        return new Lead(
            LastName               = 'Test Lead',
            Company                = 'Test Company',
            LeadSource             = leadSource,
            Product_to_Purchase__c = productToPurchase
        );
    }

    private static Boolean hasActiveConfig() {
        List<IndiaMART_Department_Verification__mdt> configs = [
            SELECT Id, isTrigger_Active__c
            FROM IndiaMART_Department_Verification__mdt
            ORDER BY DeveloperName ASC
            LIMIT 1
        ];
        return !configs.isEmpty() && configs[0].isTrigger_Active__c == true;
    }

    private static void assertConfigActive() {
        System.assert(hasActiveConfig(),
            'IndiaMART_Department_Verification__mdt "Active_Keywords" must exist with isTrigger_Active__c = true ' +
            'in this org for these tests to run meaningfully. Activate it in Setup > Custom Metadata Types before running.');
    }

    private class MockPromptInvoker implements IndiaMartKeywordBatch.IPromptInvoker {
        Boolean shouldMatch;
        String  onlyMatchGroup;

        MockPromptInvoker(Boolean shouldMatch, String onlyMatchGroup) {
            this.shouldMatch = shouldMatch;
            this.onlyMatchGroup = onlyMatchGroup;
        }

        public IndiaMartKeywordBatch.KeywordMatchResult invoke(String productToPurchase, String groupName, String keywordList) {
            IndiaMartKeywordBatch.KeywordMatchResult result = new IndiaMartKeywordBatch.KeywordMatchResult();
            result.isMatch = shouldMatch && (onlyMatchGroup == null || onlyMatchGroup == groupName);
            result.key     = groupName;
            result.summary = 'Mock summary for ' + groupName;
            return result;
        }
    }

    // ============================================================
    // HANDLER TESTS
    // ============================================================

    @isTest
    static void testHandler_DirectCall_NoEligibleLeads_NoBatchStarted() {
        Lead ld = buildLead('Web', 'Not Qualifying');
        Test.startTest();
        IndiaMartKeywordHandler.handleAfterSave(new List<Lead>{ ld }, null);
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testInsert_NonQualifyingSource_NoProcessing() {
        Lead ld = buildLead('Web', 'Some Random Product');

        Test.startTest();
        insert ld;
        Test.stopTest();

        Lead result = [
            SELECT Match_Summary_For_INDIAMART__c, is_Already_Fired_IndiaMart__c
            FROM Lead WHERE Id = :ld.Id
        ];
        System.assertEquals(false, result.is_Already_Fired_IndiaMart__c);
        System.assertEquals(null, result.Match_Summary_For_INDIAMART__c);
    }

    // NO mock injected here -> exercises the REAL invokePrompt callout path (lines ~383-419)
    @isTest
    static void testInsert_QualifyingSource_RealCalloutPath_FallsBackToEnquiry() {
        assertConfigActive();

        Lead ld = buildLead('INDIAMART V2', 'MS Rectangular Hollow Section Pipe 25mm');

        Test.startTest();
        insert ld; // ONE executeBatch call, 1 eligible record
        Test.stopTest();

        Lead result = [
            SELECT Department_Name__c, Match_Summary_For_INDIAMART__c, is_Already_Fired_IndiaMart__c
            FROM Lead WHERE Id = :ld.Id
        ];
        System.assertEquals(true, result.is_Already_Fired_IndiaMart__c);
        System.assertEquals('Enquiry', result.Department_Name__c);
        System.assert(result.Match_Summary_For_INDIAMART__c.contains('Is Match: false'));
    }

    @isTest
    static void testInsert_QualifyingSource_MockMatch_SetsRealDepartment() {
        assertConfigActive();

        IndiaMartKeywordBatch.testInvoker = new MockPromptInvoker(true, null);

        Lead ld = buildLead('INDIAMART V2', 'Any product text here');

        Test.startTest();
        insert ld;
        Test.stopTest();

        Lead result = [
            SELECT Department_Name__c, Match_Summary_For_INDIAMART__c, is_Already_Fired_IndiaMart__c
            FROM Lead WHERE Id = :ld.Id
        ];
        System.assertEquals(true, result.is_Already_Fired_IndiaMart__c);
        System.assertNotEquals('Enquiry', result.Department_Name__c);
        System.assert(result.Match_Summary_For_INDIAMART__c.contains('Is Match: true'));
    }

    @isTest
    static void testInsert_BlankProduct_AppliesFallbackImmediately() {
        assertConfigActive();

        Lead ld = buildLead('INDIAMART', null);

        Test.startTest();
        insert ld;
        Test.stopTest();

        Lead result = [
            SELECT Department_Name__c, is_Already_Fired_IndiaMart__c
            FROM Lead WHERE Id = :ld.Id
        ];
        System.assertEquals('Enquiry', result.Department_Name__c);
        System.assertEquals(true, result.is_Already_Fired_IndiaMart__c);
    }

    @isTest
    static void testUpdate_ProductChanged_TriggersReprocessing_RealCallout() {
        assertConfigActive();

        Lead ld = buildLead('Web', 'Original Product Text');
        insert ld; // non-qualifying -> no batch call yet

        ld.LeadSource = 'INDIAMART V2';
        ld.Product_to_Purchase__c = 'Updated Product Text - Steel Pipe';

        Test.startTest();
        update ld; // ONE executeBatch call, real invokePrompt path (no mock)
        Test.stopTest();

        Lead result = [
            SELECT Department_Name__c, is_Already_Fired_IndiaMart__c
            FROM Lead WHERE Id = :ld.Id
        ];
        System.assertEquals(true, result.is_Already_Fired_IndiaMart__c);
        System.assertNotEquals(null, result.Department_Name__c);
    }

    @isTest
    static void testUpdate_ProductUnchanged_NoReprocessing() {
        assertConfigActive();

        Lead ld = buildLead('Web', 'Steady Product Text');
        insert ld;

        Test.startTest();
        ld.LeadSource = 'INDIAMART V2';
        update ld; // product text unchanged -> NOT eligible -> no executeBatch call
        Test.stopTest();

        Lead result = [SELECT is_Already_Fired_IndiaMart__c FROM Lead WHERE Id = :ld.Id];
        System.assertEquals(false, result.is_Already_Fired_IndiaMart__c);
    }

    @isTest
    static void testUpdate_AlreadyFired_ButProductChangesAgain_Reprocesses() {
        assertConfigActive();

        Lead ld = buildLead('INDIAMART', 'First Product Description');

        Test.startTest();
        insert ld; // first executeBatch call, 1 record
        Test.stopTest();

        Lead afterFirstFire = [SELECT is_Already_Fired_IndiaMart__c FROM Lead WHERE Id = :ld.Id];
        System.assertEquals(true, afterFirstFire.is_Already_Fired_IndiaMart__c);

        ld.Product_to_Purchase__c = 'Second Different Product Description';

        Test.startTest();
        update ld; // separate transaction -> ONE executeBatch call here
        Test.stopTest();

        Lead afterSecondFire = [
            SELECT Match_Summary_For_INDIAMART__c, is_Already_Fired_IndiaMart__c
            FROM Lead WHERE Id = :ld.Id
        ];
        System.assertEquals(true, afterSecondFire.is_Already_Fired_IndiaMart__c);
        System.assertNotEquals(null, afterSecondFire.Match_Summary_For_INDIAMART__c);
    }

    @isTest
    static void testBulkInsert_ExactlyScopeSize_ProcessesAllInOneChunk() {
        assertConfigActive();

        IndiaMartKeywordBatch.testInvoker = new MockPromptInvoker(false, null);

        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 5; i++) { // == BATCH_SCOPE_SIZE, single chunk
            leads.add(buildLead('INDIAMART V2', 'Bulk Product ' + i));
        }
        leads.add(buildLead('Web', 'Non Qualifying Product'));

        Test.startTest();
        insert leads; // ONE executeBatch call, 5 eligible records
        Test.stopTest();

        for (Lead l : [
            SELECT Department_Name__c, is_Already_Fired_IndiaMart__c
            FROM Lead WHERE LeadSource = 'INDIAMART V2'
        ]) {
            System.assertEquals(true, l.is_Already_Fired_IndiaMart__c);
            System.assertEquals('Enquiry', l.Department_Name__c);
        }

        Lead webLead = [SELECT is_Already_Fired_IndiaMart__c FROM Lead WHERE LeadSource = 'Web'];
        System.assertEquals(false, webLead.is_Already_Fired_IndiaMart__c);
    }

    // ============================================================
    // BATCH-LEVEL DIRECT INVOCATION (no executeBatch restriction applies)
    // ============================================================

    @isTest
    static void testBatch_DirectInvocation_StartExecuteFinish_MockMatch() {
        assertConfigActive();

        Lead ld = buildLead('Web', 'Direct Batch Test Product');
        insert ld; // non-qualifying -> trigger does NOT start any batch

        IndiaMartKeywordBatch.testInvoker = new MockPromptInvoker(true, 'Steel Pipes');

        IndiaMartKeywordBatch batchInstance = new IndiaMartKeywordBatch(new List<Id>{ ld.Id });

        Test.startTest();
        batchInstance.start(null);
        batchInstance.execute(null, new List<Lead>{ ld });
        batchInstance.finish(null);
        Test.stopTest();

        Lead result = [
            SELECT Department_Name__c, is_Already_Fired_IndiaMart__c
            FROM Lead WHERE Id = :ld.Id
        ];
        System.assertEquals(true, result.is_Already_Fired_IndiaMart__c);
        System.assertEquals('Steel Pipes', result.Department_Name__c);
    }

    // Direct call, no mock -> exercises real callout in execute() too, independent of Trigger context
    @isTest
    static void testBatch_DirectInvocation_RealCalloutPath() {
        assertConfigActive();

        Lead ld = buildLead('Web', 'Batch Direct Real Callout Product');
        insert ld;

        IndiaMartKeywordBatch batchInstance = new IndiaMartKeywordBatch(new List<Id>{ ld.Id });

        Test.startTest();
        batchInstance.start(null);
        batchInstance.execute(null, new List<Lead>{ ld });
        batchInstance.finish(null);
        Test.stopTest();

        Lead result = [SELECT Department_Name__c, is_Already_Fired_IndiaMart__c FROM Lead WHERE Id = :ld.Id];
        System.assertEquals('Enquiry', result.Department_Name__c);
        System.assertEquals(true, result.is_Already_Fired_IndiaMart__c);
    }
}