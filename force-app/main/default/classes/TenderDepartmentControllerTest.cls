@isTest
private class TenderDepartmentControllerTest {

    // ============================================================
    // TEST DATA
    // ============================================================

    @TestSetup
    static void setup() {

        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
            LIMIT 1
        ];

        String uniqueValue = String.valueOf(DateTime.now().getTime());

        // --------------------------------------------------------
        // Tender User
        // --------------------------------------------------------
        User tenderUser = new User(
            FirstName         = 'Test',
            LastName          = 'TenderUser',
            Alias             = 'ttu',
            Email             = 'tender.user.' + uniqueValue + '@example.com',
            Username          = 'tender.user.' + uniqueValue + '@example.com',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Department        = 'Finance; Procurement/Legal',
            TenderUser__c     = true,
            IsActive          = true
        );

        insert tenderUser;


        // --------------------------------------------------------
        // Non Tender User
        // --------------------------------------------------------
        User nonTenderUser = new User(
            FirstName         = 'Test',
            LastName          = 'NonTenderUser',
            Alias             = 'tntu',
            Email             = 'nontender.user.' + uniqueValue + '@example.com',
            Username          = 'nontender.user.' + uniqueValue + '@example.com',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Department        = 'Finance',
            TenderUser__c     = false,
            IsActive          = true
        );

        insert nonTenderUser;


        // --------------------------------------------------------
        // Tender User with blank Department
        // Covers String.isBlank(u.Department)
        // --------------------------------------------------------
        User blankDepartmentUser = new User(
            FirstName         = 'Test',
            LastName          = 'BlankDepartmentUser',
            Alias             = 'bdu',
            Email             = 'blank.department.' + uniqueValue + '@example.com',
            Username          = 'blank.department.' + uniqueValue + '@example.com',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Department        = null,
            TenderUser__c     = true,
            IsActive          = true
        );

        insert blankDepartmentUser;


        // --------------------------------------------------------
        // Find valid Tender Department
        // --------------------------------------------------------
        String department = getFirstValidDepartment();

        System.assertNotEquals(
            null,
            department,
            'At least one valid Tender Department is required.'
        );


        // --------------------------------------------------------
        // Main Tender
        // --------------------------------------------------------
        Tender__c tender = new Tender__c(
            Department_Name__c = department
        );

        insert tender;


        // --------------------------------------------------------
        // Related Bidder
        // --------------------------------------------------------
        Bidders__c bidder = new Bidders__c(
            Name = 'Test Bidder',
            Tender__c = tender.Id
        );

        insert bidder;


        // --------------------------------------------------------
        // Related Bidder Contact
        // --------------------------------------------------------
        Bidders_Contact_Details__c contact =
            new Bidders_Contact_Details__c(
                Name = 'Test Bidder Contact',
                Tender__c = tender.Id
            );

        insert contact;


        // --------------------------------------------------------
        // Related AI Summary
        // --------------------------------------------------------
        Tender_Ai_Summary_Json__c summary =
            new Tender_Ai_Summary_Json__c(
                Tender__c = tender.Id
            );

        insert summary;


        // --------------------------------------------------------
        // Related Document
        // --------------------------------------------------------
        Tender_Docoment_Details__c document =
            new Tender_Docoment_Details__c(
                Tender__c = tender.Id
            );

        insert document;
    }


    // ============================================================
    // HELPER - FIRST VALID DEPARTMENT
    // ============================================================

    private static String getFirstValidDepartment() {

        for (
            Schema.PicklistEntry pe :
            Tender__c.Department_Name__c
                .getDescribe()
                .getPicklistValues()
        ) {

            if (
                pe.isActive() &&
                !pe.getValue().equalsIgnoreCase('Enquiry')
            ) {
                return pe.getValue();
            }
        }

        return null;
    }


    // ============================================================
    // HELPER - GET DIFFERENT VALID DEPARTMENT
    // ============================================================

    private static String getValidDepartment(
        String currentDepartment
    ) {

        for (
            Schema.PicklistEntry pe :
            Tender__c.Department_Name__c
                .getDescribe()
                .getPicklistValues()
        ) {

            if (
                pe.isActive() &&
                !pe.getValue().equalsIgnoreCase('Enquiry') &&
                pe.getValue() != currentDepartment
            ) {
                return pe.getValue();
            }
        }

        // If only one valid department exists,
        // use the same one.
        return currentDepartment;
    }


    // ============================================================
    // HELPER - CREATE TENDER USER
    // ============================================================

    private static User createTenderUser(
        String department
    ) {

        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
            LIMIT 1
        ];

        String uniqueValue =
            String.valueOf(DateTime.now().getTime());

        User u = new User(
            FirstName         = 'New',
            LastName          = 'DepartmentOwner',
            Alias             = 'ndow',
            Email             = 'new.owner.' +
                                uniqueValue +
                                '@example.com',
            Username          = 'new.owner.' +
                                uniqueValue +
                                '@example.com',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Department        = department,
            TenderUser__c     = true,
            IsActive          = true
        );

        insert u;

        return u;
    }


    // ============================================================
    // getTenderDetails - SUCCESS
    // ============================================================

    @isTest
    static void testGetTenderDetails_Success() {

        Tender__c tender = [
            SELECT
                Id,
                Department_Name__c,
                OwnerId
            FROM Tender__c
            LIMIT 1
        ];

        Test.startTest();

        TenderDepartmentController.TenderInfo info =
            TenderDepartmentController.getTenderDetails(
                tender.Id
            );

        Test.stopTest();

        System.assertNotEquals(
            null,
            info
        );

        System.assertEquals(
            tender.Department_Name__c,
            info.department
        );

        System.assertEquals(
            tender.OwnerId,
            info.ownerId
        );
    }


    // ============================================================
    // getTenderDetails - NULL ID
    // ============================================================

    @isTest
    static void testGetTenderDetails_NullId() {

        Boolean exceptionThrown = false;

        Test.startTest();

        try {

            TenderDepartmentController.getTenderDetails(null);

        } catch (AuraHandledException e) {

            exceptionThrown = true;
        }

        Test.stopTest();

        System.assert(
            exceptionThrown,
            'Expected exception for null Tender Id.'
        );
    }


    // ============================================================
    // getDepartments
    // ============================================================

    @isTest
    static void testGetDepartments() {

        Test.startTest();

        List<TenderDepartmentController.PicklistOption>
            options =
            TenderDepartmentController.getDepartments();

        Test.stopTest();

        System.assertNotEquals(
            null,
            options
        );

        System.assert(
            options.size() > 0,
            'At least one department should be returned.'
        );

        for (
            TenderDepartmentController.PicklistOption option :
            options
        ) {

            System.assertNotEquals(
                'Enquiry',
                option.value,
                'Enquiry must be excluded.'
            );

            System.assertNotEquals(
                null,
                option.label
            );

            System.assertNotEquals(
                null,
                option.value
            );
        }
    }


    // ============================================================
    // getDepartmentUsers - BLANK
    // ============================================================

    @isTest
    static void testGetDepartmentUsers_Blank() {

        Test.startTest();

        List<TenderDepartmentController.UserOption>
            result =
            TenderDepartmentController.getDepartmentUsers('');

        Test.stopTest();

        System.assertEquals(
            0,
            result.size()
        );
    }


    // ============================================================
    // getDepartmentUsers - NULL
    // ============================================================

    @isTest
    static void testGetDepartmentUsers_Null() {

        Test.startTest();

        List<TenderDepartmentController.UserOption>
            result =
            TenderDepartmentController.getDepartmentUsers(null);

        Test.stopTest();

        System.assertEquals(
            0,
            result.size()
        );
    }


    // ============================================================
    // getDepartmentUsers - FINANCE
    // ============================================================

    @isTest
    static void testGetDepartmentUsers_Finance() {

        Test.startTest();

        List<TenderDepartmentController.UserOption>
            result =
            TenderDepartmentController.getDepartmentUsers(
                'Finance'
            );

        Test.stopTest();

        System.assertEquals(
            1,
            result.size(),
            'Finance should return the Tender User.'
        );

        System.assertEquals(
            'Test TenderUser',
            result[0].label
        );

        System.assertNotEquals(
            null,
            result[0].value
        );

        System.assert(
            result[0].department.contains('Finance')
        );
    }


    // ============================================================
    // getDepartmentUsers - LEGAL
    // ============================================================

    @isTest
    static void testGetDepartmentUsers_Legal() {

        Test.startTest();

        List<TenderDepartmentController.UserOption>
            result =
            TenderDepartmentController.getDepartmentUsers(
                'legal'
            );

        Test.stopTest();

        System.assertEquals(
            1,
            result.size(),
            'Legal should match Procurement/Legal.'
        );

        System.assertEquals(
            'Test TenderUser',
            result[0].label
        );
    }


    // ============================================================
    // getDepartmentUsers - NO MATCH
    // ============================================================

    @isTest
    static void testGetDepartmentUsers_NoMatch() {

        Test.startTest();

        List<TenderDepartmentController.UserOption>
            result =
            TenderDepartmentController.getDepartmentUsers(
                'Marketing'
            );

        Test.stopTest();

        System.assertEquals(
            0,
            result.size()
        );
    }


    // ============================================================
    // updateDepartmentAndOwner
    // NULL TENDER ID
    // ============================================================

    @isTest
    static void testUpdateDepartmentAndOwner_NullTenderId() {

        User owner = [
            SELECT Id
            FROM User
            WHERE LastName = 'TenderUser'
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        Test.startTest();

        try {

            TenderDepartmentController.updateDepartmentAndOwner(
                null,
                'Finance',
                owner.Id
            );

        } catch (AuraHandledException e) {

            exceptionThrown = true;
        }

        Test.stopTest();

        System.assert(
            exceptionThrown,
            'Expected exception for null Tender Id.'
        );
    }


    // ============================================================
    // updateDepartmentAndOwner
    // BLANK DEPARTMENT
    // ============================================================

    @isTest
    static void testUpdateDepartmentAndOwner_BlankDepartment() {

        Tender__c tender = [
            SELECT Id
            FROM Tender__c
            LIMIT 1
        ];

        User owner = [
            SELECT Id
            FROM User
            WHERE LastName = 'TenderUser'
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        Test.startTest();

        try {

            TenderDepartmentController.updateDepartmentAndOwner(
                tender.Id,
                '',
                owner.Id
            );

        } catch (AuraHandledException e) {

            exceptionThrown = true;
        }

        Test.stopTest();

        System.assert(
            exceptionThrown,
            'Expected exception for blank Department.'
        );
    }


    // ============================================================
    // updateDepartmentAndOwner
    // NULL OWNER
    //
    // IMPORTANT:
    // Department_Name__c MUST be selected.
    // This fixes your SObject row error.
    // ============================================================

    @isTest
    static void testUpdateDepartmentAndOwner_NullOwnerId() {

        Tender__c tender = [
            SELECT
                Id,
                Department_Name__c
            FROM Tender__c
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        Test.startTest();

        try {

            TenderDepartmentController.updateDepartmentAndOwner(
                tender.Id,
                tender.Department_Name__c,
                null
            );

        } catch (AuraHandledException e) {

            exceptionThrown = true;
        }

        Test.stopTest();

        System.assert(
            exceptionThrown,
            'Expected exception for null Owner Id.'
        );
    }


    // ============================================================
    // SUCCESS + ALL RELATED RECORDS
    // ============================================================

    @isTest
    static void testUpdateDepartmentAndOwner_Success() {

        Tender__c tender = [
            SELECT
                Id,
                Department_Name__c,
                OwnerId
            FROM Tender__c
            LIMIT 1
        ];

        String newDepartment =
            getValidDepartment(
                tender.Department_Name__c
            );

        System.assertNotEquals(
            null,
            newDepartment
        );

        User newOwner =
            createTenderUser(newDepartment);

        Test.startTest();

        TenderDepartmentController.updateDepartmentAndOwner(
            tender.Id,
            newDepartment,
            newOwner.Id
        );

        Test.stopTest();


        // --------------------------------------------------------
        // Verify Tender
        // --------------------------------------------------------

        Tender__c updatedTender = [
            SELECT
                Id,
                Department_Name__c,
                OwnerId
            FROM Tender__c
            WHERE Id = :tender.Id
        ];

        System.assertEquals(
            newDepartment,
            updatedTender.Department_Name__c
        );

        System.assertEquals(
            newOwner.Id,
            updatedTender.OwnerId
        );


        // --------------------------------------------------------
        // Verify Bidders
        // --------------------------------------------------------

        List<Bidders__c> bidders = [
            SELECT
                Id,
                OwnerId
            FROM Bidders__c
            WHERE Tender__c = :tender.Id
        ];

        System.assertEquals(
            1,
            bidders.size()
        );

        for (Bidders__c bidder : bidders) {

            System.assertEquals(
                newOwner.Id,
                bidder.OwnerId
            );
        }


        // --------------------------------------------------------
        // Verify Contacts
        // --------------------------------------------------------

        List<Bidders_Contact_Details__c> contacts = [
            SELECT
                Id,
                OwnerId
            FROM Bidders_Contact_Details__c
            WHERE Tender__c = :tender.Id
        ];

        System.assertEquals(
            1,
            contacts.size()
        );

        for (
            Bidders_Contact_Details__c contact :
            contacts
        ) {

            System.assertEquals(
                newOwner.Id,
                contact.OwnerId
            );
        }


        // --------------------------------------------------------
        // Verify AI Summary
        // --------------------------------------------------------

        List<Tender_Ai_Summary_Json__c> summaries = [
            SELECT
                Id,
                OwnerId
            FROM Tender_Ai_Summary_Json__c
            WHERE Tender__c = :tender.Id
        ];

        System.assertEquals(
            1,
            summaries.size()
        );

        for (
            Tender_Ai_Summary_Json__c summary :
            summaries
        ) {

            System.assertEquals(
                newOwner.Id,
                summary.OwnerId
            );
        }


        // --------------------------------------------------------
        // Verify Documents
        // --------------------------------------------------------

        List<Tender_Docoment_Details__c> documents = [
            SELECT
                Id,
                OwnerId
            FROM Tender_Docoment_Details__c
            WHERE Tender__c = :tender.Id
        ];

        System.assertEquals(
            1,
            documents.size()
        );

        for (
            Tender_Docoment_Details__c document :
            documents
        ) {

            System.assertEquals(
                newOwner.Id,
                document.OwnerId
            );
        }
    }


    // ============================================================
    // SUCCESS - NO RELATED RECORDS
    // ============================================================

    @isTest
    static void testUpdateDepartmentAndOwner_NoRelatedRecords() {

        Tender__c originalTender = [
            SELECT
                Id,
                Department_Name__c
            FROM Tender__c
            LIMIT 1
        ];

        String department =
            getValidDepartment(
                originalTender.Department_Name__c
            );

        Tender__c tenderWithoutChildren =
            new Tender__c(
                Department_Name__c = department
            );

        insert tenderWithoutChildren;

        User newOwner =
            createTenderUser(department);

        Test.startTest();

        TenderDepartmentController.updateDepartmentAndOwner(
            tenderWithoutChildren.Id,
            department,
            newOwner.Id
        );

        Test.stopTest();


        // --------------------------------------------------------
        // Verify Tender
        // --------------------------------------------------------

        Tender__c updated = [
            SELECT
                Id,
                Department_Name__c,
                OwnerId
            FROM Tender__c
            WHERE Id = :tenderWithoutChildren.Id
        ];

        System.assertEquals(
            department,
            updated.Department_Name__c
        );

        System.assertEquals(
            newOwner.Id,
            updated.OwnerId
        );


        // --------------------------------------------------------
        // Verify no child records
        // --------------------------------------------------------

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Bidders__c
                WHERE Tender__c = :tenderWithoutChildren.Id
            ]
        );

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Bidders_Contact_Details__c
                WHERE Tender__c = :tenderWithoutChildren.Id
            ]
        );

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Tender_Ai_Summary_Json__c
                WHERE Tender__c = :tenderWithoutChildren.Id
            ]
        );

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Tender_Docoment_Details__c
                WHERE Tender__c = :tenderWithoutChildren.Id
            ]
        );
    }
}