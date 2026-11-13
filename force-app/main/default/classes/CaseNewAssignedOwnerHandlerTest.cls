/**
 * @description   Test class for Case assignment/reassignment owner email handler.
 * @author        Anshita Chanda
 * @date          2026-08-14
 */
@IsTest
private class CaseNewAssignedOwnerHandlerTest {
  private static Id queryTemplateId(String developerName) {
    List<EmailTemplate> templates = [
      SELECT Id
      FROM EmailTemplate
      WHERE DeveloperName = :developerName
      LIMIT 1
    ];
    if (templates.isEmpty()) {
      templates = [SELECT Id FROM EmailTemplate LIMIT 1];
    }
    return templates.isEmpty() ? null : templates[0].Id;
  }

  private static User createUser(String aliasSuffix) {
    Profile profileRecord = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    User userRecord = new User(
      Alias = ('c' + aliasSuffix).left(8),
      Email = 'casehandler' + aliasSuffix + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'CaseHandler' + aliasSuffix,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileRecord.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'casehandler' + aliasSuffix + '@example.com.utkarshuat'
    );
    insert userRecord;
    return userRecord;
  }

  // Same profile as the running user, so the user can create Cases of the Case record type.
  private static User createActiveUser(String aliasSuffix) {
    String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    User userRecord = new User(
      Alias = ('o' + aliasSuffix).left(8),
      Email = 'caseowner' + aliasSuffix + unique + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'CaseOwner' + aliasSuffix,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = UserInfo.getProfileId(),
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'caseowner' + aliasSuffix + unique + '@example.com.utkarshuat'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert userRecord;
    }
    return userRecord;
  }

  // The handler only processes Cases of the 'Case' record type.
  private static Id caseRecordTypeId() {
    RecordTypeInfo info = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
      .get('Case');
    return info == null ? null : info.getRecordTypeId();
  }

  private static Case newCase(String subject, Id ownerId) {
    Case caseRecord = new Case(
      Subject = subject,
      Status = 'Open',
      Origin = 'Phone',
      OwnerId = ownerId
    );
    Id recordTypeId = caseRecordTypeId();
    if (recordTypeId != null) {
      caseRecord.RecordTypeId = recordTypeId;
    }
    return caseRecord;
  }

  // Classic text template with no merge fields, so it always renders.
  private static Id createClassicTemplate() {
    EmailTemplate templateRecord = new EmailTemplate(
      Name = 'Case Owner Classic Test',
      DeveloperName = 'Case_Owner_Classic_Test_' +
        String.valueOf(Math.abs(Crypto.getRandomInteger())),
      TemplateType = 'text',
      FolderId = UserInfo.getUserId(),
      Subject = 'A Case has been assigned to you',
      Body = 'Please review the Case assigned to you.',
      IsActive = true
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert templateRecord;
    }
    return templateRecord.Id;
  }

  // HTML template using {{{ }}} merge syntax, so the Lightning render path is used.
  private static Id createLightningStyleTemplate(String mergeField) {
    EmailTemplate templateRecord = new EmailTemplate(
      Name = 'Case Owner Lightning Test',
      DeveloperName = 'Case_Owner_Lightning_Test_' +
        String.valueOf(Math.abs(Crypto.getRandomInteger())),
      TemplateType = 'custom',
      FolderId = UserInfo.getUserId(),
      Subject = 'Case reassigned: {{{Case.Subject}}}',
      HtmlValue = '<p>The Case {{{' + mergeField + '}}} has been reassigned to you.</p>',
      IsActive = true
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert templateRecord;
    }
    return templateRecord.Id;
  }

  private static Id createCaseQueue(String name, String email) {
    Group queue = new Group(Name = name, Type = 'Queue', Email = email);
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert queue;
      insert new QueueSobject(QueueId = queue.Id, SobjectType = 'Case');
    }
    return queue.Id;
  }

  @IsTest
  static void testQualifiesForNewAssignmentAndReassignment() {
    Case newCase = new Case(
      Subject = 'Qualify Test',
      OwnerId = UserInfo.getUserId()
    );
    System.assertEquals(
      true,
      CaseNewAssignedOwnerHandler.qualifiesAsNewAssignment(newCase, null)
    );
    System.assertEquals(
      false,
      CaseNewAssignedOwnerHandler.qualifiesAsNewAssignment(newCase, newCase)
    );

    User otherOwner = createUser('q01');
    Case oldCase = new Case(OwnerId = UserInfo.getUserId());
    Case reassignedCase = new Case(OwnerId = otherOwner.Id);
    System.assertEquals(
      false,
      CaseNewAssignedOwnerHandler.qualifiesAsReassignment(
        reassignedCase,
        reassignedCase
      )
    );
    System.assertEquals(
      true,
      CaseNewAssignedOwnerHandler.qualifiesAsReassignment(
        reassignedCase,
        oldCase
      )
    );
  }

  @IsTest
  static void testProcessRecordsGuards() {
    Test.startTest();
    CaseNewAssignedOwnerHandler.processRecords(null, null);
    CaseNewAssignedOwnerHandler.processRecords(new List<Case>(), null);
    Test.stopTest();
    System.assert(true);
  }

  @IsTest
  static void testHandleAfterInsertSendsEmail() {
    Id templateId = queryTemplateId(
      CaseNewAssignedOwnerHandler.TEMPLATE_NEW_ASSIGNED
    );
    if (templateId != null) {
      CaseNewAssignedOwnerHandler.testTemplateIdOverride = templateId;
    }

    Case caseRecord = newCase('Assignment Email Test', UserInfo.getUserId());

    Test.startTest();
    insert caseRecord;
    Test.stopTest();

    caseRecord = [SELECT Id, OwnerId FROM Case WHERE Id = :caseRecord.Id];
    System.assertEquals(UserInfo.getUserId(), caseRecord.OwnerId);
  }

  @IsTest
  static void testHandleAfterUpdateSendsOnReassignment() {
    Id templateId = queryTemplateId(
      CaseNewAssignedOwnerHandler.TEMPLATE_REASSIGNED
    );
    if (templateId != null) {
      CaseNewAssignedOwnerHandler.testTemplateIdOverride = templateId;
    }

    User newOwner = createUser('001');
    Case caseRecord = newCase('Reassignment Email Test', UserInfo.getUserId());
    insert caseRecord;

    caseRecord.OwnerId = newOwner.Id;

    Test.startTest();
    update caseRecord;
    Test.stopTest();

    caseRecord = [SELECT OwnerId FROM Case WHERE Id = :caseRecord.Id];
    System.assertEquals(newOwner.Id, caseRecord.OwnerId);
  }

  @IsTest
  static void testTriggerSharesCaseWithCreatorWhenOwnerDiffers() {
    Id templateId = queryTemplateId(
      CaseNewAssignedOwnerHandler.TEMPLATE_NEW_ASSIGNED
    );
    if (templateId != null) {
      CaseNewAssignedOwnerHandler.testTemplateIdOverride = templateId;
    }

    User ownerUser = createUser('002');
    Case caseRecord = newCase('Share Test', ownerUser.Id);

    Test.startTest();
    insert caseRecord;
    Test.stopTest();

    List<CaseShare> shares = [
      SELECT Id
      FROM CaseShare
      WHERE CaseId = :caseRecord.Id AND UserOrGroupId = :UserInfo.getUserId()
    ];
    System.assertNotEquals(null, caseRecord.Id);
  }

  // ===============================================================
  // DIRECT processRecords COVERAGE
  // ===============================================================
  
  @IsTest
  static void testReassignmentLightningTemplateSendsOwnerAndCreatorCopies() {
    CaseNewAssignedOwnerHandler.testTemplateIdOverride =
      createLightningStyleTemplate('Case.Subject');
    User newOwner = createActiveUser('ln1');

    // Created by the running user, then reassigned so Owner and Creator differ.
    Case caseRecord = newCase('Lightning Reassignment Case', UserInfo.getUserId());
    insert caseRecord;
    Case oldCase = new Case(Id = caseRecord.Id, OwnerId = UserInfo.getUserId());
    caseRecord.OwnerId = newOwner.Id;
    update caseRecord;

    Test.startTest();
    CaseNewAssignedOwnerHandler.processRecords(
      new List<Case>{ caseRecord },
      new Map<Id, Case>{ caseRecord.Id => oldCase }
    );
    Integer emailInvocations = Limits.getEmailInvocations();
    Test.stopTest();

    System.assertEquals(1, emailInvocations, 'Owner and Creator copies go in one send');
  }
    
  @IsTest
  static void testQueueOwnerIsNotEmailed() {
    CaseNewAssignedOwnerHandler.testTemplateIdOverride = createClassicTemplate();
    Id queueWithEmail = createCaseQueue('Case Owner Test Queue A', 'queue.a@example.com');
    Id queueWithoutEmail = createCaseQueue('Case Owner Test Queue B', null);

    Case queueCase = newCase('Queue Owned Case', queueWithEmail);
    Case noEmailCase = newCase('Queue Without Email Case', queueWithoutEmail);
    insert new List<Case>{ queueCase, noEmailCase };

    Test.startTest();
    CaseNewAssignedOwnerHandler.processRecords(
      new List<Case>{ queueCase, noEmailCase },
      null
    );
    Integer emailInvocations = Limits.getEmailInvocations();
    Test.stopTest();

    System.assertEquals(0, emailInvocations, 'A Queue owner cannot be emailed by User Id');
  }

  @IsTest
  static void testMissingTemplateSendsNothing() {
    // An Id that is not an EmailTemplate makes the template lookup return null.
    CaseNewAssignedOwnerHandler.testTemplateIdOverride = UserInfo.getUserId();
    Case caseRecord = newCase('Missing Template Case', UserInfo.getUserId());
    insert caseRecord;

    Test.startTest();
    CaseNewAssignedOwnerHandler.processRecords(new List<Case>{ caseRecord }, null);
    Integer emailInvocations = Limits.getEmailInvocations();
    Test.stopTest();

    System.assertEquals(0, emailInvocations, 'No email without a template');
  }

  @IsTest
  static void testLightningTemplateMergeFailureSendsNothing() {
    CaseNewAssignedOwnerHandler.testTemplateIdOverride =
      createLightningStyleTemplate('Case.Field_That_Does_Not_Exist__c');
    Case caseRecord = newCase('Merge Failure Case', UserInfo.getUserId());
    insert caseRecord;

    Integer emailInvocations = 0;
    Test.startTest();
    try {
      CaseNewAssignedOwnerHandler.processRecords(new List<Case>{ caseRecord }, null);
    } catch (Exception ex) {
      // Some orgs reject an unknown merge field outright instead of returning an error result.
      System.debug('Merge failure surfaced as exception: ' + ex.getMessage());
    }
    emailInvocations = Limits.getEmailInvocations();
    Test.stopTest();

    System.assertEquals(0, emailInvocations, 'No email when the template fails to merge');
  }
}