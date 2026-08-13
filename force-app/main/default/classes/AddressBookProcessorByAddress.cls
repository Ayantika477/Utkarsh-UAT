public without sharing class AddressBookProcessorByAddress {

    public class Input {

        @InvocableVariable(required=true)
        public Id accountId;

        @InvocableVariable(required=true)
        public Id contactId;

        @InvocableVariable(required=true)
        public Id opportunityId;

        // Null when a new Address Book should be created
        @InvocableVariable
        public Id selectedAddressBookId;

        @InvocableVariable
        public String street;

        @InvocableVariable
        public String city;

        @InvocableVariable
        public String state;

        @InvocableVariable
        public String country;

        @InvocableVariable
        public String pin;

        @InvocableVariable
        public String zone;
    }

    @InvocableMethod(label='Process Address Book Opp')
    public static void process(List<Input> inputs) {

        System.debug('================ START =================');
        System.debug('Inputs Size : ' + inputs.size());
        System.debug(JSON.serializePretty(inputs));

        if (inputs == null || inputs.isEmpty()) {
            return;
        }

        Set<Id> selectedAddressIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();

        for (Input i : inputs) {

            if (i.selectedAddressBookId != null) {
                selectedAddressIds.add(i.selectedAddressBookId);
            }

            if (i.accountId != null) {
                accountIds.add(i.accountId);
            }
        }

        Map<Id, Address_Book__c> selectedAddressMap = new Map<Id, Address_Book__c>();

        if (!selectedAddressIds.isEmpty()) {

            selectedAddressMap = new Map<Id, Address_Book__c>([
                SELECT Id,
                       Name,
                       Account__c,
                       Street__c,
                       City__c,
                       State__c,
                       Country__c,
                       PIN__c,
                       Zone__c,
                       Type__c,
                       Primary_Address__c
                FROM Address_Book__c
                WHERE Id IN :selectedAddressIds WITH
                SYSTEM_MODE
            ]);
        }

        Map<String, Address_Book__c> addressBookMap = new Map<String, Address_Book__c>();

        if (!accountIds.isEmpty()) {

            for (Address_Book__c ab : [
                SELECT Id,
                       Account__c,
                       Street__c,
                       City__c,
                       State__c,
                       Country__c,
                       PIN__c,
                       Zone__c,
                       Primary_Address__c,
                       Type__c,
                       Name
                FROM Address_Book__c
                WHERE Account__c IN :accountIds
                WITH SYSTEM_MODE
            ]) {

                String key = buildKey(
                    ab.Account__c,
                    ab.Street__c,
                    ab.City__c,
                    ab.State__c,
                    ab.PIN__c,
                    ab.Country__c,
                    ab.Zone__c
                );

                addressBookMap.put(key, ab);
            }
        }

        System.debug('=========================');
        System.debug('Address Book Map Size : ' + addressBookMap.size());

        for (String key : addressBookMap.keySet()) {
            System.debug('Map Key : ' + key);
        }

        System.debug('=========================');

        List<Address_Book__c> addressBooksToInsert = new List<Address_Book__c>();
        List<Input> createAddressInputs = new List<Input>();

        for (Input i : inputs) {

            // User already selected an Address Book
            if (i.selectedAddressBookId != null) {
                continue;
            }
            
            
            // No address entered at all
            Boolean hasAddress =
                String.isNotBlank(i.street) ||
                String.isNotBlank(i.city) ||
                String.isNotBlank(i.state) ||
                String.isNotBlank(i.pin) ||
                String.isNotBlank(i.country) ||
                String.isNotBlank(i.zone);
            
            if (!hasAddress) {
                System.debug('Skipping because no address was provided.');
                continue;
            }

            String key = buildKey(
                i.accountId,
                i.street,
                i.city,
                i.state,
                i.pin,
                i.country,
                i.zone
            );

            System.debug('Input Key = ' + key);
            System.debug('Map contains key = ' + addressBookMap.containsKey(key));

            // Existing Address Book found
            if (addressBookMap.containsKey(key)) {

                i.selectedAddressBookId = addressBookMap.get(key).Id;

                selectedAddressMap.put(
                    i.selectedAddressBookId,
                    addressBookMap.get(key)
                );

                continue;
            }

            Address_Book__c ab = new Address_Book__c();

            ab.Account__c = i.accountId;
            ab.Street__c = i.street;
            ab.City__c = i.city;
            ab.State__c = i.state;
            ab.Country__c = i.country;
            ab.PIN__c = i.pin;
            ab.Zone__c = i.zone;

            // Reserve the key to prevent duplicate inserts in same transaction
            addressBookMap.put(key, ab);

            addressBooksToInsert.add(ab);
            createAddressInputs.add(i);
        }

        if (!addressBooksToInsert.isEmpty()) {

            insert addressBooksToInsert;

            Integer index = 0;

            for (Address_Book__c ab : addressBooksToInsert) {

                selectedAddressMap.put(ab.Id, ab);

                createAddressInputs[index].selectedAddressBookId = ab.Id;

                index++;
            }
        }

        List<Opportunity_Address_Junc__c> junctions = new List<Opportunity_Address_Junc__c>();
        List<Contact> contactsToUpdate = new List<Contact>();
        
        Set<Id> opportunityIds = new Set<Id>();

        for (Input i : inputs) {
            if (i.opportunityId != null) {
                opportunityIds.add(i.opportunityId);
            }
        }
        Map<Id, Opportunity> opportunityMap = new Map<Id, Opportunity>();
        
        if (!opportunityIds.isEmpty()) {
            opportunityMap = new Map<Id, Opportunity>([
                SELECT Id, AccountId
                FROM Opportunity
                WHERE Id IN :opportunityIds WITH
                SYSTEM_MODE
            ]);
        }

        for (Input i : inputs) {
            
            Opportunity opp = opportunityMap.get(i.opportunityId);

            

            Address_Book__c ab = selectedAddressMap.get(i.selectedAddressBookId);

            if (ab == null) {
                continue;
            }

            opportunityIds.add(i.opportunityId);
            junctions.add(new Opportunity_Address_Junc__c(
                Opportunity__c = i.opportunityId,
                Address_Book__c = ab.Id
            ));
            
            contactsToUpdate.add(new Contact(
                Id = i.contactId,
                Street__c = ab.Street__c,
                City__c = ab.City__c,
                State__c = ab.State__c,
                Country__c = ab.Country__c,
                PIN__c = ab.PIN__c,
                Zone__c = ab.Zone__c
            ));
            
            System.debug('Opportunity Account : ' + opp.AccountId);
            System.debug('Input Account       : ' + i.accountId);
            System.debug('AddressBook Account : ' + ab.Account__c);
            
        }

        if (!junctions.isEmpty()) {
            //insert junctions;
            Database.insert(junctions, AccessLevel.SYSTEM_MODE);
        }

        if (!contactsToUpdate.isEmpty()) {
            Database.update(contactsToUpdate, AccessLevel.SYSTEM_MODE);
        }
    }

    private static String buildKey(
        Id accountId,
        String street,
        String city,
        String state,
        String pin,
        String country,
        String zone
    ) {

        return String.valueOf(accountId) + '|' +
            normalize(street) + '|' +
            normalize(city) + '|' +
            normalize(state) + '|' +
            normalize(pin) + '|' +
            normalize(country) + '|' +
            normalize(zone);
    }

    private static String normalize(String value) {

        if (value == null) {
            return '';
        }

        value = value.trim().toLowerCase();
        value = value.replaceAll('\\s+', ' ');

        return value;
    }
}