@isTest
private class CreateDealerOpportunityControllerTest {

    private static final String DEALER_ACCOUNT_RT_DEV_NAME = 'Dealer';

    // Pick a valid Industry__c value at runtime so a restricted picklist can't fail the insert.
    private static String firstIndustryValue() {
        List<Schema.PicklistEntry> entries =
            Opportunity.Industry__c.getDescribe().getPicklistValues();
        return entries.isEmpty() ? null : entries[0].getValue();
    }

    private static Account getAccountByName(String name) {
        return [SELECT Id, Name, Phone, Email__c FROM Account WHERE Name = :name LIMIT 1];
    }

    @TestSetup
    static void makeData() {
        Id rtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get(DEALER_ACCOUNT_RT_DEV_NAME)
            ?.getRecordTypeId();

        // Alpha: has Phone + Email__c and a Contact (no fallback needed)
        Account alpha = new Account(
            Name = 'Dealer Alpha',
            RecordTypeId = rtId,
            Phone = '111-111-1111',
            Email__c = 'alpha@dealer.test'
        );
        // Beta: blank Phone/Email__c -> exercises the Contact fallback
        Account beta = new Account(
            Name = 'Dealer Beta',
            RecordTypeId = rtId
        );
        // Gamma: has fields but NO Contact -> exercises the no-contact-role branch
        Account gamma = new Account(
            Name = 'Dealer Gamma',
            RecordTypeId = rtId,
            Phone = '333-333-3333',
            Email__c = 'gamma@dealer.test'
        );
        insert new List<Account>{ alpha, beta, gamma };

        insert new List<Contact>{
            new Contact(
                LastName = 'Alpha Contact',
                AccountId = alpha.Id,
                Email = 'alpha.contact@dealer.test',
                Phone = '999-999-9999'
            ),
            new Contact(
                LastName = 'Beta Contact',
                AccountId = beta.Id,
                Email = 'beta.contact@dealer.test',
                Phone = '888-888-8888'
            )
        };
    }

    @isTest
    static void testGetOpportunityRecordTypeId() {
        Id expected = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(BWM_EmailConstants.DEALER_OPPORTUNITY_RECORD_TYPE)
            ?.getRecordTypeId();

        Test.startTest();
        Id actual = CreateDealerOpportunityController.getOpportunityRecordTypeId();
        Test.stopTest();

        System.assertEquals(expected, actual,
            'Should return the Dealer_Opportunity record type id resolved from schema.');
    }

    @isTest
    static void testGetDealerAccounts() {
        Test.startTest();
        List<CreateDealerOpportunityController.DealerAccountOption> options =
            CreateDealerOpportunityController.getDealerAccounts();
        Test.stopTest();

        System.assert(!options.isEmpty(), 'Dealer accounts should be returned.');
        Set<String> names = new Set<String>();
        for (CreateDealerOpportunityController.DealerAccountOption opt : options) {
            System.assertNotEquals(null, opt.id, 'Option id should be populated.');
            names.add(opt.name);
        }
        System.assert(names.contains('Dealer Alpha'), 'Alpha should be present.');
        System.assert(names.contains('Dealer Beta'), 'Beta should be present.');
        System.assert(names.contains('Dealer Gamma'), 'Gamma should be present.');
    }

    @isTest
    static void testGetDealerDetailsUsesAccountFields() {
        Account alpha = getAccountByName('Dealer Alpha');

        Test.startTest();
        CreateDealerOpportunityController.DealerDetails details =
            CreateDealerOpportunityController.getDealerDetails(alpha.Id);
        Test.stopTest();

        System.assertEquals('111-111-1111', details.phone, 'Phone should come from the Account.');
        System.assertEquals('alpha@dealer.test', details.email, 'Email should come from the Account.');
        System.assertNotEquals(null, details.contactId, 'Contact should be resolved.');
        System.assertEquals('Alpha Contact', details.contactName, 'Contact name should match.');
    }

    @isTest
    static void testGetDealerDetailsFallsBackToContact() {
        Account beta = getAccountByName('Dealer Beta');

        Test.startTest();
        CreateDealerOpportunityController.DealerDetails details =
            CreateDealerOpportunityController.getDealerDetails(beta.Id);
        Test.stopTest();

        // Account has no Phone/Email__c, so both fall back to the Contact.
        System.assertEquals('888-888-8888', details.phone, 'Phone should fall back to the Contact.');
        System.assertEquals('beta.contact@dealer.test', details.email, 'Email should fall back to the Contact.');
        System.assertNotEquals(null, details.contactId, 'Contact should be resolved.');
    }

    @isTest
    static void testGetDealerDetailsNullAccountThrows() {
        Boolean thrown = false;
        Test.startTest();
        try {
            CreateDealerOpportunityController.getDealerDetails(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown, 'A null account should raise an AuraHandledException.');
    }

    @isTest
    static void testCreateDealerOpportunitySuccess() {
        Account alpha = getAccountByName('Dealer Alpha');
        Date closeDate = Date.today().addDays(30);
        Decimal amount = 250000;
        String industry = firstIndustryValue();

        Test.startTest();
        Id oppId = CreateDealerOpportunityController.createDealerOpportunity(
            alpha.Id, closeDate, amount, industry, null
        );
        Test.stopTest();

        System.assertNotEquals(null, oppId, 'Opportunity should be created.');

        Opportunity opp = [
            SELECT Id, Name, RecordTypeId, DealerAccount__c, CloseDate, Amount,
                   Industry__c, StageName, Customer_Journey__c, Phone__c, Email__c
            FROM Opportunity
            WHERE Id = :oppId
        ];

        System.assertEquals(alpha.Id, opp.DealerAccount__c, 'Dealer account should be set.');
        System.assertEquals(closeDate, opp.CloseDate, 'Close date should be set.');
        System.assertEquals(amount, opp.Amount, 'Amount should be set.');
        System.assertEquals(industry, opp.Industry__c, 'Industry should be set.');
        System.assertEquals(BWM_EmailConstants.STAGE_NEGOTIATION, opp.StageName,
            'Stage should be Negotiation.');
        System.assertEquals(BWM_EmailConstants.CUSTOMER_JOURNEY_REFER_DEALER, opp.Customer_Journey__c,
            'Customer journey should be Refer to Dealer.');
        System.assertEquals('Dealer Alpha - Dealer Opportunity', opp.Name,
            'Default name should be built from the Account name.');
        System.assertEquals('111-111-1111', opp.Phone__c, 'Phone should be copied to the Opportunity.');
        System.assertEquals('alpha@dealer.test', opp.Email__c, 'Email should be copied to the Opportunity.');
        System.assertEquals(CreateDealerOpportunityController.getOpportunityRecordTypeId(),
            opp.RecordTypeId, 'Record type should be Dealer_Opportunity.');

        List<OpportunityContactRole> roles = [
            SELECT Id, IsPrimary, Role, ContactId
            FROM OpportunityContactRole
            WHERE OpportunityId = :oppId
        ];
        System.assertEquals(1, roles.size(), 'One contact role should be created.');
        System.assertEquals(true, roles[0].IsPrimary, 'Contact role should be primary.');
        System.assertEquals('Decision Maker', roles[0].Role, 'Role should be Decision Maker.');
    }

    @isTest
    static void testCreateDealerOpportunityWithCustomName() {
        Account alpha = getAccountByName('Dealer Alpha');

        Test.startTest();
        Id oppId = CreateDealerOpportunityController.createDealerOpportunity(
            alpha.Id, Date.today().addDays(10), 1000, firstIndustryValue(), '  Custom Deal Name  '
        );
        Test.stopTest();

        Opportunity opp = [SELECT Id, Name FROM Opportunity WHERE Id = :oppId];
        System.assertEquals('Custom Deal Name', opp.Name, 'Provided name should be trimmed and used.');
    }

    @isTest
    static void testCreateDealerOpportunityNoContact() {
        Account gamma = getAccountByName('Dealer Gamma');

        Test.startTest();
        Id oppId = CreateDealerOpportunityController.createDealerOpportunity(
            gamma.Id, Date.today().addDays(15), 5000, firstIndustryValue(), null
        );
        Test.stopTest();

        System.assertNotEquals(null, oppId, 'Opportunity should be created even without a contact.');
        Integer roleCount = [
            SELECT COUNT() FROM OpportunityContactRole WHERE OpportunityId = :oppId
        ];
        System.assertEquals(0, roleCount, 'No contact role should exist when the dealer has no contacts.');
    }

    @isTest
    static void testCreateDealerOpportunityNullAccountThrows() {
        Boolean thrown = false;
        Test.startTest();
        try {
            CreateDealerOpportunityController.createDealerOpportunity(
                null, Date.today(), 100, firstIndustryValue(), null
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown, 'A null account should raise an AuraHandledException.');
    }

    @isTest
    static void testCreateDealerOpportunityNullCloseDateThrows() {
        Account alpha = getAccountByName('Dealer Alpha');
        Boolean thrown = false;
        Test.startTest();
        try {
            CreateDealerOpportunityController.createDealerOpportunity(
                alpha.Id, null, 100, firstIndustryValue(), null
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown, 'A null close date should raise an AuraHandledException.');
    }
}