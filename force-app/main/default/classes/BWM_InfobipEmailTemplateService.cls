public with sharing class BWM_InfobipEmailTemplateService {
  private static final String TEMPLATES_PATH = '/email/1/templates';
  private static final Integer PAGE_SIZE = 20;

  public class TemplateOption {
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String createdAt;
    @AuraEnabled
    public String updatedAt;
    @AuraEnabled
    public String imagePreviewUrl;
  }

  public static List<TemplateOption> fetchTemplates() {
    List<TemplateOption> allTemplates = new List<TemplateOption>();
    Integer pageNumber = 0;
    Integer totalPages = 1;

    while (pageNumber < totalPages) {
      HttpResponse response = sendGetRequest(pageNumber);
      if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
        throw new BWM_EmailException(buildHttpErrorMessage(response));
      }

      Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
        response.getBody()
      );
      List<Object> results = (List<Object>) payload.get('results');
      if (results != null) {
        for (Object row : results) {
          allTemplates.add(parseTemplateRow((Map<String, Object>) row));
        }
      }

      Map<String, Object> paging = (Map<String, Object>) payload.get('paging');
      if (paging != null && paging.containsKey('totalPages')) {
        totalPages = Integer.valueOf(String.valueOf(paging.get('totalPages')));
      } else {
        totalPages = pageNumber + 1;
      }
      pageNumber++;
    }

    allTemplates.sort(new TemplateOptionNameComparator());
    return allTemplates;
  }

  private static TemplateOption parseTemplateRow(Map<String, Object> templateRow) {
    TemplateOption option = new TemplateOption();
    Object idValue = templateRow.get('id');
    option.value = idValue == null ? null : String.valueOf(idValue);
    option.label = (String) templateRow.get('name');
    option.createdAt = (String) templateRow.get('createdAt');
    option.updatedAt = (String) templateRow.get('updatedAt');
    option.imagePreviewUrl = (String) templateRow.get('imagePreviewUrl');
    return option;
  }

  private static HttpResponse sendGetRequest(Integer pageNumber) {
    BWM_Email_Settings__mdt settings = BWM_EmailSettingsService.getSettings();
    if (settings == null) {
      throw new BWM_EmailException('BWM email settings are not configured.');
    }

    String path = TEMPLATES_PATH;
    if (pageNumber > 0) {
      path += '?page=' + pageNumber + '&size=' + PAGE_SIZE;
    }

    HttpRequest request = new HttpRequest();
    request.setEndpoint(BWM_EmailConstants.NAMED_CREDENTIAL + path);
    request.setMethod('GET');
    request.setHeader('Accept', 'application/json');

    String headerName = String.isBlank(settings.API_Key_Header__c)
      ? 'Authorization'
      : settings.API_Key_Header__c;
    if (String.isNotBlank(settings.API_App_Key__c)) {
      request.setHeader(headerName, 'App ' + settings.API_App_Key__c);
    }

    request.setTimeout(120000);
    return new Http().send(request);
  }

  private static String buildHttpErrorMessage(HttpResponse response) {
    Integer statusCode = response.getStatusCode();
    String body = response.getBody();

    if (statusCode == 401 || statusCode == 403) {
      return 'Bluewave email API authentication failed. Verify the API key in BWM Email Settings.';
    }
    if (statusCode == 500) {
      return 'Bluewave (Infobip) returned a server error while loading email templates. Please try again. If this continues, contact Bluewave support.';
    }

    if (String.isNotBlank(body)) {
      try {
        Map<String, Object> errorPayload = (Map<String, Object>) JSON.deserializeUntyped(
          body
        );
        Object description = errorPayload.get('description');
        if (description != null && String.isNotBlank(String.valueOf(description))) {
          return 'Failed to fetch Bluewave email templates: ' + String.valueOf(description);
        }
      } catch (Exception ex) {
        // Fall through to generic message.
      }
    }

    return 'Failed to fetch Bluewave email templates: HTTP ' + statusCode + '.';
  }

  private class TemplateOptionNameComparator implements Comparator<TemplateOption> {
    public Integer compare(TemplateOption first, TemplateOption second) {
      String firstName = first == null || first.label == null
        ? ''
        : first.label.toLowerCase();
      String secondName = second == null || second.label == null
        ? ''
        : second.label.toLowerCase();
      return firstName.compareTo(secondName);
    }
  }
}