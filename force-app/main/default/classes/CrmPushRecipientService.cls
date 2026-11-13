/**
 * @description   Resolves Salesforce User Ids for CRM push notification recipients.
 * @author        Anshita Chanda
 * @date          2026-08-17
 */
public without sharing class CrmPushRecipientService {
  private static final String ROLE_UTKARSH_CRM_HEAD = 'Utkarsh CRM Head';
  private static final String CRM_HEAD_SUFFIX = 'CRM Head';
  private static final String CRM_HEAD_PROFILE = 'CRM Head';

  @TestVisible
  private static Set<Id> testUserIdOverrides;

  /**
   * @description Resolves active User Ids for a Case's Department HOD.
   */
  public static Set<Id> resolveCaseDepartmentHodUserIds(Case caseRecord) {
    if (caseRecord == null) {
      return new Set<Id>();
    }

    if (Test.isRunningTest() && testUserIdOverrides != null) {
      return new Set<Id>(testUserIdOverrides);
    }

    Set<Id> recipientUserIds = new Set<Id>();
    String department = resolveCaseDepartmentName(caseRecord);

    if (String.isNotBlank(department)) {
      addActiveUsersInRole(department + ' HOD', recipientUserIds);
    }

    addUserIdByEmail(caseRecord.HOD_User_Email_Formula__c, recipientUserIds);
    return recipientUserIds;
  }

  @TestVisible
  static String resolveCaseDepartmentName(Case caseRecord) {
    String department = String.isNotBlank(caseRecord.Department_formula__c)
      ? caseRecord.Department_formula__c
      : caseRecord.Department__c;
    return EscalationMatrixEmailService.getRoleDepartmentName(department);
  }

  /**
   * @description Resolves active User Ids for a Case's CRM Head.
   */
  public static Set<Id> resolveCaseCrmHeadUserIds(Case caseRecord) {
    if (caseRecord == null) {
      return new Set<Id>();
    }

    if (Test.isRunningTest() && testUserIdOverrides != null) {
      return new Set<Id>(testUserIdOverrides);
    }

    Set<Id> recipientUserIds = new Set<Id>();
    addActiveUsersInRole(ROLE_UTKARSH_CRM_HEAD, recipientUserIds);
    addUserIdByEmail(caseRecord.CRM_User_Email_Formula__c, recipientUserIds);
    addDepartmentCrmHeadUsers(resolveCaseDepartmentKey(caseRecord), recipientUserIds);
    return recipientUserIds;
  }

  // Role names use the raw Case Department value (e.g. 'Transmission & Telecom Tower CRM Head'),
  // so the HOD role mapping in getRoleDepartmentName must not be applied here.
  @TestVisible
  static String resolveCaseDepartmentKey(Case caseRecord) {
    if (caseRecord == null) {
      return null;
    }
    String department = String.isNotBlank(caseRecord.Department_formula__c)
      ? caseRecord.Department_formula__c
      : caseRecord.Department__c;
    return String.isBlank(department) ? null : department.trim();
  }

  @TestVisible
  private static void addDepartmentCrmHeadUsers(String department, Set<Id> recipientUserIds) {
    if (String.isBlank(department) || recipientUserIds == null) {
      return;
    }

    addActiveUsersInRole(department + ' ' + CRM_HEAD_SUFFIX, recipientUserIds);

    // A CRM Head can cover several departments in User.Department (e.g. 'HDPE, Solar Structure').
    String departmentPattern = '%' + department + '%';
    for (User userRecord : [
      SELECT Id
      FROM User
      WHERE IsActive = TRUE
        AND Profile.Name = :CRM_HEAD_PROFILE
        AND Department LIKE :departmentPattern
    ]) {
      recipientUserIds.add(userRecord.Id);
    }
  }

  /**
   * @description Resolves active User Ids for an Opportunity's Department HOD and CRM Head.
   */
  public static Set<Id> resolveOpportunityHodAndCrmHeadUserIds(
    Opportunity opportunityRecord
  ) {
    if (opportunityRecord == null) {
      return new Set<Id>();
    }

    if (Test.isRunningTest() && testUserIdOverrides != null) {
      return new Set<Id>(testUserIdOverrides);
    }

    Set<Id> recipientUserIds = new Set<Id>();
    String department = resolveDepartmentName(opportunityRecord);

    if (String.isNotBlank(department)) {
      addActiveUsersInRole(department + ' HOD', recipientUserIds);
      addActiveUsersInRole(department + ' CRM User', recipientUserIds);
    }

    addActiveUsersInRole(ROLE_UTKARSH_CRM_HEAD, recipientUserIds);
    addUserIdByEmail(
      opportunityRecord.CRM_User_Email_Formula__c,
      recipientUserIds
    );

    return recipientUserIds;
  }

  @TestVisible
  static String resolveDepartmentName(Opportunity opportunityRecord) {
    String department = String.isNotBlank(opportunityRecord.Department_NameFormula__c)
      ? opportunityRecord.Department_NameFormula__c
      : opportunityRecord.Department_Name__c;
    return EscalationMatrixEmailService.getRoleDepartmentName(department);
  }

  private static void addActiveUsersInRole(String roleName, Set<Id> recipientUserIds) {
    if (String.isBlank(roleName) || recipientUserIds == null) {
      return;
    }

    for (User userRecord : [
      SELECT Id
      FROM User
      WHERE IsActive = TRUE AND UserRole.Name = :roleName
    ]) {
      recipientUserIds.add(userRecord.Id);
    }
  }

  private static void addUserIdByEmail(String emailAddress, Set<Id> recipientUserIds) {
    if (String.isBlank(emailAddress) || recipientUserIds == null) {
      return;
    }

    for (User userRecord : [
      SELECT Id
      FROM User
      WHERE IsActive = TRUE AND Email = :emailAddress.trim()
      LIMIT 1
    ]) {
      recipientUserIds.add(userRecord.Id);
    }
  }

  public static void clearTestState() {
    testUserIdOverrides = null;
  }
}