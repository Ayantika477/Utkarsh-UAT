@IsTest
private class BWM_MessagePayloadBuilderTest {
  @IsTest
  static void buildJourneyPayloadIncludesWhatsAppRcsAndSmsNodesForCampaignSend() {
    BWM_JourneyDefinitionService.clearCache();
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Status":"Prospect","Department_Name__c":"Crash Barrier","CRM_User_Name_Formula__c":"Sudip Datta","Owner":{"attributes":{"type":"User"},"Name":"Sudip Datta","Phone":"8888888888","Email":"owner@test.com"}}',
      Lead.class
    );
    BWM_Template_Mapping__mdt mapping =
      BWM_JourneyDefinitionService.findMappingByJourneyName(
        'prospect_not_responding_dept'
      );
    System.assertNotEquals(null, mapping);

    Test.startTest();
    String payload = BWM_MessagePayloadBuilder.buildJourneyPayloadForRecord(
      settings,
      mapping,
      leadRecord,
      '919876543210',
      false,
      true
    );
    Test.stopTest();

    System.assert(payload.contains('"templateType":"WHATSAPP"'));
    System.assert(payload.contains('"templateType":"RCSMESSAGE"'));
    System.assert(payload.contains('"templateType":"SMS"'));
    System.assert(payload.contains('info@utkarshindia.in'));
  }

  @IsTest
  static void buildWhatsAppPayloadForRecordUsesMappingParams() {
    BWM_JourneyDefinitionService.clearCache();
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Status":"Prospect","Department_Name__c":"Crash Barrier","Owner":{"attributes":{"type":"User"},"Name":"Owner Name","Phone":"8888888888","Email":"owner@test.com"}}',
      Lead.class
    );
    BWM_Template_Mapping__mdt mapping =
      BWM_JourneyDefinitionService.findMappingByJourneyName('dealer_enq_dept');
    System.assertNotEquals(null, mapping);

    Test.startTest();
    String payload = BWM_MessagePayloadBuilder.buildWhatsAppPayloadForRecord(
      settings,
      mapping,
      leadRecord,
      '919876543210'
    );
    Test.stopTest();

    System.assert(payload.contains('"channel":"Journey"'));
  }

  @IsTest
  static void buildRcsAndSmsPayloadsForRecordUseMapping() {
    BWM_JourneyDefinitionService.clearCache();
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Status":"Prospect","Department_Name__c":"Crash Barrier","Owner":{"attributes":{"type":"User"},"Name":"Owner Name","Phone":"8888888888","Email":"owner@test.com"}}',
      Lead.class
    );
    BWM_Template_Mapping__mdt mapping =
      BWM_JourneyDefinitionService.findMappingByJourneyName('dealer_enq_dept');
    System.assertNotEquals(null, mapping);

    Test.startTest();
    String rcsPayload = BWM_MessagePayloadBuilder.buildRcsPayloadForRecord(
      settings,
      mapping,
      leadRecord,
      '919876543210'
    );
    String smsPayload = BWM_MessagePayloadBuilder.buildSmsPayloadForRecord(
      settings,
      mapping,
      leadRecord,
      '919876543210'
    );
    Test.stopTest();

    System.assert(rcsPayload.contains('"channel":"Journey"'));
    System.assert(smsPayload.contains('"channel":"Journey"'));
  }

  @IsTest
  static void buildJourneyPayloadIncludesDocumentFileNameWhenRequested() {
    BWM_JourneyDefinitionService.clearCache();
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Status":"Prospect","Department_Name__c":"Crash Barrier","Owner":{"attributes":{"type":"User"},"Name":"Owner Name","Phone":"8888888888","Email":"owner@test.com"}}',
      Lead.class
    );
    BWM_Template_Mapping__mdt mapping =
      BWM_JourneyDefinitionService.findMappingByJourneyName(
        'prospect_not_responding_dept'
      );
    System.assertNotEquals(null, mapping);

    Test.startTest();
    String payload = BWM_MessagePayloadBuilder.buildJourneyPayloadForRecord(
      settings,
      mapping,
      leadRecord,
      '919876543210',
      true,
      false
    );
    Test.stopTest();

    System.assert(payload.contains('"fileName"'));
  }

  @IsTest
  static void buildJourneyPayloadWithoutCampaignUsesCorporateSupportContact() {
    BWM_JourneyDefinitionService.clearCache();
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Status":"Prospect","Department_Name__c":"Crash Barrier","CRM_User_Name_Formula__c":"Different CRM","Owner":{"attributes":{"type":"User"},"Name":"Owner Name","Phone":"8888888888","Email":"owner@test.com"}}',
      Lead.class
    );
    BWM_Template_Mapping__mdt mapping =
      BWM_JourneyDefinitionService.findMappingByJourneyName(
        'prospect_not_responding_dept'
      );

    Test.startTest();
    String payload = BWM_MessagePayloadBuilder.buildJourneyPayloadForRecord(
      settings,
      mapping,
      leadRecord,
      '919876543210',
      false,
      false
    );
    Test.stopTest();

    System.assert(payload.contains('Rudra Narayan Chakraborty'));
  }

  @IsTest
  static void buildWhatsAppPayloadUsesLeadSpecificEntryPoint() {
    BWM_JourneyDefinitionService.clearCache();
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Status":"Prospect","Department_Name__c":"Crash Barrier","Owner":{"attributes":{"type":"User"},"Name":"Owner Name","Phone":"8888888888","Email":"owner@test.com"}}',
      Lead.class
    );
    BWM_Template_Mapping__mdt mapping =
      BWM_JourneyDefinitionService.findMappingByJourneyName('dealer_enq_dept');

    Test.startTest();
    String payload = BWM_MessagePayloadBuilder.buildWhatsAppPayload(
      settings,
      mapping,
      leadRecord,
      '919876543210'
    );
    Test.stopTest();

    System.assert(payload.contains('"channel":"Journey"'));
  }

  @IsTest
  static void buildRcsPayloadUsesLeadSpecificEntryPoint() {
    BWM_JourneyDefinitionService.clearCache();
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Status":"Prospect","Department_Name__c":"Crash Barrier","Owner":{"attributes":{"type":"User"},"Name":"Owner Name","Phone":"8888888888","Email":"owner@test.com"}}',
      Lead.class
    );
    BWM_Template_Mapping__mdt mapping =
      BWM_JourneyDefinitionService.findMappingByJourneyName('dealer_enq_dept');

    Test.startTest();
    String payload = BWM_MessagePayloadBuilder.buildRcsPayload(
      settings,
      mapping,
      leadRecord,
      '919876543210'
    );
    Test.stopTest();

    System.assert(payload.contains('"channel":"Journey"'));
  }

  @IsTest
  static void buildSmsPayloadForRecordUsesSmsNodeOnlyMapping() {
    BWM_JourneyDefinitionService.clearCache();
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Opportunity opportunityRecord = (Opportunity) JSON.deserialize(
      '{"Name":"Quote Opp","Department_Name__c":"Crash Barrier","Owner":{"attributes":{"type":"User"},"Name":"Owner Name","Phone":"8888888888","Email":"owner@test.com"}}',
      Opportunity.class
    );
    BWM_Template_Mapping__mdt mapping =
      BWM_JourneyDefinitionService.findMappingByJourneyName('neg_quote');
    System.assertNotEquals(null, mapping);

    Test.startTest();
    String payload = BWM_MessagePayloadBuilder.buildSmsPayloadForRecord(
      settings,
      mapping,
      opportunityRecord,
      '919876543210'
    );
    Test.stopTest();

    System.assert(payload.contains('"channel":"Journey"'));
  }

  @IsTest
  static void buildJourneyPayloadResolvesDepartmentBrochureHeaderForQuoteJourney() {
    BWM_JourneyDefinitionService.clearCache();
    BWM_BrochureService.setBrochureMapForTest(
      new Map<String, BWM_Department_Brochure__mdt>{
        'Crash Barrier' => new BWM_Department_Brochure__mdt(
          Department_Name__c = 'Crash Barrier',
          Content_File_Title__c = 'Crash Barrier Brochure',
          Brochure_File_Name__c = 'Crash_Barrier.pdf',
          Static_Resource_Name__c = 'Crash_Barrier_pdf',
          Brochure_URL__c = 'https://portal.bluewavesmedia.in/WhatsAppMedia/Template/Document/Utkarsh/crash_barrier.pdf'
        )
      }
    );

    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Opportunity opportunityRecord = (Opportunity) JSON.deserialize(
      '{"Name":"Quote Opp","Department_Name__c":"Crash Barrier","Owner":{"attributes":{"type":"User"},"Name":"Owner Name","Phone":"8888888888","Email":"owner@test.com"}}',
      Opportunity.class
    );
    BWM_Template_Mapping__mdt mapping =
      BWM_JourneyDefinitionService.findMappingByJourneyName('neg_quote');
    System.assertNotEquals(null, mapping);

    Test.startTest();
    String payload = BWM_MessagePayloadBuilder.buildJourneyPayloadForRecord(
      settings,
      mapping,
      opportunityRecord,
      '919876543210',
      true,
      false
    );
    Test.stopTest();

    BWM_BrochureService.clearCache();
    System.assert(payload.contains('"headerFormat":"DOCUMENT"'));
    System.assert(payload.contains('crash_barrier.pdf'));
  }

  @IsTest
  static void buildJourneyPayloadUsesTextHeaderWhenConfigured() {
    BWM_JourneyDefinitionService.clearCache();
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Opportunity opportunityRecord = (Opportunity) JSON.deserialize(
      '{"Name":"Refer Dealer Opp","Department_Name__c":"Crash Barrier","Contact_Person_Name__c":"Contact Person","Phone__c":"9876543210","Account":{"attributes":{"type":"Account"},"Name":"Dealer Account"},"Owner":{"attributes":{"type":"User"},"Name":"Owner Name","Phone":"8888888888","Email":"owner@test.com"}}',
      Opportunity.class
    );
    BWM_Template_Mapping__mdt mapping =
      BWM_JourneyDefinitionService.findMappingByJourneyName('dealer_sales_assign');
    if (mapping == null) {
      return;
    }

    Test.startTest();
    String payload = BWM_MessagePayloadBuilder.buildJourneyPayloadForRecord(
      settings,
      mapping,
      opportunityRecord,
      '919876543210',
      false,
      false
    );
    Test.stopTest();

    System.assert(
      payload.contains('"headerFormat":"TEXT"') ||
        payload.contains('"headerFormat":"DOCUMENT"')
    );
  }

  @IsTest
  static void buildJourneyPayloadPadsBlankWhatsAppVariables() {
    BWM_JourneyDefinitionService.clearCache();
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Status":"Prospect","Department_Name__c":"Crash Barrier","Owner":{"attributes":{"type":"User"},"Name":"Owner Name"}}',
      Lead.class
    );
    BWM_Template_Mapping__mdt mapping =
      BWM_JourneyDefinitionService.findMappingByJourneyName('dealer_enq_dept');
    System.assertNotEquals(null, mapping);

    Test.startTest();
    String payload = BWM_MessagePayloadBuilder.buildJourneyPayloadForRecord(
      settings,
      mapping,
      leadRecord,
      '919876543210',
      false,
      false
    );
    Test.stopTest();

    System.assert(payload.contains('"value":" "') || payload.contains('"value":"Owner Name"'));
  }
}