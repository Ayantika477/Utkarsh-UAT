public with sharing class OfflineCampaignUploadController {
  @AuraEnabled(cacheable=true)
  public static List<OfflineCampaignUploadService.PicklistOption> getDepartmentOptions() {
    return OfflineCampaignUploadService.getDepartmentOptions();
  }

  @AuraEnabled
  public static OfflineCampaignUploadService.InsertSummary insertOfflineCampaignRows(
    String rowsJson
  ) {
    return OfflineCampaignUploadService.insertRows(
      OfflineCampaignUploadService.parseUploadRows(rowsJson)
    );
  }
}