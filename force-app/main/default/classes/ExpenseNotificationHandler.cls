/**
 * @description Handles custom notifications for Expense approval workflows.
 * 
 * Workflow stages:
 * 1. Insert/Update in 'Pending HOD Approval' -> Notify HOD users (Profile: Utkarsh HOD) matching the department.
 * 2. Status changes to 'Pending HR Approval'  -> Notify HR users (Profile: Utkarsh HR).
 * 3. Status changes to 'Pending ED Approval'  -> Notify ED users (UserRole: Utkarsh ED).
 * 4. Status changes to 'Approved by ED'       -> Notify Expense Submitter.
 * 5. Status changes to any Rejection status   -> Notify Expense Submitter (Rejected by HOD / HR / ED).
 * 6. Insert/Update in 'Pending HOD Approval'  -> Notify Expense Submitter (awaiting HOD approval).
 * 7. Status changes to 'Pending HR Approval' -> Notify Expense Submitter (approved by HOD).
 * 8. Status changes to 'Pending ED Approval' -> Notify Expense Submitter (approved by HR).
 *
 * Notification Type: 'Expense_Notification'
 */
public without sharing class ExpenseNotificationHandler {

    // Status Constants
    public static final String STATUS_PENDING_HOD_APPROVAL = 'Pending HOD Approval';
    public static final String STATUS_PENDING_HR_APPROVAL  = 'Pending HR Approval';
    public static final String STATUS_PENDING_ED_APPROVAL  = 'Pending ED Approval';
    public static final String STATUS_APPROVED_BY_ED       = 'Approved by ED';
    public static final String STATUS_REJECTED_BY_HOD      = 'Rejected by HOD';
    public static final String STATUS_REJECTED_BY_HR       = 'Rejected by HR';
    public static final String STATUS_REJECTED_BY_ED       = 'Rejected by ED';

    // Approver Profiles and Roles
    public static final String PROFILE_HOD = 'Utkarsh HOD';
    public static final String PROFILE_HR  = 'Utkarsh HR';
    public static final String ROLE_ED     = 'Utkarsh ED';

    // Submitter Profile eligible for submitter notifications
    public static final String PROFILE_SALES = 'Utkarsh Sales';

    // Custom Notification Developer Name
    public static final String NOTIFICATION_TYPE = 'Expense_Notification';

    // Submitter notification bodies
    public static final String BODY_PENDING_HOD  = 'Your expense claim is awaiting Department HOD approval.';
    public static final String BODY_APPROVED_HOD = 'Your expense claim has been approved by your Department HOD and forwarded for processing.';
    public static final String BODY_REJECTED_HOD = 'Your expense claim has been rejected by your Department HOD. Please review the remarks.';
    public static final String BODY_APPROVED_HR  = 'Your expense claim has been approved by HR and forwarded for processing.';
    public static final String BODY_REJECTED_HR  = 'Your expense claim has been rejected by HR. Please review the remarks.';
    public static final String BODY_APPROVED_ED  = 'Your expense claim has been approved successfully.';
    public static final String BODY_REJECTED_ED  = 'Your expense claim has been rejected. Please check the remarks and resubmit if required.';

    // Cached Notification Type Id
    private static Id cachedNotificationTypeId;

    /**
     * Called after Expense__c insert.
     * Triggers notification to HOD when inserted in Pending HOD Approval status.
     */
    public static void handleAfterInsert(List<Expense__c> expenses) {
        if (expenses == null || expenses.isEmpty()) {
            return;
        }

        List<Expense__c> pendingHodExpenses = new List<Expense__c>();

        for (Expense__c exp : expenses) {
            if (exp.Status__c == STATUS_PENDING_HOD_APPROVAL) {
                pendingHodExpenses.add(exp);
            }
        }

        if (!pendingHodExpenses.isEmpty()) {
            notifyHodApprovers(pendingHodExpenses);
            notifySubmitters(pendingHodExpenses, 'Expense pending approval', BODY_PENDING_HOD);
        }
    }

    /**
     * Called after Expense__c update.
     * Handles notifications across approval and rejection status changes.
     */
    public static void handleAfterUpdate(List<Expense__c> expenses, Map<Id, Expense__c> oldExpenses) {
        if (expenses == null || expenses.isEmpty() || oldExpenses == null) {
            return;
        }

        List<Expense__c> hodExpenses = new List<Expense__c>();
        List<Expense__c> hrExpenses  = new List<Expense__c>();
        List<Expense__c> edExpenses  = new List<Expense__c>();
        List<Expense__c> finalApprovedExpenses = new List<Expense__c>();
        List<Expense__c> rejectedByHodExpenses = new List<Expense__c>();
        List<Expense__c> rejectedByHrExpenses  = new List<Expense__c>();
        List<Expense__c> rejectedByEdExpenses  = new List<Expense__c>();

        for (Expense__c exp : expenses) {
            Expense__c oldExp = oldExpenses.get(exp.Id);
            if (oldExp == null) {
                continue;
            }

            String oldStatus = oldExp.Status__c;
            String newStatus = exp.Status__c;

            if (newStatus == oldStatus) {
                continue;
            }

            if (newStatus == STATUS_PENDING_HOD_APPROVAL) {
                hodExpenses.add(exp);
            } else if (newStatus == STATUS_PENDING_HR_APPROVAL) {
                hrExpenses.add(exp);
            } else if (newStatus == STATUS_PENDING_ED_APPROVAL) {
                edExpenses.add(exp);
            } else if (newStatus == STATUS_APPROVED_BY_ED) {
                finalApprovedExpenses.add(exp);
            } else if (newStatus == STATUS_REJECTED_BY_HOD) {
                rejectedByHodExpenses.add(exp);
            } else if (newStatus == STATUS_REJECTED_BY_HR) {
                rejectedByHrExpenses.add(exp);
            } else if (newStatus == STATUS_REJECTED_BY_ED) {
                rejectedByEdExpenses.add(exp);
            }
        }

        if (!hodExpenses.isEmpty()) {
            notifyHodApprovers(hodExpenses);
            notifySubmitters(hodExpenses, 'Expense pending approval', BODY_PENDING_HOD);
        }

        if (!hrExpenses.isEmpty()) {
            notifyHrApprovers(hrExpenses);
            notifySubmitters(hrExpenses, 'Expense approved by HOD', BODY_APPROVED_HOD);
        }

        if (!edExpenses.isEmpty()) {
            notifyEdApprovers(edExpenses);
            notifySubmitters(edExpenses, 'Expense approved by HR', BODY_APPROVED_HR);
        }

        if (!finalApprovedExpenses.isEmpty()) {
            notifySubmitters(finalApprovedExpenses, 'Expense approved by ED', BODY_APPROVED_ED);
        }

        if (!rejectedByHodExpenses.isEmpty()) {
            notifySubmitters(rejectedByHodExpenses, 'Expense rejected by HOD', BODY_REJECTED_HOD);
        }

        if (!rejectedByHrExpenses.isEmpty()) {
            notifySubmitters(rejectedByHrExpenses, 'Expense rejected by HR', BODY_REJECTED_HR);
        }

        if (!rejectedByEdExpenses.isEmpty()) {
            notifySubmitters(rejectedByEdExpenses, 'Expense rejected by ED', BODY_REJECTED_ED);
        }
    }

    /**
     * Sends custom notification to HODs matching the submitter's department.
     */
    private static void notifyHodApprovers(List<Expense__c> expenses) {
        Id notificationTypeId = getNotificationTypeId();
        if (notificationTypeId == null) {
            return;
        }

        // Collect submitter IDs
        Set<Id> submitterIds = new Set<Id>();
        for (Expense__c exp : expenses) {
            Id submitterId = getSubmitterId(exp);
            if (submitterId != null) {
                submitterIds.add(submitterId);
            }
        }

        Map<Id, User> submittersById = new Map<Id, User>();
        if (!submitterIds.isEmpty()) {
            submittersById = new Map<Id, User>([
                SELECT Id, Name, Department
                FROM User
                WHERE Id IN :submitterIds
                WITH SYSTEM_MODE
            ]);
        }

        // Collect relevant departments
        Set<String> departments = new Set<String>();
        for (Expense__c exp : expenses) {
            String dept = getDepartment(exp, submittersById);
            if (String.isNotBlank(dept)) {
                departments.add(dept);
            }
        }

        if (departments.isEmpty()) {
            return;
        }

        // Query active HODs for these departments
        Map<String, Set<String>> hodUserIdsByDept = new Map<String, Set<String>>();
        for (User hod : [
            SELECT Id, Department
            FROM User
            WHERE IsActive = true
            AND Department IN :departments
            AND Profile.Name = :PROFILE_HOD
            WITH SYSTEM_MODE
        ]) {
            if (!hodUserIdsByDept.containsKey(hod.Department)) {
                hodUserIdsByDept.put(hod.Department, new Set<String>());
            }
            hodUserIdsByDept.get(hod.Department).add(hod.Id);
        }

        if (hodUserIdsByDept.isEmpty()) {
            return;
        }

        // Send notifications
        for (Expense__c exp : expenses) {
            String dept = getDepartment(exp, submittersById);
            if (String.isBlank(dept) || !hodUserIdsByDept.containsKey(dept)) {
                continue;
            }

            Id submitterId = getSubmitterId(exp);

            // Exclude the submitter so an HOD is not notified for their own expense
            Set<String> recipientIds = new Set<String>(hodUserIdsByDept.get(dept));
            if (submitterId != null) {
                recipientIds.remove(String.valueOf(submitterId));
            }
            if (recipientIds.isEmpty()) {
                continue;
            }

            User submitter = submitterId != null ? submittersById.get(submitterId) : null;
            String submitterName = submitter != null ? submitter.Name : 'an employee';

            String title = 'New expense submitted';
            String body = 'Expense claim submitted by ' + submitterName + ' is awaiting your approval.';

            sendCustomNotification(exp.Id, title, body, recipientIds, notificationTypeId);
        }
    }

    /**
     * Sends custom notification to all active Utkarsh HR users.
     */
    private static void notifyHrApprovers(List<Expense__c> expenses) {
        Id notificationTypeId = getNotificationTypeId();
        if (notificationTypeId == null) {
            return;
        }

        Set<String> hrUserIds = new Set<String>();
        for (User hrUser : [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND Profile.Name = :PROFILE_HR
            WITH SYSTEM_MODE
        ]) {
            hrUserIds.add(hrUser.Id);
        }

        if (hrUserIds.isEmpty()) {
            return;
        }

        Map<Id, String> submitterNames = getSubmitterNames(expenses);

        for (Expense__c exp : expenses) {
            String submitterName = submitterNames.containsKey(getSubmitterId(exp)) ? submitterNames.get(getSubmitterId(exp)) : 'an employee';
            String title = 'New expense submitted and approved by HOD';
            String body = 'Expense claim submitted by ' + submitterName + ' is approved by HOD and awaiting HR approval.';

            sendCustomNotification(exp.Id, title, body, hrUserIds, notificationTypeId);
        }
    }

    /**
     * Sends custom notification to all active Utkarsh ED role users.
     */
    private static void notifyEdApprovers(List<Expense__c> expenses) {
        Id notificationTypeId = getNotificationTypeId();
        if (notificationTypeId == null) {
            return;
        }

        Set<String> edUserIds = new Set<String>();
        for (User edUser : [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND UserRole.Name = :ROLE_ED
            WITH SYSTEM_MODE
        ]) {
            edUserIds.add(edUser.Id);
        }

        if (edUserIds.isEmpty()) {
            return;
        }

        Map<Id, String> submitterNames = getSubmitterNames(expenses);

        for (Expense__c exp : expenses) {
            String submitterName = submitterNames.containsKey(getSubmitterId(exp)) ? submitterNames.get(getSubmitterId(exp)) : 'an employee';
            String title = 'New expense submitted and approved by HR';
            String body = 'Expense claim submitted by ' + submitterName + ' is approved by HR and awaiting your approval.';

            sendCustomNotification(exp.Id, title, body, edUserIds, notificationTypeId);
        }
    }

    /**
     * Sends custom notification (Expense_Notification) to the expense submitters (Employee__c / CreatedById).
     * Only submitters with the Utkarsh Sales profile are notified.
     */
    private static void notifySubmitters(List<Expense__c> expenses, String title, String body) {
        Id notificationTypeId = getNotificationTypeId();
        if (notificationTypeId == null) {
            return;
        }

        Set<Id> submitterIds = new Set<Id>();
        for (Expense__c exp : expenses) {
            Id submitterId = getSubmitterId(exp);
            if (submitterId != null) {
                submitterIds.add(submitterId);
            }
        }

        if (submitterIds.isEmpty()) {
            return;
        }

        Set<Id> salesSubmitterIds = new Map<Id, User>([
            SELECT Id
            FROM User
            WHERE Id IN :submitterIds
            AND Profile.Name = :PROFILE_SALES
            WITH SYSTEM_MODE
        ]).keySet();

        for (Expense__c exp : expenses) {
            Id submitterId = getSubmitterId(exp);
            if (submitterId == null || !salesSubmitterIds.contains(submitterId)) {
                continue;
            }

            sendCustomNotification(exp.Id, title, body, new Set<String>{ String.valueOf(submitterId) }, notificationTypeId);
        }
    }

    /**
     * Helper to safely send custom notification with exception handling.
     */
    public static void sendCustomNotification(
        Id targetId,
        String title,
        String body,
        Set<String> recipientIds,
        Id notificationTypeId
    ) {
        if (targetId == null || recipientIds == null || recipientIds.isEmpty() || notificationTypeId == null) {
            return;
        }

        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(notificationTypeId);
            notification.setTitle(title);
            notification.setBody(body);
            notification.setTargetId(targetId);
            notification.send(recipientIds);
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'ExpenseNotificationHandler failed to send notification: ' +
                ex.getMessage() +
                '\nStack Trace: ' +
                ex.getStackTraceString()
            );
        }
    }

    /**
     * Resolves the department for an expense from the record or submitter user.
     */
    private static String getDepartment(Expense__c exp, Map<Id, User> submittersById) {
        if (exp != null && String.isNotBlank(exp.User_Department__c)) {
            return exp.User_Department__c;
        }
        if (exp != null && String.isNotBlank(exp.Department__c)) {
            return exp.Department__c;
        }
        Id submitterId = getSubmitterId(exp);
        if (submitterId != null && submittersById.containsKey(submitterId)) {
            return submittersById.get(submitterId).Department;
        }
        return null;
    }

    /**
     * Resolves the submitter user ID (Employee__c if present, otherwise CreatedById).
     */
    private static Id getSubmitterId(Expense__c exp) {
        if (exp == null) {
            return null;
        }
        if (exp.Employee__c != null) {
            return exp.Employee__c;
        }
        return exp.CreatedById;
    }

    /**
     * Gets and caches the Custom Notification Type Id for 'Expense_Notification'.
     */
    public static Id getNotificationTypeId() {
        if (cachedNotificationTypeId != null) {
            return cachedNotificationTypeId;
        }

        List<CustomNotificationType> notificationTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :NOTIFICATION_TYPE
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (!notificationTypes.isEmpty()) {
            cachedNotificationTypeId = notificationTypes[0].Id;
        }

        return cachedNotificationTypeId;
    }

    /**
     * Returns submitter user names keyed by user Id for the given expenses.
     */
    private static Map<Id, String> getSubmitterNames(List<Expense__c> expenses) {
        Set<Id> submitterIds = new Set<Id>();
        for (Expense__c exp : expenses) {
            Id submitterId = getSubmitterId(exp);
            if (submitterId != null) {
                submitterIds.add(submitterId);
            }
        }

        Map<Id, String> namesById = new Map<Id, String>();
        if (submitterIds.isEmpty()) {
            return namesById;
        }

        for (User u : [
            SELECT Id, Name
            FROM User
            WHERE Id IN :submitterIds
            WITH SYSTEM_MODE
        ]) {
            namesById.put(u.Id, u.Name);
        }
        return namesById;
    }

    /**
     * Formats an amount to two decimal places.
     */
    public static String formatAmount(Decimal amount) {
        if (amount == null) {
            return '0.00';
        }
        return String.valueOf(amount.setScale(2));
    }
}