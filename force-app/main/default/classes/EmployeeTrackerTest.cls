@isTest
public class EmployeeTrackerTest {

    @TestSetup
    static void setupData() {
        // Create User Punch State
        User_Punch_State__c ups = new User_Punch_State__c(
            User__c = UserInfo.getUserId(),
            Current_Status__c = 'IN',
            Last_Punch_Time__c = System.now(),
            Latitude__c = 12.9716,
            Longitude__c = 77.5946,
            Battery_Percentage__c = 85
        );
        insert ups;

        // Create Account/Client
        Account acc = new Account(
            Name = 'Test Client',
            Location__Latitude__s = 12.9716,
            Location__Longitude__s = 77.5946
        );
        insert acc;

        // Create Punch Record
        Punch_Record__c punch = new Punch_Record__c(
            User__c = UserInfo.getUserId(),
            Punch_Time__c = System.now(),
            Action__c = 'IN',
            Punch_Type__c = 'Market Visit',
            Latitude__c = 12.9716,
            Longitude__c = 77.5946
        );
        insert punch;

        Punch_Record__c wfhPending = new Punch_Record__c(
            User__c = UserInfo.getUserId(),
            Is_WFH_Request__c = true,
            WFH_Request_Date__c = Date.today().addDays(1),
            WFH_Approval_Status__c = 'Pending',
            Punch_Time__c = System.now()
        );
        insert wfhPending;

        // Create Task Log
        Task_Log__c log = new Task_Log__c(
            Punch_Record__c = punch.Id,
            Description__c = 'Test Task Log',
            Account__c = acc.Id,
            Latitude__c = 12.9716,
            Longitude__c = 77.5946
        );
        insert log;

        // Create Track Location
        Track_Location__c track = new Track_Location__c(
            Punch_Record__c = punch.Id,
            Latitude__c = '12.9716',
            Longitude__c = '77.5946'
        );
        insert track;
    }

    @isTest
    static void testGetEmployees() {
        Test.startTest();
        List<EmployeeTracker.EmployeeDTO> employees = EmployeeTracker.getEmployees();
        Test.stopTest();
        
        System.assert(!employees.isEmpty(), 'Employees list should not be empty');
        System.assertEquals(UserInfo.getUserId(), employees[0].Id);
    }

    @isTest
    static void testIsAdminUser() {
        Test.startTest();
        Boolean isAdmin = EmployeeTracker.isAdminUser();
        Test.stopTest();
        
        // System Administrator profiles running test will be true
        System.assertNotEquals(null, isAdmin);
    }

    @isTest
    static void testGetAllUsers() {
        Test.startTest();
        List<EmployeeTracker.UserDTO> users = EmployeeTracker.getAllUsers();
        Test.stopTest();
        
        System.assert(!users.isEmpty(), 'Users list should not be empty');
    }

    @isTest
    static void testGetManagerAssignments() {
        Test.startTest();
        Map<String, String> assignments = EmployeeTracker.getManagerAssignments();
        Test.stopTest();
        
        System.assertNotEquals(null, assignments);
    }

    @isTest
    static void testSaveManagerAssignment() {
        Test.startTest();
        // Just calling to verify no exceptions (deployment won't run in test)
        EmployeeTracker.saveManagerAssignment(UserInfo.getUserId(), UserInfo.getUserId());
        Test.stopTest();
    }

    @isTest
    static void testUpdateWFHStatus() {
        Punch_Record__c punch = [SELECT Id FROM Punch_Record__c LIMIT 1];
        
        Test.startTest();
        EmployeeTracker.updateWFHStatus(punch.Id, 'Approved', 'Test remarks');
        Test.stopTest();

        Punch_Record__c updated = [SELECT WFH_Approval_Status__c, Approver_Remarks__c FROM Punch_Record__c WHERE Id = :punch.Id];
        System.assertEquals('Approved', updated.WFH_Approval_Status__c);
        System.assertEquals('Test remarks', updated.Approver_Remarks__c);
    }

    @isTest
    static void testGetClients() {
        Test.startTest();
        List<Account> clients = EmployeeTracker.getClients();
        Test.stopTest();
        
        System.assert(!clients.isEmpty(), 'Clients should not be empty');
    }

    @isTest
    static void testGetRecentTasksForEmployees() {
        List<Id> employeeIds = new List<Id>{ UserInfo.getUserId() };
        String dateStr = String.valueOf(Date.today());

        Test.startTest();
        List<EmployeeTracker.TaskRowDTO> tasks = EmployeeTracker.getRecentTasksForEmployees(employeeIds, 5, dateStr);
        List<EmployeeTracker.TaskRowDTO> tasksEmpty = EmployeeTracker.getRecentTasksForEmployees(null, 5, dateStr);
        Test.stopTest();

        System.assert(!tasks.isEmpty(), 'Tasks list should not be empty');
        System.assert(tasksEmpty.isEmpty(), 'Should return empty list for null input');
        
        Boolean foundAccountType = false;
        for (EmployeeTracker.TaskRowDTO t : tasks) {
            if (t.type == 'Account') {
                foundAccountType = true;
            }
        }
        System.assert(foundAccountType, 'Should have mapped task row type to Account');
    }

    @isTest
    static void testEmployeeTrackerClsGetEmployees() {
        Employee__c emp = new Employee__c(
            Current_Status__c = 'OUT',
            Phone__c = '9999999999',
            Latitude__c = 12.97,
            Longitude__c = 77.59
        );
        insert emp;

        Test.startTest();
        List<Employee__c> employees = EmployeeTrackerCls.getEmployees();
        Test.stopTest();

        System.assert(!employees.isEmpty(), 'EmployeeTrackerCls should return employees');
    }

    @isTest
    static void testGetEmployeesAsNonAdminManager() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User manager = new User(
            Alias = 'etmgr',
            Email = 'et.manager@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ETManager',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            UserName = 'et.manager.' + DateTime.now().getTime() + '@example.test'
        );
        insert manager;

        User subordinate = new User(
            Alias = 'etsub',
            Email = 'et.sub@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ETSub',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            UserName = 'et.sub.' + DateTime.now().getTime() + '@example.test',
            ManagerId = manager.Id
        );
        insert subordinate;

        insert new User_Punch_State__c(
            User__c = manager.Id,
            Current_Status__c = 'OUT',
            Last_Punch_Time__c = System.now()
        );
        insert new User_Punch_State__c(
            User__c = subordinate.Id,
            Current_Status__c = 'IN',
            Last_Punch_Time__c = System.now(),
            Latitude__c = 12.97,
            Longitude__c = 77.59,
            Battery_Percentage__c = 70
        );
        insert new Punch_Record__c(
            User__c = subordinate.Id,
            Is_WFH_Request__c = true,
            WFH_Request_Date__c = Date.today().addDays(1),
            WFH_Request_Start_Time__c = Time.newInstance(9, 0, 0, 0),
            WFH_Request_End_Time__c = Time.newInstance(18, 0, 0, 0),
            WFH_Approval_Status__c = 'Pending',
            Punch_Time__c = System.now()
        );

        System.runAs(manager) {
            Test.startTest();
            List<EmployeeTracker.EmployeeDTO> employees = EmployeeTracker.getEmployees();
            Test.stopTest();
            System.assert(!employees.isEmpty(), 'Non-admin manager should see punch-state users in scope');
        }
    }

    @isTest
    static void testGetRecentTasksIncludesPunchAndTrack() {
        Punch_Record__c punch = [
            SELECT Id FROM Punch_Record__c
            WHERE Is_WFH_Request__c != true
            LIMIT 1
        ];
        insert new ContentVersion(
            Title = 'selfie_day',
            PathOnClient = 'selfie.jpg',
            VersionData = Blob.valueOf('img'),
            FirstPublishLocationId = punch.Id
        );
        insert new ContentVersion(
            Title = 'odometer_day',
            PathOnClient = 'odo.jpg',
            VersionData = Blob.valueOf('odo'),
            FirstPublishLocationId = punch.Id
        );

        Test.startTest();
        List<EmployeeTracker.TaskRowDTO> rows = EmployeeTracker.getRecentTasksForEmployees(
            new List<Id>{ UserInfo.getUserId() },
            null,
            String.valueOf(Date.today())
        );
        Test.stopTest();

        Boolean foundPunch = false;
        Boolean foundTrack = false;
        for (EmployeeTracker.TaskRowDTO row : rows) {
            if (row.type == 'PUNCH') foundPunch = true;
            if (row.type == 'TRACK') foundTrack = true;
        }
        System.assert(foundPunch, 'Should include punch rows');
        System.assert(foundTrack, 'Should include track rows');
    }

    @isTest
    static void testSubordinateTracking() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User subordinateUser = new User(
            Alias = 'subUser',
            Email = 'subordinate@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Subordinate',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'subordinate' + DateTime.now().getTime() + '@example.test',
            ManagerId = UserInfo.getUserId()
        );
        insert subordinateUser;

        User_Punch_State__c upsSub = new User_Punch_State__c(
            User__c = subordinateUser.Id,
            Current_Status__c = 'IN',
            Last_Punch_Time__c = System.now(),
            Latitude__c = 12.9716,
            Longitude__c = 77.5946,
            Battery_Percentage__c = 90
        );
        insert upsSub;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Boolean isAdmin = EmployeeTracker.isAdminUser();
            List<EmployeeTracker.EmployeeDTO> employees = EmployeeTracker.getEmployees();
            Test.stopTest();
            
            System.assert(isAdmin, 'Manager user should be authorized to view tracker');
            Boolean foundSub = false;
            for (EmployeeTracker.EmployeeDTO emp : employees) {
                if (emp.Id == subordinateUser.Id) {
                    foundSub = true;
                }
            }
            System.assert(foundSub, 'Should find subordinate user in the employee tracker list');
        }
    }
}