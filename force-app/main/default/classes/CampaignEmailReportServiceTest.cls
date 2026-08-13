/**
 * @description   Test class for CampaignEmailReportService email report scenarios.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
@IsTest
private class CampaignEmailReportServiceTest {
  private class EmailReportsMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest request) {
      HttpResponse response = new HttpResponse();
      response.setHeader('Content-Type', 'application/json');
      response.setStatusCode(200);
      if (request.getEndpoint().contains('/email/4/logs')) {
        response.setBody('{"results":[]}');
        return response;
      }
      System.assert(
        request.getEndpoint().contains('/email/4/reports'),
        'Expected email reports endpoint'
      );
      response.setBody(
        '{"results":[{"bulkId":"bulk-1","messageId":"msg-1","to":"user@example.com","sender":"noreply@utkarshindialimited.in","sentAt":"2026-07-16T07:42:25.000+0000","doneAt":"2026-07-16T07:43:25.000+0000","messageCount":1,"campaignReferenceId":"camp-ref-1","attemptCount":1,"timeToFirstAttempt":3675,"price":{"pricePerMessage":0.11,"currency":"INR"},"status":{"name":"DELIVERED_TO_HANDSET","description":"Message delivered to handset"},"error":{"name":"NO_ERROR","description":"No Error"}}]}'
      );
      return response;
    }
  }

  private class EmailReportsErrorMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest request) {
      HttpResponse response = new HttpResponse();
      response.setHeader('Content-Type', 'application/json');
      response.setStatusCode(401);
      response.setBody('{"description":"Unauthorized"}');
      return response;
    }
  }

  private class EmailLogsFallbackMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest request) {
      HttpResponse response = new HttpResponse();
      response.setHeader('Content-Type', 'application/json');
      response.setStatusCode(200);
      if (request.getEndpoint().contains('/email/4/reports')) {
        response.setBody('{"results":[]}');
        return response;
      }
      response.setBody(
        '{"results":[{"bulkId":"bulk-2","messageId":"msg-2","destination":"user@example.com","sender":"noreply@utkarshindialimited.in","sentAt":"2026-07-16T07:42:25.000+0000","doneAt":"2026-07-16T07:43:25.000+0000","messageCount":1,"price":{"pricePerMessage":0.11,"currency":"INR"},"status":{"name":"DELIVERED_TO_HANDSET","description":"Message delivered to handset"},"error":{"name":"NO_ERROR","description":"No Error"}}]}'
      );
      return response;
    }
  }

  @IsTest
  static void fetchAndSaveCreatesEmailCampaignReport() {
    Test.setMock(HttpCalloutMock.class, new EmailReportsMock());

    Test.startTest();
    CampaignEmailReportService.FetchResult result = CampaignEmailReportService.fetchAndSave();
    Test.stopTest();

    System.assertEquals(1, result.rows.size());
    System.assertEquals('DELIVERED_TO_HANDSET', result.rows[0].status);
    System.assertEquals(0.11, result.rows[0].pricePerMessage);
    System.assertEquals('INR', result.rows[0].priceCurrency);
    System.assertEquals('NO_ERROR', result.rows[0].errorName);
    System.assertEquals(3675, result.rows[0].timeToFirstAttempt);
    System.assertEquals(1, result.summaryRows.size());
    System.assertEquals('user@example.com', result.summaryRows[0].recipient);
    System.assertEquals(1, result.summaryRows[0].delivered);
    System.assertEquals(0, result.summaryRows[0].failed);
    System.assertEquals(1, result.summaryRows[0].total);
    System.assertEquals(2, result.reportIds.size());

    Campaign_Report__c report = [
      SELECT
        Campaign__c,
        Report_Type__c,
        Product_Name__c,
        Email_Message_Id__c,
        Email_Recipient__c,
        Email_Status__c,
        Email_Price_Per_Message__c,
        Email_Price_Currency__c,
        Email_Error_Name__c,
        Email_Time_To_First_Attempt__c,
        Raw_Response__c
      FROM Campaign_Report__c
      WHERE Id = :result.reportIds[0]
    ];
    System.assertEquals(null, report.Campaign__c);
    System.assertEquals('Email', report.Report_Type__c);
    System.assertEquals('Email', report.Product_Name__c);
    System.assertEquals('msg-1', report.Email_Message_Id__c);
    System.assertEquals('user@example.com', report.Email_Recipient__c);
    System.assertEquals('DELIVERED_TO_HANDSET', report.Email_Status__c);
    System.assertEquals(0.11, report.Email_Price_Per_Message__c);
    System.assertEquals('INR', report.Email_Price_Currency__c);
    System.assertEquals('NO_ERROR', report.Email_Error_Name__c);
    System.assertEquals(3675, report.Email_Time_To_First_Attempt__c);
    System.assert(String.isNotBlank(report.Raw_Response__c));
  }

  @IsTest
  static void controllerDelegatesToService() {
    Test.setMock(HttpCalloutMock.class, new EmailReportsMock());

    Test.startTest();
    CampaignEmailReportService.FetchResult result = CampaignEmailReportController.fetchEmailCampaignReport();
    Test.stopTest();

    System.assertEquals(2, result.reportIds.size());
  }

  @IsTest
  static void fetchAndSaveSurfacesApiError() {
    Test.setMock(HttpCalloutMock.class, new EmailReportsErrorMock());

    Boolean threw = false;
    Test.startTest();
    try {
      CampaignEmailReportService.fetchAndSave();
    } catch (Exception ex) {
      threw = true;
      System.assert(
        ex instanceof AuraHandledException,
        'Expected AuraHandledException'
      );
    }
    Test.stopTest();

    System.assert(threw, 'Expected AuraHandledException');
    System.assertEquals(0, [SELECT COUNT() FROM Campaign_Report__c]);
  }

  @IsTest
  static void fetchAndSaveUsesLogsWhenReportsEmpty() {
    Test.setMock(HttpCalloutMock.class, new EmailLogsFallbackMock());

    Test.startTest();
    CampaignEmailReportService.FetchResult result = CampaignEmailReportService.fetchAndSave();
    Test.stopTest();

    System.assertEquals(1, result.rows.size());
    System.assertEquals('user@example.com', result.rows[0].recipient);
    System.assertEquals(1, result.summaryRows.size());
    System.assertEquals('user@example.com', result.summaryRows[0].recipient);
    System.assertEquals(1, result.summaryRows[0].delivered);
    System.assertEquals(2, result.reportIds.size());

    Integration_Log__c logRecord = [
      SELECT Endpoint__c
      FROM Integration_Log__c
      WHERE Id = :result.integrationLogId
    ];
    System.assertEquals('/email/4/reports+/email/4/logs', logRecord.Endpoint__c);
  }

  @IsTest
  static void mergeResponseBodiesCombinesReportsAndLogs() {
    String reportsBody = '{"results":[{"messageId":"shared-id","to":"reports@example.com","sentAt":"2026-07-16T08:00:00.000+0000","attemptCount":2}]}';
    String logsBody = '{"results":[{"messageId":"shared-id","destination":"logs@example.com","sentAt":"2026-07-16T09:00:00.000+0000"},{"messageId":"logs-only","destination":"new@example.com","sentAt":"2026-07-16T10:00:00.000+0000"}]}';

    String mergedBody = CampaignEmailReportService.mergeResponseBodies(
      reportsBody,
      logsBody
    );
    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(mergedBody);
    List<Object> results = (List<Object>) payload.get('results');

    System.assertEquals(2, results.size());
    Map<String, Object> newest = (Map<String, Object>) results[0];
    System.assertEquals('logs-only', newest.get('messageId'));
  }

  @IsTest
  static void listBridgeRedirectsToEmailReportLwc() {
    ApexPages.StandardSetController setController = new ApexPages.StandardSetController(
      new List<Campaign>()
    );
    CampaignEmailReportListBridgeController controller = new CampaignEmailReportListBridgeController(
      setController
    );

    Test.startTest();
    PageReference target = controller.redirectToLwc();
    Test.stopTest();

    System.assertNotEquals(null, target);
    System.assert(
      target.getUrl().contains('c__campaignEmailReport'),
      'Expected email report LWC redirect URL'
    );
    System.assertEquals(
      null,
      target.getParameters().get('c__recordIds'),
      'Email report is not campaign-scoped'
    );
  }
}