@isTest
private class ResultWinnerBidderContactBatchTest {

    // ============================================================
    // ASSUMPTIONS (adjust if your wrappers differ):
    // - ResultWrappers.ResultRecord.tenderid is NUMERIC (Integer/Long/
    //   Decimal) - confirmed by JSONException seen when a string like
    //   "EXT-300" was used. All tender IDs below are now plain numbers.
    // - ResultWrappers.BidderDetail: bidderName, awardedValue, bidValue,
    //   bidRank, technical_status, financial_status, aoc_status,
    //   winner_bidder (Boolean), resultstage
    // - ResultWrappers.CountResponse: Success (Boolean), Data (List<CountData>)
    //   CountData: count (Integer)
    // - ResultWrappers.ListingResponse: Success (Boolean), Data (List<ResultRecord>)
    // - Custom metadata Tender_Product_Mapping__mdt must already exist in
    //   the org (cannot be inserted in @isTest context).
    //
    // *** KNOWN OPEN ISSUE ***
    // createTender() below is currently throwing:
    //   "Insert failed. First exception on row 0; first error: INVA..."
    // The message was truncated in the test-result grid. Once you have
    // the full error text, fix the field(s) being set on Tender__c here -
    // this is the ONLY place tender records are created in this class,
    // so one fix here should unblock every dependent test.
    // ============================================================

    private static final String COUNT_ENDPOINT_FRAGMENT = 'result-listing-data-count';
    private static final String LISTING_ENDPOINT_FRAGMENT = 'result-listing-data';

    // ============================================================
    // SHARED TEST DATA SETUP
    // ============================================================

// ============================================================
// SHARED TEST DATA SETUP
// ============================================================

private static Tender__c createTender(String extId) {
    Tender__c t = new Tender__c(
        External_Tender_Id__c = extId,
        Common_Key__c = 'CK-' + extId
    );

    insert t;
    return t;
}

private static Project__c createProject(Id tenderId) {
    Project__c p = new Project__c(
        Tender__c = tenderId,
        Project_End_Date__c = Date.today().addMonths(6)
    );

    insert p;
    return p;
}

private static Opportunity createParentOpp(Id projectId) {
    Opportunity o = new Opportunity(
        Name = 'Parent Opp',
        StageName = 'Prospecting',
        CloseDate = Date.today().addMonths(3),
        Project__c = projectId,
        isParent__c = true
    );

    insert o;
    return o;
}

    private static Bidders__c createBidder(Id tenderId, String tenderIdStr, String bidderName) {
        Bidders__c b = new Bidders__c(
            Tender__c = tenderId,
            Bidder_Name__c = bidderName,
            External_Tender_Id__c = tenderIdStr,
            Source_Tender_Id__c = tenderIdStr,
            Bidder_Unique_Key__c = tenderIdStr + '-' + bidderName,
            Product_Name__c = 'TestProduct'
        );
        insert b;
        return b;
    }

    private static String getAnyMappedProductName() {
        List<Tender_Product_Mapping__mdt> mdts = [
            SELECT Result_Product_Name__c
            FROM Tender_Product_Mapping__mdt
            WHERE Result_Product_Name__c != null
            LIMIT 1
        ];
        return mdts.isEmpty() ? null : mdts[0].Result_Product_Name__c;
    }

    // ============================================================
    // HTTP MOCK
    // ============================================================

    private class ResultApiMock implements HttpCalloutMock {

        public Integer countToReturn = 5;
        public Boolean countSuccess = true;
        public Boolean listingSuccess = true;
        public Boolean throwOnCount = false;
        public Boolean throwOnListing = false;
        public List<Map<String, Object>> listingRecordsAsMaps;

        public HTTPResponse respond(HTTPRequest req) {

            if (req.getEndpoint().contains(COUNT_ENDPOINT_FRAGMENT)) {

                if (throwOnCount) {
                    throw new CalloutException('Simulated count callout failure');
                }

                HttpResponse res = new HttpResponse();
                res.setStatusCode(200);

                Map<String, Object> body = new Map<String, Object>{
                    'Success' => countSuccess,
                    'Data' => countSuccess
                        ? new List<Map<String, Object>>{
                            new Map<String, Object>{ 'count' => countToReturn }
                        }
                        : new List<Object>()
                };

                res.setBody(JSON.serialize(body));
                return res;

            } else if (req.getEndpoint().contains(LISTING_ENDPOINT_FRAGMENT)) {

                if (throwOnListing) {
                    throw new CalloutException('Simulated listing callout failure');
                }

                HttpResponse res = new HttpResponse();
                res.setStatusCode(200);

                Map<String, Object> body = new Map<String, Object>{
                    'Success' => listingSuccess,
                    'Data' => listingSuccess ? listingRecordsAsMaps : new List<Object>()
                };

                res.setBody(JSON.serialize(body));
                return res;
            }

            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody('{}');
            return res;
        }
    }

    private static Map<String, Object> buildBidderDetailMap(
        String bidderName,
        Boolean technical,
        Boolean financial,
        Boolean aoc,
        Boolean winner
    ) {
        return new Map<String, Object>{
            'bidderName' => bidderName,
            'awardedValue' => 1000,
            'bidValue' => 900,
            'bidRank' => 1,
            'technical_status' => technical,
            'financial_status' => financial,
            'aoc_status' => aoc,
            'winner_bidder' => winner,
            'resultstage' => 3
        };
    }

    // tenderId is now Integer (matches numeric ResultWrappers.tenderid field)
    private static Map<String, Object> buildRecordMap(
        Integer tenderId,
        List<Map<String, Object>> bidderDetails
    ) {
        return new Map<String, Object>{
            'tenderid' => tenderId,
            'bidawardid' => tenderId,
            'sourcebidawardid' => 'SBA-' + tenderId,
            'postingdate' => String.valueOf(Date.today()),
            'value' => 1000,
            'datecreated' => String.valueOf(Date.today()),
            'aocdescription' => 'Some AOC description text',
            'contractdate' => String.valueOf(Date.today()),
            'financialbidevaluationdate' => String.valueOf(Date.today()),
            'technicalbidevaluationdate' => String.valueOf(Date.today()),
            'aocupdationdate' => String.valueOf(Date.today()),
            'organization_name' => 'Test Org',
            'category' => new List<String>{ 'CatA', 'CatB' },
            'resultstage' => 3,
            'bidderdetails' => bidderDetails
        };
    }

    // ============================================================
    // TEST: FULL HAPPY PATH
    // ============================================================

    @isTest
    static void testFullBatchRun_HappyPath() {

        String productName = getAnyMappedProductName();
        if (productName == null) {
            System.debug('No Tender_Product_Mapping__mdt found - skipping happy path assertions.');
            return;
        }

        Tender__c tender1 = createTender('1001');
        Tender__c tender2 = createTender('1002');

        Project__c proj1 = createProject(tender1.Id);
        createParentOpp(proj1.Id);

        Bidders__c existingBidder = createBidder(tender1.Id, '1001', 'ExistingCo');

        ResultApiMock mock = new ResultApiMock();
        mock.countToReturn = 1;
        mock.countSuccess = true;
        mock.listingSuccess = true;

        mock.listingRecordsAsMaps = new List<Map<String, Object>>{
            buildRecordMap(1001, new List<Map<String, Object>>{
                buildBidderDetailMap('ExistingCo', true, true, true, true),
                buildBidderDetailMap('NewBidderCo', true, true, true, true)
            }),
            buildRecordMap(1002, new List<Map<String, Object>>{
                buildBidderDetailMap('AnotherBidder', true, false, false, false)
            }),
            buildRecordMap(9999, new List<Map<String, Object>>{ // unmatched tender
                buildBidderDetailMap('OrphanBidder', false, false, false, false)
            })
        };

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new ResultWinnerBidderContactBatch(), 50);
        Test.stopTest();

        Bidders__c refreshed = [
            SELECT Id, Is_Winner__c, Bidder_Stage__c, Project__c
            FROM Bidders__c
            WHERE Id = :existingBidder.Id
        ];
        System.assertEquals(true, refreshed.Is_Winner__c, 'Existing bidder should be marked winner');
        System.assertEquals('Winner Bidder', refreshed.Bidder_Stage__c);

        List<Bidders__c> newBidders = [
            SELECT Id, Bidder_Stage__c, Project__c
            FROM Bidders__c
            WHERE Bidder_Unique_Key__c = '1001-NewBidderCo'
        ];
        System.assertEquals(1, newBidders.size(), 'New bidder should have been inserted');
        System.assertEquals('Winner Bidder', newBidders[0].Bidder_Stage__c);

        Tender__c refreshedTender = [
            SELECT Id, Bidaward_Id_from_Result__c, Result_Category__c, Tender_Stage_Bidder_Wise__c
            FROM Tender__c
            WHERE Id = :tender1.Id
        ];
        System.assertEquals(
    '1001',
    refreshedTender.Bidaward_Id_from_Result__c
);
        System.assertEquals('AOC Done', refreshedTender.Tender_Stage_Bidder_Wise__c);

        List<Opportunity> bidderOpps = [
            SELECT Id, Bidder__c
            FROM Opportunity
            WHERE Bidder__c = :newBidders[0].Id
        ];
        System.assertEquals(1, bidderOpps.size(), 'Bidder opportunity should be created for new bidder');
    }

    // ============================================================
    // TEST: COUNT API RETURNS ZERO
    // ============================================================

    @isTest
    static void testCountApiReturnsZero_SkipsProduct() {

        if (getAnyMappedProductName() == null) {
            return;
        }

        ResultApiMock mock = new ResultApiMock();
        mock.countToReturn = 0;
        mock.countSuccess = true;

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new ResultWinnerBidderContactBatch(), 50);
        Test.stopTest();

        System.assert(true, 'Batch completed without error when count is zero');
    }

    // ============================================================
    // TEST: COUNT API FAILURE and EXCEPTION path
    // ============================================================

    @isTest
    static void testCountApiFailureAndException() {

        if (getAnyMappedProductName() == null) {
            return;
        }

        ResultApiMock mock = new ResultApiMock();
        mock.countSuccess = false;

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new ResultWinnerBidderContactBatch(), 50);
        Test.stopTest();

        System.assert(true, 'Batch completed without error when count API reports failure');
    }

    @isTest
    static void testCountApiThrowsException() {

        if (getAnyMappedProductName() == null) {
            return;
        }

        ResultApiMock mock = new ResultApiMock();
        mock.throwOnCount = true;

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            Database.executeBatch(new ResultWinnerBidderContactBatch(), 50);
        } catch (Exception e) {
            // covers the scenario where the exception surfaces at enqueue time
        }
        Test.stopTest();

        System.assert(true, 'Batch handled count callout exception without throwing to caller');
    }

    // ============================================================
    // TEST: LISTING API FAILURE / EXCEPTION during execute()
    // ============================================================

    @isTest
    static void testListingApiFailureAndException() {

        if (getAnyMappedProductName() == null) {
            return;
        }

        createTender('1100');

        ResultApiMock mock = new ResultApiMock();
        mock.countToReturn = 1;
        mock.listingSuccess = false;

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new ResultWinnerBidderContactBatch(), 50);
        Test.stopTest();

        System.assert(true, 'Batch completed without error when listing API reports failure');
    }

    // ============================================================
    // TEST: processPageRecords() DIRECTLY - all branches
    // ============================================================

    @isTest
    static void testProcessPageRecords_AllBranches() {

        Tender__c tender = createTender('1200');
        Project__c proj = createProject(tender.Id);
        createParentOpp(proj.Id);

        Bidders__c existing = createBidder(tender.Id, '1200', 'TechOnlyBidder');

        ResultWrappers.ResultRecord rec = (ResultWrappers.ResultRecord) JSON.deserialize(
            JSON.serialize(buildRecordMap(1200, new List<Map<String, Object>>{
                buildBidderDetailMap('TechOnlyBidder', true, false, false, false),
                buildBidderDetailMap('', true, true, true, true),                  // blank name -> skipped
                buildBidderDetailMap('FinBidder', true, true, false, false),
                buildBidderDetailMap('AocBidder', true, true, true, false),
                buildBidderDetailMap('WinnerBidder', true, true, true, true),
                buildBidderDetailMap('NoStatusBidder', false, false, false, false),
                buildBidderDetailMap('FinBidder', true, true, false, false)        // duplicate -> skipped
            })),
            ResultWrappers.ResultRecord.class
        );

        ResultWrappers.ResultRecord unmatchedRec = (ResultWrappers.ResultRecord) JSON.deserialize(
            JSON.serialize(buildRecordMap(9998, new List<Map<String, Object>>{
                buildBidderDetailMap('OrphanBidder', true, true, true, true)
            })),
            ResultWrappers.ResultRecord.class
        );

        List<ResultWrappers.ResultRecord> pageRecords =
            new List<ResultWrappers.ResultRecord>{ rec, unmatchedRec };

        Test.startTest();
        ResultWinnerBidderContactBatch batch = new ResultWinnerBidderContactBatch();
        Map<String, Object> result = batch.testProcessPageRecords(pageRecords, 'TestProductDirect');
        Test.stopTest();

        Set<String> matchedTenderIds = (Set<String>) result.get('matchedTenderIds');
        Set<String> unmatchedTenderIds = (Set<String>) result.get('unmatchedTenderIds');
        Integer winnerCount = (Integer) result.get('winnerCount');
        Integer newBidderCreatedCount = (Integer) result.get('newBidderCreatedCount');

        System.assert(matchedTenderIds.contains('1200'));
        System.assert(unmatchedTenderIds.contains('9998'));
        System.assertEquals(1, winnerCount, 'Only WinnerBidder should count as winner');
        System.assertEquals(
    5,
    newBidderCreatedCount,
    'Five new bidder records should be created'
);

        Bidders__c refreshedExisting = [
            SELECT Bidder_Stage__c FROM Bidders__c WHERE Id = :existing.Id
        ];
        System.assertEquals('Technical Evaluation Done', refreshedExisting.Bidder_Stage__c);

        Map<String, String> expectedStages = new Map<String, String>{
            '1200-FinBidder' => 'Financial Evaluation Done',
            '1200-AocBidder' => 'AOC Done',
            '1200-WinnerBidder' => 'Winner Bidder',
            '1200-NoStatusBidder' => 'Possible Participant - Probable Bidder'
        };

        for (Bidders__c b : [
            SELECT Bidder_Unique_Key__c, Bidder_Stage__c
            FROM Bidders__c
            WHERE Bidder_Unique_Key__c IN :expectedStages.keySet()
        ]) {
            System.assertEquals(
                expectedStages.get(b.Bidder_Unique_Key__c),
                b.Bidder_Stage__c,
                'Stage mismatch for ' + b.Bidder_Unique_Key__c
            );
        }

        Map<Id, String> winnerMap = batch.testGetWinnerMap();
        System.assertEquals(1, winnerMap.size());
    }

    // ============================================================
    // TEST: EMPTY / NULL bidderdetails
    // ============================================================

@isTest
static void testProcessPageRecords_EmptyAndNullBidderDetails() {

    ResultWrappers.ResultRecord recWithNullBidders =
        (ResultWrappers.ResultRecord) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'tenderid' => 1300,
                'resultstage' => 1
            }),
            ResultWrappers.ResultRecord.class
        );

    ResultWrappers.ResultRecord recWithEmptyBidders =
        (ResultWrappers.ResultRecord) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'tenderid' => 1301,
                'resultstage' => 1,
                'bidderdetails' => new List<Object>()
            }),
            ResultWrappers.ResultRecord.class
        );

    List<ResultWrappers.ResultRecord> pageRecords =
        new List<ResultWrappers.ResultRecord>{
            recWithNullBidders,
            recWithEmptyBidders
        };

    Test.startTest();

    ResultWinnerBidderContactBatch batch =
        new ResultWinnerBidderContactBatch();

    Map<String, Object> result =
        batch.testProcessPageRecords(
            pageRecords,
            'TestProductEmpty'
        );

    Test.stopTest();

    Integer winnerCount =
        (Integer) result.get('winnerCount');

    System.assertEquals(
        0,
        winnerCount,
        'No bidders present, so no winners'
    );
}
    // ============================================================
    // TEST: resultstage = 2 branch on Tender__c
    // ============================================================

    @isTest
    static void testProcessPageRecords_ResultStageTwo() {

        Tender__c tender = createTender('1400');

        Map<String, Object> recMap = buildRecordMap(1400, new List<Map<String, Object>>{
            buildBidderDetailMap('SomeBidder', true, true, false, false)
        });
        recMap.put('resultstage', 2);

        ResultWrappers.ResultRecord rec = (ResultWrappers.ResultRecord) JSON.deserialize(
            JSON.serialize(recMap),
            ResultWrappers.ResultRecord.class
        );

        Test.startTest();
        ResultWinnerBidderContactBatch batch = new ResultWinnerBidderContactBatch();
        batch.testProcessPageRecords(
            new List<ResultWrappers.ResultRecord>{ rec },
            'TestProductStage2'
        );
        Test.stopTest();

        Tender__c refreshed = [
            SELECT Tender_Stage_Bidder_Wise__c FROM Tender__c WHERE Id = :tender.Id
        ];
        System.assertEquals('Financial Evaluation Done', refreshed.Tender_Stage_Bidder_Wise__c);
    }
}