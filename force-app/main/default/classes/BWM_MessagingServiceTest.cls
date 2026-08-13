@IsTest
private class BWM_MessagingServiceTest {
  @IsTest
  static void sendsWhatsAppForInboundEmailProductDepartment() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'High Mast & Polygonal',
      '9876543210'
    );

    Test.startTest();
    BWM_MessagingService.SendResult result = BWM_MessagingService.sendForLeadCreate(
      leadRecord.Id
    );
    Test.stopTest();

    System.assertEquals(true, result.sent, 'Journey should succeed.');
    System.assertEquals('Journey', result.channelUsed);
    System.assertEquals(1, result.logs.size());
    System.assertEquals('Sent', result.logs[0].Status__c);
    System.assertEquals('200', result.logs[0].Response_Code__c);
  }

  @IsTest
  static void sendsWhatsAppForOutboundCallEnquiry() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Lead leadRecord = createLead(
      'OUTBOUND PHONE CALL',
      'Prospect',
      'Enquiry',
      '9876543211'
    );

    Test.startTest();
    BWM_MessagingService.SendResult result = BWM_MessagingService.sendForLeadCreate(
      leadRecord.Id
    );
    Test.stopTest();

    System.assertEquals(true, result.sent);
    System.assertEquals('Journey', result.channelUsed);
  }

  @IsTest
  static void sendsInboundEmailWithEnquiryDepartment() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Enquiry',
      '9876543212'
    );

    Test.startTest();
    BWM_MessagingService.SendResult result = BWM_MessagingService.sendForLeadCreate(
      leadRecord.Id
    );
    Test.stopTest();

    System.assertEquals(true, result.sent);
    System.assertEquals('Journey', result.channelUsed);
    System.assertEquals('prospect_enq_gen', result.logs[0].Template_Name__c);
  }

  @IsTest
  static void journeySendFailsWhenApiReturnsError() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"400","message":"Journey failed"}',
        '{"code":"200","message":"unused"}'
      )
    );

    Lead leadRecord = createLead(
      'OUTBOUND PHONE CALL',
      'Prospect',
      'Enquiry',
      '9876543213'
    );

    Test.startTest();
    BWM_MessagingService.SendResult result = BWM_MessagingService.sendForLeadCreate(
      leadRecord.Id
    );
    Test.stopTest();

    System.assertEquals(false, result.sent);
    System.assertEquals(1, result.logs.size());
    System.assertEquals('Failed', result.logs[0].Status__c);
    System.assert(result.skipReason.contains('Journey'));
  }

  @IsTest
  static void journeyPayloadContainsWhatsAppRcsAndSmsNodes() {
    Lead leadRecord = createLead(
      'OUTBOUND PHONE CALL',
      'Prospect',
      'Enquiry',
      '9876543210'
    );
    leadRecord = [
      SELECT
        Id,
        FirstName,
        LastName,
        Company,
        Company_Name__c,
        Department_Name__c,
        Product_Category__c,
        Owner.Name,
        Email,
        LeadSource,
        Status
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];

    BWM_TemplateResolver.ResolveResult resolved = BWM_TemplateResolver.resolveForLeadCreate(
      leadRecord
    );
    String payload = BWM_MessagePayloadBuilder.buildJourneyPayloadForRecord(
      BWM_SettingsService.getSettings(),
      resolved.mapping,
      leadRecord,
      '919876543210'
    );

    System.assert(payload.contains('"channel":"Journey"'));
    System.assert(payload.contains('"journeyname":"prospect_enq_gen"'));
    System.assert(payload.contains('"templateType":"WHATSAPP"'));
    System.assert(payload.contains('"templateType":"RCSMESSAGE"'));
    System.assert(payload.contains('"templateType":"SMS"'));
    System.assert(payload.contains('"prospect_enq_gen"'));
    System.assert(payload.contains('"headerFormat":"DOCUMENT"'));
    System.assert(
      payload.contains('corporate_brochure') ||
        payload.contains('portal.bluewavesmedia.in/WhatsAppMedia/Template/Document/Utkarsh'),
      'prospect_enq_gen must attach corporate brochure document header.'
    );
    System.assertEquals(2, resolved.mapping.RCS_SMS_Param_Limit__c);
  }

  @IsTest
  static void invocableQueuesMessaging() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Crash Barrier',
      '9876543215'
    );

    BWM_SendMessageInvocable.Request requestItem = new BWM_SendMessageInvocable.Request();
    requestItem.leadId = leadRecord.Id;

    Test.startTest();
    List<BWM_SendMessageInvocable.Response> responses = BWM_SendMessageInvocable.sendMessage(
      new List<BWM_SendMessageInvocable.Request>{ requestItem }
    );
    Test.stopTest();

    System.assertEquals(true, responses[0].queued);
  }

  @IsTest
  static void queueableAndTriggerCreateLogs() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Test.startTest();
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Crash Barrier',
      '9876543214',
      true
    );
    Test.stopTest();

    List<Message_Log__c> logs = [
      SELECT Id, Status__c, Channel__c
      FROM Message_Log__c
      WHERE Lead__c = :leadRecord.Id
    ];
    System.assertEquals(1, logs.size());
    System.assertEquals('Sent', logs[0].Status__c);
    System.assertEquals('Journey', logs[0].Channel__c);
  }

  @IsTest
  static void phoneFormatterAddsCountryCode() {
    System.assertEquals(
      '919876543210',
      BWM_PhoneFormatter.formatForMessaging('9876543210', '91')
    );
    System.assertEquals(
      '919876543210',
      BWM_PhoneFormatter.formatForMessaging('+91 98765-43210', '91')
    );
    System.assertEquals(
      null,
      BWM_PhoneFormatter.formatForMessaging('980828320', '91')
    );
  }

  @IsTest
  static void settingsServiceLoadsDefaultDocumentId() {
    BWM_SettingsService.clearCache();
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    System.assertNotEquals(null, settings);
    System.assert(String.isNotBlank(settings.Default_WhatsApp_Document_Id__c));
  }

  @IsTest
  static void journeyPayloadMatchesInboundEmailWorkingJson() {
    BWM_SettingsService.clearCache();
    BWM_BrochureService.clearCache();

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'High Mast & Polygonal',
      '9876543210'
    );
    leadRecord = [
      SELECT
        Id,
        FirstName,
        LastName,
        Company,
        Company_Name__c,
        Department_Name__c,
        Product_Category__c,
        Owner.Name,
        Email,
        LeadSource,
        Status
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];

    BWM_TemplateResolver.ResolveResult resolved = BWM_TemplateResolver.resolveForLeadCreate(
      leadRecord
    );
    String payload = BWM_MessagePayloadBuilder.buildJourneyPayloadForRecord(
      BWM_SettingsService.getSettings(),
      resolved.mapping,
      leadRecord,
      '919876543210'
    );

    System.assert(payload.contains('"journeyname":"prospect_enq_dept"'));
    System.assert(payload.contains('"templateName":"prospect_enq_dept"'));
    System.assert(payload.contains('"headerFormat":"DOCUMENT"'));
    System.assert(
      payload.contains('portal.bluewavesmedia.in/WhatsAppMedia/Template/Document'),
      'Header must use a Blue Waves portal PDF URL.'
    );
    System.assert(
      !payload.contains('utkarshindia.in/brochures'),
      'Header must not use blocked utkarshindia brochure URLs.'
    );
    System.assert(payload.contains('"format":"{{7}}"'));

    Map<String, Object> payloadMap = (Map<String, Object>) JSON.deserializeUntyped(
      payload
    );
    Map<String, Object> content = (Map<String, Object>) payloadMap.get('content');
    Map<String, Object> data = (Map<String, Object>) content.get('data');
    Map<String, Object> journeyPayload = (Map<String, Object>) data.get(
      'journeypayload'
    );
    Map<String, Object> nodes = (Map<String, Object>) journeyPayload.get('nodes');
    Map<String, Object> rcsNode = (Map<String, Object>) nodes.get('2');
    Map<String, Object> rcsData = (Map<String, Object>) rcsNode.get('data');
    Map<String, Object> rcsBody = (Map<String, Object>) rcsData.get('bodyData');
    System.assertEquals(
      6,
      rcsBody.size(),
      'RCS should include six named body parameters.'
    );
    System.assert(
      rcsBody.containsKey('Department_name_1'),
      'RCS bodyData must use named Department_name_1 key.'
    );
    System.assert(
      rcsBody.containsKey('Product_Brief'),
      'RCS bodyData must use named Product_Brief key.'
    );
    System.assert(
      rcsBody.containsKey('Lead_owner_phone'),
      'RCS bodyData must use named Lead_owner_phone key.'
    );
    System.assertEquals('Pros_Enq_dept_c_br', rcsData.get('templateName'));

    Map<String, Object> smsNode = (Map<String, Object>) nodes.get('3');
    Map<String, Object> smsData = (Map<String, Object>) smsNode.get('data');
    Map<String, Object> smsMappings = (Map<String, Object>) smsData.get(
      'variableMappings'
    );
    System.assertEquals(1, smsMappings.size(), 'SMS should only include one variable.');
    System.assertEquals(
      '919830637280',
      smsMappings.get('1'),
      'SMS variable should come from journey definition support phone.'
    );
    System.assertEquals('DEALER_Enq_dept', smsData.get('templateName'));
  }

  @IsTest
  static void emptyFieldTokenStaysBlank() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Steel Pipes',
      '9876543210'
    );
    leadRecord = BWM_RecordQueryService.queryLead(leadRecord.Id);

    System.assertEquals(
      '',
      BWM_FieldValueResolver.resolveRecord(leadRecord, 'EMPTY')
    );
  }

  @IsTest
  static void resolveParamsFallsBackWhenEmailMissing() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Crash Barrier',
      '9876543212'
    );
    leadRecord.Email = null;
    update leadRecord;

    leadRecord = [
      SELECT
        Id,
        FirstName,
        LastName,
        Company_Name__c,
        Department_Name__c,
        Product_Category__c,
        Owner.Name,
        Owner.Email,
        Email,
        LeadSource,
        Status
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];

    List<String> params = BWM_FieldValueResolver.resolveParams(
      leadRecord,
      BWM_TemplateResolver.resolveForLeadCreate(leadRecord).mapping
    );

    System.assertNotEquals('NA', params[6], 'Param7 email should fall back when lead email is blank.');
    System.assertEquals(7, params.size());
  }

  @IsTest
  static void resolveParamsSanitizesInvalidEmail() {
    Lead leadRecord = new Lead(
      FirstName = 'Test',
      LastName = 'User',
      Company_Name__c = 'Test Co',
      LeadSource = 'INBOUND EMAIL',
      Status = 'Prospect',
      Department_Name__c = 'Crash Barrier',
      Product_Category__c = 'MS Pipes',
      Email = 'bad@example.com'
    );

    BWM_TemplateResolver.ResolveResult resolved = BWM_TemplateResolver.resolveForLeadCreate(
      leadRecord
    );
    List<String> params = BWM_FieldValueResolver.resolveParams(
      leadRecord,
      resolved.mapping
    );

    System.assertEquals(
      BWM_MessagingConstants.FALLBACK_CONTACT_EMAIL,
      params[6],
      'Invalid owner email should fall back to support contact email.'
    );
  }

  @IsTest
  static void resolveParamsStripsSandboxInvalidSuffixFromOwnerEmail() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Crash Barrier',
      'customer@gmail.com'
    );
    leadRecord = BWM_RecordQueryService.queryLead(leadRecord.Id);

    BWM_TemplateResolver.ResolveResult resolved = BWM_TemplateResolver.resolveForLeadCreate(
      leadRecord
    );
    List<String> params = BWM_FieldValueResolver.resolveParams(
      leadRecord,
      resolved.mapping
    );

    System.assert(
      params[6].contains('@utkarshindia'),
      'Sandbox owner email should strip .invalid for contact display.'
    );
    System.assert(
      !params[6].contains('.invalid'),
      'Contact email should not keep the sandbox .invalid suffix.'
    );
  }

  @IsTest
  static void prospectEnqDeptMapsDepartmentBriefAndOwnerContact() {
    BWM_MessagingProductBriefService.setBriefMapForTest(
      new Map<String, BWM_Department_Brochure__mdt>{
        'Steel Pipes' => new BWM_Department_Brochure__mdt(
          Department_Name__c = 'Steel Pipes',
          Product_Brief__c = 'Strong, durable steel pipe solutions.'
        )
      }
    );

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Steel Pipes',
      '9876543210'
    );
    leadRecord = [
      SELECT
        Id,
        Department_Name__c,
        Phone,
        Email,
        Owner.Name,
        Owner.Email,
        Owner.Phone
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];

    BWM_Template_Mapping__mdt mapping = [
      SELECT
        Param1_Field__c,
        Param2_Field__c,
        Param3_Field__c,
        Param4_Field__c,
        Param5_Field__c,
        Param6_Field__c,
        Param7_Field__c,
        Param8_Field__c
      FROM BWM_Template_Mapping__mdt
      WHERE DeveloperName = 'Prospect_Dept_Inbound_Email'
      LIMIT 1
    ];
    List<String> params = BWM_FieldValueResolver.resolveParamsForRecord(
      leadRecord,
      mapping
    );

    System.assertEquals('Steel Pipes', params[0], '{{1}} should be department name.');
    System.assertEquals('Steel Pipes', params[1], '{{2}} should be department name.');
    System.assertEquals(
      'Strong, durable steel pipe solutions.',
      params[2],
      '{{3}} should be WhatsApp product brief.'
    );
    System.assertEquals('Steel Pipes', params[3], '{{4}} should be department name.');
    System.assert(String.isNotBlank(params[4]), '{{5}} should be lead owner name.');
    System.assertNotEquals(
      '9876543210',
      params[5],
      '{{6}} must be owner phone, not the Lead phone.'
    );
    System.assertNotEquals('NA', params[6], '{{7}} should resolve owner email.');
    BWM_MessagingProductBriefService.clearCache();
  }

  @IsTest
  static void ownerPhoneNeverFallsBackToLeadPhone() {
    User ownerUser = new User(
      Alias = 'ownrph',
      Email = 'owner.phone.test@utkarshindia.in',
      EmailEncodingKey = 'UTF-8',
      LastName = 'OwnerPhoneTest',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = UserInfo.getProfileId(),
      TimeZoneSidKey = 'Asia/Kolkata',
      UserName = 'owner.phone.test.' +
        String.valueOf(DateTime.now().getTime()) +
        '@utkarshindia.in',
      Phone = null,
      MobilePhone = '9000011122'
    );
    insert ownerUser;

    Lead leadRecord;
    System.runAs(ownerUser) {
      leadRecord = createLead(
        'INBOUND EMAIL',
        'Prospect',
        'Steel Pipes',
        '9876007788'
      );
    }

    leadRecord = BWM_RecordQueryService.queryLead(leadRecord.Id);
    BWM_Template_Mapping__mdt mapping = [
      SELECT
        Param1_Field__c,
        Param2_Field__c,
        Param3_Field__c,
        Param4_Field__c,
        Param5_Field__c,
        Param6_Field__c,
        Param7_Field__c,
        Param8_Field__c
      FROM BWM_Template_Mapping__mdt
      WHERE DeveloperName = 'Prospect_Dept_Inbound_Email'
      LIMIT 1
    ];

    List<String> params = BWM_FieldValueResolver.resolveParamsForRecord(
      leadRecord,
      mapping
    );

    System.assertEquals(
      '9000011122',
      params[5],
      'WhatsApp contact phone must be the record owner mobile number.'
    );
    System.assertNotEquals(
      '9876007788',
      params[5],
      'WhatsApp contact phone must not use the Lead phone.'
    );
    System.assertEquals(
      '9000011122',
      BWM_FieldValueResolver.resolveRecord(leadRecord, 'Owner.Phone')
    );
    System.assertEquals(
      '9000011122',
      BWM_FieldValueResolver.resolveRecord(leadRecord, 'Owner.MobilePhone')
    );

    ownerUser.MobilePhone = null;
    ownerUser.Phone = '9000033344';
    update ownerUser;
    System.assertEquals(
      '9000033344',
      BWM_FieldValueResolver.resolveRecord(leadRecord, 'Owner.Phone'),
      'When mobile is blank, owner Phone should be used.'
    );

    ownerUser.Phone = null;
    update ownerUser;
    List<String> blankPhoneParams = BWM_FieldValueResolver.resolveParamsForRecord(
      leadRecord,
      mapping
    );
    System.assertEquals(
      '',
      blankPhoneParams[5],
      'When owner has no phone, pass blank — not Lead phone and not NA.'
    );
    System.assertNotEquals('9876007788', blankPhoneParams[5]);
    System.assertNotEquals('NA', blankPhoneParams[5]);
  }

  @IsTest
  static void resolveParamsHandlesMinimallyQueriedLead() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Steel Pipes',
      '9876001299'
    );
    Lead minimalLead = new Lead(Id = leadRecord.Id);

    BWM_Template_Mapping__mdt mapping = [
      SELECT
        Param1_Field__c,
        Param2_Field__c,
        Param3_Field__c,
        Param4_Field__c,
        Param5_Field__c,
        Param6_Field__c,
        Param7_Field__c,
        Param8_Field__c
      FROM BWM_Template_Mapping__mdt
      WHERE DeveloperName = 'Prospect_Dept_Inbound_Email'
      LIMIT 1
    ];
    List<String> params = BWM_FieldValueResolver.resolveParamsForRecord(
      minimalLead,
      mapping
    );

    System.assertEquals(7, params.size());
    System.assertNotEquals(null, params[5]);
    System.assertNotEquals(null, params[6]);
  }

  @IsTest
  static void templateResolverMatchesProductDepartment() {
    Lead leadRecord = new Lead(
      LeadSource = 'INBOUND EMAIL',
      Status = 'Prospect',
      Department_Name__c = 'HDPE'
    );

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolveForLeadCreate(
      leadRecord
    );
    System.assertEquals(true, result.shouldSend);
    System.assertEquals(
      'prospect_enq_dept',
      result.mapping.WhatsApp_Template_Name__c
    );
    System.assertEquals('prospect_enq_dept', result.mapping.Journey_Name__c);
  }

  @IsTest
  static void templateResolverMatchesProspectGenForCorporateBrochureDepartments() {
    for (String departmentName : new List<String>{
      'Enquiry',
      'Transmission & Telecom Tower',
      'Pre Engineering Building',
      'Railway Electrification Structure'
    }) {
      Lead leadRecord = new Lead(
        LeadSource = 'INBOUND EMAIL',
        Status = 'Prospect',
        Department_Name__c = departmentName
      );

      BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolveForLeadCreate(
        leadRecord
      );
      System.assertEquals(
        true,
        result.shouldSend,
        'Should send for department: ' + departmentName
      );
      System.assertEquals(
        'prospect_enq_gen',
        result.mapping.WhatsApp_Template_Name__c,
        'Expected gen template for: ' + departmentName
      );
      System.assertEquals(
        'Corporate',
        result.mapping.Brochure_Attachment_Mode__c,
        'Corporate brochure required for: ' + departmentName
      );
    }
  }

  @IsTest
  static void sendsLeadCallbackForProspectStage() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Steel Pipes',
      '9876543220'
    );

    Test.startTest();
    BWM_MessagingService.SendResult result = BWM_MessagingService.send(
      leadRecord.Id,
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT
    );
    Test.stopTest();

    System.assertEquals(true, result.sent);
    System.assertEquals('prospect_not_responding_dept', result.logs[0].Template_Name__c);
  }

  @IsTest
  static void sendsLeadCallbackForProspectStageViaInvocable() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Steel Pipes',
      '9876543220'
    );

    BWM_SendTaskMessageInvocable.Request requestItem = new BWM_SendTaskMessageInvocable.Request();
    requestItem.recordId = leadRecord.Id;
    requestItem.taskAction = 'Callback';
    requestItem.stageAtAction = 'Prospect';

    Test.startTest();
    BWM_SendTaskMessageInvocable.sendTaskMessage(
      new List<BWM_SendTaskMessageInvocable.Request>{ requestItem }
    );
    Test.stopTest();

    List<Message_Log__c> logs = [
      SELECT Template_Name__c, Status__c
      FROM Message_Log__c
      WHERE
        Lead__c = :leadRecord.Id
        AND Trigger_Point__c = :BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT
    ];
    System.assertEquals(1, logs.size());
    System.assertEquals('prospect_not_responding_dept', logs[0].Template_Name__c);
  }

  @IsTest
  static void skipsLeadCallbackWhenStageDoesNotMatch() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospecting',
      'Steel Pipes',
      '9876543221'
    );

    Test.startTest();
    BWM_MessagingService.SendResult result = BWM_MessagingService.send(
      leadRecord.Id,
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT
    );
    Test.stopTest();

    System.assertEquals(false, result.sent);
    System.assert(result.skipReason.contains('Prospect'));
  }

  @IsTest
  static void sendsLeadLostDetailsForProspectingStage() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospecting',
      'HDPE',
      '9876543222'
    );
    leadRecord.Lost_Reason__c = BWM_MessagingConstants.LOST_REASON_DETAILS_NOT_RECEIVED;
    update leadRecord;

    Test.startTest();
    BWM_MessagingService.SendResult result = BWM_MessagingService.send(
      leadRecord.Id,
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_LOST_DETAILS_PROSPECTING
    );
    Test.stopTest();

    System.assertEquals(true, result.sent);
    System.assertEquals(
      'u_prospecting_det_not_rec',
      result.logs[0].Template_Name__c
    );
  }

  @IsTest
  static void invocableQueuesTriggerPointMessaging() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Crash Barrier',
      '9876543223'
    );

    BWM_SendMessageInvocable.Request requestItem = new BWM_SendMessageInvocable.Request();
    requestItem.recordId = leadRecord.Id;
    requestItem.triggerPoint = BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT;

    Test.startTest();
    List<BWM_SendMessageInvocable.Response> responses = BWM_SendMessageInvocable.sendMessage(
      new List<BWM_SendMessageInvocable.Request>{ requestItem }
    );
    Test.stopTest();

    System.assertEquals(true, responses[0].queued);
  }

  @IsTest
  static void lostReasonRouterResolvesNurtureTriggers() {
    System.assertEquals(
      BWM_MessagingConstants.TRIGGER_OPP_LOST_DETAILS_NURTURE,
      BWM_MessagingOpportunityLostReasonRouter.resolveTriggerPoint(
        BWM_MessagingConstants.STAGE_NURTURE,
        'Customer details not received'
      )
    );
    System.assertEquals(
      BWM_MessagingConstants.TRIGGER_OPP_LOST_DETAILS_NURTURE,
      BWM_MessagingOpportunityLostReasonRouter.resolveTriggerPoint(
        BWM_MessagingConstants.STAGE_CLOSED_LOST,
        BWM_MessagingConstants.STAGE_NURTURE,
        'Customer details not received'
      )
    );
    System.assertEquals(
      BWM_MessagingConstants.TRIGGER_OPP_LOST_NOT_RESPONDING_NURTURE,
      BWM_MessagingOpportunityLostReasonRouter.resolveTriggerPoint(
        BWM_MessagingConstants.STAGE_NURTURE,
        'Not responding'
      )
    );
  }

  @IsTest
  static void templateResolverValidatesReferToDealer() {
    Opportunity opportunityRecord = new Opportunity(
      Name = 'Refer Dealer Opp',
      StageName = 'Prospecting',
      Customer_Journey__c = BWM_MessagingConstants.CUSTOMER_JOURNEY_REFER_DEALER,
      DealerAccount__c = '001000000000000AAA',
      CloseDate = Date.today().addDays(30)
    );

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_OPPORTUNITY_REFER_TO_DEALER,
      opportunityRecord
    );

    System.assertEquals(true, result.shouldSend);
    System.assertEquals('dealer_sales_assign', result.mapping.Journey_Name__c);
  }

  @IsTest
  static void dealerSalesAssignMapsCustomerFieldsToWhatsAppSlots() {
    BWM_Template_Mapping__mdt mapping = [
      SELECT
        Param1_Field__c,
        Param2_Field__c,
        Param3_Field__c,
        Param4_Field__c,
        Param5_Field__c,
        Param6_Field__c,
        Param7_Field__c,
        Param8_Field__c
      FROM BWM_Template_Mapping__mdt
      WHERE DeveloperName = 'Opportunity_Refer_To_Dealer'
      LIMIT 1
    ];

    Account dealerAccount = new Account(
      Name = 'Dealer Partner',
      Phone = '6290459140',
      RecordTypeId = '012C2000000kFCAIA2'
    );
    insert dealerAccount;

    Account customerAccount = new Account(Name = 'Customer Company');
    insert customerAccount;

    Contact contactRecord = new Contact(
      FirstName = 'Jane',
      LastName = 'Customer',
      AccountId = customerAccount.Id
    );
    insert contactRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Opp Internal Name',
      AccountId = customerAccount.Id,
      ContactId = contactRecord.Id,
      StageName = BWM_MessagingConstants.STAGE_NURTURE,
      Customer_Journey__c = BWM_MessagingConstants.CUSTOMER_JOURNEY_REFER_DEALER,
      DealerAccount__c = dealerAccount.Id,
      Phone__c = '9876501234',
      Email__c = 'jane@valid-domain.com',
      City__c = 'Kolkata',
      State__c = 'West Bengal',
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    opportunityRecord = BWM_RecordQueryService.queryOpportunity(opportunityRecord.Id);

    List<String> params = BWM_FieldValueResolver.resolveParamsForRecord(
      opportunityRecord,
      mapping
    );

    System.assertEquals(7, params.size());
    System.assertEquals('Jane Customer', params[0]);
    System.assertEquals('Customer Company', params[1]);
    System.assertEquals('9876501234', params[2]);
    System.assertEquals('jane@valid-domain.com', params[3]);
    System.assertEquals('Kolkata', params[4]);
    System.assertEquals('West Bengal', params[5]);
  }

  @IsTest
  static void hasRecentLogPreventsDuplicateBatchSend() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Steel Pipes',
      '6290459110'
    );

    insert new Message_Log__c(
      Lead__c = leadRecord.Id,
      Related_Record_Id__c = leadRecord.Id,
      Trigger_Point__c = BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT,
      Status__c = BWM_MessagingConstants.LOG_STATUS_SENT
    );

    System.assertEquals(
      true,
      [
          SELECT COUNT()
          FROM Message_Log__c
          WHERE
            Related_Record_Id__c = :leadRecord.Id
            AND Trigger_Point__c = :BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT
            AND Status__c = :BWM_MessagingConstants.LOG_STATUS_SENT
            AND CreatedDate = TODAY
        ] > 0
    );
  }

  @IsTest
  static void generalizedQueueableProcessesTriggerPoint() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = true;
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Polymer',
      '6290459111'
    );
    BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = false;

    Test.startTest();
    System.enqueueJob(
      new BWM_MessagingQueueable(
        new List<BWM_MessagingRequest>{
          new BWM_MessagingRequest(
            leadRecord.Id,
            BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT
          )
        }
      )
    );
    Test.stopTest();

    List<Message_Log__c> logs = [
      SELECT Template_Name__c
      FROM Message_Log__c
      WHERE
        Lead__c = :leadRecord.Id
        AND Trigger_Point__c = :BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT
    ];
    System.assertEquals(1, logs.size());
    System.assertEquals('prospect_not_responding_dept', logs[0].Template_Name__c);
  }

  @IsTest
  static void hasRecentLogChecksOpportunityWithinWindow() {
    Account accountRecord = new Account(
      Name = 'Log Test ' + String.valueOf(DateTime.now().getTime()),
      Phone = '6290459110'
    );
    insert accountRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Log Test Opp',
      AccountId = accountRecord.Id,
      StageName = 'Negotiation',
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    insert new Message_Log__c(
      Opportunity__c = opportunityRecord.Id,
      Related_Record_Id__c = opportunityRecord.Id,
      Trigger_Point__c = BWM_MessagingConstants.TRIGGER_OPPORTUNITY_NEGOTIATION_STALE_30_DAYS,
      Status__c = BWM_MessagingConstants.LOG_STATUS_SENT
    );

    System.assertEquals(
      true,
      BWM_MessageLogService.hasRecentLog(
        opportunityRecord.Id,
        BWM_MessagingConstants.TRIGGER_OPPORTUNITY_NEGOTIATION_STALE_30_DAYS,
        30
      )
    );
  }

  @IsTest
  static void buildLogHelpersCoverMessageLogService() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'HDPE',
      '6290459112'
    );

    Message_Log__c logRecord = BWM_MessageLogService.buildLog(
      leadRecord,
      BWM_MessagingConstants.TRIGGER_LEAD_CREATE,
      BWM_MessagingConstants.LOG_CHANNEL_WHATSAPP,
      'test_template',
      '919876543210',
      BWM_MessagingConstants.LOG_STATUS_SENT,
      null
    );
    logRecord.Request_Curl__c = 'curl test';
    BWM_MessageLogService.insertLogs(new List<Message_Log__c>{ logRecord });

    System.assertEquals(
      false,
      BWM_MessageLogService.hasRecentLog(null, 'x', 30)
    );
  }

  @IsTest
  static void buildRequestCurlIncludesTokenAndPayload() {
    BWM_SettingsService.clearCache();
    String payload = '{"channel":"WhatsApp","to":["919876543210"]}';
    String curl = BWM_MessagingCallout.buildRequestCurl(payload);
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();

    System.assert(curl.contains('curl --location'), 'Should start with curl command.');
    System.assert(
      curl.contains('https://portal.bluewavesmedia.in/api/v1/send'),
      'Should include API URL.'
    );
    System.assert(
      String.isNotBlank(settings.API_Bearer_Token__c),
      'Test settings should include bearer token.'
    );
    System.assert(
      curl.contains('Bearer ' + settings.API_Bearer_Token__c),
      'Stored curl should include the configured bearer token.'
    );
    System.assert(curl.contains(payload), 'JSON body should be in curl.');
  }

  @IsTest
  static void messageLogStoresRequestCurlOnSend() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Crash Barrier',
      '6290459110'
    );

    Test.startTest();
    BWM_MessagingService.SendResult result = BWM_MessagingService.sendForLeadCreate(
      leadRecord.Id
    );
    BWM_MessageLogService.insertLogs(result.logs);
    Test.stopTest();

    System.assertEquals(1, result.logs.size());
    System.assert(String.isNotBlank(result.logs[0].Request_Curl__c));
    System.assert(result.logs[0].Request_Curl__c.contains('curl --location'));
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    System.assert(
      result.logs[0].Request_Curl__c.contains(
        'Bearer ' + settings.API_Bearer_Token__c
      )
    );
    System.assert(String.isNotBlank(result.logs[0].Request_Payload__c));
    System.assert(result.logs[0].Request_Payload__c.contains('WHATSAPP'));
    System.assertEquals('200', result.logs[0].Response_Code__c);
    System.assertEquals('200', result.logs[0].Response_Http_Status__c);
    System.assert(String.isNotBlank(result.logs[0].Response_Payload__c));
  }

  @IsTest
  static void apiResponseParseHandlesEmptyBody() {
    HttpResponse response = new HttpResponse();
    response.setStatusCode(500);
    response.setBody('');

    BWM_ApiResponse parsed = BWM_ApiResponse.parse(response, '202');

    System.assertEquals('Empty response body.', parsed.message);
    System.assertEquals(false, parsed.isSuccess);
    System.assertEquals(500, parsed.httpStatus);
  }

  @IsTest
  static void apiResponseParseUsesErrorFieldWhenMessageMissing() {
    HttpResponse response = new HttpResponse();
    response.setStatusCode(400);
    response.setBody('{"code":"400","error":"Invalid phone number"}');

    BWM_ApiResponse parsed = BWM_ApiResponse.parse(response, '202');

    System.assertEquals('400', parsed.code);
    System.assertEquals('Invalid phone number', parsed.message);
    System.assertEquals(false, parsed.isSuccess);
  }

  @IsTest
  static void apiResponseParseFallsBackToRawBodyForInvalidJson() {
    HttpResponse response = new HttpResponse();
    response.setStatusCode(502);
    response.setBody('Bad Gateway');

    BWM_ApiResponse parsed = BWM_ApiResponse.parse(response, '202');

    System.assertEquals('Bad Gateway', parsed.message);
    System.assertEquals(false, parsed.isSuccess);
  }

  @IsTest
  static void apiResponseParseMarksSuccessWhenCodeMatches() {
    HttpResponse response = new HttpResponse();
    response.setStatusCode(200);
    response.setBody('{"code":"202","message":"Accepted"}');

    BWM_ApiResponse parsed = BWM_ApiResponse.parse(response, '202');

    System.assertEquals('202', parsed.code);
    System.assertEquals('Accepted', parsed.message);
    System.assertEquals(true, parsed.isSuccess);
    System.assertEquals('{"code":"202","message":"Accepted"}', parsed.rawBody);
  }

  @IsTest
  static void templateResolverRejectsBlankTriggerPoint() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Steel Pipes',
      '9876543290'
    );

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      '',
      BWM_RecordQueryService.queryLead(leadRecord.Id)
    );

    System.assertEquals(false, result.shouldSend);
    System.assert(result.skipReason.contains('Trigger point'));
  }

  @IsTest
  static void templateResolverRejectsOpportunityWrongStageForQualify() {
    Opportunity opportunityRecord = new Opportunity(
      Name = 'Resolver Test',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_OPPORTUNITY_QUALIFY_NURTURE,
      BWM_RecordQueryService.queryOpportunity(opportunityRecord.Id)
    );

    System.assertEquals(false, result.shouldSend);
    System.assert(result.skipReason.contains('Nurture'));
  }

  @IsTest
  static void templateResolverAcceptsOpportunityQualifyNurture() {
    Opportunity opportunityRecord = new Opportunity(
      Name = 'Resolver Nurture',
      StageName = 'Nurture',
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_OPPORTUNITY_QUALIFY_NURTURE,
      BWM_RecordQueryService.queryOpportunity(opportunityRecord.Id)
    );

    System.assertEquals(true, result.shouldSend);
    System.assertNotEquals(null, result.mapping);
    System.assert(String.isNotBlank(result.mapping.Journey_Name__c));
  }

  @IsTest
  static void templateResolverRejectsReferToDealerWithoutDealerAccount() {
    Opportunity opportunityRecord = new Opportunity(
      Name = 'Resolver Dealer',
      StageName = 'Prospecting',
      Customer_Journey__c = BWM_MessagingConstants.CUSTOMER_JOURNEY_REFER_DEALER,
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_OPPORTUNITY_REFER_TO_DEALER,
      BWM_RecordQueryService.queryOpportunity(opportunityRecord.Id)
    );

    System.assertEquals(false, result.shouldSend);
    System.assert(result.skipReason.contains('Dealer account'));
  }

  @IsTest
  static void templateResolverRejectsLeadLostWithoutReason() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Steel Pipes',
      '9876543291'
    );

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_LOST_DETAILS_PROSPECT,
      BWM_RecordQueryService.queryLead(leadRecord.Id)
    );

    System.assertEquals(false, result.shouldSend);
    System.assert(result.skipReason.contains('Lost reason'));
  }

  @IsTest
  static void templateResolverRejectsStaleBatchWhenNotNegotiation() {
    Opportunity opportunityRecord = new Opportunity(
      Name = 'Stale Batch Opp',
      StageName = 'Nurture',
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_OPPORTUNITY_NEGOTIATION_STALE_30_DAYS,
      BWM_RecordQueryService.queryOpportunity(opportunityRecord.Id)
    );

    System.assertEquals(false, result.shouldSend);
    System.assert(result.skipReason.contains('Negotiation'));
  }

  @IsTest
  static void templateResolverRejectsStaleBatchWithoutSubStage() {
    Opportunity opportunityRecord = new Opportunity(
      Name = 'Stale Batch Opp',
      StageName = 'Negotiation',
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_OPPORTUNITY_NEGOTIATION_STALE_30_DAYS,
      BWM_RecordQueryService.queryOpportunity(opportunityRecord.Id)
    );

    System.assertEquals(false, result.shouldSend);
    System.assert(result.skipReason.contains('Sub Stage'));
  }

  @IsTest
  static void templateResolverRejectsNullRecord() {
    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT,
      null
    );

    System.assertEquals(false, result.shouldSend);
    System.assert(result.skipReason.contains('null'));
  }

  @IsTest
  static void templateResolverRejectsProspectingCallbackForProspectLead() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Steel Pipes',
      '9876543292'
    );

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECTING,
      BWM_RecordQueryService.queryLead(leadRecord.Id)
    );

    System.assertEquals(false, result.shouldSend);
    System.assert(result.skipReason.contains('Prospecting'));
  }

  @IsTest
  static void templateResolverAcceptsStaleBatchWithActiveSubStage() {
    Opportunity opportunityRecord = new Opportunity(
      Name = 'Stale Active Opp',
      StageName = 'Negotiation',
      Sub_Stage__c = BWM_MessagingConstants.SUB_STAGE_ACTIVE,
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_OPPORTUNITY_NEGOTIATION_STALE_30_DAYS,
      BWM_RecordQueryService.queryOpportunity(opportunityRecord.Id)
    );

    System.assertEquals(true, result.shouldSend);
    System.assertEquals('neg_stage_update', result.mapping.Journey_Name__c);
  }

  @IsTest
  static void negotiationBatchEnqueuesStaleNegotiationOpportunities() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Account accountRecord = new Account(
      Name = 'Batch Test ' + String.valueOf(DateTime.now().getTime()),
      Phone = '6290459120'
    );
    insert accountRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Stale Negotiation Opp',
      AccountId = accountRecord.Id,
      StageName = BWM_MessagingConstants.STAGE_NEGOTIATION,
      Sub_Stage__c = BWM_MessagingConstants.SUB_STAGE_ACTIVE,
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    Test.startTest();
    new BWM_NegotiationStageUpdateBatch().execute(
      null,
      new List<Opportunity>{ opportunityRecord }
    );
    new BWM_NegotiationStageUpdateBatch().execute(null);
    Test.stopTest();

    List<Message_Log__c> logs = [
      SELECT Template_Name__c
      FROM Message_Log__c
      WHERE
        Opportunity__c = :opportunityRecord.Id
        AND Trigger_Point__c = :BWM_MessagingConstants.TRIGGER_OPPORTUNITY_NEGOTIATION_STALE_30_DAYS
    ];
    System.assertEquals(1, logs.size());
    System.assertEquals('u_neg_stge_update', logs[0].Template_Name__c);
  }

  @IsTest
  static void negotiationBatchSkipsNonActiveSubStage() {
    Opportunity opportunityRecord = new Opportunity(
      Name = 'Inactive Sub Stage Opp',
      StageName = BWM_MessagingConstants.STAGE_NEGOTIATION,
      Sub_Stage__c = null,
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    Test.startTest();
    new BWM_NegotiationStageUpdateBatch().execute(
      null,
      new List<Opportunity>{ opportunityRecord }
    );
    Test.stopTest();

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Message_Log__c
        WHERE Opportunity__c = :opportunityRecord.Id
      ]
    );
  }

  @IsTest
  static void quoteExpiryFieldResolverMapsContactDateAndLink() {
    Account accountRecord = new Account(Name = 'Resolver Account');
    insert accountRecord;

    Contact contactRecord = new Contact(
      LastName = 'Mehta',
      FirstName = 'Priya',
      AccountId = accountRecord.Id
    );
    insert contactRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Resolver Quote Opp',
      AccountId = accountRecord.Id,
      ContactId = contactRecord.Id,
      StageName = BWM_MessagingConstants.STAGE_NURTURE,
      CloseDate = Date.today().addDays(30),
      Quotation_Date__c = Date.newInstance(2026, 8, 15)
    );
    insert opportunityRecord;
    opportunityRecord = BWM_RecordQueryService.queryOpportunity(opportunityRecord.Id);

    System.assertEquals(
      Date.newInstance(2026, 8, 15).format(),
      BWM_FieldValueResolver.resolveRecord(opportunityRecord, 'Quotation_Date__c')
    );
    System.assert(
      String.isNotBlank(
        BWM_FieldValueResolver.resolveRecord(
          opportunityRecord,
          'Contact_Person_Name__c'
        )
      )
    );
    System.assert(
      BWM_FieldValueResolver.resolveRecord(
        opportunityRecord,
        BWM_MessagingConstants.FIELD_OPPORTUNITY_LINK
      ).contains(String.valueOf(opportunityRecord.Id))
    );
  }

  @IsTest
  static void quoteExpiryReminderResolverRequiresQuotationDate() {
    Opportunity opportunityRecord = new Opportunity(
      Name = 'Quote Expiry Missing Date',
      StageName = BWM_MessagingConstants.STAGE_NURTURE,
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    BWM_TemplateResolver.ResolveResult resolveResult = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_OPPORTUNITY_QUOTE_EXPIRY_REMINDER,
      opportunityRecord
    );

    System.assertEquals(false, resolveResult.shouldSend);
    System.assert(resolveResult.skipReason.contains('Quotation Date'));
  }

  @IsTest
  static void quoteExpiryReminderBatchEnqueuesForMatchingOpportunity() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    User ownerUser = [
      SELECT Id, Phone, MobilePhone
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    String originalPhone = ownerUser.Phone;
    String originalMobile = ownerUser.MobilePhone;
    ownerUser.Phone = null;
    ownerUser.MobilePhone = '6290459144';
    update ownerUser;

    Account accountRecord = new Account(
      Name = 'Quote Expiry Account',
      Phone = '6290459145'
    );
    insert accountRecord;

    Contact contactRecord = new Contact(
      LastName = 'Kumar',
      FirstName = 'Rajesh',
      AccountId = accountRecord.Id
    );
    insert contactRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Quote Expiry Opp',
      AccountId = accountRecord.Id,
      ContactId = contactRecord.Id,
      StageName = BWM_MessagingConstants.STAGE_NURTURE,
      CloseDate = Date.today().addDays(30),
      Quotation_Date__c = System.today().addDays(1)
    );
    insert opportunityRecord;

    Test.startTest();
    new BWM_QuoteExpiryReminderBatch().execute(
      null,
      new List<Opportunity>{ opportunityRecord }
    );
    new BWM_QuoteExpiryReminderBatch().execute(null);
    Test.stopTest();

    List<Message_Log__c> logs = [
      SELECT Template_Name__c, Trigger_Point__c, Phone_Number__c
      FROM Message_Log__c
      WHERE
        Opportunity__c = :opportunityRecord.Id
        AND Trigger_Point__c = :BWM_MessagingConstants.TRIGGER_OPPORTUNITY_QUOTE_EXPIRY_REMINDER
    ];
    System.assertEquals(1, logs.size());
    System.assertEquals('u_quote_exp_reminder', logs[0].Template_Name__c);

    ownerUser.Phone = originalPhone;
    ownerUser.MobilePhone = originalMobile;
    update ownerUser;
  }

  @IsTest
  static void quoteExpiryReminderPayloadMapsOwnerContactDateAndLink() {
    Account accountRecord = new Account(Name = 'Payload Account');
    insert accountRecord;

    Contact contactRecord = new Contact(
      LastName = 'Sharma',
      FirstName = 'Anita',
      AccountId = accountRecord.Id
    );
    insert contactRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Payload Opp',
      AccountId = accountRecord.Id,
      ContactId = contactRecord.Id,
      StageName = BWM_MessagingConstants.STAGE_NURTURE,
      CloseDate = Date.today().addDays(30),
      Quotation_Date__c = Date.newInstance(2026, 7, 27)
    );
    insert opportunityRecord;

    opportunityRecord = BWM_RecordQueryService.queryOpportunity(opportunityRecord.Id);

    BWM_Template_Mapping__mdt mapping = new BWM_Template_Mapping__mdt(
      Journey_Name__c = 'quote_exp_reminder',
      WhatsApp_Template_Name__c = 'u_quote_exp_reminder',
      RCS_Template_Name__c = 'quote_exp_reminder',
      Param1_Field__c = 'Owner.Name',
      Param2_Field__c = 'Contact_Person_Name__c',
      Param3_Field__c = 'Quotation_Date__c',
      Param4_Field__c = BWM_MessagingConstants.FIELD_OPPORTUNITY_LINK,
      RCS_SMS_Param_Limit__c = 4,
      Include_Brochure_Header__c = false
    );

    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    String payload = BWM_MessagePayloadBuilder.buildJourneyPayloadForRecord(
      settings,
      mapping,
      opportunityRecord,
      '917980828320'
    );

    System.assert(payload.contains('quote_exp_reminder'));
    System.assert(payload.contains('u_quote_exp_reminder'));
    System.assert(payload.contains('Anita Sharma'));
    System.assert(payload.contains('/lightning/r/Opportunity/'));
    System.assert(!payload.contains('"SMS"'));
  }

  @IsTest
  static void opportunityHandlerEnqueuesQualifyReferAndLostReason() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Account dealerAccount = new Account(
      Name = 'Dealer Account',
      Phone = '6290459130'
    );
    insert dealerAccount;

    Account accountRecord = new Account(
      Name = 'Opp Handler ' + String.valueOf(DateTime.now().getTime()),
      Phone = '6290459131'
    );
    insert accountRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Handler Nurture Opp',
      AccountId = accountRecord.Id,
      StageName = BWM_MessagingConstants.STAGE_NURTURE,
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    Test.startTest();
    BWM_OpportunityMessagingTriggerHandler.handleAfterInsert(
      new List<Opportunity>{ opportunityRecord }
    );

    Opportunity oldRecord = opportunityRecord.clone(true, true, true, true);
    opportunityRecord = [
      SELECT
        Id,
        StageName,
        Lost_Reason__c,
        Customer_Journey__c,
        DealerAccount__c
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    oldRecord.Lost_Reason__c = null;
    oldRecord.Customer_Journey__c = null;
    opportunityRecord.Lost_Reason__c = 'Customer details not received';
    opportunityRecord.Customer_Journey__c = BWM_MessagingConstants.CUSTOMER_JOURNEY_REFER_DEALER;
    opportunityRecord.DealerAccount__c = dealerAccount.Id;

    BWM_OpportunityMessagingTriggerHandler.handleAfterUpdate(
      new List<Opportunity>{ opportunityRecord },
      new Map<Id, Opportunity>{ opportunityRecord.Id => oldRecord }
    );
    Test.stopTest();

    System.assert(
      [
          SELECT COUNT()
          FROM Message_Log__c
          WHERE Opportunity__c = :opportunityRecord.Id
        ] >= 1
    );
  }

  @IsTest
  static void fieldValueResolverResolvesOpportunityAndDealerFields() {
    Account accountRecord = new Account(
      Name = 'Customer Co',
      Phone = '6290459132'
    );
    insert accountRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Resolver Opp',
      AccountId = accountRecord.Id,
      StageName = BWM_MessagingConstants.STAGE_NURTURE,
      Email__c = 'customer@valid-domain.com',
      Phone__c = '6290459131',
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    opportunityRecord = [
      SELECT
        Id,
        Name,
        Email__c,
        Phone__c,
        Owner.Name,
        Owner.Email,
        Owner.Phone,
        Account.Name
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    opportunityRecord.putSObject(
      'DealerAccount__r',
      new Account(Name = 'Dealer Co', Phone = '6290459130')
    );

    System.assertEquals('', BWM_FieldValueResolver.resolveRecord(null, 'Name'));
    System.assertEquals('', BWM_FieldValueResolver.resolveRecord(opportunityRecord, ''));
    System.assertEquals(
      '6290459130',
      BWM_FieldValueResolver.resolveRecord(
        opportunityRecord,
        'DealerAccount__r.Phone'
      )
    );
    System.assertEquals(
      'Dealer Co',
      BWM_FieldValueResolver.resolveRecord(
        opportunityRecord,
        'DealerAccount__r.Name'
      )
    );
    System.assertEquals(
      'customer@valid-domain.com',
      BWM_FieldValueResolver.resolveRecord(opportunityRecord, 'Email')
    );
    System.assertEquals(
      '6290459131',
      BWM_FieldValueResolver.resolveRecord(opportunityRecord, 'Phone')
    );
    System.assertEquals(
      'Customer Co',
      BWM_FieldValueResolver.resolveRecord(opportunityRecord, 'Account.Name')
    );
    System.assertEquals(
      '',
      BWM_FieldValueResolver.resolveRecord(opportunityRecord, 'FirstName')
    );
    System.assertEquals(
      '',
      BWM_FieldValueResolver.resolveRecord(opportunityRecord, 'LastName')
    );
    System.assert(
      String.isNotBlank(
        BWM_FieldValueResolver.resolveRecord(opportunityRecord, 'Owner.Name')
      )
    );
    System.assert(
      String.isNotBlank(
        BWM_FieldValueResolver.resolveRecord(opportunityRecord, 'Owner.Email')
      )
    );
    System.assert(
      String.isNotBlank(
        BWM_FieldValueResolver.resolveRecord(
          opportunityRecord,
          BWM_MessagingConstants.FIELD_OPPORTUNITY_LINK
        )
      )
    );
    System.assert(
      BWM_FieldValueResolver.resolveRecord(
        opportunityRecord,
        BWM_MessagingConstants.FIELD_OPPORTUNITY_LINK
      ).contains('/lightning/r/Opportunity/')
    );

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'HDPE',
      '6290459133'
    );
    leadRecord = [
      SELECT
        Id,
        FirstName,
        LastName,
        Company,
        Company_Name__c,
        Department_Name__c,
        Product_Category__c,
        Owner.Name,
        Owner.Email,
        Owner.Phone,
        Email
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];

    System.assertEquals(
      'HDPE',
      BWM_FieldValueResolver.resolveDepartmentName(leadRecord)
    );
    System.assertEquals(
      null,
      BWM_FieldValueResolver.resolveDepartmentName(null)
    );
    System.assertEquals(
      '',
      BWM_FieldValueResolver.resolveRecord(leadRecord, 'Owner.Phone')
    );

    BWM_Template_Mapping__mdt mapping = [
      SELECT
        Param1_Field__c,
        Param2_Field__c,
        Param3_Field__c,
        Param4_Field__c,
        Param5_Field__c,
        Param6_Field__c,
        Param7_Field__c,
        Param8_Field__c
      FROM BWM_Template_Mapping__mdt
      WHERE DeveloperName = 'Prospect_Dept_Inbound_Email'
      LIMIT 1
    ];
    leadRecord.Email = 'bad@example.com';
    List<String> params = BWM_FieldValueResolver.resolveParamsForRecord(
      leadRecord,
      mapping
    );
    System.assertNotEquals('NA', params[6], 'Param7 email should never remain NA after fallback.');
  }

  @IsTest
  static void opportunitySendUsesLeadPhoneBeforeOpportunityPhone() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Steel Pipes',
      '9876543888'
    );

    Account accountRecord = new Account(
      Name = 'Lead Phone Opp ' + String.valueOf(DateTime.now().getTime()),
      Phone = '6290459140'
    );
    insert accountRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Lead Phone Opp',
      AccountId = accountRecord.Id,
      Lead__c = leadRecord.Id,
      StageName = BWM_MessagingConstants.STAGE_NURTURE,
      Phone__c = '6290459141',
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    Test.startTest();
    BWM_MessagingService.SendResult result = BWM_MessagingService.send(
      opportunityRecord.Id,
      BWM_MessagingConstants.TRIGGER_OPPORTUNITY_QUALIFY_NURTURE
    );
    Test.stopTest();

    System.assertEquals(true, result.sent);
    System.assertEquals(1, result.logs.size());
    System.assertEquals(
      '919876543888',
      result.logs[0].Phone_Number__c,
      'Customer phone should come from related Lead, not Opportunity Phone__c.'
    );
  }

  @IsTest
  static void sendTaskMessageInvocableQueuesCallback() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Steel Pipes',
      '9876543299'
    );

    BWM_SendTaskMessageInvocable.Request requestItem = new BWM_SendTaskMessageInvocable.Request();
    requestItem.recordId = leadRecord.Id;
    requestItem.taskAction = 'Callback';
    requestItem.stageAtAction = 'Prospect';

    Test.startTest();
    List<BWM_SendTaskMessageInvocable.Response> responses = BWM_SendTaskMessageInvocable.sendTaskMessage(
      new List<BWM_SendTaskMessageInvocable.Request>{ requestItem }
    );
    Test.stopTest();

    System.assertEquals(true, responses[0].queued);
    System.assertEquals(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT,
      responses[0].message
    );
  }

  @IsTest
  static void sendTaskMessageInvocableQueuesOpportunityNurtureCallback() {
    Account accountRecord = new Account(
      Name = 'Nurture Callback Account',
      Phone = '6290459150'
    );
    insert accountRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Nurture Callback Opp',
      AccountId = accountRecord.Id,
      StageName = BWM_MessagingConstants.STAGE_NURTURE,
      Department_Name__c = 'Enquiry',
      Phone__c = '6290459151',
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    BWM_SendTaskMessageInvocable.Request requestItem = new BWM_SendTaskMessageInvocable.Request();
    requestItem.recordId = opportunityRecord.Id;
    requestItem.taskAction = 'Callback';
    requestItem.stageAtAction = BWM_MessagingConstants.STAGE_NURTURE;

    Test.startTest();
    List<BWM_SendTaskMessageInvocable.Response> responses = BWM_SendTaskMessageInvocable.sendTaskMessage(
      new List<BWM_SendTaskMessageInvocable.Request>{ requestItem }
    );
    Test.stopTest();

    System.assertEquals(true, responses[0].queued);
    System.assertEquals(
      BWM_MessagingConstants.TRIGGER_OPPORTUNITY_TASK_CALLBACK_NURTURE,
      responses[0].message
    );
  }

  @IsTest
  static void opportunityTaskCallbackNurtureResolverMatchesAllDepartments() {
    Account accountRecord = new Account(Name = 'Resolver Account');
    insert accountRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Resolver Nurture Opp',
      AccountId = accountRecord.Id,
      StageName = BWM_MessagingConstants.STAGE_NURTURE,
      Department_Name__c = 'Steel Pipes',
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    BWM_TemplateResolver.ResolveResult resolveResult = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_OPPORTUNITY_TASK_CALLBACK_NURTURE,
      opportunityRecord,
      BWM_MessagingConstants.STAGE_NURTURE
    );

    System.assertEquals(true, resolveResult.shouldSend);
    System.assertEquals(
      'nurture_not_responding_cont',
      resolveResult.mapping.Journey_Name__c
    );
    System.assertEquals(
      'Nurture_not_responding_cont',
      resolveResult.mapping.SMS_Template_Name__c
    );
  }

  @IsTest
  static void opportunityTaskCallbackNurtureSendBuildsJourneyPayload() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Account accountRecord = new Account(
      Name = 'Payload Nurture Account',
      Phone = '6290459152'
    );
    insert accountRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Payload Nurture Opp',
      AccountId = accountRecord.Id,
      StageName = BWM_MessagingConstants.STAGE_NURTURE,
      Department_Name__c = 'HDPE',
      Phone__c = '6290459153',
      CloseDate = Date.today().addDays(30)
    );
    insert opportunityRecord;

    BWM_SendTaskMessageInvocable.Request requestItem = new BWM_SendTaskMessageInvocable.Request();
    requestItem.recordId = opportunityRecord.Id;
    requestItem.taskAction = 'Callback';
    requestItem.stageAtAction = BWM_MessagingConstants.STAGE_NURTURE;

    Test.startTest();
    BWM_SendTaskMessageInvocable.sendTaskMessage(
      new List<BWM_SendTaskMessageInvocable.Request>{ requestItem }
    );
    Test.stopTest();

    List<Message_Log__c> logs = [
      SELECT Template_Name__c, Trigger_Point__c
      FROM Message_Log__c
      WHERE
        Opportunity__c = :opportunityRecord.Id
        AND Trigger_Point__c = :BWM_MessagingConstants.TRIGGER_OPPORTUNITY_TASK_CALLBACK_NURTURE
    ];
    System.assertEquals(1, logs.size());
    System.assertEquals('u_nurt_not_resp', logs[0].Template_Name__c);
  }

  @IsTest
  static void sendTaskMessageInvocableQueuesLostDetails() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospecting',
      'HDPE',
      '9876543298'
    );

    BWM_SendTaskMessageInvocable.Request requestItem = new BWM_SendTaskMessageInvocable.Request();
    requestItem.recordId = leadRecord.Id;
    requestItem.taskAction = 'Lost';
    requestItem.stageAtAction = 'Prospecting';
    requestItem.lostReason = 'Customer details not received';

    Test.startTest();
    List<BWM_SendTaskMessageInvocable.Response> responses = BWM_SendTaskMessageInvocable.sendTaskMessage(
      new List<BWM_SendTaskMessageInvocable.Request>{ requestItem }
    );
    Test.stopTest();

    System.assertEquals(true, responses[0].queued);
    System.assertEquals(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_LOST_DETAILS_PROSPECTING,
      responses[0].message
    );
  }

  @IsTest
  static void sendTaskMessageInvocableSkipsUnsupportedAction() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Steel Pipes',
      '9876543297'
    );

    BWM_SendTaskMessageInvocable.Request requestItem = new BWM_SendTaskMessageInvocable.Request();
    requestItem.recordId = leadRecord.Id;
    requestItem.taskAction = 'Unknown';

    List<BWM_SendTaskMessageInvocable.Response> responses = BWM_SendTaskMessageInvocable.sendTaskMessage(
      new List<BWM_SendTaskMessageInvocable.Request>{ requestItem }
    );

    System.assertEquals(false, responses[0].queued);
  }

  @IsTest
  static void messagingDispatchesWhenQueueableLimitReached() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Crash Barrier',
      '9876543288'
    );
    leadRecord.Status = BWM_MessagingConstants.STAGE_PROSPECTING;
    update leadRecord;

    Test.startTest();
    BWM_EmailEnqueueService.enqueue(
      leadRecord.Id,
      BWM_EmailConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT
    );
    BWM_SendTaskMessageInvocable.Request requestItem = new BWM_SendTaskMessageInvocable.Request();
    requestItem.recordId = leadRecord.Id;
    requestItem.taskAction = 'Callback';
    requestItem.stageAtAction = BWM_MessagingConstants.STAGE_PROSPECT;
    BWM_SendTaskMessageInvocable.sendTaskMessage(
      new List<BWM_SendTaskMessageInvocable.Request>{ requestItem }
    );
    Test.stopTest();

    List<Message_Log__c> logs = [
      SELECT Template_Name__c
      FROM Message_Log__c
      WHERE
        Lead__c = :leadRecord.Id
        AND Trigger_Point__c = :BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT
    ];
    System.assertEquals(
      1,
      logs.size(),
      'Messaging should still send after email uses the queueable slot.'
    );
    System.assertEquals('prospect_not_responding_dept', logs[0].Template_Name__c);
  }

  @IsTest
  static void callbackProspectPayloadUsesDetailsNotReceivedTemplate() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Steel Pipes',
      '9876543287'
    );
    leadRecord = BWM_RecordQueryService.queryLead(leadRecord.Id);

    BWM_TemplateResolver.ResolveResult resolved = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT,
      leadRecord
    );
    String payload = BWM_MessagePayloadBuilder.buildJourneyPayloadForRecord(
      BWM_SettingsService.getSettings(),
      resolved.mapping,
      leadRecord,
      '917980828320'
    );

    System.assert(payload.contains('"journeyname":"prospect_not_responding_dept"'));
    System.assert(payload.contains('"templateName":"prospect_not_responding_dept"'));
    System.assert(payload.contains('"templateName":"Prosp_nt_resp_dept"'));
    System.assert(payload.contains('"templateName":"Prospect_not_resp"'));
    System.assert(payload.contains('"headerFormat":"DOCUMENT"'));
  }

  @IsTest
  static void messagingFutureDispatcherProcessesRequests() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Crash Barrier',
      '9876543289'
    );

    Test.startTest();
    BWM_MessagingFutureDispatcher.dispatch(
      new List<BWM_MessagingRequest>{
        new BWM_MessagingRequest(
          leadRecord.Id,
          BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT
        )
      }
    );
    Test.stopTest();

    List<Message_Log__c> logs = [
      SELECT Template_Name__c
      FROM Message_Log__c
      WHERE
        Lead__c = :leadRecord.Id
        AND Trigger_Point__c = :BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT
    ];
    System.assertEquals(1, logs.size());
    System.assertEquals('prospect_not_responding_dept', logs[0].Template_Name__c);
  }

  @IsTest
  static void callbackProspectSendsAfterLeadMovesToProspecting() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Crash Barrier',
      '9876543210'
    );
    leadRecord.Status = BWM_MessagingConstants.STAGE_PROSPECTING;
    update leadRecord;

    Test.startTest();
    BWM_MessagingService.SendResult result = BWM_MessagingService.send(
      leadRecord.Id,
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT,
      BWM_MessagingConstants.STAGE_PROSPECT
    );
    Test.stopTest();

    System.assertEquals(true, result.sent);
    System.assertEquals('prospect_not_responding_dept', result.logs[0].Template_Name__c);
  }

  @IsTest
  static void sendTaskMessageInvocableQueuesProspectLostDetails() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Polymer',
      '9876543296'
    );

    BWM_SendTaskMessageInvocable.Request requestItem = new BWM_SendTaskMessageInvocable.Request();
    requestItem.recordId = leadRecord.Id;
    requestItem.taskAction = 'Lost';
    requestItem.stageAtAction = 'Lost';
    requestItem.lostReason = 'Customer Details Not Received';

    List<BWM_SendTaskMessageInvocable.Response> responses = BWM_SendTaskMessageInvocable.sendTaskMessage(
      new List<BWM_SendTaskMessageInvocable.Request>{ requestItem }
    );

    System.assertEquals(true, responses[0].queued);
    System.assertEquals(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_LOST_DETAILS_PROSPECT,
      responses[0].message
    );
  }

  @IsTest
  static void callbackProspectResolvesGenJourneyWhenOwnerMatchesCrmUser() {
    Lead leadRecord = buildLeadForOwnerCrmMatch(
      'Prospect',
      'Crash Barrier',
      'Owner Match Lead'
    );

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT,
      leadRecord
    );

    System.assertEquals(true, result.shouldSend);
    System.assertEquals(
      'prospect_not_responding_gen',
      result.mapping.Journey_Name__c
    );
  }

  @IsTest
  static void callbackProspectResolvesDeptJourneyWhenOwnerDoesNotMatchCrmUser() {
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Status":"Prospect","Department_Name__c":"Crash Barrier","CRM_User_Name_Formula__c":"CRM User","Owner":{"attributes":{"type":"User"},"Name":"Different Owner"}}',
      Lead.class
    );

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT,
      leadRecord
    );

    System.assertEquals(true, result.shouldSend);
    System.assertEquals(
      'prospect_not_responding_dept',
      result.mapping.Journey_Name__c
    );
  }

  @IsTest
  static void callbackProspectResolvesGenJourneyForEnquiryDepartment() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Enquiry',
      '9876543405'
    );

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT,
      BWM_RecordQueryService.queryLead(leadRecord.Id)
    );

    System.assertEquals(true, result.shouldSend);
    System.assertEquals('prospect_not_responding_gen', result.mapping.Journey_Name__c);
  }

  @IsTest
  static void callbackProspectResolvesGenJourneyForTowerDepartment() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'Transmission & Telecom Tower',
      '9876543401'
    );

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECT,
      BWM_RecordQueryService.queryLead(leadRecord.Id)
    );

    System.assertEquals(true, result.shouldSend);
    System.assertEquals('prospect_not_responding_gen', result.mapping.Journey_Name__c);
    System.assertEquals(
      'https://portal.bluewavesmedia.in/WhatsAppMedia/Template/Document/Utkarsh/corporate_brochure_2026.pdf',
      result.mapping.Document_Header_URL__c
    );
  }

  @IsTest
  static void callbackProspectingResolvesGenJourneyWhenOwnerMatchesCrmUser() {
    Lead leadRecord = buildLeadForOwnerCrmMatch(
      'Prospecting',
      'Crash Barrier',
      'Owner Match Lead'
    );

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECTING,
      leadRecord
    );

    System.assertEquals(true, result.shouldSend);
    System.assertEquals(
      'prospecting_not_responding_gen',
      result.mapping.Journey_Name__c
    );
  }

  @IsTest
  static void callbackProspectingResolvesDeptJourneyWhenOwnerDoesNotMatchCrmUser() {
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Status":"Prospecting","Department_Name__c":"Crash Barrier","CRM_User_Name_Formula__c":"CRM User","Owner":{"attributes":{"type":"User"},"Name":"Different Owner"}}',
      Lead.class
    );

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECTING,
      leadRecord
    );

    System.assertEquals(true, result.shouldSend);
    System.assertEquals(
      'prospecting_not_responding_dept',
      result.mapping.Journey_Name__c
    );
  }

  @IsTest
  static void callbackProspectingResolvesDeptJourneyForProductDepartment() {
    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospecting',
      'Crash Barrier',
      '9876543402'
    );

    BWM_TemplateResolver.ResolveResult result = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_CALLBACK_PROSPECTING,
      BWM_RecordQueryService.queryLead(leadRecord.Id)
    );

    System.assertEquals(true, result.shouldSend);
    System.assertEquals(
      'prospecting_not_responding_dept',
      result.mapping.Journey_Name__c
    );
  }

  @IsTest
  static void lostNotRespondingProspectingRoutesDeptAndGen() {
    Lead deptLead = createLead(
      'INBOUND EMAIL',
      'Prospecting',
      'HDPE',
      '9876543403'
    );
    Lead genLead = createLead(
      'INBOUND EMAIL',
      'Prospecting',
      'Pre Engineering Building',
      '9876543404'
    );

    BWM_SendTaskMessageInvocable.Request deptRequest = new BWM_SendTaskMessageInvocable.Request();
    deptRequest.recordId = deptLead.Id;
    deptRequest.taskAction = 'Lost';
    deptRequest.stageAtAction = 'Prospecting';
    deptRequest.lostReason = 'Not responding';

    BWM_SendTaskMessageInvocable.Request genRequest = new BWM_SendTaskMessageInvocable.Request();
    genRequest.recordId = genLead.Id;
    genRequest.taskAction = 'Lost';
    genRequest.stageAtAction = 'Prospecting';
    genRequest.lostReason = 'Not responding';

    List<BWM_SendTaskMessageInvocable.Response> responses = BWM_SendTaskMessageInvocable.sendTaskMessage(
      new List<BWM_SendTaskMessageInvocable.Request>{ deptRequest, genRequest }
    );

    System.assertEquals(true, responses[0].queued);
    System.assertEquals(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_LOST_NOT_RESPONDING_PROSPECTING,
      responses[0].message
    );
    System.assertEquals(true, responses[1].queued);

    deptLead.Lost_Reason__c = 'Not responding';
    genLead.Lost_Reason__c = 'Not responding';

    BWM_TemplateResolver.ResolveResult deptResolved = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_LOST_NOT_RESPONDING_PROSPECTING,
      deptLead
    );
    BWM_TemplateResolver.ResolveResult genResolved = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_LOST_NOT_RESPONDING_PROSPECTING,
      genLead
    );

    System.assertEquals(
      'prospecting_not_responding_lost_dept',
      deptResolved.mapping.Journey_Name__c
    );
    System.assertEquals(
      'prospecting_not_resp_gen_lost',
      genResolved.mapping.Journey_Name__c
    );
  }

  @IsTest
  static void lostNotRespondingProspectingDeptUsesLeadCrmFormulaContact() {
    BWM_Template_Mapping__mdt deptMapping = [
      SELECT
        Param1_Field__c,
        Param2_Field__c,
        Param3_Field__c,
        Param4_Field__c,
        Param5_Field__c,
        Param6_Field__c
      FROM BWM_Template_Mapping__mdt
      WHERE DeveloperName = 'Lead_Task_Lost_NotResp_Prospecting'
      LIMIT 1
    ];

    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Department_Name__c":"Polymer","CRM_User_Name_Formula__c":"Provakar Roy","CRM_User_Contact_No_Formula__c":"8100996170","CRM_User_Email_Formula__c":"p.roy@utkarshindia.in","Owner":{"attributes":{"type":"User"},"Name":"Shubhrajyoti Dasgupta","Phone":"9000011111","Email":"owner@test.com"}}',
      Lead.class
    );

    List<String> params = BWM_FieldValueResolver.resolveParamsForRecord(
      leadRecord,
      deptMapping
    );

    System.assertEquals('Provakar Roy', params[3]);
    System.assertEquals('8100996170', params[4]);
    System.assertEquals('p.roy@utkarshindia.in', params[5]);
    System.assert(
      !params[3].contains('Rudra'),
      'CRM contact name must come from Lead formula, not corporate default.'
    );
  }

  @IsTest
  static void lostDetailsProspectingMapsOwnerContactToWhatsAppSlots() {
    BWM_Template_Mapping__mdt deptMapping = [
      SELECT
        Param1_Field__c,
        Param2_Field__c,
        Param3_Field__c,
        Param4_Field__c,
        Param5_Field__c,
        Param6_Field__c,
        Param7_Field__c,
        Param8_Field__c
      FROM BWM_Template_Mapping__mdt
      WHERE DeveloperName = 'Lead_Task_Lost_Details_Prospecting'
      LIMIT 1
    ];
    BWM_Template_Mapping__mdt genMapping = [
      SELECT
        Param1_Field__c,
        Param2_Field__c,
        Param3_Field__c,
        Param4_Field__c,
        Param5_Field__c,
        Param6_Field__c,
        Param7_Field__c,
        Param8_Field__c
      FROM BWM_Template_Mapping__mdt
      WHERE DeveloperName = 'Lead_Task_Lost_Details_Prospecting_Gen'
      LIMIT 1
    ];

    Lead leadRecord = (Lead) JSON.deserialize(
      '{"FirstName":"Customer","LastName":"LastOnly","Company":"Test Co","Company_Name__c":"Test Co","Department_Name__c":"HDPE","Owner":{"attributes":{"type":"User"},"Name":"","Phone":"9000099999","Email":"owner@test.com"}}',
      Lead.class
    );

    List<String> deptParams = BWM_FieldValueResolver.resolveParamsForRecord(
      leadRecord,
      deptMapping
    );
    List<String> genParams = BWM_FieldValueResolver.resolveParamsForRecord(
      leadRecord,
      genMapping
    );

    System.assertEquals(6, deptParams.size());
    System.assertEquals(3, genParams.size());
    System.assertNotEquals(
      'LastOnly',
      deptParams[0],
      'Owner name slot must not use customer LastName.'
    );
    System.assertNotEquals(
      'LastOnly',
      deptParams[1],
      'Owner phone slot must not use customer LastName.'
    );
    System.assertNotEquals(
      'Test Co',
      deptParams[1],
      'Owner phone slot must not use company name.'
    );
    System.assertEquals('9000099999', deptParams[1]);
    System.assertEquals('9000099999', genParams[1]);
  }

  @IsTest
  static void lostDetailsProspectingDeptUsesLeadCrmFormulaContact() {
    BWM_Template_Mapping__mdt deptMapping = [
      SELECT
        Param1_Field__c,
        Param2_Field__c,
        Param3_Field__c,
        Param4_Field__c,
        Param5_Field__c,
        Param6_Field__c
      FROM BWM_Template_Mapping__mdt
      WHERE DeveloperName = 'Lead_Task_Lost_Details_Prospecting'
      LIMIT 1
    ];

    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Department_Name__c":"Steel Pipes","CRM_User_Name_Formula__c":"Lala Ankita Roy","CRM_User_Contact_No_Formula__c":"9147769526","CRM_User_Email_Formula__c":"lalaankita.roy@utkarshindia.in","Owner":{"attributes":{"type":"User"},"Name":"Debmallya Banerjee","Phone":"9000022222","Email":"owner@test.com"}}',
      Lead.class
    );

    List<String> params = BWM_FieldValueResolver.resolveParamsForRecord(
      leadRecord,
      deptMapping
    );

    System.assertEquals('Lala Ankita Roy', params[3]);
    System.assertEquals('9147769526', params[4]);
    System.assertEquals('lalaankita.roy@utkarshindia.in', params[5]);
    System.assert(
      !params[3].contains('Rudra'),
      'OR contact must use Lead CRM formula, not corporate default.'
    );
  }

  @IsTest
  static void lostDetailsProspectingSplitsBrochureByDepartment() {
    Lead deptLead = new Lead(
      Status = 'Prospecting',
      Department_Name__c = 'Steel Tubular Poles',
      Lost_Reason__c = 'Customer details not received'
    );
    Lead genLead = new Lead(
      Status = 'Prospecting',
      Department_Name__c = 'Railway Electrification Structure',
      Lost_Reason__c = 'Customer details not received'
    );

    BWM_TemplateResolver.ResolveResult deptResolved = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_LOST_DETAILS_PROSPECTING,
      deptLead
    );
    BWM_TemplateResolver.ResolveResult genResolved = BWM_TemplateResolver.resolve(
      BWM_MessagingConstants.TRIGGER_LEAD_TASK_LOST_DETAILS_PROSPECTING,
      genLead
    );

    System.assertEquals('u_prospecting_det_not_rec', deptResolved.mapping.Journey_Name__c);
    System.assertEquals('None', deptResolved.mapping.Brochure_Attachment_Mode__c);
    System.assertEquals(
      'prospecting_det_nt_rc_lost_gen',
      genResolved.mapping.Journey_Name__c
    );
    System.assertEquals('Corporate', genResolved.mapping.Brochure_Attachment_Mode__c);
  }

  @IsTest
  static void smsDirectPayloadUsesDirectSmsChannel() {
    BWM_SmsDirectPayloadBuilder.clearCache();
    BWM_JourneyDefinitionService.clearCache();
    BWM_SmsDirectPayloadBuilder.cacheTemplates(
      new List<Object>{
        new Map<String, Object>{
          'templateName' => 'DEALER_Enq_dept',
          'dltTemplateId' => '1007088206584852810',
          'templateText' =>
            'Dear Customer, please call us on {#numeric#} for more details about {#alphanumeric#}.'
        }
      }
    );

    Lead leadRecord = createLead(
      'INBOUND EMAIL',
      'Prospect',
      'High Mast & Polygonal',
      '9876543210'
    );
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();

    Test.startTest();
    String payload = BWM_SmsDirectPayloadBuilder.buildPayload(
      settings,
      'DEALER_Enq_dept',
      leadRecord,
      '919876543210'
    );
    Test.stopTest();

    Map<String, Object> payloadMap = (Map<String, Object>) JSON.deserializeUntyped(
      payload
    );
    Map<String, Object> content = (Map<String, Object>) payloadMap.get('content');
    Map<String, Object> data = (Map<String, Object>) content.get('data');
    Map<String, Object> params = (Map<String, Object>) content.get('params');

    System.assertEquals('SMS', payloadMap.get('channel'));
    System.assertEquals('919876543210', ((List<Object>) payloadMap.get('to'))[0]);
    System.assertEquals('UTKRSI', payloadMap.get('from'));
    System.assertEquals('1007088206584852810', data.get('dlttemplateid'));
    System.assert(
      String.valueOf(data.get('text')).contains('{#numeric#}'),
      'Template text should be included in payload.'
    );
    System.assertEquals('1701159714233362956', data.get('peid'));
    System.assertEquals(
      '1701159714233362956,140200000077',
      data.get('chainvalue')
    );
    System.assert(!params.isEmpty(), 'SMS params should be populated.');
    System.assert(params.containsKey('var1'), 'SMS params should use var1 format.');
  }

  @IsTest
  static void leadCreateProductDepartmentsExcludeTowers() {
    Lead towerLead = new Lead(
      LeadSource = 'INBOUND EMAIL',
      Status = 'Prospect',
      Department_Name__c = 'Transmission & Telecom Tower'
    );
    Lead productLead = new Lead(
      LeadSource = 'INBOUND EMAIL',
      Status = 'Prospect',
      Department_Name__c = 'High Mast & Polygonal'
    );

    System.assertEquals(
      'prospect_enq_gen',
      BWM_TemplateResolver.resolveForLeadCreate(towerLead).mapping.Journey_Name__c
    );
    System.assertEquals(
      'prospect_enq_dept',
      BWM_TemplateResolver.resolveForLeadCreate(productLead).mapping.Journey_Name__c
    );
    System.assertEquals(
      'Department',
      BWM_TemplateResolver.resolveForLeadCreate(productLead)
        .mapping.Brochure_Attachment_Mode__c
    );
  }

  private static Lead createLead(
    String leadSource,
    String status,
    String department,
    String phone
  ) {
    return createLead(leadSource, status, department, phone, false);
  }

  private static Lead createLead(
    String leadSource,
    String status,
    String department,
    String phone,
    Boolean allowTriggerMessaging
  ) {
    if (!allowTriggerMessaging) {
      BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = true;
    }

    Lead leadRecord = new Lead(
      LastName = 'Messaging Test',
      Company = 'Test Co',
      Company_Name__c = 'Test Co',
      LeadSource = leadSource,
      Status = status,
      Department_Name__c = department,
      Phone = String.isBlank(phone) ? '6290459110' : phone,
      Email = 'test@example.com'
    );
    insert leadRecord;

    if (!allowTriggerMessaging) {
      BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = false;
    }

    return leadRecord;
  }

  @IsTest
  static void railwayBrochureUsesUploadedFilePublicLinkNotCorporate() {
    BWM_BrochureService.setBrochureMapForTest(
      new Map<String, BWM_Department_Brochure__mdt>{
        'Railway Electrification Structure' => new BWM_Department_Brochure__mdt(
          Department_Name__c = 'Railway Electrification Structure',
          Content_File_Title__c = 'Railway Electrification Structures',
          Brochure_File_Name__c = 'Railway_Electrification_Structures.pdf',
          Static_Resource_Name__c = 'Railway_Electrification_Structures_pdf',
          Brochure_URL__c = null
        )
      }
    );
    BWM_BrochureFileService.setPublicUrlMapForTest(
      new Map<String, String>{
        'Railway Electrification Structures' =>
          'https://momentum-customer-397--utkarshuat.sandbox.file.force.com/sfc/dist/version/download/?oid=00DC2000003CoP7&ids=068C20000053MXN&d=test&asPdf=false'
      }
    );

    BWM_BrochureService.BrochureInfo brochure = BWM_BrochureService.getBrochureForDepartment(
      'Railway Electrification Structure'
    );
    String resolved = BWM_BrochureService.resolveWhatsAppDocumentUrl(
      brochure,
      BWM_MessagingConstants.DEFAULT_PORTAL_BROCHURE_URL
    );

    System.assert(
      resolved.contains('file.force.com') &&
        resolved.contains('/sfc/dist/version/download/'),
      'Railway must use uploaded file public link.'
    );
    System.assert(
      !resolved.contains('corporate_brochure'),
      'Railway must not fall back to corporate brochure.'
    );
    BWM_BrochureService.clearCache();
  }

  @IsTest
  static void corporatePortalUrlIsSkippedWhenPublicStaticLinkExists() {
    BWM_BrochureService.BrochureInfo brochure = new BWM_BrochureService.BrochureInfo();
    brochure.brochureUrl = BWM_MessagingConstants.DEFAULT_PORTAL_BROCHURE_URL;
    brochure.fileName = 'Railway_Electrification_Structures.pdf';
    brochure.publicDownloadUrl =
      'https://example.file.force.com/sfc/dist/version/download/?oid=1&ids=2&d=3&asPdf=false';

    String resolved = BWM_BrochureService.resolveWhatsAppDocumentUrl(
      brochure,
      BWM_MessagingConstants.DEFAULT_PORTAL_BROCHURE_URL
    );
    System.assertEquals(
      brochure.publicDownloadUrl,
      resolved,
      'Corporate portal URL must yield to department static-resource public link.'
    );
  }

  private static Lead buildLeadForOwnerCrmMatch(
    String status,
    String departmentName,
    String ownerName
  ) {
    return (Lead) JSON.deserialize(
      '{"Status":"' +
        status +
        '","Department_Name__c":"' +
        departmentName +
        '","CRM_User_Name_Formula__c":"' +
        ownerName +
        '","Owner":{"attributes":{"type":"User"},"Name":"' +
        ownerName +
        '"}}',
      Lead.class
    );
  }
}