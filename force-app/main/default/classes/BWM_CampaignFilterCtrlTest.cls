@IsTest
private class BWM_CampaignFilterCtrlTest {
    @TestSetup
    static void setupData() {
        insert new List<Lead>{
            new Lead(
                LastName = 'Filter Lead',
                Company = 'Filter Co',
                Status = 'Prospect',
                Department_Name__c = 'Crash Barrier',
                Country__c = 'India',
                State__c = 'West Bengal'
            )
        };

        Account accountRecord = new Account(
            Name = 'Filter Account',
            Phone = '9876543210',
            Email__c = 'filter.account@example.com',
            Department_Name__c = 'Crash Barrier',
            Country__c = 'India',
            State__c = 'Maharashtra'
        );
        insert accountRecord;

        insert new Contact(
            LastName = 'Filter Contact',
            AccountId = accountRecord.Id,
            Email = 'filter.contact@example.com',
            Phone = '9876543211',
            Country__c = 'India',
            State__c = 'Karnataka'
        );

        insert new Opportunity(
            Name = 'Filter Opportunity',
            StageName = 'Nurture',
            CloseDate = Date.today().addDays(30),
            Department_Name__c = 'Crash Barrier',
            Country__c = 'India',
            State__c = 'Delhi'
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
        Test.stopTest();
    }

    @IsTest
    static void searchMethodsApplyFilters() {
        Test.startTest();
        List<Lead> leads = BWM_CampaignFilterCtrl.searchLeads(
            'Filter',
            new List<String>{ 'Prospect' },
            'Crash',
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
                'Crash',
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
            'Crash',
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
        Test.stopTest();

        System.assertEquals(1, leads.size());
        System.assertEquals(1, opportunities.size());
        System.assertEquals(1, accounts.size());
        System.assertEquals(1, contacts.size());
    }
}