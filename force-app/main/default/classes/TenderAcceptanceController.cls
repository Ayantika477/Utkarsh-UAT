public with sharing class TenderAcceptanceController {

    public class TenderInfo {
        @AuraEnabled public Id authorityId;
        @AuraEnabled public String authorityName;
        @AuraEnabled public String hodChoice;
        @AuraEnabled public String currentChoice;
        @AuraEnabled public String contactName;
        @AuraEnabled public String addressBookName;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<String> getTenderUserChoices() {

    List<String> values = new List<String>();

    Schema.DescribeFieldResult field =
        Tender__c.Tender_User_Choice__c.getDescribe();

    for (Schema.PicklistEntry p : field.getPicklistValues()) {
        if (p.isActive()) {
            values.add(p.getValue());
        }
    }

    return values;
    }
    
    @AuraEnabled(cacheable=true)
public static TenderInfo getTenderInfo(Id recordId) {

    Tender__c t = [
        SELECT Id,
               Authority__c,
               Authority__r.Name,
               HOD_Choice__c,
               Tender_User_Choice__c,
               Contact__c,
               Contact__r.Name
        FROM Tender__c
        WHERE Id = :recordId
        LIMIT 1
    ];

    TenderInfo info = new TenderInfo();

    info.authorityId = t.Authority__c;
    info.authorityName = t.Authority__r != null ? t.Authority__r.Name : null;
    info.hodChoice = t.HOD_Choice__c;
    info.currentChoice = t.Tender_User_Choice__c;

    info.contactName = '-';
    if (t.Contact__c != null) {
        info.contactName = t.Contact__r.Name;
    }

    List<Tender_Addressbook_Junc__c> junctions = [
        SELECT Address_Book__c,
               Address_Book__r.Name
        FROM Tender_Addressbook_Junc__c
        WHERE Tender__c = :recordId
        LIMIT 1
    ];

    info.addressBookName = '-';
    if (!junctions.isEmpty() &&
        junctions[0].Address_Book__c != null) {

        info.addressBookName =
            junctions[0].Address_Book__r.Name;
    }

    return info;
}

    @AuraEnabled(cacheable=true)
    public static List<Contact> getContactsForAccount(Id accountId) {
        if (accountId == null) {
            return new List<Contact>();
        }
        return [
            SELECT Id, Name, Email, Phone
            FROM Contact
            WHERE AccountId = :accountId
            ORDER BY Name
            LIMIT 200
        ];
    }

    @AuraEnabled
    public static Id createContact(String firstName, String lastName, String email, String phone, Id accountId) {
        if (String.isBlank(lastName)) {
            throw new AuraHandledException('Last Name is required to create a Contact.');
        }
        if (accountId == null) {
            throw new AuraHandledException('An Account is required to create a Contact.');
        }

        Contact c = new Contact(
            FirstName = firstName,
            LastName  = lastName,
            Email     = email,
            Phone     = phone,
            AccountId = accountId
        );
        insert c;
        return c.Id;
    }
    

    /**
     * Updates the Tender_user_choice__c picklist, and optionally the
     * Contact__c lookup (used by the "Send for Tender Participation" flow).
     */
   @AuraEnabled
public static void updateTenderChoice(
    Id tenderId,
    String choice,
    String rejectionReason
) {

    Map<String, String> deptMap = new Map<String, String>{
        'High Mast & Polygonal'             => 'High_Mast_Department',
        'Crash Barrier'                     => 'Crash_Barrier_Department',
        'HDPE'                              => 'HDPE_Pipe_Department',
        'Steel Tubular Poles'               => 'Steel_Tubular_Pole_Department',
        'Polymer'                           => 'PVC',
        'Transmission & Telecom Tower'      => 'Transmission_Tower_Department',
        'Pre Engineering Building'          => 'PEB_Department',
        'Solar Structure'                   => 'Solar_Structure_Department',
        'Railway Electrification Structure' => 'Core_Department',
        'Steel Pipes'                       => 'Steel_Pipes_Department'
    };

    if (tenderId == null || String.isBlank(choice)) {
        throw new AuraHandledException(
            'Tender record and choice are required.'
        );
    }

    if (
        (choice == 'Reject and Close' || choice == 'Reject and Create Project') &&
        String.isBlank(rejectionReason)
    ) {
        throw new AuraHandledException(
            'Please enter a rejection reason.'
        );
    }

    Tender__c tender = [
        SELECT Id,
               Name,
               Department_Name__c,
               Comments__c
        FROM Tender__c
        WHERE Id = :tenderId
        WITH SYSTEM_MODE
        LIMIT 1
    ];

    String updatedComments = appendComment(tender.Comments__c, rejectionReason);

    String userDepartment = deptMap.get(tender.Department_Name__c);

    if (!String.isBlank(userDepartment)) {

        User hod = [
            SELECT Id, Name
            FROM User
            WHERE IsActive = true
            AND Profile.Name = 'Utkarsh HOD'
            AND Departments__c INCLUDES (:userDepartment)
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (hod != null) {
            notifyHod(tender, hod.Id);
        }
    }

    Tender__c t = new Tender__c(
        Id                     = tenderId,
        Tender_User_Choice__c  = choice,
        Comments__c            = updatedComments,
        Tender_Stage__c        = 'Sent for Approval',
        HOD_choice__c          = ''
    );

    Database.update(t);
}

private static void notifyHod(Tender__c tender, Id hodId) {

    CustomNotificationType notifType = [
        SELECT Id
        FROM CustomNotificationType
        WHERE DeveloperName = 'Tender_Approval_Notification'
        WITH SYSTEM_MODE
        LIMIT 1
    ];

    Messaging.CustomNotification notification = new Messaging.CustomNotification();
    notification.setTitle('Tender needs review');
    notification.setBody('Please review "' + tender.Name + '".');
    notification.setNotificationTypeId(notifType.Id);
    notification.setTargetId(tender.Id);

    try {
        notification.send(new Set<String>{ hodId });
    } catch (Exception e) {
        System.debug('Failed to send review notification: ' + e.getMessage());
    }
}
   
private static String appendComment(String existingComments, String newComment) {

    if (String.isBlank(newComment)) {
        return existingComments;
    }

    String entry = '-' + newComment;

    if (String.isBlank(existingComments)) {
        return entry;
    }

    return entry + '\n' + existingComments;
}
}