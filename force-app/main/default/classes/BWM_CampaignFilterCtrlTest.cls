@IsTest
private class BWM_CampaignFilterCtrlTest {
    @TestSetup
    static void setupData() {
        insert as system new List<Lead>{
            new Lead(
                LastName = 'Filter Lead ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                Company = 'Filter Co ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                Status = 'Prospect',
                Department_Name__c = 'Crash Barrier',
                Country__c = 'India',
                State__c = 'West Bengal'
            )
        };

        Account accountRecord = new Account(
            Name = 'Filter Account ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Phone = '9876543210',
            Email__c = 'filter.account@example.com',
            Department_Name__c = 'Crash Barrier',
            Country__c = 'India',
            State__c = 'Maharashtra'
        );
        insert as system accountRecord;

        insert as system new Contact(
            LastName = 'Filter Contact ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            AccountId = accountRecord.Id,
            Email = 'filter.contact+' + String.valueOf(Math.abs(Crypto.getRandomInteger())) + '@example.com',
            Phone = '9876543211',
            Country__c = 'India',
            State__c = 'Karnataka'
        );

        insert as system new Opportunity(
            Name = 'Filter Opportunity ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            StageName = 'Nurture',
            CloseDate = Date.today().addDays(30),
            Department_Name__c = 'Crash Barrier',
            Country__c = 'India',
            State__c = 'Delhi'
        );

        insert as system new Offline_Campaign__c(
            Name = 'Filter Offline Campaign ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Phone__c = '9876543212',
            Email__c = 'filter.offline@example.com',
            Department__c = 'Crash Barrier',
            Group_List__c = 'North Region List',
            Active__c = true
        );
    }

    @IsTest
    static void picklistOptionsLoad() {
        Test.startTest();
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getLeadCustomerCategoryOptions());
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getLeadCountryOptions());
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getLeadStateOptions());
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getOpportunityCustomerCategoryOptions());
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getOpportunityCountryOptions());
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getOpportunityStateOptions());
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getAccountCountryOptions());
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getAccountStateOptions());
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getContactCountryOptions());
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getContactStateOptions());
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getLeadDepartmentOptions());
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getOpportunityDepartmentOptions());
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getAccountDepartmentOptions());
        System.assertNotEquals(null, BWM_CampaignFilterCtrl.getOfflineCampaignDepartmentOptions());
        Test.stopTest();
    }

    @IsTest
    static void searchLeadsIncludesQualifiedStage() {
        insert as system new Lead(
            LastName = 'Qualified Filter Lead',
            Company = 'Qualified Co',
            Status = 'Qualified',
            Department_Name__c = 'Crash Barrier'
        );

        Test.startTest();
        List<Lead> leads = BWM_CampaignFilterCtrl.searchLeads(
            'Qualified Filter',
            new List<String>{ 'Qualified' },
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(1, leads.size());
        System.assertEquals('Qualified', leads[0].Status);
    }

    @IsTest
    static void searchMethodsApplyFilters() {
        Test.startTest();
        List<Lead> leads = BWM_CampaignFilterCtrl.searchLeads(
            'Filter',
            new List<String>{ 'Prospect' },
            new List<String>{ 'Crash Barrier' },
            null,
            null,
            Date.today().addDays(-1),
            Date.today().addDays(1),
            null,
            'India',
            new List<String>{ 'West Bengal' }
        );
        List<DealerOpportunityManagementController.OpportunityListItem> opportunities =
            BWM_CampaignFilterCtrl.searchDealerOpportunities(
                'Filter',
                null,
                new List<String>{ 'Nurture' },
                new List<String>{ 'Crash Barrier' },
                null,
                Date.today().addDays(-1),
                Date.today().addDays(1),
                null,
                'India',
                new List<String>{ 'Delhi' }
            );
        List<Account> accounts = BWM_CampaignFilterCtrl.searchAccounts(
            'Filter',
            '9876',
            'filter.account',
            new List<String>{ 'Crash Barrier' },
            'India',
            new List<String>{ 'Maharashtra' }
        );
        List<Contact> contacts = BWM_CampaignFilterCtrl.searchContacts(
            'Filter',
            '9876',
            'filter.contact',
            'India',
            new List<String>{ 'Karnataka' }
        );
        List<Offline_Campaign__c> offlineCampaigns = BWM_CampaignFilterCtrl.searchOfflineCampaigns(
            'Filter Offline',
            '9876',
            'filter.offline',
            new List<String>{ 'Crash Barrier' },
            'North Region List'
        );
        Test.stopTest();

        System.assertEquals(1, leads.size());
        System.assertEquals(1, opportunities.size());
        System.assertEquals(1, accounts.size());
        System.assertEquals(1, contacts.size());
        System.assertEquals(1, offlineCampaigns.size());
    }

    @IsTest
    static void searchOfflineCampaignsUsesPartialGroupListMatch() {
        insert as system new List<Offline_Campaign__c>{
            new Offline_Campaign__c(
                Name = 'Trial Group A ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                Group_List__c = 'Trial Batch 1',
                Active__c = true
            ),
            new Offline_Campaign__c(
                Name = 'Trial Group B ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                Group_List__c = 'October trial list',
                Active__c = true
            ),
            new Offline_Campaign__c(
                Name = 'Other Group ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                Group_List__c = 'Dealer Meet',
                Active__c = true
            )
        };

        Test.startTest();
        List<Offline_Campaign__c> trialMatches = BWM_CampaignFilterCtrl.searchOfflineCampaigns(
            null,
            null,
            null,
            null,
            'trial'
        );
        List<Offline_Campaign__c> batchMatches = BWM_CampaignFilterCtrl.searchOfflineCampaigns(
            null,
            null,
            null,
            null,
            '  batch 1 '
        );
        Test.stopTest();

        System.assertEquals(2, trialMatches.size(), 'trial should match every group containing trial');
        for (Offline_Campaign__c row : trialMatches) {
            System.assert(row.Group_List__c.containsIgnoreCase('trial'), row.Group_List__c);
        }
        System.assertEquals(1, batchMatches.size());
        System.assertEquals('Trial Batch 1', batchMatches[0].Group_List__c);
    }

    @IsTest
    static void searchOfflineCampaignsByGroupMatchUsesExactNameWhenPicked() {
        insert as system new List<Offline_Campaign__c>{
            new Offline_Campaign__c(Name = 'Pick A', Group_List__c = 'Test', Active__c = true),
            new Offline_Campaign__c(Name = 'Pick B', Group_List__c = 'Test 1', Active__c = true),
            new Offline_Campaign__c(Name = 'Pick C', Group_List__c = 'Test7octcamp', Active__c = true)
        };

        Test.startTest();
        List<Offline_Campaign__c> picked = BWM_CampaignFilterCtrl.searchOfflineCampaignsByGroupMatch(
            null,
            null,
            null,
            null,
            'Test',
            true
        );
        List<Offline_Campaign__c> typed = BWM_CampaignFilterCtrl.searchOfflineCampaignsByGroupMatch(
            null,
            null,
            null,
            null,
            'Test',
            false
        );
        Test.stopTest();

        System.assertEquals(1, picked.size(), 'Picked name should return only that group');
        System.assertEquals('Test', picked[0].Group_List__c);
        System.assertEquals(3, typed.size(), 'Typed text should still match partially');
    }

    @IsTest
    static void searchOfflineCampaignGroupListsReturnsDistinctMatchingNames() {
        insert as system new List<Offline_Campaign__c>{
            new Offline_Campaign__c(Name = 'Suggest A', Group_List__c = 'test group', Active__c = true),
            new Offline_Campaign__c(Name = 'Suggest B', Group_List__c = 'test group', Active__c = true),
            new Offline_Campaign__c(Name = 'Suggest C', Group_List__c = 'Second Test', Active__c = true),
            new Offline_Campaign__c(Name = 'Suggest D', Group_List__c = 'test inactive', Active__c = false),
            new Offline_Campaign__c(Name = 'Suggest E', Group_List__c = 'Dealer Meet', Active__c = true)
        };

        Test.startTest();
        List<String> names = BWM_CampaignFilterCtrl.searchOfflineCampaignGroupLists(' test ');
        List<String> blankNames = BWM_CampaignFilterCtrl.searchOfflineCampaignGroupLists('  ');
        Test.stopTest();

        System.assertEquals(2, names.size(), String.valueOf(names));
        System.assert(new Set<String>(names).contains('test group'));
        System.assert(new Set<String>(names).contains('Second Test'));
        System.assertEquals(0, blankNames.size());
    }
}