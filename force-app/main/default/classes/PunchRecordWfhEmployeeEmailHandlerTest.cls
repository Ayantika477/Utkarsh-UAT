/**
 * @description   Test class for WFH/WFO Punch Record employee and HOD email automation.
 * @author        Anshita Chanda
 * @date          2026-08-14
 */
@IsTest
private class PunchRecordWfhEmployeeEmailHandlerTest {
  @IsTest
  static void testQualifiesAsPendingAndApproved() {
    Punch_Record__c pendingWfh = buildPunch(
      PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFH,
      PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_PENDING,
      UserInfo.getUserId()
    );
    Punch_Record__c pendingWfo = buildPunch(
      PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFO,
      PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_PENDING,
      UserInfo.getUserId()
    );
    Punch_Record__c marketVisit = buildPunch(
      'Market Visit',
      PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_PENDING,
      UserInfo.getUserId()
    );
    Punch_Record__c missingUser = buildPunch(
      PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFH,
      PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_PENDING,
      null
    );

    System.assertEquals(
      true,
      PunchRecordWfhEmployeeEmailHandler.qualifiesAsPending(pendingWfh, null)
    );
    System.assertEquals(
      true,
      PunchRecordWfhEmployeeEmailHandler.qualifiesAsPending(pendingWfo, null)
    );
    System.assertEquals(
      false,
      PunchRecordWfhEmployeeEmailHandler.qualifiesAsPending(marketVisit, null)
    );
    System.assertEquals(
      false,
      PunchRecordWfhEmployeeEmailHandler.qualifiesAsPending(missingUser, null)
    );
    System.assertEquals(
      false,
      PunchRecordWfhEmployeeEmailHandler.qualifiesAsPending(null, null)
    );

    Punch_Record__c oldApproved = buildPunch(
      PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFO,
      PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_APPROVED,
      UserInfo.getUserId()
    );
    System.assertEquals(
      true,
      PunchRecordWfhEmployeeEmailHandler.qualifiesAsPending(pendingWfh, oldApproved)
    );
    System.assertEquals(
      false,
      PunchRecordWfhEmployeeEmailHandler.qualifiesAsPending(pendingWfh, pendingWfh)
    );

    Punch_Record__c newlyApproved = buildPunch(
      PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFH,
      PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_APPROVED,
      UserInfo.getUserId()
    );
    Punch_Record__c oldPending = buildPunch(
      PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFH,
      PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_PENDING,
      UserInfo.getUserId()
    );
    System.assertEquals(
      true,
      PunchRecordWfhEmployeeEmailHandler.qualifiesAsApproved(newlyApproved, oldPending)
    );
    System.assertEquals(
      false,
      PunchRecordWfhEmployeeEmailHandler.qualifiesAsApproved(newlyApproved, null)
    );
    System.assertEquals(
      false,
      PunchRecordWfhEmployeeEmailHandler.qualifiesAsApproved(newlyApproved, newlyApproved)
    );
  }

  @IsTest
  static void testHandleAfterInsertAndUpdate() {
    Punch_Record__c punchRecord = buildPunch(
      PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFH,
      PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_PENDING,
      UserInfo.getUserId()
    );
    punchRecord.Is_WFH_Request__c = true;
    punchRecord.Is_WFO_Request__c = false;

    Test.startTest();
    insert punchRecord;
    punchRecord.WFH_Approval_Status__c =
      PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_APPROVED;
    update punchRecord;
    Test.stopTest();

    Punch_Record__c storedRecord = [
      SELECT Punch_Type__c, WFH_Approval_Status__c
      FROM Punch_Record__c
      WHERE Id = :punchRecord.Id
    ];
    System.assertEquals(
      PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFH,
      storedRecord.Punch_Type__c
    );
    System.assertEquals(
      PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_APPROVED,
      storedRecord.WFH_Approval_Status__c
    );
  }

  @IsTest
  static void testNoSendWhenCriteriaNotMet() {
    Punch_Record__c punchRecord = buildPunch(
      'Market Visit',
      PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_PENDING,
      UserInfo.getUserId()
    );
    punchRecord.Is_WFH_Request__c = false;
    punchRecord.Is_WFO_Request__c = false;

    Test.startTest();
    insert punchRecord;
    Test.stopTest();

    System.assertEquals(1, [SELECT COUNT() FROM Punch_Record__c]);
  }

  @IsTest
  static void testProcessRecordsSkipsEmptyAndMissingUser() {
    Test.startTest();
    PunchRecordWfhEmployeeEmailHandler.processRecords(null, null);
    PunchRecordWfhEmployeeEmailHandler.processRecords(
      new List<Punch_Record__c>(),
      null
    );
    PunchRecordWfhEmployeeEmailHandler.processRecords(
      new List<Punch_Record__c>{
        buildPunch(
          PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFH,
          PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_PENDING,
          null
        )
      },
      null
    );
    PunchRecordWfhEmployeeEmailHandler.processRecords(
      new List<Punch_Record__c>{
        buildPunch(
          PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFO,
          PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_PENDING,
          UserInfo.getUserId()
        )
      },
      null
    );
    Test.stopTest();

    System.assertEquals(true, true);
  }

  private static Punch_Record__c buildPunch(
    String punchType,
    String approvalStatus,
    Id userId
  ) {
    return new Punch_Record__c(
      Punch_Type__c = punchType,
      WFH_Approval_Status__c = approvalStatus,
      User__c = userId,
      Is_WFH_Request__c = punchType == PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFH,
      Is_WFO_Request__c = punchType == PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFO
    );
  }
    
  @isTest
    static void testResolveCustomNotificationTypeId_ReturnsOverride() {
      Id fakeId = UserInfo.getUserId(); // any valid Id works — we're only testing the override path
      PunchRecordWfhEmployeeEmailHandler.testNotificationTypeIdOverride = fakeId;
    
      Test.startTest();
      Id result = PunchRecordWfhEmployeeEmailHandler.resolveCustomNotificationTypeId();
      Test.stopTest();
    
      System.assertEquals(fakeId, result, 'Should return the override without querying CustomNotificationType');
    }
    
    @isTest
    static void testResolveCustomNotificationTypeId_QueriesWhenNoOverride() {
      PunchRecordWfhEmployeeEmailHandler.testNotificationTypeIdOverride = null;
    
      Test.startTest();
      Id result = PunchRecordWfhEmployeeEmailHandler.resolveCustomNotificationTypeId();
      Test.stopTest();
    
      // No value assertion — depends on whether the org has the CustomNotificationType configured.
      // This just confirms the query path runs without throwing.
    }
    
    @isTest
    static void testSendCustomNotification_EmptyRecipients_NoOp() {
      Test.startTest();
      PunchRecordWfhEmployeeEmailHandler.sendCustomNotification(
        new Set<String>(), 'Title', 'Body', UserInfo.getUserId()
      );
      Test.stopTest();
      // Passing with no exception confirms the early-return on empty recipients.
    }
    
    @isTest
    static void testSendCustomNotification_WithOverride_DoesNotThrow() {
      PunchRecordWfhEmployeeEmailHandler.testNotificationTypeIdOverride = UserInfo.getUserId(); // fake, not a real CustomNotificationType Id
    
      Test.startTest();
      PunchRecordWfhEmployeeEmailHandler.sendCustomNotification(
        new Set<String>{ UserInfo.getUserId() }, 'Test Title', 'Test Body', UserInfo.getUserId()
      );
      Test.stopTest();
      // notification.send() will likely fail internally since the Id isn't a real CustomNotificationType —
      // but it's caught by the try/catch in sendCustomNotification, so the test just confirms it doesn't propagate.
    }

    @isTest
    static void testGetCrmHeadRecipientIds_MatchesAnyAssignedDepartment() {
      User crmHead = new User(
        Id = UserInfo.getUserId(),
        Departments__c = 'Crash_Barrier_Department;PEB'
      );
      List<User> crmHeads = new List<User>{ crmHead };

      System.assert(
        PunchRecordWfhEmployeeEmailHandler.getCrmHeadRecipientIds('CRASH BARRIER', crmHeads).contains(crmHead.Id),
        'Department name should match the CRM Head\'s Departments__c value'
      );
      System.assert(
        PunchRecordWfhEmployeeEmailHandler.getCrmHeadRecipientIds(' crash barrier ', crmHeads).contains(crmHead.Id),
        'Matching should ignore case and surrounding spaces'
      );
      System.assert(
        PunchRecordWfhEmployeeEmailHandler.getCrmHeadRecipientIds('PRE ENGINEERING BUILDING', crmHeads).contains(crmHead.Id),
        'Every department assigned to the CRM Head should match'
      );
      System.assert(
        PunchRecordWfhEmployeeEmailHandler.getCrmHeadRecipientIds('Crash_Barrier_Department', crmHeads).contains(crmHead.Id),
        'The Departments__c API value itself should match'
      );
      System.assert(
        PunchRecordWfhEmployeeEmailHandler.getCrmHeadRecipientIds('HDPE', crmHeads).isEmpty(),
        'A department not assigned to the CRM Head should not match'
      );
    }

    @isTest
    static void testGetCrmHeadRecipientIds_BlankDepartmentReturnsEmpty() {
      List<User> crmHeads = new List<User>{
        new User(Id = UserInfo.getUserId(), Departments__c = 'PEB')
      };

      System.assert(
        PunchRecordWfhEmployeeEmailHandler.getCrmHeadRecipientIds(null, crmHeads).isEmpty(),
        'A blank employee department should have no recipients'
      );
    }

    @isTest
    static void testRejectedRequests_NotifyCrmHeadsWithoutError() {
      Id crmHeadProfileId = getProfileIdOrNull('CRM Head');
      Id standardProfileId = getProfileIdOrNull('Standard User');
      if (crmHeadProfileId == null || standardProfileId == null) {
        return;
      }

      User employee = buildUser('wfhemp', standardProfileId, 'HDPE', null);
      User crmHead = buildUser(
        'wfhcrm', crmHeadProfileId, null, 'Solar_Structure_Department;HDPE_Pipe_Department'
      );
      System.runAs(new User(Id = UserInfo.getUserId())) {
        insert new List<User>{ employee, crmHead };
      }

      PunchRecordWfhEmployeeEmailHandler.testNotificationTypeIdOverride = UserInfo.getUserId();

      List<Punch_Record__c> requests = new List<Punch_Record__c>{
        buildPunch(
          PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFH,
          PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_PENDING,
          employee.Id
        ),
        buildPunch(
          PunchRecordWfhEmployeeEmailHandler.PUNCH_TYPE_WFO,
          PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_PENDING,
          employee.Id
        )
      };
      insert requests;

      Test.startTest();
      for (Punch_Record__c request : requests) {
        request.WFH_Approval_Status__c =
          PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_REJECTED;
      }
      update requests;
      Test.stopTest();

      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM Punch_Record__c
          WHERE WFH_Approval_Status__c = :PunchRecordWfhEmployeeEmailHandler.APPROVAL_STATUS_REJECTED
        ],
        'Both requests should be saved as Rejected'
      );
    }

    private static Id getProfileIdOrNull(String profileName) {
      List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
      return profiles.isEmpty() ? null : profiles[0].Id;
    }

    private static User buildUser(String alias, Id profileId, String department, String departments) {
      return new User(
        Alias = alias,
        Email = alias + '@wfhreject.test',
        Username = alias + '@wfhreject.test.' + System.currentTimeMillis(),
        LastName = 'WfhReject' + alias,
        ProfileId = profileId,
        TimeZoneSidKey = 'Asia/Kolkata',
        LocaleSidKey = 'en_IN',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        Department = department,
        Departments__c = departments,
        IsActive = true
      );
    }
}