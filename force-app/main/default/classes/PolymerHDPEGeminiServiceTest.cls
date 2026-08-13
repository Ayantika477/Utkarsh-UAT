@IsTest
private class PolymerHDPEGeminiServiceTest {

// ------------------------------------------------------------
// Mock HTTP response
// ------------------------------------------------------------
private class GeminiMock implements HttpCalloutMock {

    private Integer statusCode;
    private String responseBody;

    GeminiMock(Integer statusCode, String responseBody) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
    }

    public HttpResponse respond(HttpRequest req) {

        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(responseBody);

        return res;
    }
}

// ------------------------------------------------------------
// Helper method to create KeywordConfig
// ------------------------------------------------------------
private static PolymerHDPEKeywordService.KeywordConfig createConfig(
    String label,
    String positiveKeywords,
    String negativeKeywords,
    String schemaPrompt
) {

    PolymerHDPEKeywordService.KeywordConfig config =
        new PolymerHDPEKeywordService.KeywordConfig();

    config.label = label;
    config.positiveKeywords = positiveKeywords;
    config.negativeKeywords = negativeKeywords;
    config.schemaPrompt = schemaPrompt;
    config.isExcluded = false;
    config.isRelevant = false;

    return config;
}

// ------------------------------------------------------------
// SUCCESS - excluded + relevant matched
// ------------------------------------------------------------
@IsTest
static void testCheckFileSuccess() {

    String responseBody =
        '{"candidates":[{"content":{"parts":[{"text":"{\\"excludedMatched\\":true,\\"relevantMatched\\":false,\\"reasoning\\":\\"HDPE keyword found\\"}"}]}}]}';

    PolymerHDPEKeywordService.KeywordConfig excludedCfg =
        createConfig(
            'Polymer - Excluded',
            '',
            'HDPE, High Density Polyethylene',
            'Check HDPE products first.'
        );

    PolymerHDPEKeywordService.KeywordConfig relevantCfg =
        createConfig(
            'Polymer - Relevant',
            'Polymer, PVC',
            '',
            'Check polymer products.'
        );

    Test.setMock(
        HttpCalloutMock.class,
        new GeminiMock(200, responseBody)
    );

    Test.startTest();

    PolymerHDPEGeminiService.MatchResult result =
        PolymerHDPEGeminiService.checkFile(
            Blob.valueOf('Test tender document'),
            'application/pdf',
            'Tender.pdf',
            excludedCfg,
            relevantCfg
        );

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(false, result.hadError);
    System.assertEquals(true, result.excludedMatched);
    System.assertEquals(false, result.relevantMatched);
    System.assertEquals(
        'HDPE keyword found',
        result.reasoning
    );
    System.assertEquals('', result.errorMessage);
}

// ------------------------------------------------------------
// SUCCESS - relevant matched
// ------------------------------------------------------------
@IsTest
static void testCheckFileRelevantMatched() {

    String responseBody =
        '{"candidates":[{"content":{"parts":[{"text":"{\\"excludedMatched\\":false,\\"relevantMatched\\":true,\\"reasoning\\":\\"Polymer keyword found\\"}"}]}}]}';

    PolymerHDPEKeywordService.KeywordConfig excludedCfg =
        createConfig(
            'Polymer - Excluded',
            '',
            'HDPE',
            ''
        );

    PolymerHDPEKeywordService.KeywordConfig relevantCfg =
        createConfig(
            'Polymer - Relevant',
            'Polymer',
            '',
            'Polymer related tender.'
        );

    Test.setMock(
        HttpCalloutMock.class,
        new GeminiMock(200, responseBody)
    );

    Test.startTest();

    PolymerHDPEGeminiService.MatchResult result =
        PolymerHDPEGeminiService.checkFile(
            Blob.valueOf('Test document'),
            'text/plain',
            'Tender.txt',
            excludedCfg,
            relevantCfg
        );

    Test.stopTest();

    System.assertEquals(false, result.hadError);
    System.assertEquals(false, result.excludedMatched);
    System.assertEquals(true, result.relevantMatched);
    System.assertEquals(
        'Polymer keyword found',
        result.reasoning
    );
}

// ------------------------------------------------------------
// SUCCESS - neither matched
// ------------------------------------------------------------
@IsTest
static void testCheckFileNeitherMatched() {

    String responseBody =
        '{"candidates":[{"content":{"parts":[{"text":"{\\"excludedMatched\\":false,\\"relevantMatched\\":false,\\"reasoning\\":\\"No matching keyword found\\"}"}]}}]}';

    Test.setMock(
        HttpCalloutMock.class,
        new GeminiMock(200, responseBody)
    );

    Test.startTest();

    PolymerHDPEGeminiService.MatchResult result =
        PolymerHDPEGeminiService.checkFile(
            Blob.valueOf('Test document'),
            'text/html',
            'Tender.html',
            null,
            null
        );

    Test.stopTest();

    System.assertEquals(false, result.hadError);
    System.assertEquals(false, result.excludedMatched);
    System.assertEquals(false, result.relevantMatched);
    System.assertEquals(
        'No matching keyword found',
        result.reasoning
    );
}

// ------------------------------------------------------------
// SUCCESS - fields missing from JSON
// ------------------------------------------------------------
@IsTest
static void testCheckFileMissingFields() {

    String responseBody =
        '{"candidates":[{"content":{"parts":[{"text":"{}"}]}}]}';

    Test.setMock(
        HttpCalloutMock.class,
        new GeminiMock(200, responseBody)
    );

    Test.startTest();

    PolymerHDPEGeminiService.MatchResult result =
        PolymerHDPEGeminiService.checkFile(
            Blob.valueOf('Test document'),
            'application/pdf',
            'Tender.pdf',
            null,
            null
        );

    Test.stopTest();

    System.assertEquals(false, result.hadError);
    System.assertEquals(false, result.excludedMatched);
    System.assertEquals(false, result.relevantMatched);
    System.assertEquals('', result.reasoning);
}

// ------------------------------------------------------------
// ERROR - Gemini returns non-200
// ------------------------------------------------------------
@IsTest
static void testCheckFileNon200Response() {

    String responseBody =
        '{"error":{"message":"Gemini API error"}}';

    Test.setMock(
        HttpCalloutMock.class,
        new GeminiMock(400, responseBody)
    );

    Test.startTest();

    PolymerHDPEGeminiService.MatchResult result =
        PolymerHDPEGeminiService.checkFile(
            Blob.valueOf('Test document'),
            'application/pdf',
            'Tender.pdf',
            null,
            null
        );

    Test.stopTest();

    System.assertEquals(true, result.hadError);
    System.assert(
        result.errorMessage.contains('Status: 400')
    );
}

// ------------------------------------------------------------
// ERROR - Empty Gemini response
// ------------------------------------------------------------
@IsTest
static void testCheckFileEmptyResponse() {

    String responseBody =
        '{"candidates":[]}';

    Test.setMock(
        HttpCalloutMock.class,
        new GeminiMock(200, responseBody)
    );

    Test.startTest();

    PolymerHDPEGeminiService.MatchResult result =
        PolymerHDPEGeminiService.checkFile(
            Blob.valueOf('Test document'),
            'application/pdf',
            'Tender.pdf',
            null,
            null
        );

    Test.stopTest();

    System.assertEquals(true, result.hadError);
    System.assert(
        result.errorMessage.contains(
            'Empty/unreadable Gemini response'
        )
    );
}

// ------------------------------------------------------------
// ERROR - Invalid JSON returned by Gemini
// ------------------------------------------------------------
@IsTest
static void testCheckFileInvalidJson() {

    String responseBody =
        '{"candidates":[{"content":{"parts":[{"text":"INVALID JSON"}]}}]}';

    Test.setMock(
        HttpCalloutMock.class,
        new GeminiMock(200, responseBody)
    );

    Test.startTest();

    PolymerHDPEGeminiService.MatchResult result =
        PolymerHDPEGeminiService.checkFile(
            Blob.valueOf('Test document'),
            'application/pdf',
            'Tender.pdf',
            null,
            null
        );

    Test.stopTest();

    System.assertEquals(true, result.hadError);
    System.assert(
        result.errorMessage.contains(
            'Could not parse Gemini JSON'
        )
    );
}

// ------------------------------------------------------------
// ERROR - Callout exception
// ------------------------------------------------------------
@IsTest
static void testCheckFileCalloutException() {

    Test.setMock(
        HttpCalloutMock.class,
        new ExceptionMock()
    );

    Test.startTest();

    PolymerHDPEGeminiService.MatchResult result =
        PolymerHDPEGeminiService.checkFile(
            Blob.valueOf('Test document'),
            'application/pdf',
            'Tender.pdf',
            null,
            null
        );

    Test.stopTest();

    System.assertEquals(true, result.hadError);
    System.assert(
        result.errorMessage.contains(
            'Exception in checkFile'
        )
    );
}

// ------------------------------------------------------------
// Mock that throws an exception
// ------------------------------------------------------------
private class ExceptionMock implements HttpCalloutMock {

    public HttpResponse respond(HttpRequest req) {
        throw new CalloutException('Test callout exception');
    }
}


}