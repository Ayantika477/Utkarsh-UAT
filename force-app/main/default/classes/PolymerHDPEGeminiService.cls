public with sharing class PolymerHDPEGeminiService {

    public class MatchResult {
        public Boolean excludedMatched = false;
        public Boolean relevantMatched = false;
        public String  reasoning       = '';
        public Boolean hadError        = false;
        public String  errorMessage    = '';
    }

    public static MatchResult checkFile(
        Blob   fileBytes,
        String mimeType,
        String fileName,
        PolymerHDPEKeywordService.KeywordConfig excludedCfg,
        PolymerHDPEKeywordService.KeywordConfig relevantCfg
    ) {
        MatchResult result = new MatchResult();

        try {
            String prompt     = buildPrompt(fileName, excludedCfg, relevantCfg);
            String base64Data = EncodingUtil.base64Encode(fileBytes);

            List<Object> parts = new List<Object>();
            parts.add(new Map<String, Object>{ 'text' => prompt });
            parts.add(new Map<String, Object>{
                'inline_data' => new Map<String, Object>{
                    'mime_type' => mimeType,
                    'data'      => base64Data
                }
            });

            Map<String, Object> body = new Map<String, Object>{
                'contents' => new List<Object>{
                    new Map<String, Object>{ 'parts' => parts }
                },
                'generationConfig' => new Map<String, Object>{
                    'temperature'      => 0.1,
                    'responseMimeType' => 'application/json'
                }
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Gemini/v1beta/models/gemini-2.5-flash:generateContent');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(120000);
            req.setBody(JSON.serialize(body));

            Http         http = new Http();
            HttpResponse res  = http.send(req);

            System.debug('Gemini Polymer/HDPE check status: ' + res.getStatusCode() + ' for file: ' + fileName);

            if (res.getStatusCode() != 200) {
                result.hadError     = true;
                result.errorMessage = 'Gemini call failed - Status: ' + res.getStatusCode()
                    + ' | Body: ' + (res.getBody() != null ? res.getBody().left(300) : '');
                return result;
            }

            String text = extractText(res.getBody());
            if (String.isBlank(text)) {
                result.hadError     = true;
                result.errorMessage = 'Empty/unreadable Gemini response for file: ' + fileName;
                return result;
            }

            Map<String, Object> parsed;
            try {
                parsed = (Map<String, Object>) JSON.deserializeUntyped(text);
            } catch (Exception pe) {
                result.hadError     = true;
                result.errorMessage = 'Could not parse Gemini JSON for file "' + fileName + '": ' + pe.getMessage();
                return result;
            }

            result.excludedMatched = parsed.containsKey('excludedMatched') && parsed.get('excludedMatched') == true;
            result.relevantMatched = parsed.containsKey('relevantMatched') && parsed.get('relevantMatched') == true;
            result.reasoning       = parsed.containsKey('reasoning') ? String.valueOf(parsed.get('reasoning')) : '';

        } catch (Exception e) {
            result.hadError     = true;
            result.errorMessage = 'Exception in checkFile for "' + fileName + '": ' + e.getMessage();
            System.debug('PolymerHDPEGeminiService ERROR: ' + e.getMessage() + ' | ' + e.getStackTraceString());
        }

        return result;
    }

    private static String buildPrompt(
        String fileName,
        PolymerHDPEKeywordService.KeywordConfig excludedCfg,
        PolymerHDPEKeywordService.KeywordConfig relevantCfg
    ) {
        String prompt = 'You are a Tender Document Analyzer. Your ONLY task here is to decide between two outcomes: Polymer-Excluded (product is HDPE) or Polymer-Relevant (product is Polymer). Ignore all other categories.\n\n';
        prompt += 'File being analyzed: ' + fileName + '\n\n';

        prompt += '--- POLYMER EXCLUDED CRITERIA (check this FIRST) ---\n';
        if (excludedCfg != null) {
            if (String.isNotBlank(excludedCfg.negativeKeywords)) {
                prompt += 'If ANY of these keywords/phrases are present in the document, it is EXCLUDED (product = HDPE): '
                    + excludedCfg.negativeKeywords + '\n';
            }
            if (String.isNotBlank(excludedCfg.schemaPrompt)) {
                prompt += 'Additional instruction: ' + excludedCfg.schemaPrompt + '\n';
            }
        } else {
            prompt += '(No Excluded criteria configured)\n';
        }

        prompt += '\n--- POLYMER RELEVANT CRITERIA (check ONLY if NOT excluded) ---\n';
        if (relevantCfg != null) {
            if (String.isNotBlank(relevantCfg.positiveKeywords)) {
                prompt += 'If ANY of these keywords/phrases are present in the document, it is RELEVANT (product = Polymer): '
                    + relevantCfg.positiveKeywords + '\n';
            }
            if (String.isNotBlank(relevantCfg.schemaPrompt)) {
                prompt += 'Additional instruction: ' + relevantCfg.schemaPrompt + '\n';
            }
        } else {
            prompt += '(No Relevant criteria configured)\n';
        }

        prompt += '\n--- INSTRUCTIONS ---\n';
        prompt += 'Read the attached document carefully.\n';
        prompt += 'Step 1: Check the Excluded criteria. If matched, set excludedMatched=true and relevantMatched=false, and stop.\n';
        prompt += 'Step 2: If NOT excluded, check the Relevant criteria. If matched, set relevantMatched=true.\n';
        prompt += 'Step 3: If neither matched, set both to false.\n';
        prompt += 'Return ONLY a valid JSON object. No markdown. No explanation outside the JSON.\n\n';
        prompt += '{\n';
        prompt += '  "excludedMatched": true/false,\n';
        prompt += '  "relevantMatched": true/false,\n';
        prompt += '  "reasoning": "<brief explanation - which specific keyword(s) or content led to this decision, or why neither matched>"\n';
        prompt += '}';

        return prompt;
    }

    private static String extractText(String responseBody) {
        try {
            Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> candidates  = (List<Object>) resp.get('candidates');
            if (candidates == null || candidates.isEmpty()) return null;

            Map<String, Object> firstCandidate = (Map<String, Object>) candidates[0];
            if (firstCandidate == null) return null;

            Map<String, Object> content = (Map<String, Object>) firstCandidate.get('content');
            if (content == null) return null;

            List<Object> parts = (List<Object>) content.get('parts');
            if (parts == null || parts.isEmpty()) return null;

            Map<String, Object> firstPart = (Map<String, Object>) parts[0];
            if (firstPart == null) return null;

            return (String) firstPart.get('text');

        } catch (Exception e) {
            System.debug('extractText error: ' + e.getMessage());
            return null;
        }
    }
}