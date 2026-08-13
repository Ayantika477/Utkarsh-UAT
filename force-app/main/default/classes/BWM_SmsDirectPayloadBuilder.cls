public without sharing class BWM_SmsDirectPayloadBuilder {
  @TestVisible
  private static Map<String, Map<String, Object>> templateByName;

  public static void cacheTemplates(List<Object> templateRows) {
    templateByName = new Map<String, Map<String, Object>>();
    if (templateRows == null) {
      return;
    }

    for (Object templateObject : templateRows) {
      Map<String, Object> templateMap = (Map<String, Object>) templateObject;
      String templateName = readTemplateName(templateMap);
      if (String.isNotBlank(templateName)) {
        templateByName.put(normalizeName(templateName), templateMap);
      }
    }
  }

  public static String buildPayload(
    BWM_Messaging_Settings__mdt settings,
    String templateName,
    SObject record,
    String phoneNumber
  ) {
    ensureTemplateCacheLoaded(settings);

    String normalizedTemplateName = templateName == null ? '' : templateName.trim();
    if (String.isBlank(normalizedTemplateName)) {
      throw new BWM_MessagingException('SMS template name is required.');
    }

    Map<String, Object> templateMap = templateByName == null
      ? null
      : templateByName.get(normalizeName(normalizedTemplateName));
    if (templateMap == null) {
      throw new BWM_MessagingException(
        'SMS template not found: ' + normalizedTemplateName
      );
    }

    String dltTemplateId = readDltTemplateId(templateMap);
    String templateText = readTemplateText(templateMap);
    if (String.isBlank(dltTemplateId) || String.isBlank(templateText)) {
      throw new BWM_MessagingException(
        'SMS template metadata is incomplete for: ' + normalizedTemplateName
      );
    }

    String journeyName = BWM_JourneyDefinitionService.findJourneyNameBySmsTemplateName(
      normalizedTemplateName
    );
    BWM_Template_Mapping__mdt mapping =
      BWM_JourneyDefinitionService.findMappingBySmsTemplateName(
        normalizedTemplateName
      );
    Map<String, Object> variableMappings = resolveVariableMappings(
      settings,
      record,
      mapping,
      journeyName,
      normalizedTemplateName
    );

    String senderId = String.isNotBlank(settings == null ? null : settings.SMS_From__c)
      ? settings.SMS_From__c.trim()
      : 'UTKRSI';

    Map<String, Object> payload = new Map<String, Object>{
      'channel' => BWM_MessagingConstants.CHANNEL_SMS,
      'to' => new List<String>{ phoneNumber },
      'from' => senderId,
      'content' => new Map<String, Object>{
        'data' => new Map<String, Object>{
          'dlttemplateid' => dltTemplateId,
          'text' => templateText,
          'peid' => resolvePeid(settings),
          'chainvalue' => resolveChainValue(settings)
        },
        'params' => toVarParams(variableMappings)
      }
    };

    return JSON.serialize(payload);
  }

  private static Map<String, Object> toVarParams(
    Map<String, Object> variableMappings
  ) {
    Map<String, Object> params = new Map<String, Object>();
    if (variableMappings == null || variableMappings.isEmpty()) {
      return params;
    }

    for (String key : variableMappings.keySet()) {
      String paramKey = String.isNotBlank(key) && key.startsWith('var')
        ? key
        : 'var' + key;
      params.put(paramKey, variableMappings.get(key));
    }
    return params;
  }

  private static String resolvePeid(BWM_Messaging_Settings__mdt settings) {
    return DEFAULT_SMS_PEID;
  }

  private static String resolveChainValue(BWM_Messaging_Settings__mdt settings) {
    return DEFAULT_SMS_CHAIN_VALUE;
  }

  private static final String DEFAULT_SMS_PEID = '1701159714233362956';
  private static final String DEFAULT_SMS_CHAIN_VALUE =
    '1701159714233362956,140200000077';

  private static Map<String, Object> resolveVariableMappings(
    BWM_Messaging_Settings__mdt settings,
    SObject record,
    BWM_Template_Mapping__mdt mapping,
    String journeyName,
    String templateName
  ) {
    if (String.isNotBlank(journeyName)) {
      Map<String, Object> templateMappings =
        BWM_JourneyDefinitionService.getSmsVariableMappingsTemplate(journeyName);
      if (!templateMappings.isEmpty()) {
        Map<String, Object> resolvedMappings = (Map<String, Object>) BWM_JourneyPayloadResolver.resolveDataPayload(
          record,
          templateMappings,
          mapping
        );
        Map<String, Object> variableMappings = new Map<String, Object>();
        for (String key : resolvedMappings.keySet()) {
          Object rawValue = resolvedMappings.get(key);
          String value = rawValue == null ? '' : String.valueOf(rawValue).trim();
          if (String.isNotBlank(value)) {
            variableMappings.put(key, value);
          }
        }
        if (!variableMappings.isEmpty()) {
          return variableMappings;
        }
      }
    }

    Map<String, Object> templateMap = templateByName == null
      ? null
      : templateByName.get(normalizeName(templateName));
    return buildVariableMappingsFromTemplateText(settings, record, templateMap);
  }

  private static void ensureTemplateCacheLoaded(
    BWM_Messaging_Settings__mdt settings
  ) {
    if (templateByName != null && !templateByName.isEmpty()) {
      return;
    }

    if (settings == null || Test.isRunningTest()) {
      return;
    }

    HttpResponse response = BWM_SmsTemplateService.fetchTemplatesResponse(settings);
    if (response == null || response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
      return;
    }

    Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
      response.getBody()
    );
    cacheTemplates((List<Object>) responseBody.get('data'));
  }

  private static Map<String, Object> buildVariableMappingsFromTemplateText(
    BWM_Messaging_Settings__mdt settings,
    SObject record,
    Map<String, Object> templateMap
  ) {
    Map<String, Object> variableMappings = new Map<String, Object>();
    List<String> placeholderTypes = extractPlaceholderTypes(templateMap);
    if (placeholderTypes.isEmpty()) {
      return variableMappings;
    }

    List<String> values = buildVariableValues(
      settings,
      record,
      templateMap,
      placeholderTypes
    );
    for (Integer index = 0; index < placeholderTypes.size(); index++) {
      String value = index < values.size() ? values[index] : '';
      variableMappings.put(
        String.valueOf(index + 1),
        String.isNotBlank(value) ? value.trim() : 'NA'
      );
    }

    return variableMappings;
  }

  private static List<String> extractPlaceholderTypes(Map<String, Object> templateMap) {
    List<String> placeholderTypes = new List<String>();
    if (templateMap == null) {
      return placeholderTypes;
    }

    String templateText = readTemplateText(templateMap);
    if (String.isBlank(templateText)) {
      return placeholderTypes;
    }

    Matcher matcher = Pattern.compile('\\{#([^#]+)#\\}').matcher(templateText);
    while (matcher.find()) {
      placeholderTypes.add(matcher.group(1).trim().toLowerCase());
    }

    return placeholderTypes;
  }

  private static List<String> buildVariableValues(
    BWM_Messaging_Settings__mdt settings,
    SObject record,
    Map<String, Object> templateMap,
    List<String> placeholderTypes
  ) {
    List<String> values = new List<String>();
    String templateText = readTemplateText(templateMap);
    String departmentName = BWM_FieldValueResolver.resolveDepartmentName(record);
    String ownerName = BWM_FieldValueResolver.resolveRecord(record, 'Owner.Name');
    String ownerPhone = formatSmsPhoneValue(
      BWM_FieldValueResolver.resolveRecord(record, 'Owner.Phone'),
      settings
    );
    String recordName = BWM_FieldValueResolver.resolveRecord(record, 'Name');
    String supportPhoneOne = formatSmsPhoneValue(
      resolveCorporateSupportPhone(settings, 1),
      settings
    );
    String supportPhoneTwo = formatSmsPhoneValue(
      resolveCorporateSupportPhone(settings, 2),
      settings
    );
    String defaultSupportPhone = String.isNotBlank(supportPhoneOne)
      ? supportPhoneOne
      : formatSmsPhoneValue(settings.WhatsApp_From__c, settings);

    Integer phoneSlot = 0;
    for (String placeholderType : placeholderTypes) {
      if (placeholderType == 'numeric') {
        values.add(
          pickPhoneValue(
            phoneSlot == 0 ? defaultSupportPhone : supportPhoneTwo,
            ownerPhone,
            defaultSupportPhone
          )
        );
        phoneSlot++;
        continue;
      }

      if (placeholderType == 'alphanumeric') {
        if (looksLikePhoneSlot(templateText, values.size())) {
          values.add(
            pickPhoneValue(
              phoneSlot == 0 ? defaultSupportPhone : supportPhoneTwo,
              ownerPhone,
              defaultSupportPhone
            )
          );
          phoneSlot++;
        } else if (String.isNotBlank(departmentName)) {
          values.add(departmentName);
        } else if (String.isNotBlank(recordName)) {
          values.add(recordName);
        } else {
          values.add('NA');
        }
        continue;
      }

      if (placeholderType == 'var') {
        if (looksLikePhoneSlot(templateText, values.size())) {
          values.add(
            pickPhoneValue(
              phoneSlot == 0 ? defaultSupportPhone : supportPhoneTwo,
              ownerPhone,
              defaultSupportPhone
            )
          );
          phoneSlot++;
        } else if (String.isNotBlank(ownerName)) {
          values.add(ownerName);
        } else if (String.isNotBlank(departmentName)) {
          values.add(departmentName);
        } else {
          values.add('NA');
        }
        continue;
      }

      values.add('NA');
    }

    return values;
  }

  private static Boolean looksLikePhoneSlot(String templateText, Integer placeholderIndex) {
    if (String.isBlank(templateText)) {
      return false;
    }

    Matcher matcher = Pattern.compile('\\{#([^#]+)#\\}').matcher(templateText);
    Integer currentIndex = 0;
    while (matcher.find()) {
      if (currentIndex == placeholderIndex) {
        Integer start = Math.max(0, matcher.start() - 40);
        String context = templateText.substring(start, matcher.start()).toLowerCase();
        return context.contains('call') ||
          context.contains('contact') ||
          context.contains('phone') ||
          context.contains('reach') ||
          context.contains('connect');
      }
      currentIndex++;
    }

    return false;
  }

  private static String pickPhoneValue(
    String primaryPhone,
    String secondaryPhone,
    String fallbackPhone
  ) {
    if (String.isNotBlank(primaryPhone)) {
      return primaryPhone;
    }
    if (String.isNotBlank(secondaryPhone)) {
      return secondaryPhone;
    }
    return String.isNotBlank(fallbackPhone) ? fallbackPhone : 'NA';
  }

  private static String formatSmsPhoneValue(
    String rawPhone,
    BWM_Messaging_Settings__mdt settings
  ) {
    if (String.isBlank(rawPhone)) {
      return '';
    }

    String formattedPhone = BWM_PhoneFormatter.formatForMessaging(
      rawPhone,
      settings == null ? null : settings.Default_Country_Code__c
    );
    return String.isBlank(formattedPhone)
      ? rawPhone.trim()
      : formattedPhone.replaceAll('[^0-9]', '');
  }

  private static String resolveCorporateSupportPhone(
    BWM_Messaging_Settings__mdt settings,
    Integer slot
  ) {
    if (settings == null) {
      return null;
    }

    return slot == 1
      ? settings.Corporate_Support_Contact_1_Phone__c
      : settings.Corporate_Support_Contact_2_Phone__c;
  }

  private static String readTemplateName(Map<String, Object> templateMap) {
    Object templateName = templateMap.get('TemplateName');
    if (templateName == null || String.isBlank(String.valueOf(templateName))) {
      templateName = templateMap.get('templateName');
    }
    return templateName == null ? null : String.valueOf(templateName);
  }

  private static String readTemplateText(Map<String, Object> templateMap) {
    Object templateText = templateMap.get('templateText');
    if (templateText == null || String.isBlank(String.valueOf(templateText))) {
      templateText = templateMap.get('TemplateText');
    }
    if (templateText == null || String.isBlank(String.valueOf(templateText))) {
      templateText = templateMap.get('MessageText');
    }
    return templateText == null ? null : String.valueOf(templateText);
  }

  private static String readDltTemplateId(Map<String, Object> templateMap) {
    Object dltTemplateId = templateMap.get('dltTemplateId');
    if (dltTemplateId == null || String.isBlank(String.valueOf(dltTemplateId))) {
      dltTemplateId = templateMap.get('dlttemplateid');
    }
    if (dltTemplateId == null || String.isBlank(String.valueOf(dltTemplateId))) {
      dltTemplateId = templateMap.get('DltTemplateId');
    }
    return dltTemplateId == null ? null : String.valueOf(dltTemplateId);
  }

  private static String normalizeName(String value) {
    return String.isBlank(value) ? '' : value.trim().toLowerCase();
  }

  @TestVisible
  static void clearCache() {
    templateByName = null;
  }
}