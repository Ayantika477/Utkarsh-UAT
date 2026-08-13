public with sharing class PolymerHDPEKeywordService {

    public class KeywordConfig {
        public String  label;
        public String  positiveKeywords;
        public String  negativeKeywords;
        public String  schemaPrompt;
        public Boolean isExcluded;
        public Boolean isRelevant;
    }

    // Returns a map keyed by Label: "Polymer - Excluded" / "Polymer - Relevant"
    public static Map<String, KeywordConfig> getPolymerKeywords() {
        Map<String, KeywordConfig> result = new Map<String, KeywordConfig>();

        List<Tender_Key_words_Final__mdt> mdtList = [
            SELECT Label, Matched_Positive_Keywords__c, Matched_Negative_Keywords__c,
                   Schema_Prompt__c, Is_Excluded__c, Is_Relevant__c
            FROM Tender_Key_words_Final__mdt
            WHERE Label = 'Polymer - Relevant' OR Label = 'Polymer - Excluded'
        ];

        for (Tender_Key_words_Final__mdt m : mdtList) {
            KeywordConfig kc     = new KeywordConfig();
            kc.label             = m.Label;
            kc.positiveKeywords  = m.Matched_Positive_Keywords__c;
            kc.negativeKeywords  = m.Matched_Negative_Keywords__c;
            kc.schemaPrompt      = m.Schema_Prompt__c;
            kc.isExcluded        = m.Is_Excluded__c;
            kc.isRelevant        = m.Is_Relevant__c;
            result.put(m.Label, kc);
        }

        System.debug('PolymerHDPEKeywordService: loaded ' + result.size() + ' keyword configs.');
        return result;
    }
}