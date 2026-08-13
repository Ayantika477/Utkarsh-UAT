@IsTest
private class OfflineCampaignManagementControllerTest {
  @IsTest
  static void searchOfflineCampaignsReturnsMatchingActiveRecords() {
    Offline_Campaign__c activeRecord = new Offline_Campaign__c(
      Name = 'Offline Test',
      Phone__c = '9876543210',
      Email__c = 'offline.test@example.com',
      Department__c = 'Crash Barrier',
      Active__c = true
    );
    Offline_Campaign__c inactiveRecord = new Offline_Campaign__c(
      Name = 'Offline Inactive',
      Phone__c = '9876543210',
      Email__c = 'inactive@example.com',
      Department__c = 'Crash Barrier',
      Active__c = false
    );
    insert new List<Offline_Campaign__c>{ activeRecord, inactiveRecord };

    Test.startTest();
    List<Offline_Campaign__c> results = OfflineCampaignManagementController.searchOfflineCampaigns(
      'Offline Test',
      '9876',
      'offline.test',
      'Crash'
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals(activeRecord.Id, results[0].Id);
  }
}