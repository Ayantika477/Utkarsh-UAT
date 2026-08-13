public with sharing class TenderSharingHandler {

    public static void shareTenders(List<Tender__c> tenders) {

        if (tenders == null || tenders.isEmpty()) return;

        // Get all active users
        List<User> users = [
            SELECT Id, Departments__c, Profile.Name
            FROM User
            WHERE IsActive = TRUE
        ];

        // Prepare User → Departments map
        Map<Id, Set<String>> userDeptMap = new Map<Id, Set<String>>();

        for (User usr : users) {
            if (usr.Departments__c != null) {
                Set<String> deptSet = new Set<String>();
                for (String d : usr.Departments__c.split(';')) {
                    deptSet.add(d.trim());
                }
                userDeptMap.put(usr.Id, deptSet);
            }
        }

        // Department normalization map
        Map<String, String> deptMap = new Map<String, String>{
            'HIGH MAST & POLYGONAL' => 'High_Mast_Department',
            'CRASH BARRIER' => 'Crash_Barrier_Department',
            'HDPE' => 'HDPE_Pipe_Department',
            'STEEL TUBULAR POLES' => 'Steel_Tubular_Pole_Department',
            'POLYMER' => 'PVC',
            'TRANSMISSION & TELECOM TOWER' => 'Transmission_Tower_Department',
            'PRE ENGINEERING BUILDING' => 'PEB',
            'SOLAR STRUCTURE' => 'Solar_Structure_Department',
            'RAILWAY ELECTRIFICATION STRUCTURE' => 'Core_Department',
            'STEEL PIPES' => 'Steel_Pipes_Department'
        };

        List<Tender__Share> shareRecords = new List<Tender__Share>();

        for (Tender__c tender : tenders) {

            if (tender.Department_Name__c == null) continue;

            // Normalize department
            String deptKey = tender.Department_Name__c.trim().toUpperCase();
            String normalizedDept = deptMap.containsKey(deptKey)
                ? deptMap.get(deptKey)
                : tender.Department_Name__c.trim();

            for (User usr : users) {

                // Skip Admins
                if (usr.Profile.Name == 'System Administrator' ||
                    usr.Profile.Name == 'Utkarsh Admin') {
                    continue;
                }

                // Skip if user has no department mapping
                if (!userDeptMap.containsKey(usr.Id)) continue;

                
                System.debug('--- DEBUG START ---');
				System.debug('User Id: ' + usr.Id);
				System.debug('Tender Dept Raw: ' + tender.Department_Name__c);
				System.debug('Normalized Dept: ' + normalizedDept);
				System.debug('User Departments: ' + userDeptMap.get(usr.Id));
				System.debug('Is Same Dept: ' + userDeptMap.get(usr.Id).contains(normalizedDept));
				System.debug('--- DEBUG END ---');
                
                
                Boolean isSameDept = userDeptMap.get(usr.Id).contains(normalizedDept);

                //  HOD & CRM Head → All records of their department
                if (
                    (usr.Profile.Name == 'Utkarsh HOD' ||
                     usr.Profile.Name == 'CRM Head') &&
                    isSameDept
                ) {
                    shareRecords.add(
                        createShare(tender.Id, usr.Id, 'Edit')
                    );
                }

                //  Tender User → ONLY OWN records + same department
                else if (
                    usr.Profile.Name == 'Utkarsh Tender' &&
                    tender.OwnerId == usr.Id &&
                    isSameDept
                ) {
                    shareRecords.add(
                        createShare(tender.Id, usr.Id, 'Edit')
                    );
                }
            }
        }

        if (!shareRecords.isEmpty()) {
            Database.insert(shareRecords, false);
        }
    }

    private static Tender__Share createShare(Id recordId, Id userId, String accessLevel) {
        Tender__Share share = new Tender__Share();
        share.ParentId = recordId;
        share.UserOrGroupId = userId;
        share.AccessLevel = accessLevel;
        share.RowCause = Schema.Tender__Share.RowCause.Manual;
        return share;
    }
}