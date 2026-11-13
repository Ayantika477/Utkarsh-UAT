public with sharing class LeadProspectingEscalationEmailService {

    public static Messaging.SingleEmailMessage buildEmail(
        List<Lead> leads,
        Set<String> recipients,
        Integer escalationLevel,
        String department
    ){

        if(
            leads == null ||
            leads.isEmpty() ||
            recipients == null ||
            recipients.isEmpty()
        ){
            return null;
        }
        String body =

            'Lead Prospecting Escalation - '
            + escalationLevel +
            ' Hours\n\n';

        if(String.isNotBlank(department)){

            body +=
                'Department : '
                + department +
                '\n\n';
        }

        body +=
            'The following leads have had no activity in Prospecting stage for more than '
            + escalationLevel +
            ' hours.\n\n';

        for(Lead ld : leads){

            body +=

                'Lead Name : '
                + ld.Name +

                '\nStatus : '
                + ld.Status +

                '\nDepartment : '
                + ld.Department_NameFormula__c +

                '\nLast Prospecting Activity : '
                + String.valueOf(
                    ld.Last_Prospecting_Activity__c
                ) +

                '\n---------------------------------\n';
        }

        Messaging.SingleEmailMessage mail =
            new Messaging.SingleEmailMessage();

        // Not used: buildEmails sends to User Ids and copies only the subject/body.
        // mail.setToAddresses(
        //     new List<String>(recipients)
        // );

        mail.setSubject(

            'Prospecting Escalation - '
            + escalationLevel +
            ' Hours'

        );

        mail.setPlainTextBody(
            body
        );

        return mail;
    }

    // Sends to User Ids so the email counts as internal (not against the daily
    // external email limit). setTargetObjectId takes a single User, so one copy
    // of the escalation email is built per recipient. Addresses without an active
    // User are skipped (email address fallback disabled).
    public static List<Messaging.SingleEmailMessage> buildEmails(
        List<Lead> leads,
        Set<String> recipients,
        Integer escalationLevel,
        String department
    ){

        List<Messaging.SingleEmailMessage> messages =
            new List<Messaging.SingleEmailMessage>();

        Messaging.SingleEmailMessage template =
            buildEmail(leads, recipients, escalationLevel, department);

        if(template == null){
            return messages;
        }

        Map<String, Id> userIdByEmail =
            resolveActiveUserIdsByEmail(recipients);

        Set<Id> addedUserIds = new Set<Id>();

        for(String email : recipients){

            Id userId = String.isBlank(email)
                ? null
                : userIdByEmail.get(email.trim().toLowerCase());

            if(userId == null){
                System.debug(
                    'LeadProspectingEscalationEmailService: no active User Id for recipient ' + email +
                    ' - email address fallback is disabled, email not sent.'
                );
                continue;
            }

            if(addedUserIds.contains(userId)){
                continue;
            }
            addedUserIds.add(userId);

            Messaging.SingleEmailMessage mail =
                new Messaging.SingleEmailMessage();

            mail.setTargetObjectId(userId);
            mail.setSaveAsActivity(false);
            mail.setSubject(template.getSubject());
            mail.setPlainTextBody(template.getPlainTextBody());

            messages.add(mail);
        }

        return messages;
    }

    // Maps lowercased email → first active User (by CreatedDate) with that email.
    @TestVisible
    private static Map<String, Id> resolveActiveUserIdsByEmail(Set<String> emails){

        Map<String, Id> userIdByEmail = new Map<String, Id>();

        if(emails == null || emails.isEmpty()){
            return userIdByEmail;
        }

        for(User activeUser : [
            SELECT Id, Email
            FROM User
            WHERE IsActive = true
            AND Email IN :emails
            ORDER BY CreatedDate
        ]){
            String key = activeUser.Email.toLowerCase();
            if(!userIdByEmail.containsKey(key)){
                userIdByEmail.put(key, activeUser.Id);
            }
        }

        return userIdByEmail;
    }

    /**
     * Department Mapping
     * Lead Department Value
     * ->
     * Role Name Prefix
     */
    public static String getRoleDepartmentName(
        String department
    ){

        Map<String,String> departmentMap =
            new Map<String,String>{

                'Transmission & Telecom Tower'
                    => 'Transmission Tower'
            };

        return departmentMap.containsKey(
            department
        )
        ? departmentMap.get(
            department
        )
        : department;
    }
}