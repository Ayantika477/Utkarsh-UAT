public with sharing class OfflineCampaignManagementWhatsAppService {
  public static LeadManagementWhatsAppService.SendWhatsAppResult sendToOfflineCampaigns(
    List<Id> offlineCampaignIds,
    String templateName
  ) {
    return BWM_CampaignWhatsAppSendService.sendToRecords(
      BWM_CampaignRecordSupport.queryOfflineCampaignsByIds(offlineCampaignIds),
      templateName,
      BWM_MessagingConstants.TRIGGER_OFFLINE_CAMPAIGN,
      BWM_MessagingConstants.OBJECT_TYPE_OFFLINE_CAMPAIGN
    );
  }
}