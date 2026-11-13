/**
 * LeadConversionScreenController
 *
 * Apex backend for the leadConversionScreen LWC - an LWC/Apex re-implementation of the
 * "Lead Conversion Flow" screen flow (v67), built to run alongside the flow during migration.
 * The flow remains active; nothing here is referenced by it.
 *
 * Reuses the same invocable classes the flow calls:
 *   - LeadConversionProcess.convertLead()  (account/contact/opportunity conversion)
 *   - AddressBookProcessor.process()       (address book linking)
 *
 * Flow parity notes:
 *   - Flow runs in SystemModeWithoutSharing -> this class is "without sharing".
 *   - Entry point is the Task record (recordId input), lead resolved via Task.WhoId.
 *   - Department "Enquiry" is not allowed for conversion.
 *   - After conversion the Lead's department/owner are restored to their original
 *     values if the user changed them on screen (flow: back_update_department /
 *     update_Lead_Owner_to_previous).
 */
public without sharing class LeadConversionScreenController {

    // ---------- DTOs ----------

    public class InitData {
        @AuraEnabled public String taskId;
        @AuraEnabled public String leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String company;
        @AuraEnabled public String companyName;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String pin;
        @AuraEnabled public String country;
        @AuraEnabled public String state;
        @AuraEnabled public String zone;
        @AuraEnabled public String customerCategory;
        @AuraEnabled public String department;        // Department_NameFormula__c
        @AuraEnabled public String departmentRaw;     // Department_Name__c
        @AuraEnabled public Boolean isEnquiry;
        @AuraEnabled public String leadSource;
        @AuraEnabled public String docRequired;
        @AuraEnabled public Boolean hasFile;
        @AuraEnabled public Date defaultClosureDate;
        @AuraEnabled public List<PicklistOption> departments;
        @AuraEnabled public List<PicklistOption> customerCategories;
        @AuraEnabled public List<PicklistOption> countries;
        @AuraEnabled public List<PicklistOption> states;
        @AuraEnabled public List<PicklistOption> zones;
        @AuraEnabled public List<PicklistOption> uoms;
        @AuraEnabled public Map<String, List<String>> productCategoriesByDepartment;
        @AuraEnabled public List<ExistingProductCategory> existingProductCategories;
        @AuraEnabled public List<MatchingAccount> matchingAccounts;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PicklistOption(String l, String v) { label = l; value = v; }
    }

    public class ExistingProductCategory {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String productCategory;
        @AuraEnabled public String uom;
        @AuraEnabled public Decimal quantity;
    }

    public class MatchingAccount {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
    }

    public class ContactOption {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
    }

    public class AddressBookOption {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
    }

    // Conversion request. All lookups typed as String on purpose:
    // Id-typed fields in @AuraEnabled input classes deserialize as null from LWC.
    public class ConversionRequest {
        public String taskId;
        public String useExistingAccount;   // 'true' / 'false'
        public String accountId;            // when using existing
        public String accountName;          // when creating new
        public String parentAccountId;      // when new account is a Site
        public String selectedAddressBookId;
        public String street;
        public String city;
        public String pin;
        public String country;
        public String state;
        public String zone;
        public String companyName;
        public String customerCategory;
        public String department;
        public String email;
        public String note;
        public String tentativeClosureDate; // yyyy-MM-dd
        public Boolean createContact;
        public String contactId;            // when selecting existing contact
        public String ownerId;
        public List<ProductRow> productRows;
    }

    public class ProductRow {
        public String department;
        public String productCategory;
        public String uom;
        public Decimal quantity;
    }

    public class ConversionResult {
        @AuraEnabled public String accountId;
        @AuraEnabled public String contactId;
        @AuraEnabled public String opportunityId;
        @AuraEnabled public String status;
    }

    // ---------- Helpers ----------

    // The component can be launched from a Task (flow-parity: lead via Task.WhoId)
    // or directly from a Lead quick action (recordId is the Lead itself).
    private static Id resolveLeadId(String recordId) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('No record Id was provided.');
        }
        Id recId;
        try {
            recId = Id.valueOf(recordId);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid record Id.');
        }
        if (recId.getSobjectType() == Lead.SObjectType) {
            return recId;
        }
        if (recId.getSobjectType() == Task.SObjectType) {
            Task t = [SELECT WhoId FROM Task WHERE Id = :recId WITH SYSTEM_MODE LIMIT 1];
            if (t.WhoId == null || t.WhoId.getSobjectType() != Lead.SObjectType) {
                throw new AuraHandledException('This task is not linked to a Lead.');
            }
            return t.WhoId;
        }
        throw new AuraHandledException('Launch this component from a Lead or a Task linked to a Lead.');
    }

    // ---------- Init ----------

    @AuraEnabled(cacheable=false)
    public static InitData getInitData(String taskId) {
        // Accepts either a Task Id (flow-parity entry: lead via Task.WhoId)
        // or a Lead Id directly (quick action button on the Lead record).
        Id leadRecordId = resolveLeadId(taskId);

        Lead ld = [
            SELECT Id, Name, Company, Company_Name__c, Email, Phone, Street__c, City__c, PIN__c,
                   Country__c, State__c, Zone__c, Customer_Category__c, Department_Name__c,
                   Department_NameFormula__c, Lead_Stage_custom_formula__c, LeadSource,
                   Doc_Required__c, Notes__c, OwnerId, Owner.Name
            FROM Lead WHERE Id = :leadRecordId WITH SYSTEM_MODE LIMIT 1
        ];

        InitData d = new InitData();
        d.taskId = taskId;
        d.leadId = ld.Id;
        d.leadName = ld.Name;
        d.company = ld.Company;
        d.companyName = ld.Company_Name__c;
        d.ownerName = ld.Owner.Name;
        d.email = ld.Email;
        d.phone = ld.Phone;
        d.street = ld.Street__c;
        d.city = ld.City__c;
        d.pin = ld.PIN__c;
        d.country = ld.Country__c;
        d.state = ld.State__c;
        d.zone = ld.Zone__c;
        d.customerCategory = ld.Customer_Category__c;
        d.department = ld.Department_NameFormula__c;
        d.departmentRaw = ld.Department_Name__c;
        d.isEnquiry = ld.Department_Name__c == 'Enquiry';
        d.leadSource = ld.LeadSource;
        d.docRequired = ld.Doc_Required__c;
        d.hasFile = ![SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :ld.Id WITH SYSTEM_MODE LIMIT 1].isEmpty();
        d.defaultClosureDate = Date.today().addDays(7);

        d.departments = picklist(Lead.Department_Name__c);
        d.customerCategories = picklist(Lead.Customer_Category__c);
        d.countries = picklist(Lead.Country__c);
        d.states = picklist(Lead.State__c);
        d.zones = picklist(Lead.Zone__c);
        d.uoms = picklist(Lead.UOM__c);
        d.productCategoriesByDepartment = dependentPicklist(
            Product_Category__c.Department_Name__c, Product_Category__c.Product_Category__c);

        d.existingProductCategories = new List<ExistingProductCategory>();
        for (Product_Category__c pc : [
            SELECT Id, Name, Product_Category__c, UOM__c, Quantity__c
            FROM Product_Category__c
            WHERE Lead__c = :ld.Id AND Department_Name__c = :ld.Department_Name__c
            WITH SYSTEM_MODE
        ]) {
            ExistingProductCategory e = new ExistingProductCategory();
            e.id = pc.Id; e.name = pc.Name; e.productCategory = pc.Product_Category__c;
            e.uom = pc.UOM__c; e.quantity = pc.Quantity__c;
            d.existingProductCategories.add(e);
        }

        // Accounts matching the lead's email or phone (flow: Account_with_Matching_Email_Phone_With_lead)
        d.matchingAccounts = new List<MatchingAccount>();
        if (String.isNotBlank(ld.Email) || String.isNotBlank(ld.Phone)) {
            for (Account a : [
                SELECT Id, Name FROM Account
                WHERE (Email__c = :ld.Email AND Email__c != null) OR (Phone = :ld.Phone AND Phone != null)
                WITH SYSTEM_MODE
                LIMIT 50
            ]) {
                MatchingAccount m = new MatchingAccount();
                m.id = a.Id; m.name = a.Name;
                d.matchingAccounts.add(m);
            }
        }
        return d;
    }

    @AuraEnabled(cacheable=true)
    public static List<ContactOption> getContacts(String accountId) {
        List<ContactOption> result = new List<ContactOption>();
        for (Contact c : [SELECT Id, Name FROM Contact WHERE AccountId = :accountId WITH SYSTEM_MODE LIMIT 200]) {
            ContactOption o = new ContactOption();
            o.id = c.Id; o.name = c.Name;
            result.add(o);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<AddressBookOption> getAddressBooks(String accountId) {
        List<AddressBookOption> result = new List<AddressBookOption>();
        for (Address_Book__c ab : [
            SELECT Id, Street__c, City__c, State__c, PIN__c
            FROM Address_Book__c WHERE Account__c = :accountId WITH SYSTEM_MODE LIMIT 200
        ]) {
            AddressBookOption o = new AddressBookOption();
            o.id = ab.Id;
            o.label = joinNonBlank(new List<String>{ ab.Street__c, ab.City__c, ab.State__c, ab.PIN__c });
            result.add(o);
        }
        return result;
    }

    // Active users whose Department contains the given department (flow: DepartmentUserOwner)
    @AuraEnabled(cacheable=true)
    public static List<ContactOption> getOwnerOptions(String department) {
        String pattern = '%' + String.escapeSingleQuotes(department) + '%';
        List<ContactOption> result = new List<ContactOption>();
        for (User u : [
            SELECT Id, Name FROM User
            WHERE Department LIKE :pattern AND IsActive = true
            WITH SYSTEM_MODE
            ORDER BY Name LIMIT 500
        ]) {
            ContactOption o = new ContactOption();
            o.id = u.Id; o.name = u.Name;
            result.add(o);
        }
        return result;
    }

    // Type-ahead search across all accounts for the existing-account combobox
    @AuraEnabled(cacheable=true)
    public static List<MatchingAccount> searchAccounts(String searchTerm) {
        List<MatchingAccount> result = new List<MatchingAccount>();
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) { return result; }
        String key = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        for (Account a : [SELECT Id, Name FROM Account WHERE Name LIKE :key WITH SYSTEM_MODE ORDER BY Name LIMIT 20]) {
            MatchingAccount m = new MatchingAccount();
            m.id = a.Id; m.name = a.Name;
            result.add(m);
        }
        return result;
    }

    // ---------- Conversion ----------

    @AuraEnabled
    public static ConversionResult convert(String reqJson) {
        ConversionRequest req;
        try {
            req = (ConversionRequest) JSON.deserialize(reqJson, ConversionRequest.class);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid request payload.');
        }

        if (req.department == 'Enquiry') {
            throw new AuraHandledException('Please select a department other than Enquiry.');
        }

        Id leadRecordId = resolveLeadId(req.taskId);
        Lead ld = [
            SELECT Id, OwnerId, Department_Name__c, Department_NameFormula__c,
                   Lead_Stage_custom_formula__c, Notes__c, Email, Phone, LastName,
                   LeadSource, Street__c, PIN__c, Doc_Required__c
            FROM Lead WHERE Id = :leadRecordId WITH SYSTEM_MODE LIMIT 1
        ];

        Id previousOwnerId = ld.OwnerId;
        String previousDepartment = ld.Department_NameFormula__c;
        String closingStage = ld.Lead_Stage_custom_formula__c;
        Boolean useExisting = req.useExistingAccount == 'true';

        Savepoint sp = Database.setSavepoint();
        try {
            // 1. Account (flow: create_an_Account)
            Id accountId;
            if (useExisting) {
                accountId = Id.valueOf(req.accountId);
            } else {
                Account acc = new Account(
                    Name = req.accountName,
                    AccountSource = ld.LeadSource,
                    City__c = req.city,
                    Country__c = req.country,
                    Department_Name__c = req.department,
                    Email__c = req.email,
                    PIN__c = ld.PIN__c,
                    Phone = ld.Phone,
                    State__c = req.state,
                    Street__c = ld.Street__c,
                    Zone__c = req.zone
                );
                if (String.isNotBlank(req.parentAccountId)) {
                    acc.ParentId = Id.valueOf(req.parentAccountId);
                }
                insert as system acc;
                accountId = acc.Id;
            }

            // 2. Contact (flow: create_contact_record / Select_Contact)
            Id contactId;
            Boolean accountHasContact =
                ![SELECT Id FROM Contact WHERE AccountId = :accountId WITH SYSTEM_MODE LIMIT 1].isEmpty();
            if (req.createContact == true || !accountHasContact) {
                Contact con = new Contact(
                    AccountId = accountId,
                    Email = ld.Email,
                    LastName = ld.LastName,
                    MobilePhone = ld.Phone
                );
                insert as system con;
                contactId = con.Id;
            } else {
                contactId = Id.valueOf(req.contactId);
            }

            // 3. Update Lead (flow: update_Lead_with_owner)
            String runningUserFullName = UserInfo.getFirstName() + '  ' + UserInfo.getLastName();
            String notes = [SELECT Notes__c FROM Lead WHERE Id = :ld.Id WITH SYSTEM_MODE].Notes__c;
            Lead leadUpdate = new Lead(
                Id = ld.Id,
                City__c = req.city,
                Closed_By_User__c = runningUserFullName,
                Company_Name__c = req.companyName,
                Country__c = req.country,
                Customer_Category__c = req.customerCategory,
                Department_Name__c = req.department,
                Email = req.email,
                InQualificationProcess__c = true,
                Notes__c = String.isBlank(notes) ? req.note : notes + '-' + req.note,
                OwnerId = Id.valueOf(req.ownerId),
                Qualified_Date_Time__c = Datetime.now(),
                Stage_Closed_From__c = closingStage,
                State__c = req.state,
                Zone__c = req.zone
            );
            if (String.isNotBlank(req.tentativeClosureDate)) {
                leadUpdate.Tentative_Closure_Date__c = Date.valueOf(req.tentativeClosureDate);
            }
            update as system leadUpdate;

            // 4. Complete all open tasks on the lead (flow: update_other_tasks + Update_Task_as_Complete)
            List<Task> taskUpdates = new List<Task>();
            for (Task other : [SELECT Id, Subject FROM Task WHERE WhoId = :ld.Id WITH SYSTEM_MODE]) {
                String subject = other.Subject == null ? '' : other.Subject;
                taskUpdates.add(new Task(
                    Id = other.Id,
                    Stage__c = 'Qualified',
                    Status = 'Completed',
                    Subject = subject.contains('- Completed') ? subject : subject + ' - Completed'
                ));
            }
            if (!taskUpdates.isEmpty()) { update as system taskUpdates; }

            // 5. Close open events (flow: update_Events)
            List<Event> eventUpdates = new List<Event>();
            for (Event ev : [
                SELECT Id FROM Event
                WHERE WhoId = :ld.Id
                  AND Disposition__c != 'Completed' AND Disposition__c != 'Not Completed'
                WITH SYSTEM_MODE
            ]) {
                eventUpdates.add(new Event(
                    Id = ev.Id,
                    Disposition__c = 'Not Completed',
                    Description = 'Closed due to conversion',
                    StartDateTime = Datetime.now()
                ));
            }
            if (!eventUpdates.isEmpty()) { update as system eventUpdates; }

            // 6. Address book (flow: create_Address_Book when none selected)
            Id addressBookId;
            if (String.isNotBlank(req.selectedAddressBookId)) {
                addressBookId = Id.valueOf(req.selectedAddressBookId);
            } else {
                Address_Book__c ab = new Address_Book__c(
                    Account__c = accountId,
                    City__c = req.city,
                    Country__c = req.country,
                    PIN__c = req.pin,
                    State__c = req.state,
                    Street__c = req.street,
                    Zone__c = req.zone
                );
                insert as system ab;
                addressBookId = ab.Id;
            }

            // 7. Convert (same invocable the flow calls)
            LeadConversionProcess.Input lcInput = new LeadConversionProcess.Input();
            lcInput.leadId = ld.Id;
            lcInput.accId = accountId;
            lcInput.contactId = contactId;
            List<LeadConversionProcess.Output> outputs =
                LeadConversionProcess.convertLead(new List<LeadConversionProcess.Input>{ lcInput });
            LeadConversionProcess.Output outcome = outputs.isEmpty() ? null : outputs[0];
            if (outcome == null || outcome.status != 'Success') {
                Database.rollback(sp);
                ConversionResult fail = new ConversionResult();
                fail.status = outcome == null ? 'Conversion returned no result.' : outcome.status;
                return fail;
            }

            // 8. Address book processing (same invocable the flow calls)
            AddressBookProcessor.Input abInput = new AddressBookProcessor.Input();
            abInput.leadId = ld.Id;
            abInput.accountId = outcome.accountId;
            abInput.contactId = outcome.contactId;
            abInput.opportunityId = outcome.opportunityId;
            abInput.selectedAddressBookId = addressBookId;
            AddressBookProcessor.process(new List<AddressBookProcessor.Input>{ abInput });

            // 9. Restore department / owner if changed (flow: back_update_department, update_Lead_Owner_to_previous)
            Lead restore = new Lead(Id = ld.Id);
            Boolean needsRestore = false;
            if (previousDepartment != req.department) {
                restore.Department_Name__c = previousDepartment;
                needsRestore = true;
            }
            if (previousOwnerId != Id.valueOf(req.ownerId)) {
                restore.OwnerId = previousOwnerId;
                needsRestore = true;
            }
            if (needsRestore) { update as system restore; }

            // 10. Product categories
            if (previousDepartment != req.department) {
                // flow: remove_lead_reference on the old department's PCs
                List<Product_Category__c> detach = new List<Product_Category__c>();
                for (Product_Category__c pc : [
                    SELECT Id FROM Product_Category__c
                    WHERE Lead__c = :ld.Id AND Department_Name__c = :previousDepartment
                    WITH SYSTEM_MODE
                ]) {
                    detach.add(new Product_Category__c(Id = pc.Id, Lead__c = null));
                }
                if (!detach.isEmpty()) { update as system detach; }
            }
            // flow: Create_Product_Categories_Admin from repeater rows
            List<Product_Category__c> newRows = new List<Product_Category__c>();
            if (req.productRows != null) {
                for (ProductRow row : req.productRows) {
                    if (String.isBlank(row.productCategory)) { continue; }
                    newRows.add(new Product_Category__c(
                        Department_Name__c = row.department,
                        Product_Category__c = row.productCategory,
                        UOM__c = row.uom,
                        Quantity__c = row.quantity,
                        Status__c = 'Active',
                        Opportunity__c = outcome.opportunityId
                    ));
                }
            }
            if (!newRows.isEmpty()) { insert as system newRows; }
            // flow: Update_PCs_with_Opportunity - link all remaining lead PCs to the opportunity
            List<Product_Category__c> linkToOpp = new List<Product_Category__c>();
            for (Product_Category__c pc : [
                SELECT Id FROM Product_Category__c WHERE Lead__c = :ld.Id WITH SYSTEM_MODE
            ]) {
                linkToOpp.add(new Product_Category__c(Id = pc.Id, Opportunity__c = outcome.opportunityId));
            }
            if (!linkToOpp.isEmpty()) { update as system linkToOpp; }

            // 11. Unschedule task logs (flow: update_records)
            List<Task_Log__c> logUpdates = new List<Task_Log__c>();
            for (Task_Log__c tl : [
                SELECT Id FROM Task_Log__c WHERE Lead__c = :ld.Id AND Is_schedule__c = true WITH SYSTEM_MODE
            ]) {
                logUpdates.add(new Task_Log__c(Id = tl.Id, Is_schedule__c = false));
            }
            if (!logUpdates.isEmpty()) { update as system logUpdates; }

            ConversionResult result = new ConversionResult();
            result.accountId = outcome.accountId;
            result.contactId = outcome.contactId;
            result.opportunityId = outcome.opportunityId;
            result.status = 'Success';
            return result;

        } catch (AuraHandledException ahe) {
            Database.rollback(sp);
            throw ahe;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ---------- Helpers ----------

    private static List<PicklistOption> picklist(Schema.SObjectField field) {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static String joinNonBlank(List<String> parts) {
        List<String> kept = new List<String>();
        for (String p : parts) {
            if (String.isNotBlank(p)) { kept.add(p); }
        }
        return String.join(kept, ', ');
    }

    // Decodes a dependent picklist's validFor bitset into controller value -> dependent values.
    private static Map<String, List<String>> dependentPicklist(
        Schema.SObjectField controlling, Schema.SObjectField dependent
    ) {
        Map<String, List<String>> result = new Map<String, List<String>>();
        List<Schema.PicklistEntry> controllingEntries = controlling.getDescribe().getPicklistValues();
        List<PicklistEntryWrapper> dependentEntries = (List<PicklistEntryWrapper>) JSON.deserialize(
            JSON.serialize(dependent.getDescribe().getPicklistValues()),
            List<PicklistEntryWrapper>.class
        );
        String base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        for (Integer i = 0; i < controllingEntries.size(); i++) {
            result.put(controllingEntries[i].getValue(), new List<String>());
        }
        for (PicklistEntryWrapper entry : dependentEntries) {
            if (String.isBlank(entry.validFor)) { continue; }
            for (Integer i = 0; i < entry.validFor.length(); i++) {
                Integer bits = base64Chars.indexOf(entry.validFor.mid(i, 1));
                for (Integer bit = 0; bit < 6; bit++) {
                    if ((bits & (32 >> bit)) != 0) {
                        Integer idx = i * 6 + bit;
                        if (idx < controllingEntries.size()) {
                            result.get(controllingEntries[idx].getValue()).add(entry.value);
                        }
                    }
                }
            }
        }
        return result;
    }

    private class PicklistEntryWrapper {
        public String label;
        public String value;
        public String validFor;
    }
}