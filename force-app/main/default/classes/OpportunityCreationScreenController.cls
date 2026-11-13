/**
 * OpportunityCreationScreenController
 *
 * Apex backend for the opportunityCreationScreen LWC - an LWC/Apex re-implementation of the
 * "Create Opportunity Custom Flow" screen flow (v42), built to run alongside the flow during
 * migration. The flow remains active; nothing here is referenced by it.
 *
 * Reuses the same invocable class the flow calls:
 *   - AddressBookProcessorByAddress.process()  (address book / junction / billing stamping)
 *
 * Flow parity notes:
 *   - Flow runs in SystemModeWithoutSharing -> this class is "without sharing".
 *   - Record type availability and Opportunity Source choices depend on profile/role,
 *     mirroring the flow's decision "check which record Type Selected" and the
 *     source-field visibility rules on the Opportunity Info screen.
 *   - Owner: Utkarsh Admin / System Administrator always pick an owner; other profiles
 *     default to themselves when their User.Department contains the chosen department
 *     (flow: Checking Profile and Department).
 *   - Doc upload requirement comes from the flow's DocRequiredFormula CASE on the source.
 *   - The flow's "Opportunity Detail Screen" is unreachable (no connector targets it)
 *     and is intentionally not replicated.
 */
public without sharing class OpportunityCreationScreenController {

    // ---------- DTOs ----------

    public class InitData {
        @AuraEnabled public String userProfile;
        @AuraEnabled public String userRole;
        @AuraEnabled public String userDepartment;
        @AuraEnabled public List<PicklistOption> recordTypes;
        @AuraEnabled public List<PicklistOption> sourceOptions;
        @AuraEnabled public List<PicklistOption> previousSources;
        @AuraEnabled public List<PicklistOption> industries;
        @AuraEnabled public List<PicklistOption> departments;
        @AuraEnabled public List<PicklistOption> customerCategories;
        @AuraEnabled public List<PicklistOption> uoms;
        @AuraEnabled public List<PicklistOption> countries;
        @AuraEnabled public List<PicklistOption> states;
        @AuraEnabled public List<PicklistOption> zones;
        @AuraEnabled public Map<String, List<String>> productCategoriesByDepartment;
        @AuraEnabled public Map<String, String> docRequiredBySource;
        @AuraEnabled public Boolean alwaysChooseOwner;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PicklistOption(String l, String v) { label = l; value = v; }
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

    // Creation request. All lookups typed as String on purpose:
    // Id-typed fields in @AuraEnabled input classes deserialize as null from LWC.
    public class CreationRequest {
        public String recordTypeName;
        public String email;
        public String phone;
        public String opportunitySource;
        public String previousSource;
        public String expectedClosureDate;  // yyyy-MM-dd
        public Decimal expectedDealValue;
        public String industry;
        public String department;
        public String customerCategory;
        public List<ProductRow> productRows;
        public List<String> contentDocumentIds;
        public String useExistingAccount;   // 'true' / 'false'
        public String accountId;            // when using existing
        public String accountName;          // when creating new
        public String parentAccountId;      // when new account is a Site
        public String selectedAddressBookId;
        public String street;
        public String city;
        public String state;
        public String country;
        public String pin;
        public String zone;
        public Boolean createContact;
        public String contactId;            // when selecting existing contact
        public String contactFirstName;
        public String contactLastName;
        public String contactEmail;
        public String contactPhone;
        public String ownerId;
    }

    public class ProductRow {
        public String productCategory;
        public String uom;
        public Decimal quantity;
    }

    public class CreationResult {
        @AuraEnabled public String accountId;
        @AuraEnabled public String contactId;
        @AuraEnabled public String opportunityId;
        @AuraEnabled public String status;
    }

    // ---------- Init ----------

    @AuraEnabled(cacheable=false)
    public static InitData getInitData() {
        InitData d = new InitData();

        d.userProfile = [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId() WITH SYSTEM_MODE LIMIT 1].Name;
        d.userRole = '';
        if (UserInfo.getUserRoleId() != null) {
            d.userRole = [SELECT Name FROM UserRole WHERE Id = :UserInfo.getUserRoleId() WITH SYSTEM_MODE LIMIT 1].Name;
        }
        d.userDepartment = [SELECT Department FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1].Department;
        if (d.userDepartment == null) { d.userDepartment = ''; }

        // Flow decision "check which record Type Selected", evaluated in the flow's rule order.
        d.recordTypes = new List<PicklistOption>();
        Set<String> adminProfiles = new Set<String>{
            'System Administrator', 'CRM Head', 'Utkarsh HOD', 'Utkarsh Admin' };
        if (adminProfiles.contains(d.userProfile)) {
            d.recordTypes.add(new PicklistOption('Master Opportunity', 'Master Opportunity'));
            d.recordTypes.add(new PicklistOption('Tender Opportunity', 'Tender Opportunity'));
            d.recordTypes.add(new PicklistOption('Project Opportunity', 'Project Opportunity'));
        } else if (d.userProfile == 'Utkarsh Sales' || d.userProfile == 'Utkarsh Projects') {
            d.recordTypes.add(new PicklistOption('Master Opportunity', 'Master Opportunity'));
            d.recordTypes.add(new PicklistOption('Project Opportunity', 'Project Opportunity'));
        } else if (d.userProfile == 'Utkarsh Tender' || d.userRole.contains('Tender')) {
            d.recordTypes.add(new PicklistOption('Master Opportunity', 'Master Opportunity'));
            d.recordTypes.add(new PicklistOption('Tender Opportunity', 'Tender Opportunity'));
        } else {
            d.recordTypes.add(new PicklistOption('Master Opportunity', 'Master Opportunity'));
        }

        // Opportunity Source choices mirror the per-profile fields on the flow's
        // Opportunity Info screen. (A Tender Opportunity record type forces 'TENDER'
        // regardless - the LWC handles that.)
        if (d.userProfile == 'System Administrator' || d.userProfile == 'Utkarsh Admin') {
            d.sourceOptions = picklist(Opportunity.LeadSource);
        } else if (d.userProfile == 'Utkarsh CRM' || d.userProfile == 'Utkarsh Department CRM User') {
            d.sourceOptions = staticOptions(new List<String>{
                'INBOUND EMAIL', 'INBOUND PHONE CALL', 'EMAIL CAMPAIGNING', 'OUTBOUND PHONE CALL',
                'OFFLINE CRM', 'TENDER', 'CRM RESOURCE', 'Offline Marketing',
                'WHATSAPP CAMPAIGNING', 'PROJECTS' });
        } else if (d.userProfile == 'CRM Head' || d.userProfile == 'Utkarsh HOD') {
            d.sourceOptions = staticOptions(new List<String>{
                'INBOUND EMAIL', 'INBOUND PHONE CALL', 'EMAIL CAMPAIGNING', 'OUTBOUND PHONE CALL',
                'OFFLINE CRM', 'TENDER', 'CRM RESOURCE', 'Offline Marketing',
                'WHATSAPP CAMPAIGNING', 'EVENT ACTIVATION', 'PROJECTS' });
        } else if (d.userProfile == 'Utkarsh Sales') {
            d.sourceOptions = staticOptions(new List<String>{ 'TENDER', 'Offline Marketing', 'PROJECTS' });
        } else if (d.userProfile == 'Utkarsh Tender') {
            d.sourceOptions = staticOptions(new List<String>{ 'TENDER', 'PROJECTS' });
        } else {
            // Profiles the flow shows no source field for; closest usable fallback.
            d.sourceOptions = staticOptions(new List<String>{ 'TENDER', 'Offline Marketing', 'PROJECTS' });
        }

        d.previousSources = picklist(Opportunity.Previous_Source__c);
        d.industries = picklist(Opportunity.Industry__c);
        d.departments = picklist(Opportunity.Department_Name__c);
        // 'Enquiry' stays active on the field for data/integration use but must not be
        // offered as a department when creating an opportunity from this screen.
        for (Integer i = d.departments.size() - 1; i >= 0; i--) {
            if (d.departments[i].value == 'Enquiry') {
                d.departments.remove(i);
            }
        }
        d.customerCategories = picklist(Opportunity.Customer_Category__c);
        d.uoms = picklist(Opportunity.UOM__c);
        d.countries = picklist(Opportunity.Country__c);
        d.states = picklist(Opportunity.State__c);
        d.zones = picklist(Opportunity.Zone__c);
        d.productCategoriesByDepartment = dependentPicklist(
            Product_Category__c.Department_Name__c, Product_Category__c.Product_Category__c);

        // Flow: DocRequiredFormula CASE on the selected source.
        d.docRequiredBySource = new Map<String, String>{
            'FACEBOOK' => 'REQUIRED',
            'FB LEAD ADS' => 'NOT REQUIRED',
            'INBOUND EMAIL' => 'REQUIRED',
            'INBOUND PHONE CALL' => 'REQUIRED',
            'INDIAMART' => 'REQUIRED',
            'ONLINE CAMPAIGNING' => 'NOT REQUIRED',
            'PAY PER CLICK ADS' => 'REQUIRED',
            'WEBSITE' => 'REQUIRED',
            'WHATSAPP CAMPAIGNING' => 'REQUIRED',
            'EMAIL CAMPAIGNING' => 'REQUIRED',
            'Offline Marketing' => 'NOT REQUIRED',
            'OUTBOUND PHONE CALL' => 'REQUIRED',
            'EVENT ACTIVATION' => 'NOT REQUIRED',
            'TENDER' => 'REQUIRED',
            'CRM RESOUCE' => 'NOT REQUIRED',
            'WEBSITE BOT CHAT' => 'REQUIRED',
            'OFFLINE CRM' => 'NOT REQUIRED',
            'PROJECTS' => 'REQUIRED'
        };

        // Flow: Checking Profile and Department - admins always pick an owner.
        d.alwaysChooseOwner =
            d.userProfile == 'Utkarsh Admin' || d.userProfile == 'System Administrator';

        return d;
    }

    // Flow: MatchingAccountList dynamic choice - (Email equal AND not null) OR Phone equal.
    @AuraEnabled(cacheable=true)
    public static List<MatchingAccount> getMatchingAccounts(String email, String phone) {
        List<MatchingAccount> result = new List<MatchingAccount>();
        if (String.isBlank(email) && String.isBlank(phone)) { return result; }
        for (Account a : [
            SELECT Id, Name FROM Account
            WHERE (Email__c = :email AND Email__c != null) OR (Phone = :phone AND Phone != null)
            WITH SYSTEM_MODE
            LIMIT 50
        ]) {
            MatchingAccount m = new MatchingAccount();
            m.id = a.Id; m.name = a.Name;
            result.add(m);
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

    // ---------- Creation ----------

    @AuraEnabled
    public static CreationResult create(String reqJson) {
        CreationRequest req;
        try {
            req = (CreationRequest) JSON.deserialize(reqJson, CreationRequest.class);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid request payload.');
        }

        RecordType rt = [
            SELECT Id, Name FROM RecordType
            WHERE SobjectType = 'Opportunity' AND Name = :req.recordTypeName WITH SYSTEM_MODE LIMIT 1
        ];

        Boolean useExisting = req.useExistingAccount == 'true';
        Savepoint sp = Database.setSavepoint();
        try {
            // 1. Account (flow: update_account / create_account)
            Id accountId;
            String accountName;
            if (useExisting) {
                accountId = Id.valueOf(req.accountId);
                accountName = [SELECT Name FROM Account WHERE Id = :accountId WITH SYSTEM_MODE LIMIT 1].Name;
            } else {
                Account acc = new Account(
                    Name = req.accountName,
                    AccountSource = req.opportunitySource,
                    Department_Name__c = req.department,
                    Email__c = req.email,
                    Phone = req.phone
                );
                if (String.isNotBlank(req.parentAccountId)) {
                    acc.ParentId = Id.valueOf(req.parentAccountId);
                }
                insert as system acc;
                accountId = acc.Id;
                accountName = acc.Name;
            }

            // 2. Contact (flow: create_contact_new / update_existing_contact)
            Id contactId;
            String opptyEmail;
            String opptyPhone;
            if (req.createContact == true) {
                Contact con = new Contact(
                    AccountId = accountId,
                    FirstName = req.contactFirstName,
                    LastName = req.contactLastName,
                    Email = req.contactEmail,
                    Phone = req.contactPhone
                );
                insert as system con;
                contactId = con.Id;
                opptyEmail = req.contactEmail;
                opptyPhone = req.contactPhone;
            } else {
                contactId = Id.valueOf(req.contactId);
                update as system new Contact(Id = contactId, AccountId = accountId);
                Contact existing = [SELECT Email, Phone FROM Contact WHERE Id = :contactId WITH SYSTEM_MODE LIMIT 1];
                opptyEmail = existing.Email;
                opptyPhone = existing.Phone;
            }
            // When the chosen contact has no email/phone, fall back to the values typed
            // on the creation screen so the opportunity never ends up uncontactable.
            if (String.isBlank(opptyEmail)) {
                opptyEmail = req.email;
            }
            if (String.isBlank(opptyPhone)) {
                opptyPhone = req.phone;
            }

            // 3. Opportunity (flow: create_opportunity; Name = Department-AccountName,
            //    stage Nurture - the Dealer Opportunity branch is not reachable from the
            //    record type selection, so JourneyValue is always blank)
            Opportunity opp = new Opportunity(
                AccountId = accountId,
                Amount = req.expectedDealValue,
                ContactId = contactId,
                Customer_Category__c = req.customerCategory,
                Customer_Journey__c = '',
                Department_Name__c = req.department,
                Email__c = opptyEmail,
                Industry__c = req.industry,
                Name = req.department + '-' + accountName,
                Opportunity_Source__c = req.opportunitySource,
                // Flow: Assign the user as Opportunity owner when no selection step was shown.
                OwnerId = String.isNotBlank(req.ownerId) ? Id.valueOf(req.ownerId) : UserInfo.getUserId(),
                Phone__c = opptyPhone,
                Previous_Source__c = req.previousSource,
                RecordTypeId = rt.Id,
                // Tender opportunities start locked at Negotiation; everything else at Nurture.
                StageName = rt.Name == 'Tender Opportunity' ? 'Negotiation' : 'Nurture'
            );
            if (String.isNotBlank(req.expectedClosureDate)) {
                opp.CloseDate = Date.valueOf(req.expectedClosureDate);
            }
            insert as system opp;

            // 4. Product categories (flow: lopp_through_product_category + Create_Product_Categories)
            List<Product_Category__c> pcs = new List<Product_Category__c>();
            if (req.productRows != null) {
                for (ProductRow row : req.productRows) {
                    if (String.isBlank(row.productCategory)) { continue; }
                    pcs.add(new Product_Category__c(
                        Department_Name__c = req.department,
                        Product_Category__c = row.productCategory,
                        UOM__c = row.uom,
                        Quantity__c = row.quantity,
                        Status__c = 'Active',
                        Opportunity__c = opp.Id
                    ));
                }
            }
            if (!pcs.isEmpty()) { insert as system pcs; }

            // 5. Link uploaded documents (flow: Loop_Through_Opp_Docs + Create_Opp_Content_Document_Links)
            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            if (req.contentDocumentIds != null) {
                for (String docId : req.contentDocumentIds) {
                    if (String.isBlank(docId)) { continue; }
                    links.add(new ContentDocumentLink(
                        ContentDocumentId = Id.valueOf(docId),
                        LinkedEntityId = opp.Id,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    ));
                }
            }
            if (!links.isEmpty()) { insert as system links; }

            // 6. Address book processing (same invocable the flow calls)
            AddressBookProcessorByAddress.Input abInput = new AddressBookProcessorByAddress.Input();
            abInput.accountId = accountId;
            abInput.contactId = contactId;
            abInput.opportunityId = opp.Id;
            if (String.isNotBlank(req.selectedAddressBookId)) {
                abInput.selectedAddressBookId = Id.valueOf(req.selectedAddressBookId);
            }
            abInput.street = req.street;
            abInput.city = req.city;
            abInput.state = req.state;
            abInput.country = req.country;
            abInput.pin = req.pin;
            abInput.zone = req.zone;
            AddressBookProcessorByAddress.process(
                new List<AddressBookProcessorByAddress.Input>{ abInput });

            CreationResult result = new CreationResult();
            result.accountId = accountId;
            result.contactId = contactId;
            result.opportunityId = opp.Id;
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
        for (Schema.PicklistEntry e : field.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                options.add(new PicklistOption(e.getLabel(), e.getValue()));
            }
        }
        return options;
    }

    private static List<PicklistOption> staticOptions(List<String> values) {
        List<PicklistOption> options = new List<PicklistOption>();
        for (String v : values) {
            options.add(new PicklistOption(v, v));
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

    // Maps each controlling value to its valid dependent values using the
    // validFor base64 bitset from the dependent field's picklist entries.
    private static Map<String, List<String>> dependentPicklist(
        Schema.SObjectField controlling, Schema.SObjectField dependent
    ) {
        Map<String, List<String>> result = new Map<String, List<String>>();
        List<Schema.PicklistEntry> controllingEntries = controlling.getDescribe().getPicklistValues();
        List<PicklistEntryWrapper> dependentEntries = (List<PicklistEntryWrapper>) JSON.deserialize(
            JSON.serialize(dependent.getDescribe().getPicklistValues()),
            List<PicklistEntryWrapper>.class);

        String base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        for (Integer cIdx = 0; cIdx < controllingEntries.size(); cIdx++) {
            if (!controllingEntries[cIdx].isActive()) { continue; }
            List<String> valid = new List<String>();
            for (PicklistEntryWrapper dep : dependentEntries) {
                if (dep.active != true || String.isBlank(dep.validFor)) { continue; }
                Integer charIdx = cIdx / 6;
                Integer bitIdx = Math.mod(cIdx, 6);
                if (charIdx >= dep.validFor.length()) { continue; }
                Integer sixBits = base64Chars.indexOf(dep.validFor.mid(charIdx, 1));
                if ((sixBits & (32 >> bitIdx)) != 0) {
                    valid.add(dep.value);
                }
            }
            result.put(controllingEntries[cIdx].getValue(), valid);
        }
        return result;
    }

    private class PicklistEntryWrapper {
        public Boolean active;
        public String label;
        public String value;
        public String validFor;
    }
}