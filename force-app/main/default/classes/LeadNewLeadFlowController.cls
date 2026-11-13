/**
 * Server side for the leadNewLeadFlow LWC (LWC version of the "Lead: New Lead Flow" flow).
 * The flow runs in SystemModeWithoutSharing, hence "without sharing".
 */
public without sharing class LeadNewLeadFlowController {
  public class InitData {
    @AuraEnabled
    public String userId;
    @AuraEnabled
    public String profileName;
    @AuraEnabled
    public String department;
    @AuraEnabled
    public String roleName;
    @AuraEnabled
    public String tenderProfileId;
  }

  public class Option {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    public Option(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class CategoryRow {
    @AuraEnabled
    public String department;
    @AuraEnabled
    public String productCategory;
    @AuraEnabled
    public String uom;
    @AuraEnabled
    public Decimal quantity;
  }

  public class LeadRequest {
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String company;
    @AuraEnabled
    public String companyName;
    @AuraEnabled
    public String country;
    @AuraEnabled
    public String customerCategory;
    @AuraEnabled
    public String departmentName;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String firstName;
    @AuraEnabled
    public String industry;
    @AuraEnabled
    public String lastName;
    @AuraEnabled
    public String leadSource;
    @AuraEnabled
    public String ownerId;
    @AuraEnabled
    public String pin;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String previousSource;
    @AuraEnabled
    public String rating;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String street;
    @AuraEnabled
    public String zone;
    @AuraEnabled
    public List<String> contentDocumentIds;
    @AuraEnabled
    public List<CategoryRow> categories;
  }

  public class Result {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String leadId;
    @AuraEnabled
    public String message;
  }

  @AuraEnabled
  public static InitData getInitData() {
    User u = [
      SELECT Id, Department, Profile.Name, UserRole.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
    ];
    InitData d = new InitData();
    d.userId = u.Id;
    d.profileName = u.Profile.Name;
    d.department = u.Department;
    d.roleName = u.UserRole?.Name;
    List<Profile> tender = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Utkarsh Tender'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    d.tenderProfileId = tender.isEmpty() ? null : tender[0].Id;
    return d;
  }

  // Dynamic choice set "DepartmentUserOwnerAdmin"
  @AuraEnabled
  public static List<Option> getOwnerOptions(String department, String tenderProfileId) {
    List<Option> options = new List<Option>();
    String deptLike = '%' + (department == null ? '' : department) + '%';
    for (User u : [
      SELECT Id, Name
      FROM User
      WHERE
        Department LIKE :deptLike
        AND ProfileId != :tenderProfileId
        AND IsActive = TRUE
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT 2000
    ]) {
      options.add(new Option(u.Name, u.Id));
    }
    return options;
  }

  // getUploadedContentDocument -> Create Lead Admin -> create Content Document Link -> Create/Update Product Categories -> email + message.
  // Any failure rolls everything back (rollBack Records) and is shown on the FaultScreen.
  @AuraEnabled
  public static Result createAdminLead(String requestJson) {
    Result res = new Result();
    Savepoint sp = Database.setSavepoint();
    try {
      LeadRequest req = parseRequest(requestJson);
      // getUploadedContentDocument
      List<ContentDocument> docs = new List<ContentDocument>();
      if (req.contentDocumentIds != null && !req.contentDocumentIds.isEmpty()) {
        docs = [SELECT Id FROM ContentDocument WHERE Id IN :req.contentDocumentIds WITH SYSTEM_MODE];
      }

      Lead l = buildLead(req);
      insert as system l;

      // Looping through Docs -> create Content Document Link
      List<ContentDocumentLink> links = new List<ContentDocumentLink>();
      for (ContentDocument doc : docs) {
        links.add(
          new ContentDocumentLink(
            ContentDocumentId = doc.Id,
            LinkedEntityId = l.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
          )
        );
      }
      insert as system links;

      saveCategories(req.categories, l.Id);
      sendNotifications(l.Id);

      res.success = true;
      res.leadId = l.Id;
    } catch (Exception e) {
      Database.rollback(sp);
      res.success = false;
      res.message = e.getMessage();
    }
    return res;
  }

  // Create Lead Others -> Create/Update Product Categories. Records already created are kept on a fault
  // (the flow has no rollback on this path).
  @AuraEnabled
  public static Result createOthersLead(String requestJson) {
    Result res = new Result();
    LeadRequest req;
    Lead l;
    try {
      req = parseRequest(requestJson);
      l = buildLead(req);
      insert as system l;
      res.leadId = l.Id;
    } catch (Exception e) {
      res.success = false;
      res.message = e.getMessage();
      return res;
    }
    try {
      saveCategories(req.categories, l.Id);
      res.success = true;
    } catch (Exception e) {
      res.success = false;
      res.message = e.getMessage();
    }
    return res;
  }

  // Send Prospect Enq Email Others -> Send Prospect Enq Messaging Others
  @AuraEnabled
  public static Result sendOthersNotifications(String leadId) {
    Result res = new Result();
    try {
      sendNotifications(leadId);
      res.success = true;
      res.leadId = leadId;
    } catch (Exception e) {
      res.success = false;
      res.message = e.getMessage();
    }
    return res;
  }

  // The LWC sends the payload as a JSON string; this avoids relying on Aura binding of nested Apex types
  private static LeadRequest parseRequest(String requestJson) {
    if (String.isBlank(requestJson)) {
      throw new IllegalArgumentException('The lead details were not received.');
    }
    return (LeadRequest) JSON.deserialize(requestJson, LeadRequest.class);
  }

  private static Lead buildLead(LeadRequest req) {
    Lead l = new Lead(
      City__c = req.city,
      Company = req.company,
      Company_Name__c = req.companyName,
      Country__c = req.country,
      Customer_Category__c = req.customerCategory,
      Department_Name__c = req.departmentName,
      Email = req.email,
      FirstName = req.firstName,
      Industry = req.industry,
      LastName = req.lastName,
      LeadSource = req.leadSource,
      PIN__c = req.pin,
      Phone = req.phone,
      Previous_Source__c = req.previousSource,
      Rating = req.rating,
      State__c = req.state,
      Status = req.status,
      Street__c = req.street,
      Zone__c = req.zone
    );
    // An explicit null OwnerId fails the insert (owner cannot be blank), so fall back to the running user
    // which is the platform default when no owner is supplied.
    l.OwnerId = String.isNotBlank(req.ownerId) ? (Id) req.ownerId : UserInfo.getUserId();
    return l;
  }

  // The flow created the Product Category records first and then updated them with the
  // Lead Id; that second update tripped the Product_Category_Edit_Stop validation rule
  // (NOT(ISNEW()) is true on it), so the Lead Id is now set on the insert itself.
  private static void saveCategories(List<CategoryRow> rows, Id leadId) {
    List<Product_Category__c> cats = new List<Product_Category__c>();
    if (rows != null) {
      for (CategoryRow r : rows) {
        cats.add(
          new Product_Category__c(
            Department_Name__c = r.department,
            Product_Category__c = r.productCategory,
            UOM__c = r.uom,
            Quantity__c = r.quantity,
            Status__c = 'Active',
            Lead__c = leadId
          )
        );
      }
    }
    insert as system cats;
    // for (Product_Category__c c : cats) {
    //   c.Lead__c = leadId;
    // }
    // update as system cats;
  }

  private static void sendNotifications(Id leadId) {
    BWM_SendEmailInvocable.Request emailReq = new BWM_SendEmailInvocable.Request();
    emailReq.recordId = leadId;
    emailReq.triggerPoint = 'Email_Lead_Create';
    BWM_SendEmailInvocable.sendEmail(
      new List<BWM_SendEmailInvocable.Request>{ emailReq }
    );

    BWM_SendMessageInvocable.Request msgReq = new BWM_SendMessageInvocable.Request();
    msgReq.recordId = leadId;
    msgReq.triggerPoint = 'Lead_Create';
    BWM_SendMessageInvocable.sendMessage(
      new List<BWM_SendMessageInvocable.Request>{ msgReq }
    );
  }

}