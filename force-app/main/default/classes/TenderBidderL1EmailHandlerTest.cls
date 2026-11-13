/**
 * @description   Tests for TenderBidderL1EmailHandler.
 * @author        Anshita Chanda
 * @date          2026-10-29
 */
@IsTest
private class TenderBidderL1EmailHandlerTest {
  private static final String DEPARTMENT = 'High Mast & Polygonal';

  private static Tender__c insertTender(String department) {
    Tender__c tender = new Tender__c(Department_Name__c = department);
    Database.insert(tender, AccessLevel.SYSTEM_MODE);
    return tender;
  }

  private static Bidders__c newBidder(Id tenderId, String rank, Boolean winner) {
    return new Bidders__c(Tender__c = tenderId, Bid_Rank__c = rank, Is_Winner__c = winner);
  }

  @IsTest
  static void isDeclaredL1RequiresRankAndWinner() {
    System.assertEquals(true, TenderBidderL1EmailHandler.isDeclaredL1(newBidder(null, 'L1', true)));
    System.assertEquals(true, TenderBidderL1EmailHandler.isDeclaredL1(newBidder(null, ' l1 ', true)));
    System.assertEquals(false, TenderBidderL1EmailHandler.isDeclaredL1(newBidder(null, 'L1', false)));
    System.assertEquals(false, TenderBidderL1EmailHandler.isDeclaredL1(newBidder(null, 'L2', true)));
    System.assertEquals(false, TenderBidderL1EmailHandler.isDeclaredL1(newBidder(null, null, true)));
    System.assertEquals(false, TenderBidderL1EmailHandler.isDeclaredL1(null));
  }

  @IsTest
  static void collectReturnsOneTenderPerTransaction() {
    Tender__c tender = insertTender(DEPARTMENT);
    TenderBidderL1EmailHandler.processedTenderIds.clear();

    Set<Id> tenderIds = TenderBidderL1EmailHandler.collectNewlyDeclaredTenderIds(
      new List<Bidders__c>{
        newBidder(tender.Id, 'L1', true),
        newBidder(tender.Id, 'L1', true),
        newBidder(tender.Id, 'L2', false)
      },
      null
    );
    System.assertEquals(new Set<Id>{ tender.Id }, tenderIds);

    Set<Id> again = TenderBidderL1EmailHandler.collectNewlyDeclaredTenderIds(
      new List<Bidders__c>{ newBidder(tender.Id, 'L1', true) },
      null
    );
    System.assertEquals(true, again.isEmpty(), 'Same tender must not be emailed twice in one transaction');
  }

  @IsTest
  static void collectOnUpdateOnlyOnTransition() {
    Tender__c tender = insertTender(DEPARTMENT);
    Bidders__c bidder = newBidder(tender.Id, 'L2', false);
    Database.insert(bidder, AccessLevel.SYSTEM_MODE);

    Bidders__c becameL1 = new Bidders__c(Id = bidder.Id, Tender__c = tender.Id, Bid_Rank__c = 'L1', Is_Winner__c = true);
    Bidders__c alreadyL1 = new Bidders__c(Id = bidder.Id, Tender__c = tender.Id, Bid_Rank__c = 'L1', Is_Winner__c = true);

    TenderBidderL1EmailHandler.processedTenderIds.clear();
    System.assertEquals(
      new Set<Id>{ tender.Id },
      TenderBidderL1EmailHandler.collectNewlyDeclaredTenderIds(
        new List<Bidders__c>{ becameL1 },
        new Map<Id, Bidders__c>{ bidder.Id => bidder }
      )
    );

    TenderBidderL1EmailHandler.processedTenderIds.clear();
    System.assertEquals(
      true,
      TenderBidderL1EmailHandler.collectNewlyDeclaredTenderIds(
        new List<Bidders__c>{ becameL1 },
        new Map<Id, Bidders__c>{ bidder.Id => alreadyL1 }
      ).isEmpty(),
      'No email when the bidder was already the declared L1'
    );
  }

  @IsTest
  static void sendNowEmailsHodAndCrmHead() {
    Tender__c tender = insertTender(DEPARTMENT);
    Tender__c withEmails = [
      SELECT HOD_User_Email_Formula__c, CRM_User_Email_Formula__c
      FROM Tender__c
      WHERE Id = :tender.Id
    ];
    Integer expected =
      expectedRecipientCount(
        TenderEmailRecipientService.PROFILE_HOD,
        withEmails.HOD_User_Email_Formula__c
      ) +
      expectedRecipientCount(
        TenderEmailRecipientService.PROFILE_CRM_HEAD,
        withEmails.CRM_User_Email_Formula__c
      );

    Test.startTest();
    TenderBidderL1EmailHandler.sendNow(new List<Id>{ tender.Id });
    Integer built = TenderBidderL1EmailHandler.lastBuiltCount;
    Test.stopTest();

    System.assertEquals(expected, built, 'One email per profile/department User, else per setting address');
  }

  @IsTest
  static void sendNowUsesProfileDepartmentHodAndFallsBackForCrmHead() {
    currentTestDepartment = 'Enquiry';
    Profile hodProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = :TenderEmailRecipientService.PROFILE_HOD
      LIMIT 1
    ];
    String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    insert new User(
      ProfileId = hodProfile.Id,
      LastName = 'L1 HOD Profile Test',
      Email = 'l1.hod.profile' + unique + '@example.com',
      Username = 'l1.hod.profile' + unique + '@example.com.uat',
      Alias = ('l' + unique).left(8),
      TimeZoneSidKey = 'Asia/Kolkata',
      LocaleSidKey = 'en_IN',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      Department = 'Some Other Dept, Enquiry'
    );
    Tender__c tender = insertTender('Enquiry');
    Tender__c withEmails = [
      SELECT CRM_User_Email_Formula__c
      FROM Tender__c
      WHERE Id = :tender.Id
    ];
    Integer expected =
      expectedRecipientCount(TenderEmailRecipientService.PROFILE_HOD, null) +
      expectedRecipientCount(
        TenderEmailRecipientService.PROFILE_CRM_HEAD,
        withEmails.CRM_User_Email_Formula__c
      );

    Test.startTest();
    TenderBidderL1EmailHandler.sendNow(new List<Id>{ tender.Id });
    Integer built = TenderBidderL1EmailHandler.lastBuiltCount;
    Test.stopTest();

    System.assert(expectedRecipientCount(TenderEmailRecipientService.PROFILE_HOD, null) >= 1);
    System.assertEquals(expected, built);
  }

  private static Integer expectedRecipientCount(String profileName, String fallbackEmail) {
    Integer users = TenderEmailRecipientService.findUsersForDepartment(
      TenderEmailRecipientService.resolveUsersByProfileDepartment(
        profileName,
        new Set<String>{ currentTestDepartment }
      ),
      currentTestDepartment
    ).size();
    if (users > 0) {
      return users;
    }
    // The setting address is used only when it belongs to an active User (no external email).
    if (String.isBlank(fallbackEmail)) {
      return 0;
    }
    Map<String, Id> userIdByEmail = TenderEmailRecipientService.resolveActiveUserIdsByEmail(
      new Set<String>{ fallbackEmail }
    );
    return TenderEmailRecipientService.findUserIdByEmail(userIdByEmail, fallbackEmail) == null ? 0 : 1;
  }

  private static String currentTestDepartment = DEPARTMENT;

  @IsTest
  static void sendNowSkipsTenderWithoutRecipients() {
    Tender__c tender = insertTender(null);

    Test.startTest();
    TenderBidderL1EmailHandler.sendNow(new List<Id>{ tender.Id });
    TenderBidderL1EmailHandler.sendNow(new List<Id>());
    TenderBidderL1EmailHandler.sendNow(null);
    Test.stopTest();

    System.assertEquals(0, TenderBidderL1EmailHandler.lastSentCount);
  }

  @IsTest
  static void triggerInsertAndUpdateRunWithoutErrors() {
    Tender__c tender = insertTender(DEPARTMENT);
    Bidders__c loser = newBidder(tender.Id, 'L2', false);

    Test.startTest();
    Database.insert(
      new List<Bidders__c>{ newBidder(tender.Id, 'L1', true), loser },
      AccessLevel.SYSTEM_MODE
    );
    TenderBidderL1EmailHandler.processedTenderIds.clear();
    loser.Bid_Rank__c = 'L1';
    loser.Is_Winner__c = true;
    Database.update(loser, AccessLevel.SYSTEM_MODE);
    Test.stopTest();

    System.assertEquals(
      2,
      [SELECT COUNT() FROM Bidders__c WHERE Tender__c = :tender.Id AND Bid_Rank__c = 'L1' AND Is_Winner__c = TRUE]
    );
  }

  @IsTest
  static void queueableExecutesSendNow() {
    Tender__c tender = insertTender(DEPARTMENT);

    Test.startTest();
    System.enqueueJob(new TenderBidderL1EmailHandler.SendQueueable(new List<Id>{ tender.Id }));
    Test.stopTest();

    new TenderBidderL1EmailHandler.SendQueueable(null).execute(null);
    System.assertEquals(0, TenderBidderL1EmailHandler.lastSentCount);
  }

  // More than 40 Tenders: the extra Tenders are handed to a new job, not skipped.
  @IsTest
  static void sendNowDefersTendersAboveForty() {
    Tender__c tender = insertTender(DEPARTMENT);
    String keyPrefix = Tender__c.SObjectType.getDescribe().getKeyPrefix();
    List<Id> tenderIds = new List<Id>{ tender.Id };
    for (Integer index = 1; index <= 42; index++) {
      tenderIds.add(Id.valueOf(keyPrefix + String.valueOf(index).leftPad(12, '0')));
    }

    Test.startTest();
    TenderBidderL1EmailHandler.sendNow(tenderIds);
    Test.stopTest();

    System.assertEquals(3, TenderBidderL1EmailHandler.lastDeferredCount);
  }
}