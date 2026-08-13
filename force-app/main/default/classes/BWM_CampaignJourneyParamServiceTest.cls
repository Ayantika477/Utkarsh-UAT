/**
 * @description   Test class for BWM_CampaignJourneyParamService parameter validation
 *                scenarios.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
@IsTest
private class BWM_CampaignJourneyParamServiceTest {
  @IsTest
  static void ownerMatchesCrmUserNameForLeadAndOpportunity() {
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"CRM_User_Name_Formula__c":"Sudip Datta","Owner":{"attributes":{"type":"User"},"Name":"Sudip Datta"}}',
      Lead.class
    );
    Opportunity opportunityRecord = (Opportunity) JSON.deserialize(
      '{"CRM_User_Name_Formula__c":"Sudip Datta","Owner":{"attributes":{"type":"User"},"Name":"Sudip Datta"}}',
      Opportunity.class
    );
    Contact contactRecord = new Contact(LastName = 'No CRM');

    System.assertEquals(
      true,
      BWM_CampaignJourneyParamService.ownerMatchesCrmUserName(leadRecord)
    );
    System.assertEquals(
      true,
      BWM_CampaignJourneyParamService.ownerMatchesCrmUserName(opportunityRecord)
    );
    System.assertEquals(
      false,
      BWM_CampaignJourneyParamService.ownerMatchesCrmUserName(contactRecord)
    );
  }

  @IsTest
  static void applySecondaryContactOverrideUpdatesParamsFourThroughSix() {
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"CRM_User_Name_Formula__c":"Sudip Datta","Owner":{"attributes":{"type":"User"},"Name":"Sudip Datta"}}',
      Lead.class
    );
    List<String> params = new List<String>{
      'Owner',
      'Owner Phone',
      'Owner Email',
      'Rudra Narayan Chakraborty',
      '9999999999',
      'rudra@test.com'
    };

    List<String> updated = BWM_CampaignJourneyParamService.applySecondaryContactOverride(
      leadRecord,
      params
    );

    System.assertEquals('Sudip Datta', updated[3]);
    System.assertEquals(
      BWM_MessagingConstants.CAMPAIGN_OWNER_CRM_MATCH_PHONE,
      updated[4]
    );
    System.assertEquals(
      BWM_MessagingConstants.CAMPAIGN_OWNER_CRM_MATCH_EMAIL,
      updated[5]
    );
  }

  @IsTest
  static void applyRcsBodyDataOverrideUpdatesSecondaryContactFields() {
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"CRM_User_Name_Formula__c":"Sudip Datta","Owner":{"attributes":{"type":"User"},"Name":"Sudip Datta"}}',
      Lead.class
    );
    Map<String, Object> bodyData = new Map<String, Object>{
      'Lead_owner' => 'Sudip Datta',
      'Department_crm_phone' => '9999999999',
      'Department_crm_email' => 'crm@test.com'
    };

    Map<String, Object> updated = BWM_CampaignJourneyParamService.applyRcsBodyDataOverride(
      leadRecord,
      bodyData
    );

    System.assertEquals('Sudip Datta', updated.get('Lead_owner'));
    System.assertEquals(
      BWM_MessagingConstants.CAMPAIGN_OWNER_CRM_MATCH_PHONE,
      updated.get('Department_crm_phone')
    );
    System.assertEquals(
      BWM_MessagingConstants.CAMPAIGN_OWNER_CRM_MATCH_EMAIL,
      updated.get('Department_crm_email')
    );
  }

  /**
   * Scenario: Blank {{4}}/{{5}}/{{6}} (CRM fields empty) are filled with corporate
   *           defaults so WhatsApp does not show literal 4/5/6.
   */
  @IsTest
  static void applyCampaignContactParamFixes_FillsBlankSecondarySlots() {
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"CRM_User_Name_Formula__c":"","Owner":{"attributes":{"type":"User"},"Name":"Sudip Datta"}}',
      Lead.class
    );
    List<String> params = new List<String>{
      'Sudip Datta',
      '9830453567',
      'customersupport@utkarshindia.in',
      '',
      '',
      ''
    };

    List<String> updated = BWM_CampaignJourneyParamService.applyCampaignContactParamFixes(
      leadRecord,
      params
    );

    System.assertEquals('Sudip Datta', updated[0]);
    System.assertEquals(
      BWM_MessagingConstants.CORPORATE_SUPPORT_NAME_1_DEFAULT,
      updated[3]
    );
    System.assertEquals(
      BWM_MessagingConstants.CAMPAIGN_OWNER_CRM_MATCH_PHONE,
      updated[4]
    );
    System.assertEquals(
      BWM_MessagingConstants.FALLBACK_CONTACT_EMAIL,
      updated[5]
    );
  }

  /**
   * Scenario: Dual-contact journeys mapped with only Param1–3 are padded to 6 and
   *           secondary slots filled so WhatsApp does not show literal 4/5/6.
   */
  @IsTest
  static void applyCampaignContactParamFixes_PadsThreeParamsToSix() {
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"CRM_User_Name_Formula__c":"","Owner":{"attributes":{"type":"User"},"Name":"Sudip Datta"}}',
      Lead.class
    );
    List<String> params = new List<String>{
      'Sudip Datta',
      '9830453567',
      'customersupport@utkarshindia.in'
    };

    List<String> updated = BWM_CampaignJourneyParamService.applyCampaignContactParamFixes(
      leadRecord,
      params
    );

    System.assertEquals(6, updated.size());
    System.assertEquals(
      BWM_MessagingConstants.CORPORATE_SUPPORT_NAME_1_DEFAULT,
      updated[3]
    );
    System.assertEquals(
      BWM_MessagingConstants.CAMPAIGN_OWNER_CRM_MATCH_PHONE,
      updated[4]
    );
    System.assertEquals(
      BWM_MessagingConstants.FALLBACK_CONTACT_EMAIL,
      updated[5]
    );
  }

  /**
   * Scenario: Literal "4"/"5"/"6" secondary values are treated as missing and replaced.
   */
  @IsTest
  static void applyCampaignContactParamFixes_ReplacesLiteralIndexes() {
    Lead leadRecord = new Lead(LastName = 'Test', Company = 'Test');
    List<String> params = new List<String>{
      'Sudip Datta',
      '9830453567',
      'customersupport@utkarshindia.in',
      '4',
      '5',
      '6'
    };

    List<String> updated = BWM_CampaignJourneyParamService.applyCampaignContactParamFixes(
      leadRecord,
      params
    );

    System.assertEquals(
      BWM_MessagingConstants.CORPORATE_SUPPORT_NAME_1_DEFAULT,
      updated[3]
    );
    System.assertEquals(
      BWM_MessagingConstants.CAMPAIGN_OWNER_CRM_MATCH_PHONE,
      updated[4]
    );
    System.assertEquals(
      BWM_MessagingConstants.FALLBACK_CONTACT_EMAIL,
      updated[5]
    );
  }

  /**
   * Scenario: fillBlank alone does not pad short lists (padding is via applyCampaign*).
   */
  @IsTest
  static void fillBlankSecondaryContactParams_LeavesShortListsUnchanged() {
    List<String> params = new List<String>{ 'A', 'B', 'C' };
    List<String> updated = BWM_CampaignJourneyParamService.fillBlankSecondaryContactParams(
      params
    );
    System.assertEquals(3, updated.size());
    System.assertEquals('A', updated[0]);
  }
}