/*
public with sharing class PolymerHDPEBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    private Map<String, PolymerHDPEKeywordService.KeywordConfig> keywordMap;
    private static final Integer SUMMARY_MAX_LEN = 131072; // Long Text Area hard cap

    public PolymerHDPEBatch() {
        this.keywordMap = PolymerHDPEKeywordService.getPolymerKeywords();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('PolymerHDPEBatch START');
        return Database.getQueryLocator([
            SELECT Id, Name, MergeProduct__c, Product_Name__c,
                   Is_checked_Polymer_HDPE__c, Reading_Polymer_HDPE_summary__c,
                   (
                       SELECT Id, Name__c, Type__c, Download_URL__c, Download_URL_Text__c, Document_Id__c, CreatedDate
FROM Tender_Docoment_Details__r
                    ORDER BY CreatedDate DESC)
            FROM Tender__c
            //WHERE MergeProduct__c = true AND Is_checked_Polymer_HDPE__c = false
            WHERE MergeProduct__c = true AND Department_Name__c = null AND CreatedDate = TODAY
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Tender__c> scope) {

        PolymerHDPEKeywordService.KeywordConfig excludedCfg = keywordMap != null ? keywordMap.get('Polymer - Excluded') : null;
        PolymerHDPEKeywordService.KeywordConfig relevantCfg = keywordMap != null ? keywordMap.get('Polymer - Relevant') : null;

        List<Tender__c> toUpdate = new List<Tender__c>();

        for (Tender__c t : scope) {

            String  summary        = '=== Polymer/HDPE Check for Tender: ' + t.Name + ' (Id: ' + t.Id + ') ===\n';
            summary += 'Started: ' + System.now().format() + '\n\n';
            String  matchedProduct = null;

            try {
                if (excludedCfg == null && relevantCfg == null) {
                    summary += 'FAILED: Could not load "Polymer - Relevant" / "Polymer - Excluded" metadata records from Tender_Key_words_Final__mdt. Aborting this record.\n';
                    toUpdate.add(buildUpdateRecord(t.Id, null, summary));
                    continue;
                }

                List<Tender_Docoment_Details__c> docs = t.Tender_Docoment_Details__r;

                if (docs == null || docs.isEmpty()) {
                    summary += 'No Tender_Docoment_Details__c child records found. Nothing to process.\n';
                    summary += 'FINAL RESULT: No match found. Product Name left unchanged.\n';
                    toUpdate.add(buildUpdateRecord(t.Id, null, summary));
                    continue;
                }

                Boolean matchFound = false;

                for (Tender_Docoment_Details__c d : docs) {

                    if (matchFound) break;

                    String fileLabel = String.isNotBlank(d.Name__c) ? d.Name__c : ('DocId:' + d.Document_Id__c);

                    PolymerHDPEFileUtil.SupportCheck sc = PolymerHDPEFileUtil.checkSupport(d.Name__c);

                    if (!sc.isSupported) {
                        summary += 'SKIPPED "' + fileLabel + '" (Type: ' + d.Type__c + ') - Reason: ' + sc.reason + '\n';
                        continue;
                    }
                    
                    
                    
                    String effectiveUrl = String.isNotBlank(d.Download_URL__c)
    ? d.Download_URL__c
    : d.Download_URL_Text__c;

if (String.isBlank(effectiveUrl)) {
    summary += 'SKIPPED "' + fileLabel + '" - Reason: Both Download_URL__c and Download_URL_Text__c are blank.\n';
    continue;
}

Blob fileBytes = null;
try {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(effectiveUrl);
    req.setMethod('GET');
    req.setTimeout(120000);

 

                        Http         http = new Http();
                        HttpResponse res  = http.send(req);

                        if (res.getStatusCode() != 200) {
                            summary += 'ERROR downloading "' + fileLabel + '" - HTTP Status: ' + res.getStatusCode() + '. Skipping to next file.\n';
                            continue;
                        }
                        fileBytes = res.getBodyAsBlob();

                    } catch (Exception de) {
                        summary += 'ERROR downloading "' + fileLabel + '" - Exception: ' + de.getMessage() + '. Skipping to next file.\n';
                        continue;
                    }

                    if (fileBytes == null || fileBytes.size() == 0) {
                        summary += 'SKIPPED "' + fileLabel + '" - Downloaded content is empty.\n';
                        continue;
                    }

                    summary += 'READING "' + fileLabel + '" (Type: ' + d.Type__c + ', MIME: ' + sc.mimeType + ', Size: ' + fileBytes.size() + ' bytes)\n';

                    PolymerHDPEGeminiService.MatchResult mr = PolymerHDPEGeminiService.checkFile(
                        fileBytes, sc.mimeType, fileLabel, excludedCfg, relevantCfg
                    );

                    if (mr.hadError) {
                        summary += 'ERROR analyzing "' + fileLabel + '" via Gemini: ' + mr.errorMessage + '. Skipping to next file.\n';
                        continue;
                    }

                    if (mr.excludedMatched) {
                        matchedProduct = 'HDPE';
                        matchFound     = true;
                        summary += 'MATCH in "' + fileLabel + '": Polymer-Excluded criteria matched -> Product = HDPE.\n';
                        summary += 'Reasoning: ' + mr.reasoning + '\n';
                    } else if (mr.relevantMatched) {
                        matchedProduct = 'Polymer';
                        matchFound     = true;
                        summary += 'MATCH in "' + fileLabel + '": Polymer-Relevant criteria matched -> Product = Polymer.\n';
                        summary += 'Reasoning: ' + mr.reasoning + '\n';
                    } else {
                        summary += 'No match in "' + fileLabel + '" (neither Excluded nor Relevant). Reasoning: ' + mr.reasoning + '. Moving to next file.\n';
                    }
                }

                if (matchFound) {
                    summary += '\nFINAL RESULT: SUCCESS. Product Name updated to "' + matchedProduct + '".\n';
                } else {
                    summary += '\nFINAL RESULT: No product matched after checking all supported files. Product Name left unchanged.\n';
                }

            } catch (Exception ex) {
                summary += '\nUNEXPECTED ERROR while processing this Tender: ' + ex.getMessage() + '\n';
                System.debug('PolymerHDPEBatch record-level error for ' + t.Id + ': ' + ex.getMessage() + ' | ' + ex.getStackTraceString());
            }

            toUpdate.add(buildUpdateRecord(t.Id, matchedProduct, summary));
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> results = Database.update(toUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    System.debug('DML FAILED for Tender Id: ' + toUpdate[i].Id + ' | Errors: ' + results[i].getErrors());
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('PolymerHDPEBatch FINISHED.');
    }

    private static Tender__c buildUpdateRecord(Id tenderId, String matchedProduct, String summary) {
        Tender__c upd = new Tender__c(
            Id                                = tenderId,
            Is_checked_Polymer_HDPE__c       = true,
            Reading_Polymer_HDPE_summary__c  = truncateSummary(summary)
        );
        if (matchedProduct != null) {
            upd.Product_Name__c = matchedProduct;
        }
        return upd;
    }

    private static String truncateSummary(String summary) {
        if (summary.length() > SUMMARY_MAX_LEN) {
            return summary.substring(0, SUMMARY_MAX_LEN - 30) + '\n...[TRUNCATED - see logs]';
        }
        return summary;
    }
}
*/
/*
public with sharing class PolymerHDPEBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    private Map<String, PolymerHDPEKeywordService.KeywordConfig> keywordMap;
    private static final Integer SUMMARY_MAX_LEN = 131072; // Long Text Area hard cap

    public PolymerHDPEBatch() {
        this.keywordMap = PolymerHDPEKeywordService.getPolymerKeywords();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('PolymerHDPEBatch START');
        return Database.getQueryLocator([
            SELECT Id, Name, MergeProduct__c, Product_Name__c,
                   Is_checked_Polymer_HDPE__c, Reading_Polymer_HDPE_summary__c,
                   (
                       SELECT Id, Name__c, Type__c, Download_URL__c, Download_URL_Text__c, Document_Id__c, CreatedDate
FROM Tender_Docoment_Details__r
                    ORDER BY CreatedDate DESC)
            FROM Tender__c
            //WHERE MergeProduct__c = true AND Is_checked_Polymer_HDPE__c = false
            WHERE MergeProduct__c = true AND Department_Name__c = null AND CreatedDate = TODAY AND Polymer_HDPE_Stage_Check__c NOT IN (
    'Matched',
    'Checked - No Match',
    'No Supported Files')
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Tender__c> scope) {

        PolymerHDPEKeywordService.KeywordConfig excludedCfg = keywordMap != null ? keywordMap.get('Polymer - Excluded') : null;
        PolymerHDPEKeywordService.KeywordConfig relevantCfg = keywordMap != null ? keywordMap.get('Polymer - Relevant') : null;

        List<Tender__c> toUpdate = new List<Tender__c>();

        for (Tender__c t : scope) {

            String  summary        = '=== Polymer/HDPE Check for Tender: ' + t.Name + ' (Id: ' + t.Id + ') ===\n';
            summary += 'Started: ' + System.now().format() + '\n\n';
            String  matchedProduct = null;
            Boolean properlyChecked = false;
            String  stageStatus     = 'Failed - Unexpected Error';

            try {

                List<Tender_Docoment_Details__c> docs = t.Tender_Docoment_Details__r;

                if (docs == null || docs.isEmpty()) {
                    summary += 'No Tender_Docoment_Details__c child records found. Nothing to process.\n';
                    summary += 'FINAL RESULT: No match found. Product Name left unchanged.\n';
                    System.debug('PolymerHDPEBatch: no child documents for Tender Id: ' + t.Id);
                    //toUpdate.add(buildUpdateRecord(t.Id, null, summary));
                    toUpdate.add(buildUpdateRecord(t.Id, null, summary, false, 'Failed - No Documents'));
                    continue;
                }

                Boolean matchFound = false;
                Boolean hadProcessingError = false;
                Boolean anySupportedFileFound = false;
                for (Tender_Docoment_Details__c d : docs) {

                    if (matchFound) break;

                    String fileLabel = String.isNotBlank(d.Name__c) ? d.Name__c : ('DocId:' + d.Document_Id__c);

                    PolymerHDPEFileUtil.SupportCheck sc = PolymerHDPEFileUtil.checkSupport(d.Name__c);

                    if (!sc.isSupported) {
                        summary += 'SKIPPED "' + fileLabel + '" (Type: ' + d.Type__c + ') - Reason: ' + sc.reason + '\n';
                        System.debug('PolymerHDPEBatch: unsupported file skipped - ' + fileLabel);
                        continue;
                    }

                    anySupportedFileFound = true;
                    
                    
                    
                    String effectiveUrl = String.isNotBlank(d.Download_URL__c)
    ? d.Download_URL__c
    : d.Download_URL_Text__c;

if (String.isBlank(effectiveUrl)) {
    summary += 'SKIPPED "' + fileLabel + '" - Reason: Both Download_URL__c and Download_URL_Text__c are blank.\n';
    System.debug('PolymerHDPEBatch: blank download URL for file - ' + fileLabel);
    continue;
}

Blob fileBytes = null;
try {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(effectiveUrl);
    req.setMethod('GET');
    req.setTimeout(120000);

                        Http         http = new Http();
                        HttpResponse res  = http.send(req);

                        System.debug('PolymerHDPEBatch: download status ' + res.getStatusCode() + ' for file - ' + fileLabel);

                        if (res.getStatusCode() != 200) {
                            summary += 'ERROR downloading "' + fileLabel + '" - HTTP Status: ' + res.getStatusCode() + '. Skipping to next file.\n';
                            hadProcessingError = true;
                            continue;
                        }
                        fileBytes = res.getBodyAsBlob();

                    } catch (Exception de) {
                        summary += 'ERROR downloading "' + fileLabel + '" - Exception: ' + de.getMessage() + '. Skipping to next file.\n';
                        System.debug('PolymerHDPEBatch: download exception for file ' + fileLabel + ' - ' + de.getMessage());
                        hadProcessingError = true;
                        continue;
                    }

                    if (fileBytes == null || fileBytes.size() == 0) {
                        summary += 'SKIPPED "' + fileLabel + '" - Downloaded content is empty.\n';
                        System.debug('PolymerHDPEBatch: empty content for file - ' + fileLabel);
                        hadProcessingError = true;
                        continue;
                    }

                    summary += 'READING "' + fileLabel + '" (Type: ' + d.Type__c + ', MIME: ' + sc.mimeType + ', Size: ' + fileBytes.size() + ' bytes)\n';
                    System.debug('PolymerHDPEBatch: sending file to Gemini - ' + fileLabel + ' (' + fileBytes.size() + ' bytes)');

                    PolymerHDPEGeminiService.MatchResult mr = PolymerHDPEGeminiService.checkFile(
                        fileBytes, sc.mimeType, fileLabel, excludedCfg, relevantCfg
                    );

                    if (mr.hadError) {
                        summary += 'ERROR analyzing "' + fileLabel + '" via Gemini: ' + mr.errorMessage + '. Skipping to next file.\n';
                        System.debug('PolymerHDPEBatch: Gemini error for file ' + fileLabel + ' - ' + mr.errorMessage);
                        hadProcessingError = true;
                        continue;
                    }

                    System.debug('PolymerHDPEBatch: Gemini result for ' + fileLabel + ' - excludedMatched=' + mr.excludedMatched + ', relevantMatched=' + mr.relevantMatched);

                    if (mr.excludedMatched) {
                        matchedProduct = 'HDPE';
                        matchFound     = true;
                        summary += 'MATCH in "' + fileLabel + '": Polymer-Excluded criteria matched -> Product = HDPE.\n';
                        summary += 'Reasoning: ' + mr.reasoning + '\n';
                    } else if (mr.relevantMatched) {
                        matchedProduct = 'Polymer';
                        matchFound     = true;
                        summary += 'MATCH in "' + fileLabel + '": Polymer-Relevant criteria matched -> Product = Polymer.\n';
                        summary += 'Reasoning: ' + mr.reasoning + '\n';
                    } else {
                        summary += 'No match in "' + fileLabel + '" (neither Excluded nor Relevant). Reasoning: ' + mr.reasoning + '. Moving to next file.\n';
                        matchedProduct = 'HDPE';
                    }
                }

if (matchFound) {
    summary += '\nFINAL RESULT: SUCCESS. Product Name updated to "' + matchedProduct + '".\n';
    properlyChecked = true;
    stageStatus     = 'Matched';
} else if (hadProcessingError) {
    summary += '\nFINAL RESULT: No product matched, but one or more files FAILED to be analyzed properly (Gemini/download error). Marking as NOT checked so it retries later.\n';
    properlyChecked = false;
    stageStatus     = 'Failed - Will Retry';
    matchedProduct  = 'HDPE';
} else if (!anySupportedFileFound) {
    summary += '\nFINAL RESULT: No supported file types found to analyze (only unsupported formats present).\n';
    properlyChecked = true;
    stageStatus     = 'No Supported Files';
} else {
    summary += '\nFINAL RESULT: No product matched after checking all supported files properly. Product Name left unchanged.\n';
    properlyChecked = true;
    stageStatus     = 'Checked - No Match';
}

System.debug('PolymerHDPEBatch: Tender ' + t.Id + ' - matchFound=' + matchFound + ', hadProcessingError=' + hadProcessingError + ', anySupportedFileFound=' + anySupportedFileFound + ', properlyChecked=' + properlyChecked + ', stageStatus=' + stageStatus + ', matchedProduct=' + matchedProduct);

            } catch (Exception ex) {
                summary += '\nUNEXPECTED ERROR while processing this Tender: ' + ex.getMessage() + '\n';
                System.debug('PolymerHDPEBatch record-level error for ' + t.Id + ': ' + ex.getMessage() + ' | ' + ex.getStackTraceString());
                properlyChecked = false;
                stageStatus     = 'Failed - Unexpected Error';
                matchedProduct = 'HDPE';
            }

            //toUpdate.add(buildUpdateRecord(t.Id, matchedProduct, summary));
            toUpdate.add(buildUpdateRecord(t.Id, matchedProduct, summary, properlyChecked, stageStatus));
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> results = Database.update(toUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    System.debug('DML FAILED for Tender Id: ' + toUpdate[i].Id + ' | Errors: ' + results[i].getErrors());
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('PolymerHDPEBatch FINISHED.');
    }
    
    private static Tender__c buildUpdateRecord(Id tenderId, String matchedProduct, String summary, Boolean properlyChecked, String stageStatus) {
    System.debug('PolymerHDPEBatch: buildUpdateRecord - Tender Id: ' + tenderId + ', matchedProduct: ' + matchedProduct + ', properlyChecked: ' + properlyChecked + ', stageStatus: ' + stageStatus);
    Tender__c upd = new Tender__c(
        Id                                = tenderId,
        Is_checked_Polymer_HDPE__c       = properlyChecked,  
        Reading_Polymer_HDPE_summary__c  = truncateSummary(summary),
        Polymer_HDPE_Stage_Check__c      = stageStatus
    );
    if (matchedProduct != null) {
        upd.Product_Name__c    = matchedProduct;
        upd.Department_Name__c = matchedProduct;
        System.debug('PolymerHDPEBatch: Department_Name__c set to "' + matchedProduct + '" for Tender Id: ' + tenderId);
    }
    return upd;
}
    private static String truncateSummary(String summary) {
        if (summary.length() > SUMMARY_MAX_LEN) {
            return summary.substring(0, SUMMARY_MAX_LEN - 30) + '\n...[TRUNCATED - see logs]';
        }
        return summary;
    }
}*/
public with sharing class PolymerHDPEBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    private Map<String, PolymerHDPEKeywordService.KeywordConfig> keywordMap;
    private static final Integer SUMMARY_MAX_LEN = 131072; // Long Text Area hard cap

    public PolymerHDPEBatch() {
        this.keywordMap = PolymerHDPEKeywordService.getPolymerKeywords();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('PolymerHDPEBatch START');
        return Database.getQueryLocator([
            SELECT Id, Name, MergeProduct__c, Product_Name__c,
                   Is_checked_Polymer_HDPE__c, Reading_Polymer_HDPE_summary__c,
                   (
                       SELECT Id, Name__c, Type__c, Download_URL__c, Download_URL_Text__c, Document_Id__c, CreatedDate
                       FROM Tender_Docoment_Details__r
                       ORDER BY CreatedDate DESC)
            FROM Tender__c
            //WHERE MergeProduct__c = true AND Is_checked_Polymer_HDPE__c = false
            WHERE MergeProduct__c = true AND Department_Name__c = null AND CreatedDate = TODAY AND Polymer_HDPE_Stage_Check__c NOT IN (
    'Matched',
    'Checked - No Match',
    'No Supported Files')
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Tender__c> scope) {

        PolymerHDPEKeywordService.KeywordConfig excludedCfg = keywordMap != null ? keywordMap.get('Polymer - Excluded') : null;
        PolymerHDPEKeywordService.KeywordConfig relevantCfg = keywordMap != null ? keywordMap.get('Polymer - Relevant') : null;

        List<Tender__c> toUpdate = new List<Tender__c>();

        for (Tender__c t : scope) {

            String  summary        = '=== Polymer/HDPE Check for Tender: ' + t.Name + ' (Id: ' + t.Id + ') ===\n';
            summary += 'Started: ' + System.now().format() + '\n\n';
            String  matchedProduct = null;
            Boolean properlyChecked = false;
            String  stageStatus     = 'Failed - Unexpected Error';

            try {
                if (excludedCfg == null && relevantCfg == null) {
                    summary += 'FAILED: Could not load "Polymer - Relevant" / "Polymer - Excluded" metadata records from Tender_Key_words_Final__mdt. Aborting this record.\n';
                    System.debug('PolymerHDPEBatch: keyword metadata missing for Tender Id: ' + t.Id);
                    toUpdate.add(buildUpdateRecord(t.Id, 'HDPE', summary, false, 'Failed - Config Error'));
                    continue;
                }

                List<Tender_Docoment_Details__c> docs = t.Tender_Docoment_Details__r;

                if (docs == null || docs.isEmpty()) {
                    summary += 'No Tender_Docoment_Details__c child records found. Nothing to process.\n';
                    summary += 'FINAL RESULT: No documents to analyze. Defaulting to HDPE.\n';
                    System.debug('PolymerHDPEBatch: no child documents for Tender Id: ' + t.Id);
                    toUpdate.add(buildUpdateRecord(t.Id, 'HDPE', summary, false, 'Failed - No Documents'));
                    continue;
                }

                Boolean matchFound = false;
                Boolean hadProcessingError = false;
                Boolean anySupportedFileFound = false;
                for (Tender_Docoment_Details__c d : docs) {

                    if (matchFound) break;

                    String fileLabel = String.isNotBlank(d.Name__c) ? d.Name__c : ('DocId:' + d.Document_Id__c);

                    PolymerHDPEFileUtil.SupportCheck sc = PolymerHDPEFileUtil.checkSupport(d.Name__c);

                    if (!sc.isSupported) {
                        summary += 'SKIPPED "' + fileLabel + '" (Type: ' + d.Type__c + ') - Reason: ' + sc.reason + '\n';
                        System.debug('PolymerHDPEBatch: unsupported file skipped - ' + fileLabel);
                        continue;
                    }

                    anySupportedFileFound = true;

                    String effectiveUrl = String.isNotBlank(d.Download_URL__c)
                        ? d.Download_URL__c
                        : d.Download_URL_Text__c;

                    if (String.isBlank(effectiveUrl)) {
                        summary += 'SKIPPED "' + fileLabel + '" - Reason: Both Download_URL__c and Download_URL_Text__c are blank.\n';
                        System.debug('PolymerHDPEBatch: blank download URL for file - ' + fileLabel);
                        continue;
                    }

                    Blob fileBytes = null;
                    try {
                        HttpRequest req = new HttpRequest();
                        req.setEndpoint(effectiveUrl);
                        req.setMethod('GET');
                        req.setTimeout(120000);

                        Http         http = new Http();
                        HttpResponse res  = http.send(req);

                        System.debug('PolymerHDPEBatch: download status ' + res.getStatusCode() + ' for file - ' + fileLabel);

                        if (res.getStatusCode() != 200) {
                            summary += 'ERROR downloading "' + fileLabel + '" - HTTP Status: ' + res.getStatusCode() + '. Skipping to next file.\n';
                            hadProcessingError = true;
                            continue;
                        }
                        fileBytes = res.getBodyAsBlob();

                    } catch (Exception de) {
                        summary += 'ERROR downloading "' + fileLabel + '" - Exception: ' + de.getMessage() + '. Skipping to next file.\n';
                        System.debug('PolymerHDPEBatch: download exception for file ' + fileLabel + ' - ' + de.getMessage());
                        hadProcessingError = true;
                        continue;
                    }

                    if (fileBytes == null || fileBytes.size() == 0) {
                        summary += 'SKIPPED "' + fileLabel + '" - Downloaded content is empty.\n';
                        System.debug('PolymerHDPEBatch: empty content for file - ' + fileLabel);
                        hadProcessingError = true;
                        continue;
                    }

                    summary += 'READING "' + fileLabel + '" (Type: ' + d.Type__c + ', MIME: ' + sc.mimeType + ', Size: ' + fileBytes.size() + ' bytes)\n';
                    System.debug('PolymerHDPEBatch: sending file to Gemini - ' + fileLabel + ' (' + fileBytes.size() + ' bytes)');

                    PolymerHDPEGeminiService.MatchResult mr = PolymerHDPEGeminiService.checkFile(
                        fileBytes, sc.mimeType, fileLabel, excludedCfg, relevantCfg
                    );

                    if (mr.hadError) {
                        summary += 'ERROR analyzing "' + fileLabel + '" via Gemini: ' + mr.errorMessage + '. Skipping to next file.\n';
                        System.debug('PolymerHDPEBatch: Gemini error for file ' + fileLabel + ' - ' + mr.errorMessage);
                        hadProcessingError = true;
                        continue;
                    }

                    System.debug('PolymerHDPEBatch: Gemini result for ' + fileLabel + ' - excludedMatched=' + mr.excludedMatched + ', relevantMatched=' + mr.relevantMatched);

                    if (mr.excludedMatched) {
                        matchedProduct = 'HDPE';
                        matchFound     = true;
                        summary += 'MATCH in "' + fileLabel + '": Polymer-Excluded criteria matched -> Product = HDPE.\n';
                        summary += 'Reasoning: ' + mr.reasoning + '\n';
                    } else if (mr.relevantMatched) {
                        matchedProduct = 'Polymer';
                        matchFound     = true;
                        summary += 'MATCH in "' + fileLabel + '": Polymer-Relevant criteria matched -> Product = Polymer.\n';
                        summary += 'Reasoning: ' + mr.reasoning + '\n';
                    } else {
                        summary += 'No match in "' + fileLabel + '" (neither Excluded nor Relevant). Reasoning: ' + mr.reasoning + '. Moving to next file.\n';
                        matchedProduct = 'HDPE';
                    }
                }

                if (matchFound) {
                    summary += '\nFINAL RESULT: SUCCESS. Product Name updated to "' + matchedProduct + '".\n';
                    properlyChecked = true;
                    stageStatus     = 'Matched';
                } else if (hadProcessingError) {
                    summary += '\nFINAL RESULT: No product matched, but one or more files FAILED to be analyzed properly (Gemini/download error). Defaulting to HDPE.\n';
                    properlyChecked = false;
                    stageStatus     = 'Failed - Will Retry';
                    matchedProduct  = 'HDPE';
                } else if (!anySupportedFileFound) {
                    summary += '\nFINAL RESULT: No supported file types found to analyze (only unsupported formats present). Defaulting to HDPE.\n';
                    properlyChecked = true;
                    stageStatus     = 'No Supported Files';
                    matchedProduct  = 'HDPE';
                } else {
                    summary += '\nFINAL RESULT: No product matched after checking all supported files properly. Defaulting to HDPE.\n';
                    properlyChecked = true;
                    stageStatus     = 'Checked - No Match';
                    matchedProduct  = 'HDPE';
                }

                System.debug('PolymerHDPEBatch: Tender ' + t.Id + ' - matchFound=' + matchFound + ', hadProcessingError=' + hadProcessingError + ', anySupportedFileFound=' + anySupportedFileFound + ', properlyChecked=' + properlyChecked + ', stageStatus=' + stageStatus + ', matchedProduct=' + matchedProduct);

            } catch (Exception ex) {
                summary += '\nUNEXPECTED ERROR while processing this Tender: ' + ex.getMessage() + '\n';
                System.debug('PolymerHDPEBatch record-level error for ' + t.Id + ': ' + ex.getMessage() + ' | ' + ex.getStackTraceString());
                properlyChecked = false;
                stageStatus     = 'Failed - Unexpected Error';
                matchedProduct  = 'HDPE';
            }

            toUpdate.add(buildUpdateRecord(t.Id, matchedProduct, summary, properlyChecked, stageStatus));
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> results = Database.update(toUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    System.debug('DML FAILED for Tender Id: ' + toUpdate[i].Id + ' | Errors: ' + results[i].getErrors());
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('PolymerHDPEBatch FINISHED.');
    }

    private static Tender__c buildUpdateRecord(Id tenderId, String matchedProduct, String summary, Boolean properlyChecked, String stageStatus) {
        System.debug('PolymerHDPEBatch: buildUpdateRecord - Tender Id: ' + tenderId + ', matchedProduct: ' + matchedProduct + ', properlyChecked: ' + properlyChecked + ', stageStatus: ' + stageStatus);
        Tender__c upd = new Tender__c(
            Id                                = tenderId,
            Is_checked_Polymer_HDPE__c       = properlyChecked,
            Reading_Polymer_HDPE_summary__c  = truncateSummary(summary),
            Polymer_HDPE_Stage_Check__c      = stageStatus
        );
        if (matchedProduct != null) {
            upd.Product_Name__c    = matchedProduct;
            upd.Department_Name__c = matchedProduct;
            System.debug('PolymerHDPEBatch: Department_Name__c set to "' + matchedProduct + '" for Tender Id: ' + tenderId);
        }
        return upd;
    }

    private static String truncateSummary(String summary) {
        if (summary.length() > SUMMARY_MAX_LEN) {
            return summary.substring(0, SUMMARY_MAX_LEN - 30) + '\n...[TRUNCATED - see logs]';
        }
        return summary;
    }
}