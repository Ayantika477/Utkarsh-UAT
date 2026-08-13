/**
 * @description Campaign email report LWC — consolidated Infobip email delivery stats (last 48 hours).
 * @author      Anshita Chanda
 * @date        2026-08-06
 */
import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import fetchEmailCampaignReport from '@salesforce/apex/CampaignEmailReportController.fetchEmailCampaignReport';

const SUMMARY_COLUMNS = [
  { label: 'Index', fieldName: 'indexNo', type: 'number' },
  { label: 'Recipient', fieldName: 'recipient', type: 'text' },
  { label: 'Delivered', fieldName: 'delivered', type: 'number' },
  { label: 'Failed', fieldName: 'failed', type: 'number' },
  { label: 'Pending', fieldName: 'pending', type: 'number' },
  { label: 'Opened', fieldName: 'opened', type: 'number' }
];

export default class CampaignEmailReport extends NavigationMixin(LightningElement) {
  @track summaryRows = [];
  selectedProduct = 'Email';
  productName;
  reportIds = [];
  isLoading = false;
  fetchComplete = false;
  errorMessage;
  columns = SUMMARY_COLUMNS;

  productOptions = [{ label: 'Email', value: 'Email' }];

  get hasReport() {
    return this.summaryRows && this.summaryRows.length > 0;
  }

  /**
   * Whether to show the empty-state UI after a completed fetch with no rows.
   * @returns {boolean} True when fetch completed with no data and no error.
   */
  get showEmptyState() {
    return this.fetchComplete && !this.hasReport && !this.errorMessage;
  }

  /**
   * Whether the fetch report button should be disabled.
   * @returns {boolean} True when loading or product is missing.
   */
  get disableFetch() {
    return this.isLoading || !this.selectedProduct;
  }

  /**
   * Updates the selected product channel (Email).
   * @param {Event} event Radio group change event.
   * @returns {void} Nothing.
   */
  handleProductChange(event) {
    this.selectedProduct = event.detail.value;
  }

  /**
   * Fetches Infobip email delivery data and shows consolidated stats.
   * @returns {Promise<void>} Resolves when fetch completes.
   */
  async handleFetch() {
    this.isLoading = true;
    this.errorMessage = undefined;
    this.fetchComplete = false;
    this.summaryRows = [];
    this.productName = undefined;

    try {
      const result = await fetchEmailCampaignReport();
      this.summaryRows = (result?.summaryRows || []).map((row) => ({
        indexNo: row?.indexNo ?? 1,
        recipient: row?.recipient || '',
        delivered: row?.delivered ?? 0,
        failed: row?.failed ?? 0,
        pending: row?.pending ?? 0,
        opened: row?.opened ?? 0
      }));
      this.reportIds = result?.reportIds || [];
      this.productName = this.selectedProduct
        ? this.selectedProduct.toUpperCase()
        : 'EMAIL';
      this.fetchComplete = true;

      const toastMessage =
        this.summaryRows.length > 0
          ? 'Email campaign report loaded'
          : 'No email delivery reports were returned by Infobip for the last 48 hours.';

      this.dispatchEvent(
        new ShowToastEvent({
          title:
            this.summaryRows.length > 0
              ? 'Email campaign report saved'
              : 'No delivery reports found',
          message: toastMessage,
          variant: this.summaryRows.length > 0 ? 'success' : 'warning'
        })
      );
    } catch (error) {
      this.errorMessage = this.normalizeError(error);
      this.fetchComplete = true;
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Fetch failed',
          message: this.errorMessage,
          variant: 'error',
          mode: 'sticky'
        })
      );
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * Navigates back to the Campaign object list view.
   * @returns {void} Nothing.
   */
  handleBackToList() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: {
        objectApiName: 'Campaign',
        actionName: 'list'
      }
    });
  }

  /**
   * Normalizes an Apex or Lightning error into a readable string.
   * @param {Object} error Error object from Apex or wire.
   * @returns {string} Human-readable error message.
   */
  normalizeError(error) {
    if (!error) {
      return 'Unknown error';
    }
    if (Array.isArray(error.body)) {
      return error.body.map((item) => item.message).join(', ');
    }
    if (error.body && typeof error.body.message === 'string') {
      return error.body.message;
    }
    if (typeof error.message === 'string') {
      return error.message;
    }
    return 'Unexpected error while fetching email campaign report.';
  }
}