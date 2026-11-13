/**
 * @description   Test class for the Polymer/HDPE Refer to Dealer journey (POLY_REFER_DEALER)
 *                and its RCS variable names in BWM_RcsDirectPayloadBuilder.
 * @author        Anshita Chanda
 * @date          2026-10-29
 */
@IsTest
private class BWM_PolyReferDealerJourneyTest {
  private static Opportunity buildOpportunity(String department) {
    return (Opportunity) JSON.deserialize(
      JSON.serialize(new Map<String, Object>{
        'attributes' => new Map<String, Object>{ 'type' => 'Opportunity' },
        'Id' => '006000000000001AAA',
        'Name' => 'Poly Dealer Opp',
        'StageName' => 'Nurture',
        'Department_Name__c' => department,
        'Customer_Journey__c' => 'Refer to Dealer',
        'DealerAccount__c' => '001000000000001AAA',
        'DealerAccount__r' => new Map<String, Object>{
          'attributes' => new Map<String, Object>{ 'type' => 'Account' },
          'Name' => 'Dealer One'
        },
        'Account' => new Map<String, Object>{
          'attributes' => new Map<String, Object>{ 'type' => 'Account' },
          'Name' => 'Customer Co'
        },
        'Contact_Person_Name__c' => 'Ravi Kumar',
        'Phone__c' => '9876501234',
        'Email__c' => 'ravi@customer.test',
        'City__c' => 'Kolkata',
        'State__c' => 'West Bengal',
        'Owner' => new Map<String, Object>{
          'attributes' => new Map<String, Object>{ 'type' => 'User' },
          'Name' => 'Owner Person'
        }
      }),
      Opportunity.class
    );
  }

  @IsTest
  static void referDealerPolymerUsesPolyJourneyAndDealerValues() {
    Opportunity opportunityRecord = buildOpportunity('Polymer');

    Test.startTest();
    BWM_TemplateResolver.ResolveResult resolved = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_OPPORTUNITY_REFER_TO_DEALER,
      opportunityRecord
    );
    String payload = BWM_MessagePayloadBuilder.buildJourneyPayloadForRecord(
      BWM_SettingsService.getSettings(),
      resolved.mapping,
      opportunityRecord,
      '919999999999'
    );
    Test.stopTest();

    System.assertEquals('POLY_REFER_DEALER', resolved.mapping.Journey_Name__c);
    System.assert(payload.contains('"templateName":"poly_dealer_sales_assign"'), payload);
    System.assert(payload.contains('"templateName":"poly_dealer_assign"'), payload);
    System.assert(payload.contains('"templateName":"Dealer_sales_assign"'), payload);
    System.assert(payload.contains('"value":"Dealer One"'), payload);
    System.assert(payload.contains('"value":"Ravi Kumar"'), payload);
    System.assert(payload.contains('"value":"Customer Co"'), payload);
    System.assert(payload.contains('"value":"Kolkata"'), payload);
    System.assert(!payload.contains('"headerFormat"'), 'Refer to Dealer has no header: ' + payload);
  }

  @IsTest
  static void otherDepartmentsKeepTheExistingDealerJourney() {
    Opportunity opportunityRecord = buildOpportunity('Crash Barrier');

    Test.startTest();
    BWM_TemplateResolver.ResolveResult resolved = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_OPPORTUNITY_REFER_TO_DEALER,
      opportunityRecord
    );
    Test.stopTest();

    System.assertEquals('dealer_sales_assign', resolved.mapping.Journey_Name__c);
  }

  @IsTest
  static void dealerRcsNamesResolveFromOpportunity() {
    Opportunity opportunityRecord = buildOpportunity('HDPE');

    Test.startTest();
    Map<String, Object> bodyData = BWM_RcsDirectPayloadBuilder.buildNamedBodyDataForJourney(
      BWM_SettingsService.getSettings(),
      'poly_dealer_assign',
      opportunityRecord,
      new Map<String, Object>{
        '{{1}}' => 'dealer_name',
        '{{2}}' => 'Customer_name',
        '{{3}}' => 'Opportunity_company',
        '{{4}}' => 'Opportunity_phone',
        '{{5}}' => 'Opportunity_email',
        '{{6}}' => 'Opportunity_city',
        '{{7}}' => 'Opportunity_state'
      }
    );
    Test.stopTest();

    System.assertEquals('Dealer One', bodyData.get('dealer_name'));
    System.assertEquals('Ravi Kumar', bodyData.get('Customer_name'));
    System.assertEquals('Customer Co', bodyData.get('Opportunity_company'));
    System.assertEquals('9876501234', bodyData.get('Opportunity_phone'));
    System.assertEquals('ravi@customer.test', bodyData.get('Opportunity_email'));
    System.assertEquals('Kolkata', bodyData.get('Opportunity_city'));
    System.assertEquals('West Bengal', bodyData.get('Opportunity_state'));
  }
}