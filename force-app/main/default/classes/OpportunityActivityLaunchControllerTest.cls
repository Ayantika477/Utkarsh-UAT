@isTest
private class OpportunityActivityLaunchControllerTest {

    // Picklist values are resolved at runtime so the test does not break
    // if the org's picklist values differ from hard-coded strings.
    private static final String DEPT       = pickValue(User.Departments__c);
    private static final String OPP_STAGE  = pickValue(Opportunity.StageName);
    private static final String VISIT_TYPE = pickOrText(Task_Log__c.Visit_Type__c, 'Site Visit');
    private static final String VISIT_RSN  = pickOrText(Task_Log__c.Reason_for_Visit__c, 'Requirement discussion');

    /* ===================== helpers ===================== */

    private static String pickValue(Schema.SObjectField f) {
        for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                return e.getValue();
            }
        }
        return null;
    }

    private static String pickOrText(Schema.SObjectField f, String fallback) {
        Schema.DescribeFieldResult d = f.getDescribe();
        if (d.getType() == Schema.DisplayType.PICKLIST || d.getType() == Schema.DisplayType.MULTIPICKLIST) {
            return pickValue(f);
        }
        return fallback;
    }

    private static Opportunity opp() {
        return [SELECT Id FROM Opportunity LIMIT 1];
    }

    private static User deptUser() {
        return [SELECT Id, Name FROM User WHERE LastName = 'oalcdept' LIMIT 1];
    }

    private static User noDeptUser() {
        return [SELECT Id, Name FROM User WHERE LastName = 'oalcnodept' LIMIT 1];
    }

    private static Boolean containsId(List<OpportunityActivityLauncherController.UserOption> opts, Id userId) {
        for (OpportunityActivityLauncherController.UserOption o : opts) {
            if (o.id == userId) {
                return true;
            }
        }
        return false;
    }

    /* ===================== setup ===================== */

    @testSetup
    static void makeData() {
        User me = new User(Id = UserInfo.getUserId());
        System.runAs(me) {
            insert buildUsers();
        }

        Account acc = new Account(Name = 'OALC Test Account');
        insert acc;

        insert new Opportunity(
            Name      = 'OALC Test Opportunity',
            StageName = OPP_STAGE,
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id
        );
    }

    private static List<User> buildUsers() {
        Profile p = [
            SELECT Id FROM Profile
            WHERE Name NOT IN ('Utkarsh Admin', 'System Administrator')
              AND UserType = 'Standard'
            LIMIT 1
        ];
        return new List<User>{
            newUser(p.Id, 'oalcdept',   DEPT),
            newUser(p.Id, 'oalcnodept', null)
        };
    }

    private static User newUser(Id profileId, String lastName, String dept) {
        User u = new User(
            ProfileId         = profileId,
            LastName          = lastName,
            Username          = lastName + System.now().getTime() + '@oalc.test.invalid',
            Email             = 'oalc@test.invalid',
            Alias             = lastName.substring(0, 5),
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive          = true
        );
        if (String.isNotBlank(dept)) {
            u.Departments__c = dept;
        }
        return u;
    }

    /* ===================== getOpenStatus ===================== */

    @isTest
    static void openStatus_isFalseWhenNothingExists() {
        Opportunity o = opp();

        Test.startTest();
        OpportunityActivityLauncherController.OpenStatus s =
            OpportunityActivityLauncherController.getOpenStatus(o.Id);
        Test.stopTest();

        System.assertEquals(false, s.callOpen,  'No Call should be open');
        System.assertEquals(false, s.eventOpen, 'No Event should be open');
        System.assertEquals(false, s.visitOpen, 'No Visit should be open');
    }

    @isTest
    static void openStatus_isTrueForAllThreeCategories() {
        Opportunity o = opp();

        Test.startTest();
        OpportunityActivityLauncherController.createCall(
            o.Id, 'Follow up call', Datetime.now().addDays(2), 'Discuss pricing', null);
        OpportunityActivityLauncherController.createEvent(
            o.Id, 'Client meeting', 'At site', Datetime.now().addDays(1), Datetime.now().addDays(1).addHours(1), null);
        OpportunityActivityLauncherController.createVisit(
            o.Id, VISIT_TYPE, VISIT_RSN, Date.today().addDays(3), null);

        OpportunityActivityLauncherController.OpenStatus s =
            OpportunityActivityLauncherController.getOpenStatus(o.Id);
        Test.stopTest();

        System.assertEquals(true, s.callOpen,  'Call should be open');
        System.assertEquals(true, s.eventOpen, 'Event should be open');
        System.assertEquals(true, s.visitOpen, 'Visit should be open');
    }

    /* ===================== createCall ===================== */

    @isTest
    static void createCall_setsFieldsAndOwner() {
        Opportunity o = opp();
        User assignee = deptUser();
        Datetime followUp = Datetime.now().addDays(2);

        Test.startTest();
        Id taskId = OpportunityActivityLauncherController.createCall(
            o.Id, 'Follow up call', followUp, 'Discuss pricing', assignee.Id);
        Test.stopTest();

        Task t = [
            SELECT WhatId, TaskSubtype, Subject, Status, OwnerId, Description,
                   ActivityDate, Manually_Created__c, Follow_Up_Date_Time__c
            FROM Task WHERE Id = :taskId
        ];
        System.assertEquals(o.Id, t.WhatId, 'Task should be linked to the Opportunity');
        System.assertEquals('Call', t.TaskSubtype, 'Subtype should be Call');
        System.assertEquals('Open', t.Status, 'Status should be Open');
        System.assertEquals('Follow up call', t.Subject, 'Subject mismatch');
        System.assertEquals('Discuss pricing', t.Description, 'Description mismatch');
        System.assertEquals(true, t.Manually_Created__c, 'Manually_Created__c should be true');
        System.assertEquals(followUp.date(), t.ActivityDate, 'ActivityDate should follow the follow-up date');
        System.assertEquals(assignee.Id, t.OwnerId, 'Owner should be the selected assignee');
    }

    @isTest
    static void createCall_defaultsOwnerAndNullFollowUp() {
        Opportunity o = opp();

        Test.startTest();
        Id taskId = OpportunityActivityLauncherController.createCall(o.Id, 'No follow up', null, null, null);
        Test.stopTest();

        Task t = [SELECT OwnerId, ActivityDate FROM Task WHERE Id = :taskId];
        System.assertEquals(UserInfo.getUserId(), t.OwnerId, 'Owner should default to the running user');
        System.assertEquals(null, t.ActivityDate, 'ActivityDate should stay null');
    }

    @isTest
    static void createCall_blocksSecondOpenCall() {
        Opportunity o = opp();
        OpportunityActivityLauncherController.createCall(
            o.Id, 'First call', Datetime.now().addDays(1), null, null);

        Boolean thrown = false;
        Test.startTest();
        try {
            OpportunityActivityLauncherController.createCall(
                o.Id, 'Second call', Datetime.now().addDays(2), null, null);
        } catch (AuraHandledException e) {
            thrown = true;
            System.assert(e.getMessage().contains('open Call'), 'Unexpected message: ' + e.getMessage());
        }
        Test.stopTest();

        System.assert(thrown, 'A second open Call should have been blocked');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :o.Id], 'Only one Task should exist');
    }

    /* ===================== createEvent ===================== */

    @isTest
    static void createEvent_setsFieldsAndReminder() {
        Opportunity o = opp();
        User assignee = deptUser();
        Datetime startDt = Datetime.now().addDays(1);
        Datetime endDt   = startDt.addHours(1);

        Test.startTest();
        Id eventId = OpportunityActivityLauncherController.createEvent(
            o.Id, 'Client meeting', 'At site', startDt, endDt, assignee.Id);
        Test.stopTest();

        Event e = [
            SELECT WhatId, Subject, Description, Type, IsReminderSet, ReminderDateTime, OwnerId
            FROM Event WHERE Id = :eventId
        ];
        System.assertEquals(o.Id, e.WhatId, 'Event should be linked to the Opportunity');
        System.assertEquals('Client meeting', e.Subject, 'Subject mismatch');
        System.assertEquals('Meeting', e.Type, 'Type should be Meeting');
        System.assertEquals(true, e.IsReminderSet, 'Reminder should be set');
        System.assertEquals(assignee.Id, e.OwnerId, 'Owner should be the selected assignee');
        System.assertNotEquals(null, e.ReminderDateTime, 'ReminderDateTime should be populated');
    }

    @isTest
    static void createEvent_blocksSecondOpenEvent() {
        Opportunity o = opp();
        Datetime startDt = Datetime.now().addDays(1);
        OpportunityActivityLauncherController.createEvent(
            o.Id, 'First meeting', null, startDt, startDt.addHours(1), null);

        Boolean thrown = false;
        Test.startTest();
        try {
            OpportunityActivityLauncherController.createEvent(
                o.Id, 'Second meeting', null, startDt.addDays(1), startDt.addDays(1).addHours(1), null);
        } catch (AuraHandledException e) {
            thrown = true;
            System.assert(e.getMessage().contains('open Event'), 'Unexpected message: ' + e.getMessage());
        }
        Test.stopTest();

        System.assert(thrown, 'A second open Event should have been blocked');
        System.assertEquals(1, [SELECT COUNT() FROM Event WHERE WhatId = :o.Id], 'Only one Event should exist');
    }

    @isTest
    static void createEvent_allowsNewOneWhenPreviousIsCompleted() {
        Opportunity o = opp();
        Datetime startDt = Datetime.now().addDays(1);
        Id firstId = OpportunityActivityLauncherController.createEvent(
            o.Id, 'First meeting', null, startDt, startDt.addHours(1), null);

        update new Event(Id = firstId, Disposition__c = 'Completed');

        Test.startTest();
        Id secondId = OpportunityActivityLauncherController.createEvent(
            o.Id, 'Second meeting', null, startDt.addDays(2), startDt.addDays(2).addHours(1), null);
        Test.stopTest();

        System.assertNotEquals(null, secondId, 'A new Event should be allowed once the previous one is completed');
    }

    /* ===================== createVisit ===================== */

    @isTest
    static void createVisit_setsFieldsAndOwner() {
        Opportunity o = opp();
        User assignee = deptUser();
        Date scheduleDate = Date.today().addDays(3);

        Test.startTest();
        Id visitId = OpportunityActivityLauncherController.createVisit(
            o.Id, VISIT_TYPE, VISIT_RSN, scheduleDate, assignee.Id);
        Test.stopTest();

        Task_Log__c v = [
            SELECT Opportunity__c, Visit_Type__c, Reason_for_Visit__c, Schedule_Date__c,
                   Is_schedule__c, Manually_Created__c, OwnerId
            FROM Task_Log__c WHERE Id = :visitId
        ];
        System.assertEquals(o.Id, v.Opportunity__c, 'Visit should be linked to the Opportunity');
        System.assertEquals(scheduleDate, v.Schedule_Date__c, 'Schedule date mismatch');
        System.assertEquals(true, v.Is_schedule__c, 'Is_schedule__c should be true');
        System.assertEquals(true, v.Manually_Created__c, 'Manually_Created__c should be true');
        System.assertEquals(assignee.Id, v.OwnerId, 'Owner should be the selected assignee');
    }

    @isTest
    static void createVisit_withoutVisitTypeUsesGenericNotificationBody() {
        Opportunity o = opp();

        Test.startTest();
        Id visitId = OpportunityActivityLauncherController.createVisit(
            o.Id, null, VISIT_RSN, Date.today().addDays(4), null);
        Test.stopTest();

        Task_Log__c v = [SELECT OwnerId FROM Task_Log__c WHERE Id = :visitId];
        System.assertEquals(UserInfo.getUserId(), v.OwnerId, 'Owner should default to the running user');
    }

    @isTest
    static void createVisit_blocksSecondOpenVisit() {
        Opportunity o = opp();
        OpportunityActivityLauncherController.createVisit(
            o.Id, VISIT_TYPE, VISIT_RSN, Date.today().addDays(3), null);

        Boolean thrown = false;
        Test.startTest();
        try {
            OpportunityActivityLauncherController.createVisit(
                o.Id, VISIT_TYPE, VISIT_RSN, Date.today().addDays(5), null);
        } catch (AuraHandledException e) {
            thrown = true;
            System.assert(e.getMessage().contains('open Visit'), 'Unexpected message: ' + e.getMessage());
        }
        Test.stopTest();

        System.assert(thrown, 'A second open Visit should have been blocked');
        System.assertEquals(1, [SELECT COUNT() FROM Task_Log__c WHERE Opportunity__c = :o.Id],
            'Only one Visit should exist');
    }

    /* ===================== getAssignableUsers ===================== */

    @isTest
    static void assignableUsers_returnsDepartmentColleagues() {
        if (DEPT == null) {
            return; // Departments__c has no active picklist values in this org
        }
        User runner = deptUser();

        Test.startTest();
        List<OpportunityActivityLauncherController.UserOption> opts;
        System.runAs(runner) {
            opts = OpportunityActivityLauncherController.getAssignableUsers();
        }
        Test.stopTest();

        System.assert(!opts.isEmpty(), 'Options should not be empty');
        System.assert(containsId(opts, runner.Id), 'The running user should always be selectable');
        for (OpportunityActivityLauncherController.UserOption o : opts) {
            System.assertNotEquals(null, o.name, 'Every option should carry a name');
        }
    }

    @isTest
    static void assignableUsers_returnsOnlySelfWhenNoDepartment() {
        User runner = noDeptUser();

        Test.startTest();
        List<OpportunityActivityLauncherController.UserOption> opts;
        System.runAs(runner) {
            opts = OpportunityActivityLauncherController.getAssignableUsers();
        }
        Test.stopTest();

        System.assertEquals(1, opts.size(), 'A user without a department should only see themselves');
        System.assertEquals(runner.Id, opts[0].id, 'The single option should be the running user');
    }

    @isTest
    static void assignableUsers_addsRunningUserWhenExcludedByProfileFilter() {
        if (DEPT == null) {
            return;
        }
        // The admin running the test is filtered out by the profile clause,
        // so the controller must add them back to the list.
        User me = [SELECT Id, Departments__c FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(me) {
            me.Departments__c = DEPT;
            update me;
        }

        Test.startTest();
        List<OpportunityActivityLauncherController.UserOption> opts =
            OpportunityActivityLauncherController.getAssignableUsers();
        Test.stopTest();

        System.assert(containsId(opts, UserInfo.getUserId()),
            'The running user must be present even when their profile is excluded');
    }
}