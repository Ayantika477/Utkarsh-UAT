public with sharing class MarkActivityCompleteController {

    private static final String NOTIF_TYPE_DEV_NAME = 'Activity_Assignment';

    /* ---------- wrappers ---------- */
    public class CloseContext {
        @AuraEnabled public String  objectType;                 // 'Task' or 'Event'
        @AuraEnabled public Id      parentId;
        @AuraEnabled public String  parentType;                 // 'Lead' or 'Opportunity'
        @AuraEnabled public List<Option> dispositions = new List<Option>();
        @AuraEnabled public Boolean callOpen  = false;
        @AuraEnabled public Boolean eventOpen = false;
        @AuraEnabled public Boolean visitOpen = false;
    }
    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public Option(String l, String v) { label = l; value = v; }
    }
    public class UserOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
    }
    public class OpenFlags {
        @AuraEnabled public Boolean callOpen  = false;
        @AuraEnabled public Boolean eventOpen = false;
        @AuraEnabled public Boolean visitOpen = false;
    }

    /* =========================================================================
     *  CONTEXT for the record being closed.
     * ========================================================================= */
    @AuraEnabled(cacheable=true)
    public static CloseContext getContext(Id recordId) {
        CloseContext ctx = new CloseContext();
        Id whoId;
        Id whatId;

        if (recordId.getSObjectType() == Task.SObjectType) {
            ctx.objectType = 'Task';
            Task t = [SELECT WhoId, WhatId FROM Task WHERE Id = :recordId WITH SYSTEM_MODE];
            whoId = t.WhoId;  whatId = t.WhatId;
            ctx.dispositions.add(new Option('Connected', 'Connected'));
            ctx.dispositions.add(new Option('Not Connected', 'Not Connected'));
        } else {
            ctx.objectType = 'Event';
            Event e = [SELECT WhoId, WhatId FROM Event WHERE Id = :recordId WITH SYSTEM_MODE];
            whoId = e.WhoId;  whatId = e.WhatId;
            ctx.dispositions.add(new Option('Completed', 'Completed'));
            ctx.dispositions.add(new Option('Not Completed', 'Not Completed'));
        }

        if (whatId != null && whatId.getSObjectType() == Opportunity.SObjectType) {
            ctx.parentType = 'Opportunity';
            ctx.parentId   = whatId;
        } else if (whoId != null && whoId.getSObjectType() == Lead.SObjectType) {
            ctx.parentType = 'Lead';
            ctx.parentId   = whoId;
        }

        if (ctx.parentId != null) {
            ctx.callOpen  = hasOpenCall(ctx.parentId, ctx.parentType, null);
            ctx.eventOpen = hasOpenEvent(ctx.parentId, ctx.parentType, null);
            ctx.visitOpen = hasOpenVisit(ctx.parentId, ctx.parentType, null);
        }
        return ctx;
    }

    /* =========================================================================
     *  MARK COMPLETE. Called AFTER a follow-up is created (deferred close).
     *  Event 'Not Completed' does not require/record Actual Start/End.
     * ========================================================================= */
    @AuraEnabled
    public static OpenFlags markComplete(Id recordId, String objectType,
                                         String disposition, String remarks,
                                         Datetime actualStart, Datetime actualEnd,
                                         Id parentId, String parentType) {
        if (String.isBlank(disposition) || String.isBlank(remarks)) {
            throw handled('Disposition and Remarks are both required.');
        }
        if (objectType == 'Task') {
            update new Task(Id = recordId, Status = 'Completed',
                            Disposition__c = disposition, Description = remarks);
        } else {
            Event ev = new Event(Id = recordId,
                                 Disposition__c = disposition,
                                 Description    = remarks,
                                 Close_Date__c  = Datetime.now());
            if (disposition != 'Not Completed') {
                if (actualStart == null || actualEnd == null) {
                    throw handled('Actual Start Date and Actual End Date are required.');
                }
                if (actualStart > Datetime.now() || actualEnd > Datetime.now()) {
                    throw handled('Actual Start/End Date cannot be in the future.');
                }
                ev.Actual_Start_Time__c = actualStart;
                ev.Actual_End_Time__c   = actualEnd;
            }
            update ev;
        }
        return getOpenFlags(parentId, parentType, null);
    }

    /* =========================================================================
     *  OPEN status on the parent. excludeId lets the caller ignore the record
     *  that is about to be closed (still open during the deferred flow).
     * ========================================================================= */
    @AuraEnabled
    public static OpenFlags getOpenFlags(Id parentId, String parentType, Id excludeId) {
        OpenFlags f = new OpenFlags();
        if (parentId == null) {
            return f;
        }
        f.callOpen  = hasOpenCall(parentId, parentType, excludeId);
        f.eventOpen = hasOpenEvent(parentId, parentType, excludeId);
        f.visitOpen = hasOpenVisit(parentId, parentType, excludeId);
        return f;
    }

    /* =========================================================================
     *  ASSIGNABLE USERS
     * ========================================================================= */
    @AuraEnabled(cacheable=true)
    public static List<UserOption> getAssignableUsers() {
        List<UserOption> options = new List<UserOption>();
        Id runningUserId = UserInfo.getUserId();
        List<String> depts = splitDepartments(
            [SELECT Departments__c FROM User WHERE Id = :runningUserId WITH SYSTEM_MODE].Departments__c);

        List<User> users;
        if (depts.isEmpty()) {
            users = [SELECT Id, Name FROM User WHERE Id = :runningUserId WITH SYSTEM_MODE];
        } else {
            users = (List<User>) Database.query(buildIncludesSoql(depts));
        }
        Boolean runningIncluded = false;
        for (User u : users) {
            options.add(toOption(u));
            if (u.Id == runningUserId) { runningIncluded = true; }
        }
        if (!runningIncluded) {
            options.add(0, toOption([SELECT Id, Name FROM User WHERE Id = :runningUserId WITH SYSTEM_MODE]));
        }
        return options;
    }

    private static List<String> splitDepartments(String multi) {
        List<String> result = new List<String>();
        if (String.isNotBlank(multi)) {
            for (String d : multi.split(';')) {
                if (String.isNotBlank(d)) { result.add(d.trim()); }
            }
        }
        return result;
    }

    private static String buildIncludesSoql(List<String> departments) {
        List<String> conditions = new List<String>();
        for (String dept : departments) {
            conditions.add('Departments__c INCLUDES (\'' + String.escapeSingleQuotes(dept) + '\')');
        }
        return 'SELECT Id, Name FROM User '
             + 'WHERE IsActive = true '
             + 'AND Profile.Name NOT IN (\'Utkarsh Admin\', \'System Administrator\') '
             + 'AND (' + String.join(conditions, ' OR ') + ') WITH SYSTEM_MODE ORDER BY Name';
    }

    private static UserOption toOption(User u) {
        UserOption o = new UserOption();
        o.id = u.Id;  o.name = u.Name;
        return o;
    }

    /* =========================================================================
     *  OPEN checks (parent may be a Lead or an Opportunity). excludeId optional.
     * ========================================================================= */
    private static Boolean hasOpenCall(Id parentId, String parentType, Id excludeId) {
        String f = (parentType == 'Opportunity') ? 'WhatId' : 'WhoId';
        String soql = 'SELECT COUNT() FROM Task WHERE ' + f + ' = :parentId '
            + 'AND TaskSubtype = \'Call\' AND Status = \'Open\' ';
        if (excludeId != null) { soql += 'AND Id != :excludeId '; }
        soql += 'WITH SYSTEM_MODE';
        return Database.countQuery(soql) > 0;
    }

    private static Boolean hasOpenEvent(Id parentId, String parentType, Id excludeId) {
        String f = (parentType == 'Opportunity') ? 'WhatId' : 'WhoId';
        Datetime nowDt = Datetime.now();
        String soql = 'SELECT COUNT() FROM Event WHERE ' + f + ' = :parentId '
            + 'AND (Disposition__c = null OR Disposition__c NOT IN (\'Completed\',\'Not Completed\')) '
            + 'AND StartDateTime >= :nowDt AND (EndDateTime >= :nowDt OR EndDateTime = null) ';
        if (excludeId != null) { soql += 'AND Id != :excludeId '; }
        soql += 'WITH SYSTEM_MODE';
        return Database.countQuery(soql) > 0;
    }

    private static Boolean hasOpenVisit(Id parentId, String parentType, Id excludeId) {
        String f = (parentType == 'Opportunity') ? 'Opportunity__c' : 'Lead__c';
        String soql = 'SELECT COUNT() FROM Task_Log__c WHERE ' + f + ' = :parentId '
            + 'AND Is_schedule__c = true AND Logged_At__c = null ';
        if (excludeId != null) { soql += 'AND Id != :excludeId '; }
        soql += 'WITH SYSTEM_MODE';
        return Database.countQuery(soql) > 0;
    }

    /* =========================================================================
     *  CREATE follow-up activities against the same parent.
     *  excludeId ignores the still-open record being closed in the block check.
     * ========================================================================= */
    @AuraEnabled
    public static Id createCall(Id parentId, String parentType, String subject,
                                Datetime followUp, String comments, Id assignedToId, Id excludeId) {
        if (hasOpenCall(parentId, parentType, excludeId)) {
            throw handled('An open Call already exists.');
        }
        if (followUp != null && followUp < Datetime.now()) {
            throw handled('Follow-up Call date/time cannot be in the past.');
        }
        Task t = new Task();
        setActivityParent(t, parentId, parentType);
        t.TaskSubtype            = 'Call';
        t.Subject                = subject;
        t.Status                 = 'Open';
        t.Manually_Created__c    = true;
        t.Follow_Up_Date_Time__c = followUp;
        if (followUp != null) { t.ActivityDate = followUp.date(); }
        t.Description = comments;
        if (assignedToId != null) { t.OwnerId = assignedToId; }
        insert t;
        return t.Id;
    }

    @AuraEnabled
    public static Id createEvent(Id parentId, String parentType, String subject, String comments,
                                 Datetime startDt, Datetime endDt, Id assignedToId, Id excludeId) {
        if (hasOpenEvent(parentId, parentType, excludeId)) {
            throw handled('An open Event already exists.');
        }
        if (startDt != null && startDt < Datetime.now()) {
            throw handled('Event start cannot be in the past.');
        }
        Event e = new Event();
        setActivityParent(e, parentId, parentType);
        e.Subject       = subject;
        e.Description   = comments;
        e.StartDateTime = startDt;
        e.EndDateTime   = endDt;
        e.Type          = 'Meeting';
        e.IsReminderSet = true;
        if (startDt != null) { e.ReminderDateTime = startDt.addMinutes(-15); }
        if (assignedToId != null) { e.OwnerId = assignedToId; }
        insert e;
        notifyOwner(effectiveOwner(assignedToId), e.Id, 'New Event assigned',
            String.isBlank(subject) ? 'An event has been assigned to you.' : subject);
        return e.Id;
    }

    @AuraEnabled
    public static Id createVisit(Id parentId, String parentType, String visitType,
                                 String reason, Date scheduleDate, Id assignedToId, Id excludeId) {
        if (hasOpenVisit(parentId, parentType, excludeId)) {
            throw handled('An open Visit already exists.');
        }
        Task_Log__c v = new Task_Log__c();
        v.put((parentType == 'Opportunity') ? 'Opportunity__c' : 'Lead__c', parentId);
        v.Visit_Type__c       = visitType;
        v.Reason_for_Visit__c = reason;
        v.Schedule_Date__c    = scheduleDate;
        v.Is_schedule__c      = true;
        v.Manually_Created__c = true;
        if (assignedToId != null) { v.OwnerId = assignedToId; }
        insert v;
        String body = String.isBlank(visitType) ? 'A visit has been assigned to you.'
                                                 : 'Visit (' + visitType + ') has been assigned to you.';
        notifyOwner(effectiveOwner(assignedToId), v.Id, 'New Visit assigned', body);
        return v.Id;
    }

    private static void setActivityParent(SObject activity, Id parentId, String parentType) {
        if (parentType == 'Opportunity') {
            activity.put('WhatId', parentId);
        } else {
            activity.put('WhoId', parentId);
        }
    }

    /* ---- notification (non-blocking) ---- */
    private static Id effectiveOwner(Id assignedToId) {
        return assignedToId != null ? assignedToId : UserInfo.getUserId();
    }

    private static void notifyOwner(Id ownerId, Id targetRecordId, String title, String body) {
        if (ownerId == null) { return; }
        Id typeId = notificationTypeId();
        if (typeId == null) { return; }
        try {
            Messaging.CustomNotification n = new Messaging.CustomNotification();
            n.setTitle(title);
            n.setBody(body);
            n.setNotificationTypeId(typeId);
            n.setTargetId(targetRecordId);
            n.send(new Set<String>{ String.valueOf(ownerId) });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Owner notification failed: ' + e.getMessage());
        }
    }

    private static Id cachedNotifTypeId;
    private static Boolean notifTypeResolved = false;
    private static Id notificationTypeId() {
        if (!notifTypeResolved) {
            List<CustomNotificationType> types = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :NOTIF_TYPE_DEV_NAME WITH SYSTEM_MODE LIMIT 1
            ];
            cachedNotifTypeId = types.isEmpty() ? null : types[0].Id;
            notifTypeResolved = true;
        }
        return cachedNotifTypeId;
    }

    private static AuraHandledException handled(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }
}