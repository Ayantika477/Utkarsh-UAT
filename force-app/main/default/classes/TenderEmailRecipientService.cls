/**
 * @description   Resolves active internal Users for Tender email recipients so HOD, CRM Head
 *                and Tender Owner emails can be sent by User Id. Emails sent to a User Id do
 *                not count toward the org's daily single-email limit; recipients without a
 *                matching active User keep being emailed by address.
 * @author        Anshita Chanda
 * @date          2026-11-03
 */
public without sharing class TenderEmailRecipientService {
  public static final String PROFILE_HOD = 'Utkarsh HOD';
  public static final String PROFILE_CRM_HEAD = 'CRM Head';

  /**
   * @description Active internal Users with the given profile, keyed by each department
   *              (lower-cased) listed in User.Department. User.Department may hold several
   *              departments separated by commas (e.g. "HDPE, Solar Structure").
   */
  public static Map<String, List<User>> resolveUsersByProfileDepartment(
    String profileName,
    Set<String> departments
  ) {
    Map<String, List<User>> usersByDepartment = new Map<String, List<User>>();
    Set<String> wantedDepartments = new Set<String>();
    if (departments != null) {
      for (String department : departments) {
        if (String.isNotBlank(department)) {
          wantedDepartments.add(department.trim().toLowerCase());
        }
      }
    }
    if (String.isBlank(profileName) || wantedDepartments.isEmpty()) {
      return usersByDepartment;
    }

    for (User activeUser : [
      SELECT Id, Email, Department
      FROM User
      WHERE
        IsActive = TRUE
        AND UserType = 'Standard'
        AND Profile.Name = :profileName
        AND Department != NULL
        AND Email != NULL
      WITH SYSTEM_MODE
      ORDER BY CreatedDate ASC
    ]) {
      for (String userDepartment : activeUser.Department.split(',')) {
        String key = userDepartment.trim().toLowerCase();
        if (!wantedDepartments.contains(key)) {
          continue;
        }
        if (!usersByDepartment.containsKey(key)) {
          usersByDepartment.put(key, new List<User>());
        }
        usersByDepartment.get(key).add(activeUser);
      }
    }
    return usersByDepartment;
  }

  public static List<User> findUsersForDepartment(
    Map<String, List<User>> usersByDepartment,
    String department
  ) {
    if (usersByDepartment == null || String.isBlank(department)) {
      return new List<User>();
    }
    List<User> users = usersByDepartment.get(department.trim().toLowerCase());
    return users == null ? new List<User>() : users;
  }
  /**
   * @description Maps each email (lower-cased) to an active internal User with exactly that email.
   */
  public static Map<String, Id> resolveActiveUserIdsByEmail(Set<String> emails) {
    Map<String, Id> userIdByEmail = new Map<String, Id>();
    Set<String> normalizedEmails = new Set<String>();
    if (emails != null) {
      for (String email : emails) {
        if (String.isNotBlank(email)) {
          normalizedEmails.add(email.trim().toLowerCase());
        }
      }
    }
    if (normalizedEmails.isEmpty()) {
      return userIdByEmail;
    }

    for (User activeUser : [
      SELECT Id, Email
      FROM User
      WHERE IsActive = TRUE AND UserType = 'Standard' AND Email IN :normalizedEmails
      WITH SYSTEM_MODE
      ORDER BY CreatedDate ASC
    ]) {
      String key = activeUser.Email.toLowerCase();
      if (!userIdByEmail.containsKey(key)) {
        userIdByEmail.put(key, activeUser.Id);
      }
    }
    return userIdByEmail;
  }

  public static Id findUserIdByEmail(Map<String, Id> userIdByEmail, String email) {
    if (userIdByEmail == null || String.isBlank(email)) {
      return null;
    }
    return userIdByEmail.get(email.trim().toLowerCase());
  }

  /**
   * @description Returns the subset of the given Ids that are active internal Users.
   */
  public static Set<Id> resolveActiveUserIds(Set<Id> userIds) {
    Set<Id> activeUserIds = new Set<Id>();
    if (userIds == null || userIds.isEmpty()) {
      return activeUserIds;
    }
    for (User activeUser : [
      SELECT Id
      FROM User
      WHERE Id IN :userIds AND IsActive = TRUE AND UserType = 'Standard'
      WITH SYSTEM_MODE
    ]) {
      activeUserIds.add(activeUser.Id);
    }
    return activeUserIds;
  }

  /**
   * @description Copies a rendered template into a new message addressed to a User Id.
   *              Salesforce rejects a WhatId with a User target and cannot save it as an activity.
   */
  public static Messaging.SingleEmailMessage buildUserMessage(
    Messaging.SingleEmailMessage rendered,
    Id userId,
    Id oweaId
  ) {
    if (rendered == null || userId == null) {
      return null;
    }
    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    if (String.isNotBlank(rendered.getSubject())) {
      mail.setSubject(rendered.getSubject());
    }
    if (String.isNotBlank(rendered.getHtmlBody())) {
      mail.setHtmlBody(rendered.getHtmlBody());
    }
    if (String.isNotBlank(rendered.getPlainTextBody())) {
      mail.setPlainTextBody(rendered.getPlainTextBody());
    }
    mail.setTargetObjectId(userId);
    mail.setSaveAsActivity(false);
    if (oweaId != null) {
      mail.setOrgWideEmailAddressId(oweaId);
    }
    return mail;
  }
}