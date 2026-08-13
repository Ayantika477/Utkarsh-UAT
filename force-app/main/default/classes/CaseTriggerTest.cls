@isTest
private class CaseTriggerTest {
    @isTest
    static void testCreatorSharing() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User testOwner = new User(
            Alias = 'towner',
            Email = 'testowner@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestingOwner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testownerCaseShare' + DateTime.now().getTime() + '@example.com'
        );
        insert testOwner;

        Case c = new Case(
            Subject = 'Test Case Creator Share',
            Status = 'Open',
            OwnerId = testOwner.Id
        );

        Test.startTest();
        insert c;
        Test.stopTest();

        List<CaseShare> shares = [SELECT UserOrGroupId, CaseAccessLevel, RowCause FROM CaseShare WHERE CaseId = :c.Id AND UserOrGroupId = :UserInfo.getUserId()];
        System.assert(!shares.isEmpty(), 'A CaseShare record should have been created for the creator');
        System.assertEquals('Edit', shares[0].CaseAccessLevel, 'The CaseShare access level should be Edit');
    }
}