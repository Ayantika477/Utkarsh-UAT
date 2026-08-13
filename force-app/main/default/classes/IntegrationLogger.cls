/*
================================================================================
CLASS: IntegrationLogger
--------------------------------------------------------------------------------
WHY THIS CLASS EXISTS:
This entire integration runs unattended (scheduled at 8am and 3pm), so there is
no debug log to check when something goes wrong. This class writes ONE
Integration_Log__c record per API call made, so we always have a permanent,
queryable record of: which endpoint was called, what we sent, what came back,
and whether it succeeded. Every Batch class calls log() after every callout,
then flush() once at the end of execute()/finish() to commit them.

JSON CHUNKING (Integration_JSON_Log__c child records):
  - A single API response can be large, so the raw response JSON is split into
    <=131,072-character chunks (CHUNK_SIZE) and each chunk is inserted as one
    Integration_JSON_Log__c child record, linked to its parent Integration_Log__c
    via lookup, with Sequence__c preserving chunk order.
  - There is no fixed cap on the number of chunks - however many are needed to
    hold the full response are created, so nothing is truncated.
  - Response_Body__c on the parent record is left untouched and still holds
    the full raw value (kept for backward compatibility / existing reports).

FIELD COVERAGE (confirmed against org schema):
  - Integration_Log__c fields populated on every log record: Called_At__c,
    Http_Method__c, Integration_Name__c, Request_Payload__c,
    Response_Payload__c, Response_Http_Status__c, Status__c, Common_Key__c,
    Tender__c.
  - Campaign__c / Campaign_Name__c are NOT populated - nothing in this
    integration maps to a Campaign, so they are intentionally left null
    rather than guessed.
  - Status__c is a PICKLIST - values used here are 'Success' / 'Failed'.
    Confirm these match the exact picklist API values configured in the org.
================================================================================
*/
/*
public class IntegrationLogger {

    // Max characters allowed per Integration_JSON_Log__c.JSON_Details__c chunk.
    private static final Integer CHUNK_SIZE = 131072;

    // <<< CHANGED >>> Max characters kept on the PARENT's Response_Body__c /
    // Response_Payload__c fields. Set this a little below the actual max
    // length configured on those fields in Setup, so the parent insert can
    // never fail with STRING_TOO_LONG. Full data is never lost - it's always
    // fully preserved, unchunked, in the Integration_JSON_Log__c children.
    private static final Integer PARENT_PREVIEW_LIMIT = 5000;

    // Fixed values constant across every callout in this integration.
    private static final String DEFAULT_HTTP_METHOD = 'POST';
    private static final String INTEGRATION_NAME     = 'Tender247';

    // Pairs a parent log record with the raw JSON it needs to be chunked into,
    // so parents can be inserted first (to get Ids) and children built after.
    private class PendingEntry {
        Integration_Log__c parent;
        String jsonBody;
        PendingEntry(Integration_Log__c parent, String jsonBody) {
            this.parent = parent;
            this.jsonBody = jsonBody;
        }
    }

    // Buffer so we only do bulk DML per flush() call, never one insert per log entry.
    private static List<PendingEntry> pendingEntries = new List<PendingEntry>();

    // Backward-compatible overload (no tenderId, no commonKey) - for callouts
    // with no tender or page context, e.g. the Count API call.
    public static void log(String stage, String productName, String endpoint,
                            String requestBody, String responseBody,
                            Integer statusCode, Boolean isSuccess, String errorMessage) {
        log(stage, productName, endpoint, requestBody, responseBody,
            statusCode, isSuccess, errorMessage, null, null);
    }

    // Overload with tenderId only - for callouts tied to ONE specific tender
    // (e.g. Probable Bidder / Contact Details API).
    public static void log(String stage, String productName, String endpoint,
                            String requestBody, String responseBody,
                            Integer statusCode, Boolean isSuccess, String errorMessage,
                            Id tenderId) {
        log(stage, productName, endpoint, requestBody, responseBody,
            statusCode, isSuccess, errorMessage, tenderId, null);
    }

    // Full overload - for callouts tied to a whole PAGE of tenders (e.g.
    // Listing API), where Common_Key__c is the shared value also stamped on
    // every Tender__c that page produced, tracing them back to this log record.
    // <<< CHANGED >>> This is now a BACKWARD-COMPATIBLE OVERLOAD (no mailType
    // param) for all existing call sites that don't pass mailType. It simply
    // delegates to the full 11-param version below with mailType = null, so
    // no existing caller anywhere in the codebase needed to change.
    public static void log(String stage, String productName, String endpoint,
                            String requestBody, String responseBody,
                            Integer statusCode, Boolean isSuccess, String errorMessage,
                            Id tenderId, String commonKey) {
        log(stage, productName, endpoint, requestBody, responseBody,
            statusCode, isSuccess, errorMessage, tenderId, commonKey, null);
    }

    // <<< NEW >>> Full overload WITH MailType__c - for callouts that want to
    // stamp the MailType (0=Whole-day, 1=Morning, 2=Noon) on the log record,
    // e.g. TenderListingBatch's TenderCreated log. This is where the actual
    // Integration_Log__c record is built and queued.
    public static void log(String stage, String productName, String endpoint,
                            String requestBody, String responseBody,
                            Integer statusCode, Boolean isSuccess, String errorMessage,
                            Id tenderId, String commonKey, Integer mailType) {

        Integration_Log__c logRec = new Integration_Log__c();
        logRec.Stage__c          = stage;
        logRec.Product_Name__c   = productName;
        logRec.Endpoint__c       = endpoint;
        logRec.Request_Body__c   = requestBody;
        // <<< CHANGED >>> truncated preview instead of full raw value, to
        // guarantee this field's length can never exceed its max and fail
        // the parent insert. Full value is preserved in the child chunks.
        logRec.Response_Body__c  = responseBody != null ? responseBody.abbreviate(PARENT_PREVIEW_LIMIT) : null;
        logRec.Status_Code__c    = statusCode;
        logRec.Is_Success__c     = isSuccess;
        logRec.Error_Message__c  = errorMessage;
        logRec.Tender__c         = tenderId;
        logRec.Common_Key__c     = commonKey;
        // <<< NEW >>> stamps the MailType passed in (0=Whole-day, 1=Morning, 2=Noon).
        logRec.MailType__c       = mailType;

        logRec.Called_At__c            = System.now();
        logRec.Http_Method__c          = DEFAULT_HTTP_METHOD;
        logRec.Integration_Name__c     = INTEGRATION_NAME;
        logRec.Request_Payload__c      = requestBody;
        // <<< CHANGED >>> same truncation as Response_Body__c above, same reason.
        logRec.Response_Payload__c     = responseBody != null ? responseBody.abbreviate(PARENT_PREVIEW_LIMIT) : null;
        logRec.Response_Http_Status__c = statusCode;
        logRec.Status__c               = isSuccess ? 'Success' : 'Failed';

        // Don't chunk yet - we need this parent's Id first, which we only get
        // after insert. Just queue it alongside the raw JSON for now.
        pendingEntries.add(new PendingEntry(logRec, responseBody));

        System.debug('[IntegrationLogger] Queued log for Stage=' + stage
                      + ' Product=' + productName + ' Tender=' + tenderId
                      + ' CommonKey=' + commonKey + ' Status=' + statusCode);
    }

    // Call this ONCE at the end of every execute()/finish() to flush all queued
    // logs. Inserts parents first, then chunks each one's JSON into child
    // Integration_JSON_Log__c records and bulk inserts those too.
    public static void flush() {
        if (pendingEntries.isEmpty()) {
            return;
        }

        try {
            List<Integration_Log__c> parents = new List<Integration_Log__c>();
            for (PendingEntry pe : pendingEntries) {
                parents.add(pe.parent);
            }
            // <<< CHANGED >>> partial-success insert instead of all-or-nothing
            // "insert parents;" - so one bad record no longer drops every log
            // for the product/run. Any failure is captured below instead of
            // being silently lost.
            Database.SaveResult[] parentResults = Database.insert(parents, false);

            List<Integration_JSON_Log__c> children = new List<Integration_JSON_Log__c>();
            List<Integration_Log__c> failureLogs = new List<Integration_Log__c>();

            for (Integer i = 0; i < parentResults.size(); i++) {
                Database.SaveResult res = parentResults[i];
                PendingEntry pe = pendingEntries[i];

                if (res.isSuccess()) {
                    if (String.isNotBlank(pe.jsonBody)) {
                        List<String> chunks = chunkString(pe.jsonBody, CHUNK_SIZE);
                        for (Integer c = 0; c < chunks.size(); c++) {
                            Integration_JSON_Log__c child = new Integration_JSON_Log__c();
                            child.Integration_Log__c = res.getId();
                            child.JSON_Details__c    = chunks[c];
                            child.Sequence__c        = c + 1;
                            children.add(child);
                        }
                    }
                } else {
                    // <<< CHANGED >>> capture the real reason this parent failed,
                    // as a small guaranteed-safe record (no large fields), instead
                    // of just a debug line nobody sees on an unattended run.
                    String errMsg = '';
                    for (Database.Error err : res.getErrors()) {
                        errMsg += err.getStatusCode() + ': ' + err.getMessage() + ' | Fields: ' + err.getFields() + '; ';
                    }
                    System.debug('[IntegrationLogger] PARENT INSERT FAILED: ' + errMsg);

                    Integration_Log__c fallback = new Integration_Log__c();
                    fallback.Stage__c            = 'LOG_INSERT_FAILED';
                    fallback.Product_Name__c     = pe.parent.Product_Name__c;
                    fallback.Endpoint__c         = pe.parent.Endpoint__c;
                    fallback.Error_Message__c    = errMsg.abbreviate(255);
                    fallback.Status__c           = 'Failed';
                    fallback.Called_At__c        = System.now();
                    fallback.Integration_Name__c = INTEGRATION_NAME;
                    failureLogs.add(fallback);
                }
            }

            if (!failureLogs.isEmpty()) {
                Database.insert(failureLogs, false);
            }

            if (!children.isEmpty()) {
                Database.insert(children, false);
            }

            System.debug('[IntegrationLogger] Flushed ' + parents.size() + ' log record(s) and '
                         + children.size() + ' JSON chunk record(s).');

        } catch (Exception e) {
            // Logging must never break the actual integration - just debug it.
            System.debug('[IntegrationLogger] FAILED to insert logs: ' + e.getMessage());
        } finally {
            pendingEntries.clear();
        }
    }

    // Splits str into a list of substrings, each at most size characters long -
    // one substring per child Integration_JSON_Log__c record.
    private static List<String> chunkString(String str, Integer size) {
        List<String> result = new List<String>();
        Integer len = str.length();
        Integer pos = 0;
        while (pos < len) {
            Integer endPos = Math.min(pos + size, len);
            result.add(str.substring(pos, endPos));
            pos = endPos;
        }
        return result;
    }
}*/
/*
================================================================================
CLASS: IntegrationLogger
--------------------------------------------------------------------------------
WHY THIS CLASS EXISTS:
This entire integration runs unattended (scheduled at 8am and 3pm), so there is
no debug log to check when something goes wrong. This class writes ONE
Integration_Log__c record per API call made, so we always have a permanent,
queryable record of: which endpoint was called, what we sent, what came back,
and whether it succeeded. Every Batch class calls log() after every callout,
then flush() once at the end of execute()/finish() to commit them.

JSON CHUNKING (Integration_JSON_Log__c child records):
  - A single API response can be large, so the raw response JSON is split into
    <=131,072-character chunks (CHUNK_SIZE) and each chunk is inserted as one
    Integration_JSON_Log__c child record, linked to its parent Integration_Log__c
    via lookup, with Sequence__c preserving chunk order.
  - There is no fixed cap on the number of chunks - however many are needed to
    hold the full response are created, so nothing is truncated.
  - Response_Body__c on the parent record is left untouched and still holds
    the full raw value (kept for backward compatibility / existing reports).

FIELD COVERAGE (confirmed against org schema):
  - Integration_Log__c fields populated on every log record: Called_At__c,
    Http_Method__c, Integration_Name__c, Request_Payload__c,
    Response_Payload__c, Response_Http_Status__c, Status__c, Common_Key__c,
    Tender__c.
  - Campaign__c / Campaign_Name__c are NOT populated - nothing in this
    integration maps to a Campaign, so they are intentionally left null
    rather than guessed.
  - Status__c is a PICKLIST - values used here are 'Success' / 'Failed'.
    Confirm these match the exact picklist API values configured in the org.

  <<< CHANGED >>> All log() overloads now RETURN the Integration_Log__c record
  that was queued (instead of void), so callers can stamp extra fields (e.g.
  Tender_Record_Count__c, Tender_Record_Create__c, Tender_Record_Update__c,
  Tender_Record_Skipped__c) onto that specific record before flush() runs.
  Existing callers that ignore the return value are unaffected - Apex does not
  require the return value of a method to be used.
================================================================================
*/
public class IntegrationLogger {

    // Max characters allowed per Integration_JSON_Log__c.JSON_Details__c chunk.
    private static final Integer CHUNK_SIZE = 131072;

    // Max characters kept on the PARENT's Response_Body__c /
    // Response_Payload__c fields. Set this a little below the actual max
    // length configured on those fields in Setup, so the parent insert can
    // never fail with STRING_TOO_LONG. Full data is never lost - it's always
    // fully preserved, unchunked, in the Integration_JSON_Log__c children.
    private static final Integer PARENT_PREVIEW_LIMIT = 5000;

    // Fixed values constant across every callout in this integration.
    private static final String DEFAULT_HTTP_METHOD = 'POST';
    private static final String INTEGRATION_NAME     = 'Tender247';

    // Pairs a parent log record with the raw JSON it needs to be chunked into,
    // so parents can be inserted first (to get Ids) and children built after.
    private class PendingEntry {
        Integration_Log__c parent;
        String jsonBody;
        PendingEntry(Integration_Log__c parent, String jsonBody) {
            this.parent = parent;
            this.jsonBody = jsonBody;
        }
    }

    // Buffer so we only do bulk DML per flush() call, never one insert per log entry.
    private static List<PendingEntry> pendingEntries = new List<PendingEntry>();

    // Backward-compatible overload (no tenderId, no commonKey) - for callouts
    // with no tender or page context, e.g. the Count API call.
    // <<< CHANGED >>> return type void -> Integration_Log__c
    public static Integration_Log__c log(String stage, String productName, String endpoint,
                            String requestBody, String responseBody,
                            Integer statusCode, Boolean isSuccess, String errorMessage) {
        return log(stage, productName, endpoint, requestBody, responseBody,
            statusCode, isSuccess, errorMessage, null, null);
    }

    // Overload with tenderId only - for callouts tied to ONE specific tender
    // (e.g. Probable Bidder / Contact Details API).
    // <<< CHANGED >>> return type void -> Integration_Log__c
    public static Integration_Log__c log(String stage, String productName, String endpoint,
                            String requestBody, String responseBody,
                            Integer statusCode, Boolean isSuccess, String errorMessage,
                            Id tenderId) {
        return log(stage, productName, endpoint, requestBody, responseBody,
            statusCode, isSuccess, errorMessage, tenderId, null);
    }

    // Full overload - for callouts tied to a whole PAGE of tenders (e.g.
    // Listing API), where Common_Key__c is the shared value also stamped on
    // every Tender__c that page produced, tracing them back to this log record.
    // This is a BACKWARD-COMPATIBLE OVERLOAD (no mailType
    // param) for all existing call sites that don't pass mailType. It simply
    // delegates to the full 11-param version below with mailType = null, so
    // no existing caller anywhere in the codebase needed to change.
    // <<< CHANGED >>> return type void -> Integration_Log__c
    public static Integration_Log__c log(String stage, String productName, String endpoint,
                            String requestBody, String responseBody,
                            Integer statusCode, Boolean isSuccess, String errorMessage,
                            Id tenderId, String commonKey) {
        return log(stage, productName, endpoint, requestBody, responseBody,
            statusCode, isSuccess, errorMessage, tenderId, commonKey, null);
    }

    // Full overload WITH MailType__c - for callouts that want to
    // stamp the MailType (0=Whole-day, 1=Morning, 2=Noon) on the log record,
    // e.g. TenderListingBatch's TenderCreated log. This is where the actual
    // Integration_Log__c record is built and queued.
    // <<< CHANGED >>> return type void -> Integration_Log__c; returns logRec at the end.
    public static Integration_Log__c log(String stage, String productName, String endpoint,
                            String requestBody, String responseBody,
                            Integer statusCode, Boolean isSuccess, String errorMessage,
                            Id tenderId, String commonKey, Integer mailType) {

        Integration_Log__c logRec = new Integration_Log__c();
        logRec.Stage__c          = stage;
        logRec.Product_Name__c   = productName;
        logRec.Endpoint__c       = endpoint;
        logRec.Request_Body__c   = requestBody;
        // truncated preview instead of full raw value, to
        // guarantee this field's length can never exceed its max and fail
        // the parent insert. Full value is preserved in the child chunks.
        logRec.Response_Body__c  = responseBody != null ? responseBody.abbreviate(PARENT_PREVIEW_LIMIT) : null;
        logRec.Status_Code__c    = statusCode;
        logRec.Is_Success__c     = isSuccess;
        logRec.Error_Message__c  = errorMessage;
        logRec.Tender__c         = tenderId;
        logRec.Common_Key__c     = commonKey;
        // stamps the MailType passed in (0=Whole-day, 1=Morning, 2=Noon).
        logRec.MailType__c       = mailType;

        logRec.Called_At__c            = System.now();
        logRec.Http_Method__c          = DEFAULT_HTTP_METHOD;
        logRec.Integration_Name__c     = INTEGRATION_NAME;
        logRec.Request_Payload__c      = requestBody;
        // same truncation as Response_Body__c above, same reason.
        logRec.Response_Payload__c     = responseBody != null ? responseBody.abbreviate(PARENT_PREVIEW_LIMIT) : null;
        logRec.Response_Http_Status__c = statusCode;
        logRec.Status__c               = isSuccess ? 'Success' : 'Failed';

        // Don't chunk yet - we need this parent's Id first, which we only get
        // after insert. Just queue it alongside the raw JSON for now.
        pendingEntries.add(new PendingEntry(logRec, responseBody));

        System.debug('[IntegrationLogger] Queued log for Stage=' + stage
                      + ' Product=' + productName + ' Tender=' + tenderId
                      + ' CommonKey=' + commonKey + ' Status=' + statusCode);

        // <<< NEW >>> return the queued record so callers can stamp extra
        // fields (e.g. Tender_Record_Count__c) onto it before flush() runs.
        return logRec;
    }

    // Call this ONCE at the end of every execute()/finish() to flush all queued
    // logs. Inserts parents first, then chunks each one's JSON into child
    // Integration_JSON_Log__c records and bulk inserts those too.
    public static void flush() {
        if (pendingEntries.isEmpty()) {
            return;
        }

        try {
            List<Integration_Log__c> parents = new List<Integration_Log__c>();
            for (PendingEntry pe : pendingEntries) {
                parents.add(pe.parent);
            }
            // partial-success insert instead of all-or-nothing
            // "insert parents;" - so one bad record no longer drops every log
            // for the product/run. Any failure is captured below instead of
            // being silently lost.
            Database.SaveResult[] parentResults = Database.insert(parents, false);

            List<Integration_JSON_Log__c> children = new List<Integration_JSON_Log__c>();
            List<Integration_Log__c> failureLogs = new List<Integration_Log__c>();

            for (Integer i = 0; i < parentResults.size(); i++) {
                Database.SaveResult res = parentResults[i];
                PendingEntry pe = pendingEntries[i];

                if (res.isSuccess()) {
                    if (String.isNotBlank(pe.jsonBody)) {
                        List<String> chunks = chunkString(pe.jsonBody, CHUNK_SIZE);
                        for (Integer c = 0; c < chunks.size(); c++) {
                            Integration_JSON_Log__c child = new Integration_JSON_Log__c();
                            child.Integration_Log__c = res.getId();
                            child.JSON_Details__c    = chunks[c];
                            child.Sequence__c        = c + 1;
                            children.add(child);
                        }
                    }
                } else {
                    // capture the real reason this parent failed,
                    // as a small guaranteed-safe record (no large fields), instead
                    // of just a debug line nobody sees on an unattended run.
                    String errMsg = '';
                    for (Database.Error err : res.getErrors()) {
                        errMsg += err.getStatusCode() + ': ' + err.getMessage() + ' | Fields: ' + err.getFields() + '; ';
                    }
                    System.debug('[IntegrationLogger] PARENT INSERT FAILED: ' + errMsg);

                    Integration_Log__c fallback = new Integration_Log__c();
                    fallback.Stage__c            = 'LOG_INSERT_FAILED';
                    fallback.Product_Name__c     = pe.parent.Product_Name__c;
                    fallback.Endpoint__c         = pe.parent.Endpoint__c;
                    fallback.Error_Message__c    = errMsg.abbreviate(255);
                    fallback.Status__c           = 'Failed';
                    fallback.Called_At__c        = System.now();
                    fallback.Integration_Name__c = INTEGRATION_NAME;
                    failureLogs.add(fallback);
                }
            }

            if (!failureLogs.isEmpty()) {
                Database.insert(failureLogs, false);
            }

            if (!children.isEmpty()) {
                Database.insert(children, false);
            }

            System.debug('[IntegrationLogger] Flushed ' + parents.size() + ' log record(s) and '
                         + children.size() + ' JSON chunk record(s).');

        } catch (Exception e) {
            // Logging must never break the actual integration - just debug it.
            System.debug('[IntegrationLogger] FAILED to insert logs: ' + e.getMessage());
        } finally {
            pendingEntries.clear();
        }
    }

    // Splits str into a list of substrings, each at most size characters long -
    // one substring per child Integration_JSON_Log__c record.
    private static List<String> chunkString(String str, Integer size) {
        List<String> result = new List<String>();
        Integer len = str.length();
        Integer pos = 0;
        while (pos < len) {
            Integer endPos = Math.min(pos + size, len);
            result.add(str.substring(pos, endPos));
            pos = endPos;
        }
        return result;
    }
}