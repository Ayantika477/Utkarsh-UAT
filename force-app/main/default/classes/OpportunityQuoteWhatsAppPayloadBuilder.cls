public without sharing class OpportunityQuoteWhatsAppPayloadBuilder {
  private static final String TEMPLATE_NAME = 'u_quotation_manual_trigger';
  private static final String TEMPLATE_LANGUAGE = 'en';
  public static final String WHATSAPP_FROM = '919147100753';

  public static String buildPayload(
    BWM_Messaging_Settings__mdt settings,
    BWM_Template_Mapping__mdt mapping,
    Opportunity opportunityRecord,
    String phoneNumber
  ) {
    if (settings == null || mapping == null || opportunityRecord == null) {
      throw new AuraHandledException('Quote WhatsApp payload inputs are incomplete.');
    }
    if (String.isBlank(phoneNumber)) {
      throw new AuraHandledException('Phone number is required.');
    }

    List<String> params = BWM_FieldValueResolver.resolveParamsForRecord(
      opportunityRecord,
      mapping
    );
    String documentLink = resolveQuoteDocumentUrl(settings, opportunityRecord);
    String callbackData = String.valueOf(opportunityRecord.Id);
    Map<String, Object> dataContent = new Map<String, Object>{
      'templatepayload' => buildTemplatePayload(params, documentLink, callbackData),
      'biz_opaque_callback_data' => callbackData
    };
    applyWebhookSettings(dataContent, settings);

    Map<String, Object> payload = new Map<String, Object>{
      'channel' => BWM_MessagingConstants.CHANNEL_WHATSAPP,
      'to' => new List<String>{ phoneNumber },
      'content' => new Map<String, Object>{
        'data' => dataContent
      }
    };

    payload.put('from', WHATSAPP_FROM);

    return JSON.serialize(payload);
  }

  private static Map<String, Object> buildTemplatePayload(
    List<String> params,
    String documentLink,
    String callbackData
  ) {
    return new Map<String, Object>{
      'messaging_product' => 'whatsapp',
      'recipient_type' => 'individual',
      'type' => 'template',
      'template' => new Map<String, Object>{
        'name' => TEMPLATE_NAME,
        'language' => new Map<String, Object>{ 'code' => TEMPLATE_LANGUAGE },
        'components' => buildTemplateComponents(params, documentLink)
      },
      'biz_opaque_callback_data' => callbackData
    };
  }

  private static void applyWebhookSettings(
    Map<String, Object> dataContent,
    BWM_Messaging_Settings__mdt settings
  ) {
    if (settings == null || String.isBlank(settings.Webhook_Callback_URL__c)) {
      return;
    }

    String webhookUrl = settings.Webhook_Callback_URL__c.trim();
    dataContent.put('webhookUrl', webhookUrl);
    dataContent.put('callbackUrl', webhookUrl);
  }

  private static List<Object> buildTemplateComponents(
    List<String> params,
    String documentLink
  ) {
    return new List<Object>{
      new Map<String, Object>{
        'type' => 'header',
        'parameters' => new List<Object>{
          new Map<String, Object>{
            'type' => 'document',
            'document' => new Map<String, Object>{ 'link' => documentLink }
          }
        }
      },
      new Map<String, Object>{
        'type' => 'body',
        'parameters' => new List<Object>{
          buildTextParameter(getParam(params, 0)),
          buildTextParameter(getParam(params, 1)),
          buildTextParameter(getParam(params, 2)),
          buildTextParameter(getParam(params, 3))
        }
      },
      buildQuickReplyButton('0', 'Yes'),
      buildQuickReplyButton('1', 'No')
    };
  }

  private static Map<String, Object> buildQuickReplyButton(
    String index,
    String payloadValue
  ) {
    return new Map<String, Object>{
      'type' => 'button',
      'sub_type' => 'quick_reply',
      'index' => index,
      'parameters' => new List<Object>{
        new Map<String, Object>{
          'type' => 'payload',
          'payload' => payloadValue
        }
      }
    };
  }

  private static Map<String, Object> buildTextParameter(String value) {
    return new Map<String, Object>{
      'type' => 'text',
      'text' => String.isBlank(value) ? ' ' : value.trim()
    };
  }

  private static String getParam(List<String> params, Integer index) {
    if (params == null || index >= params.size()) {
      return '';
    }
    return params[index];
  }

  private static String resolveQuoteDocumentUrl(
    BWM_Messaging_Settings__mdt settings,
    Opportunity opportunityRecord
  ) {
    String departmentName = BWM_FieldValueResolver.resolveDepartmentName(
      opportunityRecord
    );
    BWM_BrochureService.BrochureInfo brochure = BWM_BrochureService.getBrochureForDepartment(
      departmentName
    );
    String brochureUrl = BWM_BrochureService.resolveWhatsAppDocumentUrl(
      brochure,
      settings.Default_Brochure_Portal_URL__c
    );

    if (isInaccessibleDocumentUrl(brochureUrl)) {
      brochureUrl = BWM_BrochureService.resolveCorporateWhatsAppUrl(settings);
    }

    if (String.isBlank(brochureUrl)) {
      throw new AuraHandledException(
        'Quotation document URL is not available for WhatsApp delivery.'
      );
    }

    return brochureUrl;
  }

  private static Boolean isInaccessibleDocumentUrl(String url) {
    if (String.isBlank(url)) {
      return true;
    }
    String normalized = url.toLowerCase();
    return normalized.contains('sandbox.my.salesforce.com') ||
      normalized.contains('file.force.com');
  }
}