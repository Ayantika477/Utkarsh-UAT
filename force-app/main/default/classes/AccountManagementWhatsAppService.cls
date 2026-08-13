public with sharing class AccountManagementWhatsAppService {
  public static LeadManagementWhatsAppService.SendWhatsAppResult sendToAccounts(
    List<Id> accountIds,
    String templateName
  ) {
    return BWM_CampaignWhatsAppSendService.sendToRecords(
      BWM_CampaignRecordSupport.queryAccountsByIds(accountIds),
      templateName,
      BWM_MessagingConstants.TRIGGER_ACCOUNT_CAMPAIGN,
      BWM_MessagingConstants.OBJECT_TYPE_ACCOUNT
    );
  }
}