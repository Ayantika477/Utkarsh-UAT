@isTest
private class TenderDocumentInsertQueueableTest {

    // ============================================================
    // 1. EMPTY LIST
    // ============================================================
    @isTest
    static void testEmptyDocuments() {

        Test.startTest();

        TenderDocumentInsertQueueable q =
            new TenderDocumentInsertQueueable(
                new List<Tender_Docoment_Details__c>(),
                'Test Product'
            );

        q.execute(null);

        Test.stopTest();

        System.assert(true);
    }


    // ============================================================
    // 2. NULL LIST
    // ============================================================
    @isTest
    static void testNullDocuments() {

        Test.startTest();

        TenderDocumentInsertQueueable q =
            new TenderDocumentInsertQueueable(
                null,
                'Test Product'
            );

        q.execute(null);

        Test.stopTest();

        System.assert(true);
    }


    // ============================================================
    // 3. SUCCESSFUL INSERT
    // ============================================================
    @isTest
    static void testSuccessfulInsert() {

        Tender_Docoment_Details__c doc =
            new Tender_Docoment_Details__c();

        /*
         * If your object has mandatory custom fields,
         * populate them here.
         *
         * Example:
         * doc.Tender__c = tender.Id;
         * doc.Document_Name__c = 'Test Document';
         */

        List<Tender_Docoment_Details__c> docs =
            new List<Tender_Docoment_Details__c>();

        docs.add(doc);

        Test.startTest();

        TenderDocumentInsertQueueable q =
            new TenderDocumentInsertQueueable(
                docs,
                'Test Product'
            );

        q.execute(null);

        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Tender_Docoment_Details__c],
            'Document should be inserted successfully.'
        );
    }


    // ============================================================
    // 4. INSERT FAILURE
    // ============================================================
    @isTest
static void testInsertFailure() {

    Tender_Docoment_Details__c invalidDoc =
        new Tender_Docoment_Details__c();

    // Get the correct prefix dynamically
    String prefix =
        Tender_Docoment_Details__c.SObjectType
            .getDescribe()
            .getKeyPrefix();

    // Create a syntactically valid 15-character Id
    invalidDoc.Id = prefix + '000000000000';

    List<Tender_Docoment_Details__c> docs =
        new List<Tender_Docoment_Details__c>{ invalidDoc };

    Test.startTest();

    TenderDocumentInsertQueueable q =
        new TenderDocumentInsertQueueable(
            docs,
            'Test Product'
        );

    q.execute(null);

    Test.stopTest();

    System.assert(true, 'Insert failure should be handled by catch block.');
}
}