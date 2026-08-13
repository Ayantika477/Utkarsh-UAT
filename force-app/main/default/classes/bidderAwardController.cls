public without sharing class bidderAwardController {

    /** Type and search on Account Name. */
    @AuraEnabled(cacheable=true)
    public static String getBidderName(Id opportunityId) {
    Opportunity opp = [
        SELECT Bidder__r.Name
        FROM Opportunity
        WHERE Id = :opportunityId
        WITH USER_MODE
        LIMIT 1
    ];
    return opp.Bidder__r != null ? opp.Bidder__r.Name : null;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Account> searchAccounts(String searchKey) {
        if (String.isBlank(searchKey) || searchKey.trim().length() < 2) {
            return new List<Account>();
        }
        String key = '%' + String.escapeSingleQuotes(searchKey.trim()) + '%';
        return [
            SELECT Id, Name, Phone, Email__c, BillingCity
            FROM Account
            WHERE Name LIKE :key
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 10
        ];
    }

    /**
     * Duplicate detection: exact Phone OR exact Email__c OR fuzzy Name.
     */
    @AuraEnabled
    public static List<Account> findDuplicateAccounts(String companyName, String phone, String email) {
        Account candidate = new Account(
            Name    = companyName,
            Phone   = phone,
            Email__c = email
        );

        List<Datacloud.FindDuplicatesResult> fdResults =
            Datacloud.FindDuplicates.findDuplicates(new List<Account>{ candidate });

        Set<Id> candidateIds = new Set<Id>();
        for (Datacloud.FindDuplicatesResult fdr : fdResults) {
            for (Datacloud.DuplicateResult dr : fdr.getDuplicateResults()) {
                for (Datacloud.MatchResult mr : dr.getMatchResults()) {
                    for (Datacloud.MatchRecord rec : mr.getMatchRecords()) {
                        candidateIds.add(rec.getRecord().Id);
                    }
                }
            }
        }

        if (candidateIds.isEmpty()) {
            return new List<Account>();
        }

        Map<Id, Account> candidates = new Map<Id, Account>([
            SELECT Id, Name, Phone, Email__c
            FROM Account
            WHERE Id IN :candidateIds
            WITH SYSTEM_MODE
        ]);

        List<Account> matches = new List<Account>();
        for (Account a : candidates.values()) {
            Boolean phoneMatch = String.isNotBlank(phone) && phone == a.Phone;
            Boolean emailMatch = String.isNotBlank(email) && email == a.Email__c;
            Boolean nameFuzzy  = String.isNotBlank(companyName) && a.Name != null
                && companyName.toLowerCase().contains(a.Name.toLowerCase().left(4));
            if (phoneMatch || emailMatch || nameFuzzy) {
                matches.add(a);
            }
        }
        return matches;
    }

    /** Fetch existing contacts for a selected Account */
    @AuraEnabled
    public static List<Contact> getAccountContacts(Id accountId) {
        return [
            SELECT Id, Name, Email, Phone 
            FROM Contact 
            WHERE AccountId = :accountId 
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ];
    }

    /** Fetch Bidder Contact Details related to the Opportunity */
    @AuraEnabled(cacheable=true)
    public static Bidders_Contact_Details__c getBidderContactDetails(Id opportunityId) {
        // First get the Bidder ID from the Opportunity
        Opportunity opp = [SELECT Bidder__c FROM Opportunity WHERE Id = :opportunityId WITH USER_MODE LIMIT 1];
        
        if (opp.Bidder__c != null) {
            // Then get the related Bidder Contact Details
            List<Bidders_Contact_Details__c> details = [
                SELECT Name, Contact_Number__c, Email__c,Bidders__r.Name
                FROM Bidders_Contact_Details__c 
                WHERE Bidders__c = :opp.Bidder__c 
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            
            if (!details.isEmpty()) {
                return details[0];
            }
        }
        return null;
    }

    /**
     * Finalizes the Award process:
     * 1. Changes the awarded Opp to 'Master_Opportunity' Record Type
     * 2. Marks the Parent Opp and all sibling Opps as Closed Lost with reason 'Tender lost'
     */
    @AuraEnabled
    public static void finalizeOpportunityAward(Id awardedOppId) {
        // 1. Get the Awarded Opp and its parent
        Opportunity awardedOpp = [
            SELECT Id, Parent_Opportunity__c 
            FROM Opportunity 
            WHERE Id = :awardedOppId 
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        // 2. Get the 'Master_Opportunity' Record Type ID
        Id masterRecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
                                      .get('Master_Opportunity').getRecordTypeId();

        // 3. Prepare the list of Opportunities to update
        List<Opportunity> oppsToUpdate = new List<Opportunity>();

        // Update the Awarded Opp's Record Type
        awardedOpp.RecordTypeId = masterRecordTypeId;
        oppsToUpdate.add(awardedOpp);

        // 4. If there is a parent, close it and all of its OTHER children
        if (awardedOpp.Parent_Opportunity__c != null) {
            
            // Query the Parent and Sibling Opportunities (excluding the Awarded Opp)
            List<Opportunity> relatedOpps = [
                SELECT Id 
                FROM Opportunity 
                WHERE Id = :awardedOpp.Parent_Opportunity__c 
                   OR (Parent_Opportunity__c = :awardedOpp.Parent_Opportunity__c AND Id != :awardedOppId)
                   WITH SYSTEM_MODE
            ];

            for (Opportunity opp : relatedOpps) {
                opp.StageName = 'Closed Lost'; 
                opp.Lost_Reason__c = 'Tender lost';
                oppsToUpdate.add(opp);
            }
        }

        // 5. Perform the bulk update
        if (!oppsToUpdate.isEmpty()) {
            // Using SYSTEM_MODE to ensure we can update related records without stopping due to field-level security
            Database.update(oppsToUpdate, AccessLevel.SYSTEM_MODE); 
        }
    }
    @AuraEnabled
    public static Id createAddressBookAndJunction(Id accountId, Id opportunityId, Map<String, Object> addressData) {
    if (addressData == null || addressData.isEmpty()) {
        return null;
    }

    // Build the Address Book record from the map
    Address_Book__c ab = new Address_Book__c();          // <-- confirm object API name
    ab.Account__c      = accountId;                        // <-- confirm lookup field name
    if (addressData.containsKey('Street__c'))  ab.Street__c  = (String) addressData.get('Street__c');
    if (addressData.containsKey('City__c'))    ab.City__c    = (String) addressData.get('City__c');
    if (addressData.containsKey('State__c'))   ab.State__c   = (String) addressData.get('State__c');
    if (addressData.containsKey('Country__c')) ab.Country__c = (String) addressData.get('Country__c');
    if (addressData.containsKey('PIN__c'))     ab.PIN__c     = (String) addressData.get('PIN__c');
    if (addressData.containsKey('Zone__c'))    ab.Zone__c    = (String) addressData.get('Zone__c');
    if (addressData.containsKey('Primary_Address__c')) {
        ab.Primary_Address__c = (Boolean) addressData.get('Primary_Address__c');
    }
    
    insert as system ab;

    // Create the junction record linking Address Book <-> Opportunity
    Opportunity_Address_Junc__c junc = new Opportunity_Address_Junc__c(
        Opportunity__c   = opportunityId,   // <-- confirm field name
        Address_Book__c  = ab.Id            // <-- confirm field name
    );
    insert as system junc;

    return ab.Id;
}

    @AuraEnabled(cacheable=true)
    public static String getOpportunityDepartment(Id opportunityId) {
        Opportunity opp = [
            SELECT Department_Name__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        return opp.Department_Name__c;
    }

    @AuraEnabled
    public static void createProductCategories(List<Product_Category__c> productCategories) {
        if (productCategories == null || productCategories.isEmpty()) {
            return;
        }

        insert as system productCategories;
    }
}