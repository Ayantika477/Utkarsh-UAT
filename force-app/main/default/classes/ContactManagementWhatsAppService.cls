public with sharing class ContactManagementWhatsAppService {
  public static LeadManagementWhatsAppService.SendWhatsAppResult sendToContacts(
    List<Id> contactIds,
    String templateName
  ) {
    return BWM_CampaignWhatsAppSendService.sendToRecords(
      BWM_CampaignRecordSupport.queryContactsByIds(contactIds),
      templateName,
      BWM_MessagingConstants.TRIGGER_CONTACT_CAMPAIGN,
      BWM_MessagingConstants.OBJECT_TYPE_CONTACT
    );
  }
}