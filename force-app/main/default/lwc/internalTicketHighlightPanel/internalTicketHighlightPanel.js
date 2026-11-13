import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue, getFieldDisplayValue } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import USER_ID from '@salesforce/user/Id';
import CASE_OBJECT from '@salesforce/schema/Case';
import SUBJECT_FIELD from '@salesforce/schema/Case.Subject_formula__c';
import PRIORITY_FIELD from '@salesforce/schema/Case.Priority';
import STATUS_FIELD from '@salesforce/schema/Case.Status';
import TICKET_NO_FIELD from '@salesforce/schema/Case.Ticket_No_formula__c';
import IS_CASE_OWNER_FIELD from '@salesforce/schema/Case.isCaseOwner__c';
import PROFILE_NAME_FIELD from '@salesforce/schema/User.Profile.Name';

const TITLE = 'Internal Ticket';
const NUM_VISIBLE_ACTIONS = 4;
const RESOLVED = 'Resolved';

const SYSTEM_ADMINISTRATOR = 'System Administrator';
const UTKARSH_ADMIN = 'Utkarsh Admin';
const UTKARSH_HOD = 'Utkarsh HOD';
const CRM_HEAD = 'CRM Head';

// Same order as the "Internal ticket" compact layout; the first field is the record title.
const SECONDARY_FIELDS = [PRIORITY_FIELD, STATUS_FIELD, TICKET_NO_FIELD];

// Actions and visibility rules copied from the standard highlights panel on Internal_Ticket_Page.
const ACTIONS = [
    {
        apiName: 'Case.Change_Ticket_Owner',
        label: 'Change Ticket Owner',
        // (1 OR 2 OR 4 OR 5) AND 3
        isVisible: (ctx) =>
            (ctx.profileEquals(SYSTEM_ADMINISTRATOR) ||
                ctx.isCaseOwner ||
                ctx.profileEquals(UTKARSH_HOD) ||
                ctx.profileEquals(CRM_HEAD)) &&
            ctx.status !== RESOLVED
    },
    {
        apiName: 'Case.Create_New_Task',
        label: 'Create New Task',
        // 1 AND (2 OR 3 OR 4)
        isVisible: (ctx) =>
            ctx.status !== RESOLVED &&
            (ctx.profileEquals(UTKARSH_ADMIN) ||
                ctx.profileEquals(SYSTEM_ADMINISTRATOR) ||
                ctx.isCaseOwner)
    },
    {
        apiName: 'Case.Reopen_Ticket',
        label: 'Reopen Ticket',
        // 1 AND (2 OR 3)
        isVisible: (ctx) =>
            ctx.status === RESOLVED &&
            (ctx.profileContains(SYSTEM_ADMINISTRATOR) || ctx.profileContains(UTKARSH_ADMIN))
    },
    {
        apiName: 'Case.Resolve_Ticket',
        label: 'Resolve Ticket',
        // 1 AND (2 OR 3 OR 4 OR 5)
        isVisible: (ctx) =>
            ctx.status !== RESOLVED &&
            (ctx.profileEquals(SYSTEM_ADMINISTRATOR) ||
                ctx.profileEquals(CRM_HEAD) ||
                ctx.profileEquals(UTKARSH_HOD) ||
                ctx.isCaseOwner)
    }
];

export default class InternalTicketHighlightPanel extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    title = TITLE;
    record;
    profileName;
    objectInfo;
    errorMessage;

    @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
    wiredObjectInfo({ data }) {
        if (data) {
            this.objectInfo = data;
        }
    }

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [SUBJECT_FIELD, ...SECONDARY_FIELDS, IS_CASE_OWNER_FIELD]
    })
    wiredRecord({ data, error }) {
        if (data) {
            this.record = data;
            this.errorMessage = undefined;
        } else if (error) {
            this.record = undefined;
            this.errorMessage = this.reduceError(error);
        }
    }

    @wire(getRecord, { recordId: USER_ID, fields: [PROFILE_NAME_FIELD] })
    wiredUser({ data }) {
        if (data) {
            this.profileName = getFieldValue(data, PROFILE_NAME_FIELD);
        }
    }

    get subject() {
        return this.record ? getFieldValue(this.record, SUBJECT_FIELD) : '';
    }

    get fields() {
        if (!this.record) {
            return [];
        }
        return SECONDARY_FIELDS.map((field) => {
            const fieldInfo = this.objectInfo?.fields?.[field.fieldApiName];
            return {
                key: field.fieldApiName,
                label: fieldInfo?.label ?? field.fieldApiName,
                value: getFieldDisplayValue(this.record, field) ?? getFieldValue(this.record, field),
                isRichText: fieldInfo?.htmlFormatted === true
            };
        });
    }

    get visibleActions() {
        if (!this.record || this.profileName === undefined) {
            return [];
        }
        const profile = (this.profileName || '').toLowerCase();
        const ctx = {
            status: getFieldValue(this.record, STATUS_FIELD),
            isCaseOwner: getFieldValue(this.record, IS_CASE_OWNER_FIELD) === true,
            profileEquals: (name) => profile === name.toLowerCase(),
            profileContains: (name) => profile.includes(name.toLowerCase())
        };
        return ACTIONS.filter((action) => action.isVisible(ctx));
    }

    get buttonActions() {
        return this.visibleActions.slice(0, NUM_VISIBLE_ACTIONS);
    }

    get menuActions() {
        return this.visibleActions.slice(NUM_VISIBLE_ACTIONS);
    }

    get hasActions() {
        return this.visibleActions.length > 0;
    }

    get hasMenuActions() {
        return this.menuActions.length > 0;
    }

    handleActionClick(event) {
        this.launchQuickAction(event.currentTarget.dataset.apiName);
    }

    handleMenuSelect(event) {
        this.launchQuickAction(event.detail.value);
    }

    launchQuickAction(apiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: { apiName },
            state: {
                objectApiName: CASE_OBJECT.objectApiName,
                context: 'RECORD_DETAIL',
                recordId: this.recordId,
                backgroundContext: `/lightning/r/Case/${this.recordId}/view`
            }
        });
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }
}