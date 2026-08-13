// ============================================================
// CLASS 5 — OCRDocFileService.cls  (NEW)
// Fetches all files attached to a specific OCR_DOC__c record
// Called by TenderAnalyzerController at the very start
// ============================================================
public with sharing class OCRDocFileService {

    // ─────────────────────────────────────────────────────────
// NEW — overloaded method — accepts recordId as parameter
// Called by Job1_UploadFilesQueueable
// Original getFiles() stays UNCHANGED for TenderAnalyzerController
// ─────────────────────────────────────────────────────────
public static List<ContentVersion> getFiles(String recordId) {

    System.debug('Fetching files for OCR_DOC__c ID: ' + recordId);

    List<OCR_DOC__c> ocrDocs = [
        SELECT Id, Name
        FROM   OCR_DOC__c
        WHERE  Id = :recordId
        LIMIT  1
    ];

    if (ocrDocs.isEmpty()) {
        System.debug('ERROR: OCR_DOC__c record not found: ' + recordId);
        return new List<ContentVersion>();
    }

    List<ContentDocumentLink> links = [
        SELECT ContentDocumentId
        FROM   ContentDocumentLink
        WHERE  LinkedEntityId = :recordId
    ];

    if (links.isEmpty()) {
        System.debug('ERROR: No files attached to record: ' + recordId);
        return new List<ContentVersion>();
    }

    Set<Id> contentDocIds = new Set<Id>();
    for (ContentDocumentLink link : links) {
        contentDocIds.add(link.ContentDocumentId);
    }

    return [
        SELECT  Id, Title, FileExtension,
                ContentSize, VersionData,
                CreatedDate, CreatedBy.Name
        FROM    ContentVersion
        WHERE   ContentDocumentId IN :contentDocIds
        AND     IsLatest = true
        ORDER BY CreatedDate ASC
    ];
}
}