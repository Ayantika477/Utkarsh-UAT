/**
 * @description   Tests for TenderEmailRecipientService.
 * @author        Anshita Chanda
 * @date          2026-11-03
 */
@IsTest
private class TenderEmailRecipientServiceTest {
  @IsTest
  static void resolvesActiveUserByExactEmailIgnoringCaseAndSpaces() {
    User runningUser = [SELECT Id, Email FROM User WHERE Id = :UserInfo.getUserId()];

    Map<String, Id> userIdByEmail = TenderEmailRecipientService.resolveActiveUserIdsByEmail(
      new Set<String>{ '  ' + runningUser.Email.toUpperCase() + ' ', null, '', 'nobody.matches@example.invalid' }
    );

    Id matchedUserId = TenderEmailRecipientService.findUserIdByEmail(userIdByEmail, runningUser.Email);
    System.assertNotEquals(null, matchedUserId);
    System.assertEquals(
      runningUser.Email.toLowerCase(),
      [SELECT Email FROM User WHERE Id = :matchedUserId].Email.toLowerCase()
    );
    System.assertEquals(
      null,
      TenderEmailRecipientService.findUserIdByEmail(userIdByEmail, 'nobody.matches@example.invalid')
    );
    System.assertEquals(null, TenderEmailRecipientService.findUserIdByEmail(null, runningUser.Email));
    System.assertEquals(null, TenderEmailRecipientService.findUserIdByEmail(userIdByEmail, ' '));
  }

  @IsTest
  static void resolvesUsersByProfileAndAnyListedDepartment() {
    Profile crmHeadProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = :TenderEmailRecipientService.PROFILE_CRM_HEAD
      LIMIT 1
    ];
    String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    User crmHead = new User(
      ProfileId = crmHeadProfile.Id,
      LastName = 'Tender CRM Head Test',
      Email = 'tender.crm.head' + unique + '@example.com',
      Username = 'tender.crm.head' + unique + '@example.com.uat',
      Alias = ('t' + unique).left(8),
      TimeZoneSidKey = 'Asia/Kolkata',
      LocaleSidKey = 'en_IN',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      Department = 'Tender Test Dept A, Tender Test Dept B'
    );
    insert crmHead;

    Map<String, List<User>> usersByDepartment = TenderEmailRecipientService.resolveUsersByProfileDepartment(
      TenderEmailRecipientService.PROFILE_CRM_HEAD,
      new Set<String>{ 'Tender Test Dept B', 'Tender Test Dept C', null }
    );
    List<User> found = TenderEmailRecipientService.findUsersForDepartment(
      usersByDepartment,
      ' tender test dept b '
    );
    System.assertEquals(1, found.size(), 'User listing several departments must match each one');
    System.assertEquals(crmHead.Id, found[0].Id);
    System.assert(
      TenderEmailRecipientService.findUsersForDepartment(usersByDepartment, 'Tender Test Dept C').isEmpty()
    );
    System.assert(
      TenderEmailRecipientService.resolveUsersByProfileDepartment(
        TenderEmailRecipientService.PROFILE_HOD,
        new Set<String>{ 'Tender Test Dept A' }
      ).isEmpty(),
      'Only Users with the requested profile are returned'
    );
    System.assert(TenderEmailRecipientService.findUsersForDepartment(null, 'x').isEmpty());
    System.assert(
      TenderEmailRecipientService.resolveUsersByProfileDepartment(null, new Set<String>{ 'x' }).isEmpty()
    );
  }

  @IsTest
  static void blankInputsReturnEmptyResults() {
    System.assert(TenderEmailRecipientService.resolveActiveUserIdsByEmail(null).isEmpty());
    System.assert(TenderEmailRecipientService.resolveActiveUserIdsByEmail(new Set<String>{ ' ' }).isEmpty());
    System.assert(TenderEmailRecipientService.resolveActiveUserIds(null).isEmpty());
    System.assert(TenderEmailRecipientService.resolveActiveUserIds(new Set<Id>()).isEmpty());
  }

  @IsTest
  static void resolvesActiveUserIds() {
    Set<Id> activeIds = TenderEmailRecipientService.resolveActiveUserIds(
      new Set<Id>{ UserInfo.getUserId() }
    );
    System.assert(activeIds.contains(UserInfo.getUserId()));
  }

  @IsTest
  static void buildUserMessageAddressesUserIdWithoutWhatIdOrActivity() {
    Messaging.SingleEmailMessage rendered = new Messaging.SingleEmailMessage();
    rendered.setSubject('Tender update');
    rendered.setHtmlBody('<p>Body</p>');
    rendered.setPlainTextBody('Body');

    Messaging.SingleEmailMessage mail = TenderEmailRecipientService.buildUserMessage(
      rendered,
      UserInfo.getUserId(),
      null
    );

    System.assertEquals(UserInfo.getUserId(), mail.getTargetObjectId());
    System.assertEquals('Tender update', mail.getSubject());
    System.assertEquals('<p>Body</p>', mail.getHtmlBody());
    System.assertEquals('Body', mail.getPlainTextBody());
    System.assertEquals(null, mail.getWhatId());
    System.assertEquals(false, mail.getSaveAsActivity());
    System.assert(
      mail.getToAddresses() == null || mail.getToAddresses().isEmpty(),
      'User emails must not use an email address, so they stay internal'
    );

    System.assertEquals(null, TenderEmailRecipientService.buildUserMessage(null, UserInfo.getUserId(), null));
    System.assertEquals(null, TenderEmailRecipientService.buildUserMessage(rendered, null, null));
  }
}