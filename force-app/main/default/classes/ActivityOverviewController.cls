/**
 * Serves the activityOverview LWC: two side-by-side tables of Tasks + Events.
 *   - open      -> Task Status = 'Open'; Event with no Disposition__c (org convention:
 *                  events have no standard status; Disposition set = done).
 *   - completed -> Task Status = 'Completed'; Event Disposition__c in
 *                  ('Completed','Not Completed').
 * recordId null -> the running user's own activities; otherwise the record's
 * (WhatId/WhoId). Auto-logged BWM email tasks (Subject 'Email: ...') are excluded.
 */
public with sharing class ActivityOverviewController {
    public class Row {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String activityType;   // 'Task' | 'Event'
        @AuraEnabled public String subject;
        @AuraEnabled public Datetime whenAt;       // task due date / event start (open) or close (completed)
        @AuraEnabled public String status;
        @AuraEnabled public Boolean overdue;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String description;
    }

    public class Result {
        @AuraEnabled public List<Row> open = new List<Row>();
        @AuraEnabled public List<Row> completed = new List<Row>();
    }

    @AuraEnabled(cacheable=true)
    public static Result getActivities(Id recordId) {
        Result res = new Result();
        Id me = UserInfo.getUserId();

        List<Task> tasks;
        List<Event> events;
        if (recordId == null) {
            tasks = [
                SELECT Id, Subject, ActivityDate, Status, Disposition__c, Owner.Name, CreatedDate, Description
                FROM Task
                WHERE OwnerId = :me AND (NOT Subject LIKE 'Email:%')
                WITH SYSTEM_MODE
                ORDER BY ActivityDate DESC NULLS LAST
                LIMIT 400
            ];
            events = [
                SELECT Id, Subject, StartDateTime, EndDateTime, Disposition__c, Close_Date__c, Owner.Name, CreatedDate, Description
                FROM Event
                WHERE OwnerId = :me
                WITH SYSTEM_MODE
                ORDER BY StartDateTime DESC
                LIMIT 400
            ];
        } else {
            tasks = [
                SELECT Id, Subject, ActivityDate, Status, Disposition__c, Owner.Name, CreatedDate, Description
                FROM Task
                WHERE (WhatId = :recordId OR WhoId = :recordId)
                    AND (NOT Subject LIKE 'Email:%')
                WITH SYSTEM_MODE
                ORDER BY ActivityDate DESC NULLS LAST
                LIMIT 400
            ];
            events = [
                SELECT Id, Subject, StartDateTime, EndDateTime, Disposition__c, Close_Date__c, Owner.Name, CreatedDate, Description
                FROM Event
                WHERE WhatId = :recordId OR WhoId = :recordId
                WITH SYSTEM_MODE
                ORDER BY StartDateTime DESC
                LIMIT 400
            ];
        }

        Date today = Date.today();
        Datetime now = Datetime.now();

        for (Task t : tasks) {
            Row r = new Row();
            r.recordId = t.Id;
            r.activityType = 'Task';
            r.subject = t.Subject == null ? '(no subject)' : t.Subject;
            r.ownerName = t.Owner.Name;
            r.createdDate = t.CreatedDate;
            r.description = t.Description;
            if (t.Status == 'Completed') {
                r.status = String.isBlank(t.Disposition__c) ? 'Completed' : t.Disposition__c;
                r.whenAt = t.ActivityDate == null ? null : Datetime.newInstance(t.ActivityDate, Time.newInstance(0, 0, 0, 0));
                r.overdue = false;
                res.completed.add(r);
            } else {
                r.status = 'Open';
                r.whenAt = t.ActivityDate == null ? null : Datetime.newInstance(t.ActivityDate, Time.newInstance(0, 0, 0, 0));
                r.overdue = t.ActivityDate != null && t.ActivityDate < today;
                res.open.add(r);
            }
        }

        for (Event e : events) {
            Row r = new Row();
            r.recordId = e.Id;
            r.activityType = 'Event';
            r.subject = e.Subject == null ? '(no subject)' : e.Subject;
            r.ownerName = e.Owner.Name;
            r.createdDate = e.CreatedDate;
            r.description = e.Description;
            Boolean done = e.Disposition__c == 'Completed' || e.Disposition__c == 'Not Completed';
            if (done) {
                r.status = e.Disposition__c;
                r.whenAt = e.Close_Date__c != null ? e.Close_Date__c : e.StartDateTime;
                r.overdue = false;
                res.completed.add(r);
            } else {
                r.status = 'Open';
                r.whenAt = e.StartDateTime;
                r.overdue = e.EndDateTime != null && e.EndDateTime < now;
                res.open.add(r);
            }
        }

        sortRows(res.open, true);        // soonest due first
        sortRows(res.completed, false);  // most recently done first
        return res;
    }

    private static void sortRows(List<Row> rows, Boolean ascending) {
        List<RowWrap> wraps = new List<RowWrap>();
        for (Row r : rows) {
            wraps.add(new RowWrap(r, ascending));
        }
        wraps.sort();
        rows.clear();
        for (RowWrap w : wraps) {
            rows.add(w.row);
        }
    }

    private class RowWrap implements Comparable {
        Row row;
        Boolean ascOrder;
        RowWrap(Row r, Boolean a) { row = r; ascOrder = a; }
        public Integer compareTo(Object other) {
            Row o = ((RowWrap) other).row;
            Long a = row.whenAt == null ? (ascOrder ? 9999999999999L : 0L) : row.whenAt.getTime();
            Long b = o.whenAt == null ? (ascOrder ? 9999999999999L : 0L) : o.whenAt.getTime();
            if (a == b) { return 0; }
            Boolean less = a < b;
            if (ascOrder) { return less ? -1 : 1; }
            return less ? 1 : -1;
        }
    }
}