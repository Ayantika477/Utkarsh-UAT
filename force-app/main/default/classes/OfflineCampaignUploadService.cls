public with sharing class OfflineCampaignUploadService {
  public static final Set<String> DEPARTMENT_VALUES = new Set<String>{
    'High Mast & Polygonal',
    'Steel Pipes',
    'Crash Barrier',
    'Steel Tubular Poles',
    'Polymer',
    'HDPE',
    'Transmission & Telecom Tower',
    'Pre Engineering Building',
    'Solar Structure',
    'Railway Electrification Structure',
    'Enquiry'
  };

  public class UploadRow {
    @AuraEnabled public String rowKey;
    @AuraEnabled public String recordName;
    @AuraEnabled public String email;
    @AuraEnabled public String phone;
    @AuraEnabled public String department;
    @AuraEnabled public Boolean active;
  }

  public class RowResult {
    @AuraEnabled public String rowKey;
    @AuraEnabled public Boolean success;
    @AuraEnabled public String errors;
    @AuraEnabled public Id recordId;
  }

  public class InsertSummary {
    @AuraEnabled public Integer totalCount;
    @AuraEnabled public Integer successCount;
    @AuraEnabled public Integer failedCount;
    @AuraEnabled public List<RowResult> rowResults;
    @AuraEnabled public List<String> errorSummary;
  }

  public class PicklistOption {
    @AuraEnabled public String label;
    @AuraEnabled public String value;
  }

  public static List<PicklistOption> getDepartmentOptions() {
    List<PicklistOption> options = new List<PicklistOption>();
    for (String value : new List<String>(DEPARTMENT_VALUES)) {
      PicklistOption option = new PicklistOption();
      option.label = value;
      option.value = value;
      options.add(option);
    }
    options.sort(new PicklistOptionComparator());
    return options;
  }

  public static List<UploadRow> parseUploadRows(String rowsJson) {
    if (String.isBlank(rowsJson)) {
      throw new AuraHandledException('No rows were provided for insert.');
    }
    try {
      return (List<UploadRow>) JSON.deserialize(rowsJson, List<UploadRow>.class);
    } catch (Exception ex) {
      throw new AuraHandledException('Invalid row data: ' + ex.getMessage());
    }
  }

  public static InsertSummary insertRows(List<UploadRow> rows) {
    if (rows == null || rows.isEmpty()) {
      throw new AuraHandledException('No rows were provided for insert.');
    }

    InsertSummary summary = new InsertSummary();
    summary.totalCount = rows.size();
    summary.successCount = 0;
    summary.failedCount = 0;
    summary.rowResults = new List<RowResult>();
    summary.errorSummary = new List<String>();

    List<Offline_Campaign__c> recordsToInsert = new List<Offline_Campaign__c>();
    Map<Integer, UploadRow> indexToRow = new Map<Integer, UploadRow>();

    for (Integer index = 0; index < rows.size(); index++) {
      UploadRow row = rows[index];
      RowResult validationResult = validateRow(row);
      if (!validationResult.success) {
        summary.failedCount++;
        summary.rowResults.add(validationResult);
        addErrorSummary(summary.errorSummary, validationResult.errors);
        continue;
      }

      recordsToInsert.add(buildRecord(row));
      indexToRow.put(recordsToInsert.size() - 1, row);
    }

    if (!recordsToInsert.isEmpty()) {
      Database.SaveResult[] saveResults = Database.insert(recordsToInsert, false);
      for (Integer index = 0; index < saveResults.size(); index++) {
        Database.SaveResult saveResult = saveResults[index];
        UploadRow sourceRow = indexToRow.get(index);
        RowResult rowResult = new RowResult();
        rowResult.rowKey = sourceRow.rowKey;

        if (saveResult.isSuccess()) {
          rowResult.success = true;
          rowResult.recordId = saveResult.getId();
          summary.successCount++;
        } else {
          rowResult.success = false;
          rowResult.errors = formatSaveErrors(saveResult.getErrors());
          summary.failedCount++;
          addErrorSummary(summary.errorSummary, rowResult.errors);
        }
        summary.rowResults.add(rowResult);
      }
    }

    return summary;
  }

  @TestVisible
  static RowResult validateRow(UploadRow row) {
    RowResult result = new RowResult();
    result.rowKey = row == null ? null : row.rowKey;
    result.success = true;

    List<String> errors = new List<String>();
    if (row == null) {
      errors.add('Name: Row is empty.');
      result.success = false;
      result.errors = String.join(errors, ' ');
      return result;
    }

    if (String.isBlank(row.recordName)) {
      errors.add('Name: Name is required.');
    } else if (row.recordName.length() > 80) {
      errors.add('Name: Name cannot exceed 80 characters.');
    }

    if (String.isNotBlank(row.email) && !isValidEmail(row.email)) {
      errors.add('Email: Invalid email format.');
    }

    if (String.isNotBlank(row.phone) && !isValidPhone(row.phone)) {
      errors.add('Phone: Invalid phone format.');
    }

    if (String.isNotBlank(row.department) && !DEPARTMENT_VALUES.contains(row.department)) {
      errors.add('Department: Invalid picklist value.');
    }

    if (!errors.isEmpty()) {
      result.success = false;
      result.errors = String.join(errors, ' ');
    }

    return result;
  }

  @TestVisible
  static Offline_Campaign__c buildRecord(UploadRow row) {
    Offline_Campaign__c record = new Offline_Campaign__c();
    record.Name = row.recordName.trim();
    record.Email__c = String.isBlank(row.email) ? null : row.email.trim();
    record.Phone__c = String.isBlank(row.phone) ? null : row.phone.trim();
    record.Department__c = String.isBlank(row.department) ? null : row.department.trim();
    record.Active__c = true;
    return record;
  }

  @TestVisible
  static Boolean isValidPhone(String phone) {
    if (String.isBlank(phone)) {
      return false;
    }
    String digitsOnly = phone.replaceAll('[^0-9]', '');
    return digitsOnly.length() >= 10;
  }

  @TestVisible
  static Boolean isValidEmail(String email) {
    if (String.isBlank(email)) {
      return false;
    }
    return Pattern.matches(
      '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$',
      email.trim()
    );
  }

  @TestVisible
  static String formatSaveErrors(List<Database.Error> errors) {
    List<String> messages = new List<String>();
    for (Database.Error error : errors) {
      String fieldLabel = mapFieldToLabel(error.getFields());
      messages.add(fieldLabel + ': ' + error.getMessage());
    }
    return String.join(messages, ' ');
  }

  private static String mapFieldToLabel(List<String> fields) {
    if (fields == null || fields.isEmpty()) {
      return 'Record';
    }
    String fieldName = fields[0];
    if (fieldName == 'Name') {
      return 'Name';
    }
    if (fieldName == 'Email__c') {
      return 'Email';
    }
    if (fieldName == 'Phone__c') {
      return 'Phone';
    }
    if (fieldName == 'Department__c') {
      return 'Department';
    }
    if (fieldName == 'Active__c') {
      return 'Active';
    }
    return fieldName;
  }

  private static void addErrorSummary(List<String> summary, String errors) {
    if (String.isBlank(errors)) {
      return;
    }
    String trimmed = errors.trim();
    if (!summary.contains(trimmed)) {
      summary.add(trimmed);
    }
  }

  private class PicklistOptionComparator implements Comparator<PicklistOption> {
    public Integer compare(PicklistOption left, PicklistOption right) {
      if (left == null && right == null) {
        return 0;
      }
      if (left == null) {
        return -1;
      }
      if (right == null) {
        return 1;
      }
      return left.label.compareTo(right.label);
    }
  }
}