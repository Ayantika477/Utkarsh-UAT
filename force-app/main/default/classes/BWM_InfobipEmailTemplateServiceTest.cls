@IsTest
private class BWM_InfobipEmailTemplateServiceTest {
  @IsTest
  static void fetchTemplatesReturnsParsedResults() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_EmailCalloutMock(
        '{"results":[{"id":205000000067199,"name":"NABL_HIGH_MAST_2026","imagePreviewUrl":"/email/1/templates/205000000067199/preview.png","createdAt":"2026-07-14T09:49:49.543+0000","updatedAt":"2026-07-14T09:49:49.546+0000"}],"paging":{"page":0,"size":20,"totalPages":1,"totalResults":1}}',
        200
      )
    );

    Test.startTest();
    List<BWM_InfobipEmailTemplateService.TemplateOption> templates =
      BWM_InfobipEmailTemplateService.fetchTemplates();
    Test.stopTest();

    System.assertEquals(1, templates.size());
    System.assertEquals('205000000067199', templates[0].value);
    System.assertEquals('NABL_HIGH_MAST_2026', templates[0].label);
    System.assertEquals(
      '/email/1/templates/205000000067199/preview.png',
      templates[0].imagePreviewUrl
    );
  }

  @IsTest
  static void fetchTemplatesThrowsOnHttpError() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_EmailCalloutMock('{"description":"Something went wrong."}', 500)
    );

    Boolean threw = false;
    Test.startTest();
    try {
      BWM_InfobipEmailTemplateService.fetchTemplates();
    } catch (BWM_EmailException ex) {
      threw = true;
      System.assert(ex.getMessage().contains('server error'));
    }
    Test.stopTest();

    System.assertEquals(true, threw, 'Expected server error response to throw.');
  }
}