public with sharing class CampaignEmailReportController {
  @AuraEnabled
  public static CampaignEmailReportService.FetchResult fetchEmailCampaignReport() {
    return CampaignEmailReportService.fetchAndSave();
  }
}