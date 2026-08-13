@IsTest
private class PolymerHDPEKeywordServiceTest {


@IsTest
static void testGetPolymerKeywords() {

    Test.startTest();

    Map<String, PolymerHDPEKeywordService.KeywordConfig> result =
        PolymerHDPEKeywordService.getPolymerKeywords();

    Test.stopTest();

    System.assertNotEquals(
        null,
        result,
        'Result map should not be null.'
    );

    System.assert(
        result.containsKey('Polymer - Relevant') ||
        result.containsKey('Polymer - Excluded'),
        'At least one Polymer keyword configuration should be available.'
    );

    if (result.containsKey('Polymer - Relevant')) {

        PolymerHDPEKeywordService.KeywordConfig config =
            result.get('Polymer - Relevant');

        System.assertEquals(
            'Polymer - Relevant',
            config.label,
            'Label should match the metadata label.'
        );
    }

    if (result.containsKey('Polymer - Excluded')) {

        PolymerHDPEKeywordService.KeywordConfig config =
            result.get('Polymer - Excluded');

        System.assertEquals(
            'Polymer - Excluded',
            config.label,
            'Label should match the metadata label.'
        );
    }
}


}