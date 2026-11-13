@IsTest
private class LeadNewLeadFlowControllerTest {
  private static final String TEST_DEPARTMENT = 'Steel Pipes';

  // The BWM notification queueables make callouts when they run at Test.stopTest()
  private class SuccessMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setStatus('OK');
      res.setBody('{}');
      return res;
    }
  }

  @TestSetup
  static void setup() {
    Profile adminProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    String uniqueKey = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    List<User> users = new List<User>();
    for (Integer i = 0; i < 2; i++) {
      users.add(
        new User(
          Alias = 'lnlf' + i,
          Email = 'lnlf' + i + '.' + uniqueKey + '@example.com',
          EmailEncodingKey = 'UTF-8',
          LastName = 'LeadFlowUser' + i,
          LanguageLocaleKey = 'en_US',
          LocaleSidKey = 'en_US',
          ProfileId = adminProfile.Id,
          TimeZoneSidKey = 'Asia/Kolkata',
          UserName = 'lnlf' + i + '.' + uniqueKey + '@example.com',
          Department = TEST_DEPARTMENT,
          IsActive = (i == 0)
        )
      );
    }
    insert users;
  }

  private static User testUser() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = 'LeadFlowUser0'
      LIMIT 1
    ];
  }

  private static LeadNewLeadFlowController.LeadRequest buildRequest(Id ownerId) {
    LeadNewLeadFlowController.LeadRequest req = new LeadNewLeadFlowController.LeadRequest();
    req.firstName = 'Test';
    req.lastName = 'Prospect';
    req.company = 'Test Company';
    req.companyName = 'Test Company';
    req.email = 'test.prospect@example.com';
    req.phone = '9999999999';
    req.status = 'Prospect';
    req.leadSource = 'TENDER';
    req.departmentName = TEST_DEPARTMENT;
    req.ownerId = ownerId;
    req.country = 'India';
    req.categories = new List<LeadNewLeadFlowController.CategoryRow>();
    return req;
  }

  private static LeadNewLeadFlowController.CategoryRow buildCategory() {
    LeadNewLeadFlowController.CategoryRow row = new LeadNewLeadFlowController.CategoryRow();
    row.department = TEST_DEPARTMENT;
    row.productCategory = 'GI pipes';
    row.uom = 'Pcs';
    row.quantity = 5;
    return row;
  }

  private static Id createContentDocument() {
    ContentVersion cv = new ContentVersion(
      Title = 'Lead Flow Test File',
      PathOnClient = 'LeadFlowTest.txt',
      VersionData = Blob.valueOf('test')
    );
    insert cv;
    return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id]
    .ContentDocumentId;
  }

  @IsTest
  static void getInitData_returnsCurrentUserDetails() {
    User u = testUser();
    LeadNewLeadFlowController.InitData data;

    System.runAs(u) {
      Test.startTest();
      data = LeadNewLeadFlowController.getInitData();
      Test.stopTest();
    }

    Assert.areEqual(u.Id, data.userId, 'User id should be the running user');
    Assert.areEqual('System Administrator', data.profileName, 'Profile name should be returned');
    Assert.areEqual(TEST_DEPARTMENT, data.department, 'Department should be returned');
  }

  @IsTest
  static void getOwnerOptions_returnsOnlyActiveUsersOfDepartment() {
    User u = testUser();
    List<LeadNewLeadFlowController.Option> options;

    System.runAs(u) {
      Test.startTest();
      options = LeadNewLeadFlowController.getOwnerOptions(TEST_DEPARTMENT, null);
      Test.stopTest();
    }

    Set<String> ids = new Set<String>();
    for (LeadNewLeadFlowController.Option o : options) {
      ids.add(o.value);
    }
    Assert.isTrue(ids.contains(u.Id), 'Active user in the department should be listed');
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM User WHERE LastName = 'LeadFlowUser1' AND Id IN :ids],
      'Inactive users should not be listed'
    );
  }

  @IsTest
  static void createAdminLead_createsLeadFilesAndCategories() {
    User u = testUser();
    Test.setMock(HttpCalloutMock.class, new SuccessMock());
    LeadNewLeadFlowController.LeadRequest req = buildRequest(u.Id);
    req.contentDocumentIds = new List<String>{ createContentDocument() };
    req.categories.add(buildCategory());
    LeadNewLeadFlowController.Result res;

    System.runAs(u) {
      Test.startTest();
      res = LeadNewLeadFlowController.createAdminLead(JSON.serialize(req));
      Test.stopTest();
    }

    Assert.isTrue(res.success, 'Lead creation should succeed: ' + res.message);
    Lead created = [SELECT Id, OwnerId, LeadSource FROM Lead WHERE Id = :res.leadId];
    Assert.areEqual(u.Id, created.OwnerId, 'Lead owner should be the requested owner');
    Assert.areEqual('TENDER', created.LeadSource, 'Lead source should be saved');
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :created.Id],
      'Uploaded file should be linked to the lead'
    );
    Product_Category__c cat = [
      SELECT Lead__c, Status__c, Quantity__c
      FROM Product_Category__c
      WHERE Lead__c = :created.Id
    ];
    Assert.areEqual('Active', cat.Status__c, 'Category should be Active');
    Assert.areEqual(5, cat.Quantity__c, 'Category quantity should be saved');
  }

  @IsTest
  static void createAdminLead_blankOwner_defaultsToRunningUser() {
    User u = testUser();
    Test.setMock(HttpCalloutMock.class, new SuccessMock());
    LeadNewLeadFlowController.Result res;

    System.runAs(u) {
      Test.startTest();
      res = LeadNewLeadFlowController.createAdminLead(JSON.serialize(buildRequest(null)));
      Test.stopTest();
    }

    Assert.isTrue(res.success, 'Lead creation should succeed: ' + res.message);
    Assert.areEqual(
      u.Id,
      [SELECT OwnerId FROM Lead WHERE Id = :res.leadId].OwnerId,
      'A blank owner should default to the running user'
    );
  }

  @IsTest
  static void createAdminLead_blankPayload_returnsFault() {
    User u = testUser();
    LeadNewLeadFlowController.Result res;

    System.runAs(u) {
      Test.startTest();
      res = LeadNewLeadFlowController.createAdminLead('');
      Test.stopTest();
    }

    Assert.isFalse(res.success, 'A blank payload should be reported as a fault');
    Assert.isNotNull(res.message, 'Fault message should be returned');
  }

  @IsTest
  static void createAdminLead_withoutFilesOrCategories_succeeds() {
    User u = testUser();
    Test.setMock(HttpCalloutMock.class, new SuccessMock());
    LeadNewLeadFlowController.Result res;

    System.runAs(u) {
      Test.startTest();
      res = LeadNewLeadFlowController.createAdminLead(JSON.serialize(buildRequest(u.Id)));
      Test.stopTest();
    }

    Assert.isTrue(res.success, 'Lead creation should succeed: ' + res.message);
    Assert.areEqual(1, [SELECT COUNT() FROM Lead WHERE Id = :res.leadId], 'Lead should exist');
  }

  @IsTest
  static void createAdminLead_rollsBackEverythingOnFault() {
    User u = testUser();
    LeadNewLeadFlowController.LeadRequest req = buildRequest(u.Id);
    req.categories.add(buildCategory());
    req.categories[0].quantity = Decimal.valueOf('99999999999999999999'); // exceeds Quantity__c precision
    LeadNewLeadFlowController.Result res;

    System.runAs(u) {
      Test.startTest();
      res = LeadNewLeadFlowController.createAdminLead(JSON.serialize(req));
      Test.stopTest();
    }

    Assert.isFalse(res.success, 'Result should report the fault');
    Assert.isNotNull(res.message, 'Fault message should be returned');
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Lead WHERE Email = 'test.prospect@example.com'],
      'Lead should be rolled back'
    );
  }

  @IsTest
  static void createOthersLead_createsLeadAndCategories() {
    User u = testUser();
    LeadNewLeadFlowController.LeadRequest req = buildRequest(u.Id);
    req.categories.add(buildCategory());
    LeadNewLeadFlowController.Result res;

    System.runAs(u) {
      Test.startTest();
      res = LeadNewLeadFlowController.createOthersLead(JSON.serialize(req));
      Test.stopTest();
    }

    Assert.isTrue(res.success, 'Lead creation should succeed: ' + res.message);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Product_Category__c WHERE Lead__c = :res.leadId],
      'Category should be linked to the lead'
    );
  }

  @IsTest
  static void createOthersLead_keepsLeadWhenCategoriesFail() {
    User u = testUser();
    LeadNewLeadFlowController.LeadRequest req = buildRequest(u.Id);
    req.categories.add(buildCategory());
    req.categories[0].quantity = Decimal.valueOf('99999999999999999999');
    LeadNewLeadFlowController.Result res;

    System.runAs(u) {
      Test.startTest();
      res = LeadNewLeadFlowController.createOthersLead(JSON.serialize(req));
      Test.stopTest();
    }

    Assert.isFalse(res.success, 'Result should report the fault');
    Assert.isNotNull(res.leadId, 'Lead id should be returned');
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Lead WHERE Id = :res.leadId],
      'The flow has no rollback on this path, so the lead is kept'
    );
  }

  @IsTest
  static void createOthersLead_returnsFaultWhenLeadInvalid() {
    User u = testUser();
    LeadNewLeadFlowController.LeadRequest req = buildRequest(u.Id);
    req.lastName = null;
    LeadNewLeadFlowController.Result res;

    System.runAs(u) {
      Test.startTest();
      res = LeadNewLeadFlowController.createOthersLead(JSON.serialize(req));
      Test.stopTest();
    }

    Assert.isFalse(res.success, 'Result should report the fault');
    Assert.isNotNull(res.message, 'Fault message should be returned');
    Assert.isNull(res.leadId, 'No lead should be created');
  }

  @IsTest
  static void sendOthersNotifications_succeedsForExistingLead() {
    User u = testUser();
    Test.setMock(HttpCalloutMock.class, new SuccessMock());
    LeadNewLeadFlowController.Result created;
    LeadNewLeadFlowController.Result res;

    System.runAs(u) {
      created = LeadNewLeadFlowController.createOthersLead(JSON.serialize(buildRequest(u.Id)));
      Test.startTest();
      res = LeadNewLeadFlowController.sendOthersNotifications(created.leadId);
      Test.stopTest();
    }

    Assert.isTrue(res.success, 'Notifications should be queued: ' + res.message);
    Assert.areEqual(created.leadId, res.leadId, 'Lead id should be returned');
  }

  @IsTest
  static void sendOthersNotifications_returnsFaultForInvalidId() {
    User u = testUser();
    LeadNewLeadFlowController.Result res;

    System.runAs(u) {
      Test.startTest();
      res = LeadNewLeadFlowController.sendOthersNotifications('not-an-id');
      Test.stopTest();
    }

    Assert.isFalse(res.success, 'An invalid id should be reported as a fault');
  }
}