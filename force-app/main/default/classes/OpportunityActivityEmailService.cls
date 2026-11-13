public inherited sharing class OpportunityActivityEmailService {
    /**
     * -------------------------------------------------------------------------
     * Builds a single escalation email.
     * -------------------------------------------------------------------------
     */
    public static Messaging.SingleEmailMessage buildEmail(

        Opportunity opp,

        Set<String> recipients,

        Integer escalationLevel,

        String activityType

    ){

        OpportunityActivityUtility.log(
            'Preparing Email For Opportunity : ' +
            opp.Name
        );

        if(

            opp == null ||

            recipients == null ||

            recipients.isEmpty()

        ){

            OpportunityActivityUtility.logError(
                'Email Not Created. Opportunity or Recipients Missing.'
            );

            return null;
        }

        Messaging.SingleEmailMessage mail =
            new Messaging.SingleEmailMessage();

        // Not used: buildEmails sends to User Ids and copies only the subject/body.
        // mail.setToAddresses(
        //     new List<String>(recipients)
        // );

        mail.setSubject(

            OpportunityActivityConstants.EMAIL_SUBJECT_PREFIX +

            escalationLevel +

            ' Hours'

        );

        String body = '';

        body += 'Opportunity Activity Escalation';
        body += '\n\n';

        body += 'Opportunity Name : '
            + opp.Name;

        body += '\nOpportunity Id : '
            + opp.Id;

        body += '\nStage : '
            + opp.StageName;

        body += '\nDepartment : '
            + opp.Department_NameFormula__c;

        body += '\nActivity Type : '
            + activityType;

        body += '\nLast Open Activity : '
            + String.valueOf(
                opp.Last_Open_Activity__c
            );

        body += '\nEscalation Level : '
            + escalationLevel
            + ' Hours';

        body +=
            '\n\nThis Opportunity contains an Open '
            + activityType
            + ' that has remained unattended for more than '
            + escalationLevel
            + ' hours.';

        body +=
            '\n\nPlease review and take the necessary action.';

        mail.setPlainTextBody(
            body
        );

        OpportunityActivityUtility.logSuccess(
            'Email Prepared Successfully For Opportunity : '
            + opp.Name
        );

        return mail;
    }

    /**
     * -------------------------------------------------------------------------
     * Sends to User Ids so the email counts as internal (not against the daily
     * external email limit). setTargetObjectId takes a single User, so one copy
     * of the escalation email is built per recipient. userIdByEmail maps
     * lowercased email → active User Id. Addresses without an active User are
     * skipped (email address fallback disabled).
     * -------------------------------------------------------------------------
     */
    public static List<Messaging.SingleEmailMessage> buildEmails(

        Opportunity opp,

        Set<String> recipients,

        Integer escalationLevel,

        String activityType,

        Map<String,Id> userIdByEmail

    ){

        List<Messaging.SingleEmailMessage> messages =
            new List<Messaging.SingleEmailMessage>();

        Messaging.SingleEmailMessage template =
            buildEmail(opp, recipients, escalationLevel, activityType);

        if(template == null){
            return messages;
        }

        Set<Id> addedUserIds = new Set<Id>();

        for(String email : recipients){

            Id userId = (String.isBlank(email) || userIdByEmail == null)
                ? null
                : userIdByEmail.get(email.trim().toLowerCase());

            if(userId == null){
                System.debug(
                    'OpportunityActivityEmailService: no active User Id for recipient ' + email +
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

}