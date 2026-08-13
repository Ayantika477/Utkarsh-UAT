public without sharing class BWM_EmailDealerMonthlyAttachmentService {
  public static Messaging.EmailFileAttachment buildOpenOpportunityListPdf(Id dealerAccountId) {
    if (dealerAccountId == null) {
      return null;
    }

    try {
      PageReference pdfPage = Page.BWM_DealerMonthlyOpportunityList;
      pdfPage.getParameters().put('accountId', dealerAccountId);
      Blob pdfBody = pdfPage.getContentAsPDF();

      Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
      attachment.setFileName('Dealer_Open_Opportunities.pdf');
      attachment.setBody(pdfBody);
      attachment.setContentType('application/pdf');
      attachment.setInline(false);
      return attachment;
    } catch (Exception ex) {
      return null;
    }
  }
}