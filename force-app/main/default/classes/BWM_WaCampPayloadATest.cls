@IsTest
private class BWM_WaCampPayloadATest {
  @IsTest
  static void buildPayloadUsesWhatsAppChannelAndTemplatePayload() {
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Id":"00Q000000000001AAA","Status":"Prospect","Department_Name__c":"Crash Barrier","Owner":{"attributes":{"type":"User"},"Name":"Owner Name","Phone":"9999999999","Email":"owner@test.com"}}',
      Lead.class
    );
    Map<String, Object> templateMeta = new Map<String, Object>{
      'language' => 'en',
      'content' => new Map<String, Object>{
        'header' => new Map<String, Object>{ 'type' => 'DOCUMENT' },
        'body' => 'Hello {{1}} {{2}} {{3}} {{4}} {{5}} {{6}}'
      }
    };

    Test.startTest();
    String payload = BWM_WaCampPayloadA.buildPayload(
      settings,
      null,
      'prospect_dept_enq_280526',
      templateMeta,
      leadRecord,
      '917980828320'
    );
    Test.stopTest();

    System.assert(payload.contains('"channel":"WhatsApp"'), payload);
    System.assert(payload.contains('"templatepayload"'), payload);
    System.assert(!payload.contains('"channel":"Journey"'), payload);
    System.assert(payload.contains('"biz_opaque_callback_data"'), payload);
    System.assert(payload.contains('"type":"header"'), payload);
    System.assert(payload.contains('"type":"body"'), payload);
  }

  @IsTest
  static void buildPayloadOmitsBodyForStaticTemplate() {
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Id":"00Q000000000002AAA","Department_Name__c":"Crash Barrier"}',
      Lead.class
    );
    Map<String, Object> templateMeta = new Map<String, Object>{
      'language' => 'en',
      'content' => new Map<String, Object>{
        'body' => 'Hello customer, no variables here.'
      }
    };

    Test.startTest();
    String payload = BWM_WaCampPayloadA.buildPayload(
      settings,
      null,
      'cb_n_n_july26',
      templateMeta,
      leadRecord,
      '917980828320'
    );
    Test.stopTest();

    System.assert(payload.contains('"components":[]'), payload);
  }

  @IsTest
  static void buildPayloadIncludesQuickReplyButtonsFromTemplateJson() {
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Id":"00Q000000000003AAA","Name":"Test Lead","Department_Name__c":"Solar"}',
      Lead.class
    );
    Map<String, Object> templateMeta = new Map<String, Object>{
      'language' => 'en',
      'components' => new List<Object>{
        new Map<String, Object>{
          'type' => 'BODY',
          'text' => 'Quote {{1}} valid until {{2}}'
        },
        new Map<String, Object>{
          'type' => 'BUTTONS',
          'buttons' => new List<Object>{
            new Map<String, Object>{ 'type' => 'QUICK_REPLY', 'text' => 'Yes' },
            new Map<String, Object>{ 'type' => 'QUICK_REPLY', 'text' => 'No' }
          }
        }
      }
    };

    Test.startTest();
    String payload = BWM_WaCampPayloadA.buildPayload(
      settings,
      null,
      'quotation_manual_trigger',
      templateMeta,
      leadRecord,
      '917980828320'
    );
    Test.stopTest();

    System.assert(payload.contains('"sub_type":"quick_reply"'), payload);
    System.assert(payload.contains('"payload":"Yes"'), payload);
    System.assert(payload.contains('"payload":"No"'), payload);
    System.assert(payload.contains('"type":"body"'), payload);
  }

  @IsTest
  static void buildPayloadUsesHeaderVariableNotLiteralPlaceholder() {
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Id":"00Q000000000004AAA","Department_Name__c":"Crash Barrier"}',
      Lead.class
    );
    Map<String, Object> templateMeta = new Map<String, Object>{
      'language' => 'en',
      'components' => new List<Object>{
        new Map<String, Object>{
          'type' => 'HEADER',
          'format' => 'TEXT',
          'text' => 'Department {{1}}'
        },
        new Map<String, Object>{
          'type' => 'BODY',
          'text' => 'Hello {{1}}'
        }
      }
    };

    Test.startTest();
    String payload = BWM_WaCampPayloadA.buildPayload(
      settings,
      null,
      'prospect_enq_dept',
      templateMeta,
      leadRecord,
      '917980828320'
    );
    Test.stopTest();

    System.assert(!payload.contains('Department {{1}}'), payload);
    System.assert(payload.contains('"type":"header"'), payload);
    System.assert(payload.contains('Crash Barrier'), payload);
  }

  @IsTest
  static void buildPayloadIncludesDocumentHeaderOnlyWhenTemplateDefinesIt() {
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Id":"00Q000000000005AAA","Department_Name__c":"Crash Barrier"}',
      Lead.class
    );
    Map<String, Object> templateMeta = new Map<String, Object>{
      'language' => 'en',
      'content' => new Map<String, Object>{
        'header' => new Map<String, Object>{ 'type' => 'DOCUMENT' },
        'body' => 'Static message without variables'
      }
    };

    Test.startTest();
    String payload = BWM_WaCampPayloadA.buildPayload(
      settings,
      null,
      'cb_n_n_aug26',
      templateMeta,
      leadRecord,
      '917980828320'
    );
    Test.stopTest();

    System.assert(payload.contains('"type":"header"'), payload);
    System.assert(payload.contains('"type":"document"'), payload);
    System.assert(!payload.contains('"type":"body"'), payload);
    System.assert(payload.contains('"filename"'), payload);
  }

  @IsTest
  static void buildPayloadDoesNotSendPdfAsVideoHeader() {
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Id":"00Q000000000006AAA","Department_Name__c":"PVC Pipes and Fittings"}',
      Lead.class
    );
    Map<String, Object> templateMeta = new Map<String, Object>{
      'language' => 'en',
      'content' => new Map<String, Object>{
        'header' => new Map<String, Object>{
          'media_type' => 'DYNAMIC',
          'type' => 'VIDEO'
        },
        'body' => 'Crash-Tested Metal Beam Crash Barriers from Utkarsh India'
      }
    };

    Test.startTest();
    String payload = BWM_WaCampPayloadA.buildPayload(
      settings,
      null,
      'cb_n_n_june26',
      templateMeta,
      leadRecord,
      '917980828320'
    );
    Test.stopTest();

    System.assert(payload.contains('"type":"video"'), payload);
    System.assert(
      payload.contains('Template/Video/Utkarsh/crash_barrier.mp4'),
      payload
    );
    System.assert(!payload.contains('PVC_Pipes_and_Fittings.mp4'), payload);
    System.assert(!payload.contains('PVC_Pipes_and_Fittings.pdf'), payload);
  }

  @IsTest
  static void buildPayloadPrefersContentDocumentHeaderOverVideoComponent() {
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Id":"00Q000000000007AAA","Department_Name__c":"Crash Barrier"}',
      Lead.class
    );
    Map<String, Object> templateMeta = new Map<String, Object>{
      'language' => 'en',
      'content' => new Map<String, Object>{
        'header' => new Map<String, Object>{ 'type' => 'DOCUMENT' },
        'body' => 'Static body'
      },
      'components' => new List<Object>{
        new Map<String, Object>{
          'type' => 'HEADER',
          'format' => 'VIDEO'
        }
      }
    };

    Test.startTest();
    String payload = BWM_WaCampPayloadA.buildPayload(
      settings,
      null,
      'cb_n_n_june26',
      templateMeta,
      leadRecord,
      '917980828320'
    );
    Test.stopTest();

    System.assert(payload.contains('"type":"document"'), payload);
    System.assert(!payload.contains('"type":"video"'), payload);
  }
}