public with sharing class OCRDocController {

    // ১. OCR record তৈরি
    @AuraEnabled
    public static Id initUpload(Integer fileCount) {
        OCR_DOC__c doc = new OCR_DOC__c(
            AI_Status__c = 'Uploading',
            Uploaded_File_Count__c = fileCount
        );
        insert doc;
        return doc.Id;
    }

    // ২. Chunk upload — প্রতিটা chunk আলাদা Apex call
    // memory-তে শুধু একটা chunk (750KB) থাকবে, পুরো ফাইল না
    @AuraEnabled
    public static Id uploadChunk(
        Id docRecordId,
        String fileName,
        String base64Chunk,
        Integer chunkIndex,
        Integer totalChunks,
        Id contentVersionId
    ) {
        if (chunkIndex == 0) {
            // প্রথম chunk → নতুন ContentVersion তৈরি
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = EncodingUtil.base64Decode(base64Chunk);
            cv.IsMajorVersion = false;
            insert cv;

            // OCR record-এর সাথে link করো
            ContentVersion inserted = [
                SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
            ];
            insert new ContentDocumentLink(
                ContentDocumentId = inserted.ContentDocumentId,
                LinkedEntityId = docRecordId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );

            return cv.Id;

        } else {
            // পরের chunk → আগের version-এর সাথে append
            // Salesforce ContentVersion append pattern
            ContentVersion prev = [
                SELECT ContentDocumentId, VersionData
                FROM ContentVersion
                WHERE Id = :contentVersionId
            ];

            // আগের data + নতুন chunk একসাথে
            // Note: ছোট ফাইলে ঠিক আছে, বড় ফাইলে নিচের Gemini File API approach ব্যবহার করো
            Blob combined = mergeBlobs(prev.VersionData, EncodingUtil.base64Decode(base64Chunk));

            ContentVersion newVersion = new ContentVersion();
            newVersion.ContentDocumentId = prev.ContentDocumentId;
            newVersion.Title = prev.Title; // Title আগেরটা থেকে নাও লাগবে
            newVersion.PathOnClient = prev.Title;
            newVersion.VersionData = combined;
            newVersion.IsMajorVersion = false;
            insert newVersion;

            return newVersion.Id;
        }
    }

    // ৩. Upload শেষ → Queueable চালু করো
    @AuraEnabled
    public static void finalizeUpload(Id docRecordId) {
        update new OCR_DOC__c(
            Id = docRecordId,
            AI_Status__c = 'Pending'
        );
        System.enqueueJob(new TenderAnalysisQueueable(docRecordId));
    }

    // Blob merge helper
    private static Blob mergeBlobs(Blob a, Blob b) {
        String combinedBase64 =
            EncodingUtil.base64Encode(a) +
            EncodingUtil.base64Encode(b);
        return EncodingUtil.base64Decode(combinedBase64);
    }
}