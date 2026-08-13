@IsTest
private class CampaignManagementHubControllerTest {
  @IsTest
  static void getCampaignObjectOptionsReturnsAccessibleObjects() {
    Test.startTest();
    List<CampaignManagementHubController.CampaignObjectOption> options =
      CampaignManagementHubController.getCampaignObjectOptions();
    Test.stopTest();

    System.assertNotEquals(null, options);
  }
}