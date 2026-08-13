/*
================================================================================
CLASS: TenderAISummaryBatch
--------------------------------------------------------------------------------
PURPOSE:
Fetches AI Summary JSON for every Tender__c where Tender_AI_Summary_status__c
is 'None' or 'Fail' (picklist values: 'Success', 'Fail', 'None'). For each
such tender:
  - Reads the value stored in Tender_AI_Summary__c. This field stores the FULL
    upstream URL (e.g. "https://utkarshapi.tender247.com/Utkarsh/api/tender-ai-summary/<token>"),
    not just the bare token - so only the segment AFTER THE LAST '/' is
    extracted and used as the token when building the callout endpoint via
    the Named Credential (avoids the path getting duplicated / 404s).
  - Fires GET callout: callout:tender247_Tender/Utkarsh/api/tender-ai-summary/<token>
  - Stores the FULL raw response JSON across Tender_AI_Summary_JSON_1__c and,
    if it overflows, Tender_AI_Summary_JSON_2__c (both Rich Text Area, 131072 max)
  - Sets Tender_AI_Summary_status__c = 'Success' on a successful (200 + non-blank
    body) callout, or 'Fail' otherwise - so failed/none records are naturally
    re-picked-up by the next run (query only ever selects 'None'/'Fail'),
    while 'Success' records are never touched again.

GOVERNOR LIMIT NOTES:
  - Salesforce allows MAX 100 callouts per transaction, so batch scope size
    MUST be <= 100. Default scope passed by the scheduler is 50 (safe margin
    for logging DML that runs in the same transaction).
  - Batch framework itself handles large volumes (5000+ tenders) fine - it
    just runs execute() repeatedly, once per chunk of `scope size`, until the
    whole QueryLocator is exhausted. No special handling needed for volume.
  - Each execute() does ONE bulk Database.update(...) at the end (not one
    update per record), even though callouts must still be done one-by-one
    per tender (endpoint takes only a single token, no bulk API for this).
================================================================================
*/
/*
public class TenderAISummaryBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {

    private static final String NAMED_CREDENTIAL = 'callout:tender247_Tender';
    private static final String ENDPOINT_PATH    = '/Utkarsh/api/tender-ai-summary/';

    // Picklist values on Tender_AI_Summary_status__c.
    private static final String STATUS_SUCCESS = 'Success';
    private static final String STATUS_FAIL    = 'Fail';
    private static final String STATUS_NONE    = 'None';

    // Kept a little below the actual 131072 field max as a safety margin,
    // since Rich Text Area storage can add slight overhead for HTML-sensitive
    // characters (<, >, &) that might appear in the raw JSON.
    private static final Integer RTA_SAFE_LIMIT = 130000;

    // Stateful counters just for a clean finish() summary log - doesn't affect logic.
    private Integer totalProcessed = 0;
    private Integer totalFailed = 0;

    // Only tenders with a non-blank AI Summary value AND status still 'None' or 'Fail'.

    public Database.QueryLocator start(Database.BatchableContext bc) {
    System.debug('[TenderAISummaryBatch] START');
    return Database.getQueryLocator([
        SELECT Id, Tender_AI_Summary__c, Tender_AI_Summary_status__c
        FROM Tender__c
        WHERE CreatedDate = TODAY
          AND (Tender_AI_Summary_status__c IN :new List<String>{ STATUS_NONE, STATUS_FAIL }
               OR Tender_AI_Summary_status__c = null)
          AND Tender_AI_Summary__c != null
    ]);
}

    public void execute(Database.BatchableContext bc, List<sObject> scope) {

        List<Tender__c> tendersToUpdate = new List<Tender__c>();

        for (sObject s : scope) {
            Tender__c tnd = (Tender__c) s;
            String rawValue = tnd.Tender_AI_Summary__c;

            Tender__c toUpdate = new Tender__c(Id = tnd.Id);

            if (String.isBlank(rawValue)) {
                // Nothing to call - mark as Fail so it doesn't get silently
                // stuck as 'None' forever with no record of why it was skipped.
                toUpdate.Tender_AI_Summary_status__c = STATUS_FAIL;
                tendersToUpdate.add(toUpdate);
                continue;
            }

            // Tender_AI_Summary__c stores the FULL upstream URL, not just the
            // token - e.g. "https://utkarshapi.tender247.com/Utkarsh/api/tender-ai-summary/<token>".
            // Extract just the token (the part after the LAST '/') and hit it
            // via the Named Credential, so we don't end up with the path
            // duplicated (which was causing 404s). Falls back to the raw value
            // as-is if no '/' is found, so a bare token would still work fine.
            String actualToken = rawValue;
            Integer lastSlash = rawValue.lastIndexOf('/');
            if (lastSlash >= 0 && lastSlash < rawValue.length() - 1) {
                actualToken = rawValue.substring(lastSlash + 1);
            }

            Integer statusCode;
            String responseBody;
            Boolean success = false;

            try {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(NAMED_CREDENTIAL + ENDPOINT_PATH + actualToken);
                req.setMethod('GET');
                req.setHeader('Content-Type', 'application/json');
                req.setHeader('Accept', 'application/json');
                req.setTimeout(120000);

                Http http = new Http();
                HttpResponse res = http.send(req);
                statusCode   = res.getStatusCode();
                responseBody = res.getBody();

                if (statusCode == 200 && String.isNotBlank(responseBody)) {
                    success = true;
                }

            } catch (Exception e) {
                responseBody = 'EXCEPTION: ' + e.getMessage();
                System.debug('[TenderAISummaryBatch] EXCEPTION for Tender ' + tnd.Id + ': ' + e.getMessage());
            }

            // Store the response (success or error text) split across the two RTA fields.
            applyJsonToFields(toUpdate, responseBody);

            // Success -> 'Success' (never picked up again by the query above).
            // Anything else -> 'Fail' (stays eligible, gets retried next run).
            toUpdate.Tender_AI_Summary_status__c = success ? STATUS_SUCCESS : STATUS_FAIL;

            tendersToUpdate.add(toUpdate);

            IntegrationLogger.log(
                'TenderAISummary',
                null,
                'tender-ai-summary',
                null,
                responseBody,
                statusCode,
                success,
                success ? null : responseBody,
                tnd.Id,
                null
            );

            if (success) {
                totalProcessed++;
            } else {
                totalFailed++;
            }
        }

        // ONE bulk DML for the whole scope.
        if (!tendersToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(tendersToUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    System.debug('[TenderAISummaryBatch] UPDATE FAILED for Tender '
                                 + tendersToUpdate[i].Id + ': ' + results[i].getErrors());
                }
            }
        }

        IntegrationLogger.flush();
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('[TenderAISummaryBatch] FINISH - Processed=' + totalProcessed + ' Failed=' + totalFailed);
        IntegrationLogger.flush();
    }

    // Splits the raw JSON across the two Rich Text Area fields. If it fits in
    // field 1 alone, field 2 is cleared. If it overflows field 1, the remainder
    // goes to field 2 (truncated if it somehow exceeds field 2's capacity too -
    // there are only 2 fields available per the current schema).
    private void applyJsonToFields(Tender__c t, String json) {
        if (String.isBlank(json)) {
            t.Tender_AI_Summary_JSON_1__c = null;
            t.Tender_AI_Summary_JSON_2__c = null;
            return;
        }

        if (json.length() <= RTA_SAFE_LIMIT) {
            t.Tender_AI_Summary_JSON_1__c = json;
            t.Tender_AI_Summary_JSON_2__c = null;
            return;
        }

        t.Tender_AI_Summary_JSON_1__c = json.substring(0, RTA_SAFE_LIMIT);
        String remainder = json.substring(RTA_SAFE_LIMIT);

        if (remainder.length() > RTA_SAFE_LIMIT) {
            // Response is bigger than both fields combined can hold (~260K chars).
            // Truncating here - if this happens often, a 3rd storage field or a
            // Big Object / Attachment-based approach would be needed instead.
            remainder = remainder.substring(0, RTA_SAFE_LIMIT);
            System.debug('[TenderAISummaryBatch] WARNING: response exceeded both RTA fields combined, truncated.');
        }

        t.Tender_AI_Summary_JSON_2__c = remainder;
    }
}
*/

public class TenderAISummaryBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {

    private static final String NAMED_CREDENTIAL = 'callout:tender247_Tender';
    private static final String ENDPOINT_PATH    = '/Utkarsh/api/tender-ai-summary/';

    // Picklist values on Tender_AI_Summary_status__c.
    private static final String STATUS_SUCCESS = 'Success';
    private static final String STATUS_FAIL    = 'Fail';
    private static final String STATUS_NONE    = 'None';

    // Kept a little below the actual 131072 field max as a safety margin,
    // since Rich Text Area storage can add slight overhead for HTML-sensitive
    // characters (<, >, &) that might appear in the raw JSON.
    private static final Integer RTA_SAFE_LIMIT = 130000;

    // Stateful counters just for a clean finish() summary log - doesn't affect logic.
    private Integer totalProcessed = 0;
    private Integer totalFailed = 0;

    // Small holder so we can keep callout results in memory and only touch
    // the database (DML) after every callout in the scope has fired.
    private class CalloutResult {
        Id tenderId;
        Integer statusCode;
        String responseBody;
        Boolean success;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('[TenderAISummaryBatch] START');

        // TEMP/TEST FILTER - swap back to the real filter below when done testing.
        /*return Database.getQueryLocator([
            SELECT Id, Tender_AI_Summary__c, External_Tender_Id__c, Tender_AI_Summary_status__c
            FROM Tender__c
            WHERE External_Tender_Id__c = '102957580'
        ]);

        
        return Database.getQueryLocator([
            SELECT Id, Tender_AI_Summary__c, Tender_AI_Summary_status__c
            FROM Tender__c
            WHERE CreatedDate = TODAY
              AND (Tender_AI_Summary_status__c IN :new List<String>{ STATUS_NONE, STATUS_FAIL }
                   OR Tender_AI_Summary_status__c = null)
              AND Tender_AI_Summary__c != null
        ]);
        */
        return Database.getQueryLocator([
            SELECT Id, Tender_AI_Summary__c, Tender_AI_Summary_status__c
            FROM Tender__c
            WHERE CreatedDate = TODAY
              AND (Tender_AI_Summary_status__c IN :new List<String>{ STATUS_NONE, STATUS_FAIL }
                   OR Tender_AI_Summary_status__c = null)
              AND Tender_AI_Summary__c != null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<sObject> scope) {

        System.debug('[TenderAISummaryBatch] execute() - scope size = ' + scope.size());

        // ============================================================
        // PHASE 1: CALLOUTS ONLY. No DML of any kind allowed in here -
        // that is what was causing "uncommitted work pending" before,
        // since the old code deleted chunk records before this loop.
        // ============================================================
        List<CalloutResult> calloutResults = new List<CalloutResult>();

        for (sObject s : scope) {
            Tender__c tnd = (Tender__c) s;
            String rawValue = tnd.Tender_AI_Summary__c;

            CalloutResult cr = new CalloutResult();
            cr.tenderId = tnd.Id;

            if (String.isBlank(rawValue)) {
                // Nothing to call - mark as Fail so it doesn't get silently
                // stuck as 'None' forever with no record of why it was skipped.
                cr.success = false;
                cr.statusCode = null;
                cr.responseBody = 'SKIPPED: Tender_AI_Summary__c is blank';
                System.debug('[TenderAISummaryBatch] Skipping Tender ' + tnd.Id + ' - blank Tender_AI_Summary__c');
                calloutResults.add(cr);
                continue;
            }

            // Tender_AI_Summary__c stores the FULL upstream URL, not just the
            // token - e.g. "https://utkarshapi.tender247.com/Utkarsh/api/tender-ai-summary/<token>".
            // Extract just the token (the part after the LAST '/') and hit it
            // via the Named Credential, so we don't end up with the path
            // duplicated (which was causing 404s). Falls back to the raw value
            // as-is if no '/' is found, so a bare token would still work fine.
            String actualToken = rawValue;
            Integer lastSlash = rawValue.lastIndexOf('/');
            if (lastSlash >= 0 && lastSlash < rawValue.length() - 1) {
                actualToken = rawValue.substring(lastSlash + 1);
            }

            System.debug('[TenderAISummaryBatch] Tender ' + tnd.Id + ' - token = ' + actualToken);

            Integer statusCode;
            String responseBody;
            Boolean success = false;

            try {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(NAMED_CREDENTIAL + ENDPOINT_PATH + actualToken);
                req.setMethod('GET');
                req.setHeader('Content-Type', 'application/json');
                req.setHeader('Accept', 'application/json');
                req.setTimeout(120000);

                Http http = new Http();
                HttpResponse res = http.send(req);
                statusCode   = res.getStatusCode();
                responseBody = res.getBody();

                System.debug('[TenderAISummaryBatch] Tender ' + tnd.Id
                              + ' - statusCode=' + statusCode
                              + ' responseLength=' + (responseBody == null ? 0 : responseBody.length()));

                if (statusCode == 200 && String.isNotBlank(responseBody)) {
                    success = true;
                }

            } catch (Exception e) {
                responseBody = 'EXCEPTION: ' + e.getMessage();
                System.debug('[TenderAISummaryBatch] EXCEPTION for Tender ' + tnd.Id + ': ' + e.getMessage());
            }

            cr.statusCode = statusCode;
            cr.responseBody = responseBody;
            cr.success = success;
            calloutResults.add(cr);

            if (success) {
                totalProcessed++;
            } else {
                totalFailed++;
            }
        }

        System.debug('[TenderAISummaryBatch] All callouts complete for this scope. Moving to DML phase.');

        // ============================================================
        // PHASE 2: DML ONLY. All callouts for this scope are done, so
        // it is now safe to run DML (delete/insert/update) plus any
        // logging flush that itself performs DML.
        // ============================================================

        // 2a. Delete existing chunk records for the tenders in this scope
        //     (safe now - no callout will run after this point).
        Set<Id> scopeIds = new Set<Id>();
        for (sObject s : scope) {
            scopeIds.add(s.Id);
        }

        List<Tender_AI_Summary_JSON__c> oldChunks = [
            SELECT Id FROM Tender_AI_Summary_JSON__c WHERE Tender__c IN :scopeIds
        ];
        System.debug('[TenderAISummaryBatch] Deleting ' + oldChunks.size() + ' old chunk record(s).');
        if (!oldChunks.isEmpty()) {
            delete oldChunks;
        }

        // 2b. Build and insert new chunk records + build Tender__c status updates
        //     + log via IntegrationLogger, using the in-memory callout results.
        List<Tender_AI_Summary_JSON__c> chunksToInsert = new List<Tender_AI_Summary_JSON__c>();
        List<Tender__c> tendersToUpdate = new List<Tender__c>();

        for (CalloutResult cr : calloutResults) {
            Tender__c toUpdate = new Tender__c(Id = cr.tenderId);
            toUpdate.Tender_AI_Summary_status__c = cr.success ? STATUS_SUCCESS : STATUS_FAIL;
            tendersToUpdate.add(toUpdate);

            chunksToInsert.addAll(buildChunkRecords(cr.tenderId, cr.responseBody));

            IntegrationLogger.log(
                'TenderAISummary',
                null,
                'tender-ai-summary',
                null,
                cr.responseBody,
                cr.statusCode,
                cr.success,
                cr.success ? null : cr.responseBody,
                cr.tenderId,
                null
            );
        }

        System.debug('[TenderAISummaryBatch] Inserting ' + chunksToInsert.size() + ' new chunk record(s).');
        if (!chunksToInsert.isEmpty()) {
            Database.SaveResult[] chunkResults = Database.insert(chunksToInsert, false);

            for (Integer i = 0; i < chunkResults.size(); i++) {
                if (chunkResults[i].isSuccess()) {
                    System.debug('[TenderAISummaryBatch] CHUNK INSERT SUCCESS - Id=' + chunkResults[i].getId()
                                 + ' Seq=' + chunksToInsert[i].Sequence_Number__c
                                 + ' Tender=' + chunksToInsert[i].Tender__c);
                } else {
                    for (Database.Error err : chunkResults[i].getErrors()) {
                        System.debug('================ CHUNK INSERT ERROR ================');
                        System.debug('StatusCode : ' + err.getStatusCode());
                        System.debug('Message    : ' + err.getMessage());
                        System.debug('Fields     : ' + err.getFields());
                        System.debug('Seq        : ' + chunksToInsert[i].Sequence_Number__c);
                        System.debug('Tender     : ' + chunksToInsert[i].Tender__c);
                    }
                }
            }
        }

        System.debug('[TenderAISummaryBatch] Updating ' + tendersToUpdate.size() + ' Tender__c record(s).');
        if (!tendersToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(tendersToUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    System.debug('[TenderAISummaryBatch] UPDATE FAILED for Tender '
                                 + tendersToUpdate[i].Id + ': ' + results[i].getErrors());
                } else {
                    System.debug('[TenderAISummaryBatch] UPDATE SUCCESS for Tender ' + tendersToUpdate[i].Id);
                }
            }
        }

        // Flush logger DML AFTER all callouts - same reasoning as above.
        IntegrationLogger.flush();

        System.debug('[TenderAISummaryBatch] execute() complete for this scope.');
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('[TenderAISummaryBatch] FINISH - Processed=' + totalProcessed + ' Failed=' + totalFailed);
        IntegrationLogger.flush();
    }

    // Splits the raw JSON into RTA_SAFE_LIMIT-sized pieces, one
    // Tender_AI_Summary_JSON__c child record per piece, sequenced from 1.
    private List<Tender_AI_Summary_JSON__c> buildChunkRecords(Id tenderId, String json) {
        List<Tender_AI_Summary_JSON__c> chunks = new List<Tender_AI_Summary_JSON__c>();

        if (String.isBlank(json)) {
            return chunks;
        }

        Integer seq = 1;
        Integer offset = 0;
        Integer len = json.length();

        while (offset < len) {
            Integer endIdx = Math.min(offset + RTA_SAFE_LIMIT, len);
            String piece = json.substring(offset, endIdx);

            chunks.add(new Tender_AI_Summary_JSON__c(
                Tender__c          = tenderId,
                Sequence_Number__c = seq,
                Ai_Summary_Json__c = piece
            ));

            System.debug('[TenderAISummaryBatch] Built chunk seq=' + seq
                         + ' for Tender=' + tenderId
                         + ' length=' + piece.length());

            offset = endIdx;
            seq++;
        }

        return chunks;
    }
}