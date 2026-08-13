// New class: handles Tender_Docoment_Details__c inserts in their own
// transaction so they never compete with the Tender__c upsert / logs for
// the same product's 10,000-row DML limit.
public class TenderDocumentInsertQueueable implements Queueable {

    private List<Tender_Docoment_Details__c> docsToInsert;
    private String productName; // used only for logging on failure

    public TenderDocumentInsertQueueable(List<Tender_Docoment_Details__c> docsToInsert, String productName) {
        this.docsToInsert = docsToInsert;
        this.productName = productName;
    }

    public void execute(QueueableContext context) {
        if (docsToInsert == null || docsToInsert.isEmpty()) {
            return;
        }
        try {
            insert docsToInsert;
        } catch (Exception docEx) {
            IntegrationLogger.log(
                'DocInsertChunkFailed', productName,
                'doc-insert-queueable', null, docEx.getMessage(),
                null, false, docEx.getMessage()
            );
            IntegrationLogger.flush();
        }
    }
}