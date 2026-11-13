import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getActivities from '@salesforce/apex/ActivityOverviewController.getActivities';

const COLUMNS = [
    {
        label: 'Subject',
        fieldName: 'subject',
        type: 'subjectLink',
        typeAttributes: {
            url: { fieldName: 'recordUrl' },
            overdue: { fieldName: 'overdue' },
            cellStyle: { fieldName: 'rowStyle' }
        },
        wrapText: true
    },
    { label: 'Owner', fieldName: 'ownerName', type: 'text', initialWidth: 140 },
    {
        label: 'Created Date',
        fieldName: 'createdDate',
        type: 'date',
        initialWidth: 150,
        typeAttributes: {
            year: 'numeric', month: 'short', day: '2-digit',
            hour: '2-digit', minute: '2-digit'
        }
    },
    {
        label: 'Description',
        fieldName: 'description',
        type: 'coloredText',
        typeAttributes: { cellStyle: { fieldName: 'rowStyle' } },
        wrapText: true
    }
];

export default class ActivityOverview extends NavigationMixin(LightningElement) {
    @api recordId; // present on record pages; empty on app/home pages (= my activities)

    openRows = [];
    completedRows = [];
    error;
    loading = true;

    openColumns = COLUMNS;
    completedColumns = COLUMNS;

    @wire(getActivities, { recordId: '$recordId' })
    wiredActivities({ data, error }) {
        this.loading = false;
        if (data) {
            this.openRows = data.open.map((r) => this.toRow(r));
            this.completedRows = data.completed.map((r) => this.toRow(r));
            this.error = undefined;
        } else if (error) {
            this.error = (error.body && error.body.message) || 'Failed to load activities.';
        }
    }

    toRow(r) {
        return {
            ...r,
            id: r.recordId,
            recordUrl: '/lightning/r/' + r.activityType + '/' + r.recordId + '/view',
            rowStyle: r.overdue ? 'color:#c23934;' : ''
        };
    }

    get openTitle() {
        return 'Upcoming & Overdue (' + this.openRows.length + ')';
    }
    get completedTitle() {
        return 'Completed (' + this.completedRows.length + ')';
    }
    get hasOpen() { return this.openRows.length > 0; }
    get hasCompleted() { return this.completedRows.length > 0; }
}