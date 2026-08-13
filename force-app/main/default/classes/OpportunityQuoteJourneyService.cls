public with sharing class OpportunityQuoteJourneyService {
    public static DealerOpportunityWhatsAppService.SendWhatsAppResult sendQuoteToCustomer(
        Id opportunityId
    ) {
        DealerOpportunityWhatsAppService.SendWhatsAppResult result =
            new DealerOpportunityWhatsAppService.SendWhatsAppResult();

        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }

        BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
        if (settings == null || settings.Is_Enabled__c != true) {
            throw new AuraHandledException('WhatsApp messaging is disabled or not configured.');
        }

        Opportunity opportunityRecord = BWM_RecordQueryService.queryOpportunity(
            opportunityId
        );

        if (opportunityRecord == null) {
            throw new AuraHandledException('Opportunity not found.');
        }

        if (opportunityRecord.SyncedQuoteId == null) {
            throw new AuraHandledException(
                'Sync Quote is required before sending the quote to the customer.'
            );
        }

        BWM_TemplateResolver.ResolveResult resolveResult = BWM_TemplateResolver.resolve(
            BWM_MessagingConstants.TRIGGER_OPPORTUNITY_SEND_QUOTE_TO_CUSTOMER,
            opportunityRecord
        );

        if (!resolveResult.shouldSend || resolveResult.mapping == null) {
            throw new AuraHandledException(
                String.isNotBlank(resolveResult.skipReason)
                    ? resolveResult.skipReason
                    : 'Send Quote template mapping is not configured.'
            );
        }

        BWM_Template_Mapping__mdt mapping = resolveResult.mapping;
        List<String> templateParams = BWM_FieldValueResolver.resolveParamsForRecord(
            opportunityRecord,
            mapping
        );
        if (templateParams.size() > 2 && String.isBlank(templateParams[2])) {
            throw new AuraHandledException(
                'Quotation Date is required. Populate Quotation Date on the Opportunity or sync a Quote.'
            );
        }

        String phoneNumber = resolvePrimaryContactPhone(opportunityId, settings);
        if (String.isBlank(phoneNumber)) {
            throw new AuraHandledException(
                'No valid mobile number on the primary contact.'
            );
        }

        String payload = OpportunityQuoteWhatsAppPayloadBuilder.buildPayload(
            settings,
            mapping,
            opportunityRecord,
            phoneNumber
        );
        String requestCurl = BWM_MessagingCallout.buildRequestCurl(payload);
        String templateName = String.isNotBlank(mapping.WhatsApp_Template_Name__c)
            ? mapping.WhatsApp_Template_Name__c
            : mapping.Journey_Name__c;
        String successCode = String.isBlank(settings.WhatsApp_Success_Code__c)
            ? '202'
            : settings.WhatsApp_Success_Code__c;

        try {
            BWM_ApiResponse apiResponse = BWM_ApiResponse.parseWhatsAppDirect(
                BWM_MessagingCallout.send(payload),
                successCode
            );
            BWM_MessageLogService.insertLogs(
                new List<Message_Log__c>{
                    BWM_MessageLogService.buildLogForRecord(
                        opportunityRecord,
                        BWM_MessagingConstants.TRIGGER_OPPORTUNITY_SEND_QUOTE_TO_CUSTOMER,
                        BWM_MessagingConstants.LOG_CHANNEL_WHATSAPP,
                        templateName,
                        phoneNumber,
                        apiResponse.isSuccess
                            ? BWM_MessagingConstants.LOG_STATUS_SENT
                            : BWM_MessagingConstants.LOG_STATUS_FAILED,
                        apiResponse,
                        requestCurl,
                        payload
                    )
                }
            );

            if (apiResponse.isSuccess) {
                result.sentCount = 1;
            } else {
                result.skippedCount = 1;
                result.messages.add(
                    String.isNotBlank(apiResponse.message)
                        ? apiResponse.message
                        : 'WhatsApp send failed.'
                );
            }
        } catch (Exception ex) {
            result.skippedCount = 1;
            result.messages.add(ex.getMessage());
            BWM_MessageLogService.insertLogs(
                new List<Message_Log__c>{
                    BWM_MessageLogService.buildLogForRecord(
                        opportunityRecord,
                        BWM_MessagingConstants.TRIGGER_OPPORTUNITY_SEND_QUOTE_TO_CUSTOMER,
                        BWM_MessagingConstants.LOG_CHANNEL_WHATSAPP,
                        templateName,
                        phoneNumber,
                        BWM_MessagingConstants.LOG_STATUS_FAILED,
                        buildFailedApiResponse(ex),
                        requestCurl,
                        payload
                    )
                }
            );
        }

        return result;
    }

    private static String resolvePrimaryContactPhone(
        Id opportunityId,
        BWM_Messaging_Settings__mdt settings
    ) {
        List<OpportunityContactRole> contactRoles = [
            SELECT Contact.Phone, Contact.MobilePhone
            FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityId AND IsPrimary = TRUE
            LIMIT 1
        ];

        if (contactRoles.isEmpty() || contactRoles[0].Contact == null) {
            return null;
        }

        String rawPhone = contactRoles[0].Contact.MobilePhone;
        if (String.isBlank(rawPhone)) {
            rawPhone = contactRoles[0].Contact.Phone;
        }

        String formattedPhone = BWM_PhoneFormatter.formatForMessaging(
            rawPhone,
            settings.Default_Country_Code__c
        );

        if (
            String.isNotBlank(formattedPhone) &&
            isSamePhoneNumber(
                formattedPhone,
                OpportunityQuoteWhatsAppPayloadBuilder.WHATSAPP_FROM
            )
        ) {
            return null;
        }

        return formattedPhone;
    }

    private static Boolean isSamePhoneNumber(String phoneA, String phoneB) {
        if (String.isBlank(phoneA) || String.isBlank(phoneB)) {
            return false;
        }
        return phoneA.replaceAll('[^0-9]', '') == phoneB.replaceAll('[^0-9]', '');
    }

    private static BWM_ApiResponse buildFailedApiResponse(Exception ex) {
        BWM_ApiResponse failedResponse = new BWM_ApiResponse();
        failedResponse.message = ex.getMessage();
        failedResponse.httpStatus = 0;
        return failedResponse;
    }
}