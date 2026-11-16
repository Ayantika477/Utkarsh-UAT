@IsTest
private class InternalTicketVisibilityControllerTest {

    @IsTest
    static void returnsFalseWhenRunningUserIsNotAnL3() {
        User u = makeUser('L3 Test Off');
        System.runAs(u) {
            System.assertEquals(false, InternalTicketVisibilityController.isMatrixL3());
        }
    }

    @IsTest
    static void returnsTrueWhenRunningUserIsAnL3() {
        User u = makeUser('L3 Test On');
        insert new Internal_Ticket_Matrix__c(Name = 'Test Module', L3__c = u.Id);
        System.runAs(u) {
            System.assertEquals(true, InternalTicketVisibilityController.isMatrixL3());
        }
    }

    private static User makeUser(String lastName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'tl3' + String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 10000)),
            Email = 'l3test@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = lastName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = lastName.replace(' ', '') + System.currentTimeMillis() + '@example.com.test'
        );
        insert u;
        return u;
    }
}
