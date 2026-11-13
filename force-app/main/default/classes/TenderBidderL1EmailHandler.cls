/**
 * @description   Sends "L1 Bidder Declared" emails to the Tender's Department HOD and
 *                CRM Head when a Bidder becomes the declared L1 winner
 *                (Bid_Rank__c = 'L1' and Is_Winner__c = true).
 *                One email per Tender per recipient, sent only on the transition.
 * @author        Anshita Chanda
 * @date          2026-10-29
 */
public without sharing class TenderBidderL1EmailHandler {
  public static final String L1_RANK = 'L1';

  public static final String TEMPLATE_HOD_L1_DECLARED = 'L1_Bidder_Declared_1786625858550';
  public static final String TEMPLATE_CRM_HEAD_L1_DECLARED = 'L1_Bidder_Declared_CRM_Dept_Head_1786779877847';

  public static final String ORG_WIDE_SENDER_EMAIL = 'noreply@utkarshindialimited.in';

  // Each email render consumes one SOQL query.
  private static final Integer MAX_TENDERS_PER_TRANSACTION = 40;

  @TestVisible
  private static Set<Id> processedTenderIds = new Set<Id>();

  @TestVisible
  private static Integer lastSentCount = 0;

  @TestVisible
  private static Integer lastBuiltCount = 0;

  @TestVisible
  private static Integer lastDeferredCount = 0;

  public static void handleAfterInsert(List<Bidders__c> newBidders) {
    handle(newBidders, null);
  }

  public static void handleAfterUpdate(List<Bidders__c> newBidders, Map<Id, Bidders__c> oldBiddersById) {
    handle(newBidders, oldBiddersById);
  }

  private static void handle(List<Bidders__c> newBidders, Map<Id, Bidders__c> oldBiddersById) {
    try {
      Set<Id> tenderIds = collectNewlyDeclaredTenderIds(newBidders, oldBiddersById);
      if (tenderIds.isEmpty()) {
        return;
      }
      dispatch(new List<Id>(tenderIds));
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'TenderBidderL1EmailHandler failed: ' + e.getMessage() + '\n' + e.getStackTraceString()
      );
    }
  }

  @TestVisible
  private static Boolean isDeclaredL1(Bidders__c bidder) {
    return bidder != null &&
      bidder.Is_Winner__c == true &&
      bidder.Bid_Rank__c != null &&
      bidder.Bid_Rank__c.trim().equalsIgnoreCase(L1_RANK);
  }

  @TestVisible
  private static Set<Id> collectNewlyDeclaredTenderIds(
    List<Bidders__c> newBidders,
    Map<Id, Bidders__c> oldBiddersById
  ) {
    Set<Id> tenderIds = new Set<Id>();
    if (newBidders == null) {
      return tenderIds;
    }
    for (Bidders__c bidder : newBidders) {
      if (bidder == null || bidder.Tender__c == null || !isDeclaredL1(bidder)) {
        continue;
      }
      Bidders__c oldBidder = oldBiddersById == null ? null : oldBiddersById.get(bidder.Id);
      if (oldBidder != null && isDeclaredL1(oldBidder)) {
        continue;
      }
      if (processedTenderIds.contains(bidder.Tender__c)) {
        continue;
      }
      processedTenderIds.add(bidder.Tender__c);
      tenderIds.add(bidder.Tender__c);
    }
    return tenderIds;
  }

  // Async callers (results batch) send inline; UI/sync callers send from a Queueable
  // so the user's save is not slowed by template rendering.
  private static void dispatch(List<Id> tenderIds) {
    Boolean isAsync = System.isBatch() || System.isFuture() || System.isQueueable();
    Boolean canEnqueue = Limits.getQueueableJobs() < Limits.getLimitQueueableJobs();
    if (!isAsync && canEnqueue) {
      System.enqueueJob(new SendQueueable(tenderIds));
      return;
    }
    sendNow(tenderIds);
  }

  public class SendQueueable implements Queueable {
    private List<Id> tenderIds;

    public SendQueueable(List<Id> tenderIds) {
      this.tenderIds = tenderIds == null ? new List<Id>() : tenderIds;
    }

    public void execute(QueueableContext context) {
      try {
        sendNow(tenderIds);
      } catch (Exception e) {
        System.debug(
          LoggingLevel.ERROR,
          'TenderBidderL1EmailHandler queueable failed: ' + e.getMessage() + '\n' + e.getStackTraceString()
        );
      }
    }
  }

  @TestVisible
  private static void sendNow(List<Id> tenderIds) {
    lastSentCount = 0;
    lastBuiltCount = 0;
    lastDeferredCount = 0;
    if (tenderIds == null || tenderIds.isEmpty()) {
      return;
    }

    List<Id> chunk = new List<Id>();
    List<Id> remainingTenderIds = new List<Id>();
    for (Id tenderId : tenderIds) {
      if (chunk.size() >= MAX_TENDERS_PER_TRANSACTION) {
        remainingTenderIds.add(tenderId);
      } else {
        chunk.add(tenderId);
      }
    }
    lastDeferredCount = remainingTenderIds.size();
    enqueueRemaining(remainingTenderIds);

    Set<String> templateNames = new Set<String>{
      TEMPLATE_HOD_L1_DECLARED,
      TEMPLATE_CRM_HEAD_L1_DECLARED
    };
    Map<String, Id> templateIdByName = new Map<String, Id>();
    for (EmailTemplate template : [
      SELECT Id, DeveloperName
      FROM EmailTemplate
      WHERE DeveloperName IN :templateNames
      WITH SYSTEM_MODE
    ]) {
      templateIdByName.put(template.DeveloperName, template.Id);
    }

    Id oweaId = getOrgWideEmailAddressId();

    List<Tender__c> tenders = [
      SELECT Id, Name, Department_Name__c, HOD_User_Email_Formula__c, CRM_User_Email_Formula__c
      FROM Tender__c
      WHERE Id IN :chunk
      WITH SYSTEM_MODE
    ];
    Set<String> recipientEmails = new Set<String>();
    Set<String> departments = new Set<String>();
    for (Tender__c tender : tenders) {
      recipientEmails.add(tender.HOD_User_Email_Formula__c);
      recipientEmails.add(tender.CRM_User_Email_Formula__c);
      departments.add(tender.Department_Name__c);
    }
    Map<String, Id> userIdByEmail = TenderEmailRecipientService.resolveActiveUserIdsByEmail(
      recipientEmails
    );
    Map<String, List<User>> hodsByDepartment = TenderEmailRecipientService.resolveUsersByProfileDepartment(
      TenderEmailRecipientService.PROFILE_HOD,
      departments
    );
    Map<String, List<User>> crmHeadsByDepartment = TenderEmailRecipientService.resolveUsersByProfileDepartment(
      TenderEmailRecipientService.PROFILE_CRM_HEAD,
      departments
    );

    List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
    List<String> messageLabels = new List<String>();
    for (Tender__c tender : tenders) {
      // Profile + User.Department first; the department setting email is the fallback.
      List<User> hods = TenderEmailRecipientService.findUsersForDepartment(
        hodsByDepartment,
        tender.Department_Name__c
      );
      if (!hods.isEmpty()) {
        addUserMessages(
          messages,
          messageLabels,
          templateIdByName.get(TEMPLATE_HOD_L1_DECLARED),
          tender.Id,
          hods,
          oweaId,
          'HOD ' + tender.Name
        );
      } else {
        addMessage(
          messages,
          messageLabels,
          templateIdByName.get(TEMPLATE_HOD_L1_DECLARED),
          tender.Id,
          tender.HOD_User_Email_Formula__c,
          userIdByEmail,
          oweaId,
          'HOD ' + tender.Name
        );
      }

      List<User> crmHeads = TenderEmailRecipientService.findUsersForDepartment(
        crmHeadsByDepartment,
        tender.Department_Name__c
      );
      if (!crmHeads.isEmpty()) {
        addUserMessages(
          messages,
          messageLabels,
          templateIdByName.get(TEMPLATE_CRM_HEAD_L1_DECLARED),
          tender.Id,
          crmHeads,
          oweaId,
          'CRM Head ' + tender.Name
        );
      } else {
        addMessage(
          messages,
          messageLabels,
          templateIdByName.get(TEMPLATE_CRM_HEAD_L1_DECLARED),
          tender.Id,
          tender.CRM_User_Email_Formula__c,
          userIdByEmail,
          oweaId,
          'CRM Head ' + tender.Name
        );
      }
    }

    lastBuiltCount = messages.size();
    if (messages.isEmpty()) {
      return;
    }

    List<Messaging.SendEmailResult> results = Messaging.sendEmail(messages, false);
    for (Integer i = 0; i < results.size(); i++) {
      if (results[i].isSuccess()) {
        lastSentCount++;
      } else {
        System.debug(
          LoggingLevel.ERROR,
          'L1 Bidder Declared email failed (' + messageLabels[i] + '): ' + results[i].getErrors()
        );
      }
    }
  }

  // Tenders beyond MAX_TENDERS_PER_TRANSACTION are sent by a new job instead of being skipped.
  private static void enqueueRemaining(List<Id> remainingTenderIds) {
    if (remainingTenderIds.isEmpty() || Test.isRunningTest()) {
      return;
    }
    if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
      System.debug(
        LoggingLevel.ERROR,
        'TenderBidderL1EmailHandler could not chain ' + remainingTenderIds.size() +
          ' remaining tenders: queueable limit reached.'
      );
      return;
    }
    System.enqueueJob(new SendQueueable(remainingTenderIds));
  }

  private static void addUserMessages(
    List<Messaging.SingleEmailMessage> messages,
    List<String> messageLabels,
    Id templateId,
    Id tenderId,
    List<User> recipients,
    Id oweaId,
    String label
  ) {
    if (templateId == null || recipients == null || recipients.isEmpty()) {
      return;
    }
    Messaging.SingleEmailMessage rendered;
    try {
      rendered = Messaging.renderStoredEmailTemplate(templateId, null, tenderId);
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'L1 template render failed (' + label + '): ' + e.getMessage());
      return;
    }
    for (User recipient : recipients) {
      messages.add(TenderEmailRecipientService.buildUserMessage(rendered, recipient.Id, oweaId));
      messageLabels.add(label);
    }
  }

  private static void addMessage(
    List<Messaging.SingleEmailMessage> messages,
    List<String> messageLabels,
    Id templateId,
    Id tenderId,
    String recipientEmail,
    Map<String, Id> userIdByEmail,
    Id oweaId,
    String label
  ) {
    if (templateId == null || String.isBlank(recipientEmail)) {
      return;
    }

    // Department setting (custom metadata) emails go only to active Users, by User Id.
    Id recipientUserId = TenderEmailRecipientService.findUserIdByEmail(userIdByEmail, recipientEmail);
    if (recipientUserId == null) {
      System.debug(
        LoggingLevel.WARN,
        'L1 email skipped (' + label + '): no active User for ' + recipientEmail
      );
      return;
    }

    Messaging.SingleEmailMessage mail;
    try {
      mail = Messaging.renderStoredEmailTemplate(templateId, null, tenderId);
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'L1 template render failed (' + label + '): ' + e.getMessage());
      return;
    }
    messages.add(TenderEmailRecipientService.buildUserMessage(mail, recipientUserId, oweaId));
    messageLabels.add(label);
  }

  private static Id getOrgWideEmailAddressId() {
    List<OrgWideEmailAddress> addresses = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE Address = :ORG_WIDE_SENDER_EMAIL
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return addresses.isEmpty() ? null : addresses[0].Id;
  }
}