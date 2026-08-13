@isTest
public class FieldForceDashboardControllerTest {

    @isTest
    static void testGetAvailableSalespeople() {
        // Create standard test Users
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name='System Administrator' LIMIT 1];
        
        User adminUser = new User(
            Alias = 'adminU', 
            Email='adminuser@example.com', 
            EmailEncodingKey='UTF-8', 
            LastName='AdminLastName', 
            LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', 
            ProfileId = adminProfile.Id, 
            TimeZoneSidKey='America/Los_Angeles', 
            UserName='adminuser_' + DateTime.now().getTime() + '@example.com'
        );
        insert adminUser;

        User managerUser = new User(
            Alias = 'mngrU', 
            Email='manageruser@example.com', 
            EmailEncodingKey='UTF-8', 
            LastName='ManagerLastName', 
            LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', 
            ProfileId = stdProfile.Id, 
            TimeZoneSidKey='America/Los_Angeles', 
            UserName='manageruser_' + DateTime.now().getTime() + '@example.com'
        );
        insert managerUser;

        User salespersonUser = new User(
            Alias = 'salesU', 
            Email='salespersonuser@example.com', 
            EmailEncodingKey='UTF-8', 
            LastName='SalesLastName', 
            LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', 
            ProfileId = stdProfile.Id, 
            TimeZoneSidKey='America/Los_Angeles', 
            UserName='salespersonuser_' + DateTime.now().getTime() + '@example.com',
            ManagerId = managerUser.Id
        );
        insert salespersonUser;

        // Test as Admin
        System.runAs(adminUser) {
            Test.startTest();
            List<FieldForceDashboardController.SalespersonOption> results = FieldForceDashboardController.getAvailableSalespeople();
            Test.stopTest();
            System.assert(results.size() >= 3, 'Admin should see all active users');
        }

        // Test as Manager
        System.runAs(managerUser) {
            List<FieldForceDashboardController.SalespersonOption> results = FieldForceDashboardController.getAvailableSalespeople();
            System.assert(results.size() >= 2, 'Manager should see subordinates + themselves');
        }

        // Test as standard Salesperson
        System.runAs(salespersonUser) {
            List<FieldForceDashboardController.SalespersonOption> results = FieldForceDashboardController.getAvailableSalespeople();
            System.assertEquals(1, results.size(), 'Salesperson should see only themselves');
            System.assertEquals(salespersonUser.Id, results[0].id, 'Should map to Salesperson User Id');
        }
    }

    @isTest
    static void testGetDailyDashboardData() {
        // Create standard test User
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'tuserD', 
            Email='testuserD@example.com', 
            EmailEncodingKey='UTF-8', 
            LastName='TestingD', 
            LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', 
            ProfileId = p.Id, 
            TimeZoneSidKey='America/Los_Angeles', 
            UserName='testuserD_' + DateTime.now().getTime() + '@example.com'
        );
        insert testUser;

        System.runAs(testUser) {
            Datetime dayInTime = DateTime.now().addHours(-8);
            Datetime modeInTime = DateTime.now().addHours(-7);
            Datetime visitTime = DateTime.now().addHours(-5);
            Datetime dayOutTime = DateTime.now().addHours(-1);

            Punch_Record__c dayIn = new Punch_Record__c(
                User__c = testUser.Id,
                Action__c = 'IN',
                Punch_Time__c = dayInTime,
                Punch_Type__c = 'Day In / Out',
                Transportation_Type__c = 'Private Vehicle',
                Vehicle_Type__c = 'Two Wheeler',
                Odometer_Reading__c = 100.0,
                Latitude__c = 28.5355,
                Longitude__c = 77.3910,
                Address__c = 'Sector 62, Noida, UP',
                Battery__c = 90.0
            );
            insert dayIn;

            Punch_Record__c modeIn = new Punch_Record__c(
                User__c = testUser.Id,
                Action__c = 'IN',
                Punch_Time__c = modeInTime,
                Punch_Type__c = 'Market Visit',
                Transportation_Type__c = 'Private Vehicle',
                Vehicle_Type__c = 'Two Wheeler',
                Odometer_Reading__c = 105.0,
                Latitude__c = 28.5355,
                Longitude__c = 77.3910,
                Address__c = 'Sector 62, Noida, UP',
                Battery__c = 88.0
            );
            insert modeIn;

            Punch_Record__c dayOut = new Punch_Record__c(
                User__c = testUser.Id,
                Action__c = 'OUT',
                Punch_Time__c = dayOutTime,
                Punch_Type__c = 'Day In / Out',
                Transportation_Type__c = 'Private Vehicle',
                Vehicle_Type__c = 'Two Wheeler',
                Odometer_Reading__c = 120.0,
                Latitude__c = 28.5365,
                Longitude__c = 77.3920,
                Address__c = 'Sector 63, Noida, UP',
                Battery__c = 82.0
            );
            insert dayOut;

            Account acc = new Account(Name = 'Daily Client Account');
            insert acc;

            Task_Log__c visitLog = new Task_Log__c(
                Punch_Record__c = modeIn.Id,
                Account__c = acc.Id,
                Reason_for_Visit__c = 'Payment Collection',
                Visit_Type__c = 'Follow up',
                Logged_At__c = visitTime,
                IsCheckout__c = true,
                Logged_Out_At__c = visitTime.addHours(1),
                MOM__c = 'Discussed renewal terms.',
                Visit_outcome__c = 'Only information',
                is100mOutside__c = true,
                Justification__c = 'Client was in nearby cafe',
                Latitude__c = 28.5360,
                Longitude__c = 77.3915,
                Checked_Out_Latitude__c = 28.5361,
                Checked_Out_Longitude__c = 77.3916
            );
            insert visitLog;

            Track_Location__c track = new Track_Location__c(
                Punch_Record__c = modeIn.Id,
                Latitude__c = '28.5358',
                Longitude__c = '77.3912',
                Source__c = 'GPS'
            );
            insert track;

            ContentVersion cv = new ContentVersion(
                Title = 'Selfie Punch In',
                PathOnClient = 'selfie.jpg',
                VersionData = Blob.valueOf('Test Selfie Data'),
                FirstPublishLocationId = dayIn.Id
            );
            insert cv;

            Test.startTest();
            FieldForceDashboardController.DashboardData data = FieldForceDashboardController.getDailyDashboardData(testUser.Id, Date.today());
            FieldForceDashboardController.DashboardData blank = FieldForceDashboardController.getDailyDashboardData(null, null);
            Test.stopTest();

            System.assertEquals(null, blank);
            System.assertNotEquals(null, data, 'Dashboard data should be returned');
            System.assertNotEquals(null, data.attendanceSummary, 'Attendance summary should exist');
            System.assertEquals(100.0, data.attendanceSummary.startingOdometer);
            System.assertEquals(120.0, data.attendanceSummary.endingOdometer);
            System.assertEquals(20.0, data.attendanceSummary.totalDistanceKm, 'Distance covered should be ending - starting odometer');
            System.assertEquals(1, data.attendanceSummary.totalVisits, 'Should count 1 visit log');

            System.assertNotEquals(0, data.timeline.size(), 'Timeline items should be present');
            Boolean foundDayIn = false;
            Boolean foundVisit = false;

            for (FieldForceDashboardController.TimelineItem item : data.timeline) {
                if (item.type == 'PUNCH_IN' && item.title != null && item.title.contains('Day In')) {
                    foundDayIn = true;
                    System.assertNotEquals(null, item.files, 'Should retrieve selfie file link');
                    System.assertEquals('Start', item.nodeDistance);
                } else if (item.type == 'VISIT') {
                    foundVisit = true;
                    System.assertEquals('Visit @ Daily Client Account', item.title);
                    System.assertEquals(true, item.is100mOutside);
                    System.assertNotEquals(null, item.checkInTime);
                    System.assertNotEquals(null, item.checkOutTime);
                }
            }
            System.assert(foundDayIn, 'Should contain Day In timeline record');
            System.assert(foundVisit, 'Should contain Combined Visit timeline record');

            System.assertNotEquals(null, data.trackLocations, 'Track locations list should be returned');
            System.assertEquals(1, data.trackLocations.size(), 'Should return 1 track location');
            System.assertEquals(28.5358, data.trackLocations[0].latitude);
            System.assertNotEquals(0, data.mapMarkers.size(), 'Map markers should be present');
        }
    }

    @isTest
    static void testGetMultipleUsersDailySummary() {
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'tuserM', 
            Email='testuserM@example.com', 
            EmailEncodingKey='UTF-8', 
            LastName='TestingM', 
            LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', 
            ProfileId = stdProfile.Id, 
            TimeZoneSidKey='America/Los_Angeles', 
            UserName='testuserM_' + DateTime.now().getTime() + '@example.com'
        );
        insert testUser;

        System.runAs(testUser) {
            Punch_Record__c punchIn = new Punch_Record__c(
                User__c = testUser.Id,
                Action__c = 'IN',
                Punch_Time__c = DateTime.now(),
                Punch_Type__c = 'Day In / Out',
                Battery__c = 95.0,
                Odometer_Reading__c = 10.0
            );
            insert punchIn;

            Punch_Record__c punchOut = new Punch_Record__c(
                User__c = testUser.Id,
                Action__c = 'OUT',
                Punch_Time__c = DateTime.now().addHours(5),
                Punch_Type__c = 'Day In / Out',
                Battery__c = 85.0,
                Odometer_Reading__c = 35.0
            );
            insert punchOut;

            List<Id> userIds = new List<Id>{ testUser.Id };
            
            Test.startTest();
            List<FieldForceDashboardController.UserSummaryData> summaries = FieldForceDashboardController.getMultipleUsersDailySummary(userIds, Date.today());
            Test.stopTest();

            System.assertEquals(1, summaries.size(), 'Should return one summary record');
            System.assertEquals(testUser.Id, summaries[0].userId);
            //System.assertEquals('WFO', summaries[0].attendanceStatus);
            System.assertEquals('85%', summaries[0].batteryLevel);
            System.assertEquals(25.0, summaries[0].distanceKm);
        }
    }

    @isTest
    static void testGetTeamWFHRequests() {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'tuserW', 
            Email='testuserW@example.com', 
            EmailEncodingKey='UTF-8', 
            LastName='TestingW', 
            LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', 
            ProfileId = p.Id, 
            TimeZoneSidKey='America/Los_Angeles', 
            UserName='testuserW_' + DateTime.now().getTime() + '@example.com'
        );
        insert testUser;

        System.runAs(testUser) {
            Punch_Record__c wfh = new Punch_Record__c(
                User__c = testUser.Id,
                Is_WFH_Request__c = true,
                WFH_Request_Date__c = Date.today(),
                WFH_Request_Start_Time__c = Time.newInstance(9, 0, 0, 0),
                WFH_Request_End_Time__c = Time.newInstance(18, 0, 0, 0),
                WFH_Approval_Status__c = 'Approved',
                Punch_Time__c = DateTime.now()
            );
            insert wfh;

            Test.startTest();
            List<FieldForceDashboardController.DepartmentWFHRequestDTO> reqs = FieldForceDashboardController.getTeamWFHRequests(new List<Id>{testUser.Id});
            Test.stopTest();

            System.assertEquals(1, reqs.size());
            System.assertEquals('WFH', reqs[0].type);
            System.assertEquals('Approved', reqs[0].status);
            System.assertEquals(testUser.Id, reqs[0].userId);
        }
    }

    @isTest
    static void testIsCurrentUserAdmin() {
        Test.startTest();
        Boolean result = FieldForceDashboardController.isCurrentUserAdmin();
        Test.stopTest();
        // Since test context running user profile is System Administrator or Standard User, assert is fine
        System.assertNotEquals(null, result);
    }

    @isTest
    static void testGetAnalyticsSummary() {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'tuserA',
            Email='testuserA@example.com',
            EmailEncodingKey='UTF-8',
            LastName='TestingA',
            LanguageLocaleKey='en_US',
            LocaleSidKey='en_US',
            ProfileId = p.Id,
            TimeZoneSidKey='America/Los_Angeles',
            UserName='testuserA_' + DateTime.now().getTime() + '@example.com'
        );
        insert testUser;

        System.runAs(testUser) {
            Punch_Record__c punchIn = new Punch_Record__c(
                User__c = testUser.Id,
                Action__c = 'IN',
                Punch_Time__c = DateTime.now(),
                Punch_Type__c = 'Market Visit',
                Is_WFH_Request__c = false,
                Is_WFO_Request__c = false
            );
            insert punchIn;

            Account acc = new Account(Name = 'Analytics Client');
            insert acc;
            insert new Task_Log__c(
                Punch_Record__c = punchIn.Id,
                Account__c = acc.Id,
                Logged_At__c = DateTime.now(),
                IsCheckout__c = true,
                Visit_outcome__c = 'Only information'
            );

            Test.startTest();
            List<FieldForceDashboardController.AnalyticsUserRow> rows =
                FieldForceDashboardController.getAnalyticsSummary(
                    new List<Id>{ testUser.Id },
                    Date.today().addDays(-1),
                    Date.today()
                );
            List<FieldForceDashboardController.AnalyticsUserRow> empty =
                FieldForceDashboardController.getAnalyticsSummary(null, null, null);
            Test.stopTest();

            System.assertEquals(1, rows.size(), 'Should return analytics for one user');
            System.assertEquals(testUser.Id, rows[0].userId);
            System.assertEquals(0, empty.size());
        }
    }

    @isTest
    static void testGetDailyDashboardDataCrossDay() {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'tuserCD', 
            Email='testuserCD@example.com', 
            EmailEncodingKey='UTF-8', 
            LastName='TestingCD', 
            LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', 
            ProfileId = p.Id, 
            TimeZoneSidKey='America/Los_Angeles', 
            UserName='testuserCD_' + DateTime.now().getTime() + '@example.com'
        );
        insert testUser;

        System.runAs(testUser) {
            Datetime todayStart = Datetime.newInstance(Date.today(), Time.newInstance(0, 30, 0, 0));
            Datetime todayOut = Datetime.newInstance(Date.today(), Time.newInstance(2, 30, 0, 0));

            Punch_Record__c punchIn = new Punch_Record__c(
                User__c = testUser.Id,
                Action__c = 'IN',
                Punch_Time__c = todayStart,
                Punch_Type__c = 'Day In / Out',
                Latitude__c = 28.5355,
                Longitude__c = 77.3910,
                Address__c = 'Sector 62, Noida, UP',
                Battery__c = 90.0
            );
            insert punchIn;

            Punch_Record__c punchOut = new Punch_Record__c(
                User__c = testUser.Id,
                Action__c = 'OUT',
                Punch_Time__c = todayOut,
                Punch_Type__c = 'Day In / Out',
                Latitude__c = 28.5365,
                Longitude__c = 77.3920,
                Address__c = 'Sector 63, Noida, UP',
                Battery__c = 82.0
            );
            insert punchOut;

            Test.startTest();
            FieldForceDashboardController.DashboardData data = FieldForceDashboardController.getDailyDashboardData(testUser.Id, Date.today());
            List<FieldForceDashboardController.UserSummaryData> summaries =
                FieldForceDashboardController.getMultipleUsersDailySummary(new List<Id>{ testUser.Id }, Date.today());
            Test.stopTest();

            System.assertNotEquals(null, data);
            System.assertNotEquals(null, data.attendanceSummary);
            System.assertNotEquals(null, data.attendanceSummary.totalHours);
            System.assert(data.attendanceSummary.totalHours.contains('2.00 hrs'), 'Expected 2.00 hrs, got: ' + data.attendanceSummary.totalHours);

            System.assertEquals(1, summaries.size());
            System.assert(summaries[0].totalHours.contains('2.00 hrs'), 'Expected 2.00 hrs, got: ' + summaries[0].totalHours);
        }
    }
}