import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import sendQuoteToCustomer from '@salesforce/apex/OpportunityQuoteController.sendQuoteToCustomer';

export default class OpportunitySendQuoteAction extends LightningElement {
    @api recordId;

    @api
    async invoke() {
        try {
            await sendQuoteToCustomer({ opportunityId: this.recordId });
            this.showToast(
                'Success',
                'WhatsApp quote message sent to the customer.',
                'success'
            );
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }

    getErrorMessage(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unable to send WhatsApp message.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}