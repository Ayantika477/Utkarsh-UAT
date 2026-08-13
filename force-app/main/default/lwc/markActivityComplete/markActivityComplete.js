import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import USER_ID from '@salesforce/user/Id';

import TASK_LOG_OBJECT from '@salesforce/schema/Task_Log__c';
import VISIT_TYPE_FIELD from '@salesforce/schema/Task_Log__c.Visit_Type__c';
import REASON_FIELD from '@salesforce/schema/Task_Log__c.Reason_for_Visit__c';

import getContext from '@salesforce/apex/MarkActivityCompleteController.getContext';
import getAssignableUsers from '@salesforce/apex/MarkActivityCompleteController.getAssignableUsers';
import getOpenFlags from '@salesforce/apex/MarkActivityCompleteController.getOpenFlags';
import markComplete from '@salesforce/apex/MarkActivityCompleteController.markComplete';
import createCall from '@salesforce/apex/MarkActivityCompleteController.createCall';
import createEvent from '@salesforce/apex/MarkActivityCompleteController.createEvent';
import createVisit from '@salesforce/apex/MarkActivityCompleteController.createVisit';

export default class MarkActivityComplete extends LightningElement {
    @api recordId; // Task or Event Id

    view = 'close';
    saving = false;

    ctx = {};
    dispositionOptions = [];

    disposition = '';
    remarks = '';
    actualStart = ''; // Event + not "Not Completed"
    actualEnd = '';

    // Open status on the parent, EXCLUDING the record being closed (which is
    // still open until a follow-up is created).
    callOpen = false;
    eventOpen = false;
    visitOpen = false;

    assignableUsers = [];
    _defaultsApplied = false;

    call = { subject: '', date: '', time: '', comments: '', assignedTo: USER_ID };
    event = { subject: '', comments: '', start: '', end: '', assignedTo: USER_ID };
    visit = { visitType: '', reason: '', scheduleDate: '', assignedTo: USER_ID };

    // ---------- wires ----------
    @wire(getContext, { recordId: '$recordId' })
    wiredContext({ data, error }) {
        if (data) {
            this.ctx = data;
            this.dispositionOptions = (data.dispositions || []).map((o) => ({
                label: o.label,
                value: o.value
            }));
        } else if (error) {
            this.toast('Error', this.msgOf(error), 'error');
        }
    }

    @wire(getAssignableUsers)
    wiredUsers({ data, error }) {
        if (data) {
            this.assignableUsers = data;
            if (!this._defaultsApplied && data.length) {
                this._defaultsApplied = true;
                const me = data.find((u) => u.id === USER_ID);
                const id = me ? me.id : data[0].id;
                this.call = { ...this.call, assignedTo: id };
                this.event = { ...this.event, assignedTo: id };
                this.visit = { ...this.visit, assignedTo: id };
            }
        } else if (error) {
            this.toast('Could not load assignable users', this.msgOf(error), 'error');
        }
    }

    @wire(getObjectInfo, { objectApiName: TASK_LOG_OBJECT })
    taskLogInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$taskLogInfo.data.defaultRecordTypeId',
        fieldApiName: VISIT_TYPE_FIELD
    })
    visitTypePicklist;

    @wire(getPicklistValues, {
        recordTypeId: '$taskLogInfo.data.defaultRecordTypeId',
        fieldApiName: REASON_FIELD
    })
    reasonPicklist;

    // ---------- view getters ----------
    get showClose() { return this.view === 'close'; }
    get showMenu() { return this.view === 'menu'; }
    get showCallForm() { return this.view === 'call'; }
    get showEventForm() { return this.view === 'event'; }
    get showVisitForm() { return this.view === 'visit'; }

    get isTask() { return this.ctx.objectType === 'Task'; }
    get isEvent() { return this.ctx.objectType === 'Event'; }
    get isOpportunity() { return this.ctx.parentType === 'Opportunity'; }

    // Actual Start/End only for an Event that is being marked Completed.
    get showActualDates() { return this.isEvent && this.disposition !== 'Not Completed'; }

    // Opportunity must always have at least one open Call or Event (excluding the
    // record being closed).
    get openCallOrEvent() { return this.callOpen || this.eventOpen; }
    get mustCreate() { return this.isOpportunity && !this.openCallOrEvent; }
    get canClose() { return !this.mustCreate; }

    get nowLocal() {
        const d = new Date();
        const pad = (n) => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
            + `T${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }

    get todayDate() {
        const d = new Date();
        const pad = (n) => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    }

    // Back-dated follow-up Call / Event are blocked.
    get pastCallError() {
        if (!this.call.date || !this.call.time) return false;
        return new Date(this.combineDateTime(this.call.date, this.call.time)).getTime() < Date.now();
    }
    get pastEventError() {
        if (!this.event.start) return false;
        return new Date(this.event.start).getTime() < Date.now();
    }

    get futureDateError() {
        if (!this.showActualDates) return false;
        const now = Date.now();
        return (this.actualStart && new Date(this.actualStart).getTime() > now)
            || (this.actualEnd && new Date(this.actualEnd).getTime() > now);
    }

    get callDisabled() { return this.callOpen; }
    get eventDisabled() { return this.eventOpen; }
    get visitDisabled() { return this.visitOpen; }

    get visitTypeOptions() {
        return this.visitTypePicklist && this.visitTypePicklist.data
            ? this.visitTypePicklist.data.values.map((v) => ({ label: v.label, value: v.value }))
            : [];
    }
    get reasonOptions() {
        return this.reasonPicklist && this.reasonPicklist.data
            ? this.reasonPicklist.data.values.map((v) => ({ label: v.label, value: v.value }))
            : [];
    }
    get assignableUserOptions() {
        return (this.assignableUsers || []).map((u) => ({ label: u.name, value: u.id }));
    }
    get hasAssignees() { return this.assignableUserOptions.length > 0; }

    // ---------- validity ----------
    get closeInvalid() {
        if (!this.disposition || !this.remarks) return true;
        if (this.showActualDates) {
            if (!this.actualStart || !this.actualEnd) return true;
            if (this.futureDateError) return true;
            if (new Date(this.actualEnd) <= new Date(this.actualStart)) return true;
        }
        return false;
    }
    get callInvalid() {
        return !this.call.subject || !this.call.date || !this.call.time
            || (this.hasAssignees && !this.call.assignedTo)
            || this.pastCallError;
    }
    get eventInvalid() {
        if (!this.event.subject || !this.event.start || !this.event.end) return true;
        if (this.hasAssignees && !this.event.assignedTo) return true;
        if (this.pastEventError) return true;
        return new Date(this.event.end) <= new Date(this.event.start);
    }
    get visitInvalid() {
        return !this.visit.visitType || !this.visit.reason || !this.visit.scheduleDate
            || (this.hasAssignees && !this.visit.assignedTo);
    }

    // ---------- close-step handlers ----------
    handleDisposition(e) {
        this.disposition = e.detail.value;
        if (this.disposition === 'Not Completed') {
            this.actualStart = '';
            this.actualEnd = '';
        }
    }
    handleRemarks(e) { this.remarks = e.target.value; }
    handleActualStart(e) { this.actualStart = e.target.value; }
    handleActualEnd(e) { this.actualEnd = e.target.value; }

    // Next: does NOT close the record. Lead finishes immediately; Opportunity
    // moves to the follow-up menu (close happens after a follow-up is created).
    async doNext() {
        if (this.closeInvalid) return;
        this.saving = true;
        try {
            if (this.ctx.parentType !== 'Opportunity') {
                await this.completeCurrent();
                this.saving = false;
                this.fireClose();
                return;
            }
            const flags = await getOpenFlags({
                parentId: this.ctx.parentId,
                parentType: this.ctx.parentType,
                excludeId: this.recordId
            });
            this.applyFlags(flags);
            this.saving = false;
            this.view = 'menu';
        } catch (err) {
            this.fail(err);
        }
    }

    // Closes the current Task/Event using the held disposition/remarks/actuals.
    completeCurrent() {
        const useActuals = this.isEvent && this.disposition !== 'Not Completed';
        return markComplete({
            recordId: this.recordId,
            objectType: this.ctx.objectType,
            disposition: this.disposition,
            remarks: this.remarks,
            actualStart: useActuals ? this.actualStart : null,
            actualEnd: useActuals ? this.actualEnd : null,
            parentId: this.ctx.parentId,
            parentType: this.ctx.parentType
        });
    }

    // ---------- navigation ----------
    selectCall() { if (!this.callDisabled) this.view = 'call'; }
    selectEvent() { if (!this.eventDisabled) this.view = 'event'; }
    selectVisit() { if (!this.visitDisabled) this.view = 'visit'; }
    backToMenu() { this.view = 'menu'; }

    // ---------- create change handlers ----------
    handleCallChange(e) { this.call = { ...this.call, [e.target.dataset.field]: e.target.value }; }
    handleEventChange(e) { this.event = { ...this.event, [e.target.dataset.field]: e.target.value }; }
    handleVisitChange(e) { this.visit = { ...this.visit, [e.target.dataset.field]: e.target.value }; }

    combineDateTime(dateStr, timeStr) {
        const [y, m, d] = dateStr.split('-').map(Number);
        const [hh, mm] = timeStr.substring(0, 5).split(':').map(Number);
        return new Date(y, m - 1, d, hh, mm).toISOString();
    }

    // ---------- create saves ----------
    async saveCall() {
        if (this.callInvalid) return;
        this.saving = true;
        try {
            await createCall({
                parentId: this.ctx.parentId,
                parentType: this.ctx.parentType,
                subject: this.call.subject,
                followUp: this.combineDateTime(this.call.date, this.call.time),
                comments: this.call.comments,
                assignedToId: this.call.assignedTo || null,
                excludeId: this.recordId
            });
            await this.afterCreate('Call created');
        } catch (err) { this.fail(err); }
    }

    async saveEvent() {
        if (this.eventInvalid) return;
        this.saving = true;
        try {
            await createEvent({
                parentId: this.ctx.parentId,
                parentType: this.ctx.parentType,
                subject: this.event.subject,
                comments: this.event.comments,
                startDt: this.event.start,
                endDt: this.event.end,
                assignedToId: this.event.assignedTo || null,
                excludeId: this.recordId
            });
            await this.afterCreate('Event created');
        } catch (err) { this.fail(err); }
    }

    async saveVisit() {
        if (this.visitInvalid) return;
        this.saving = true;
        try {
            await createVisit({
                parentId: this.ctx.parentId,
                parentType: this.ctx.parentType,
                visitType: this.visit.visitType,
                reason: this.visit.reason,
                scheduleDate: this.visit.scheduleDate,
                assignedToId: this.visit.assignedTo || null,
                excludeId: this.recordId
            });
            await this.afterCreate('Visit created');
        } catch (err) { this.fail(err); }
    }

    // After a follow-up is created: refresh open status (excluding the current
    // record). If the invariant now holds, close the current record and finish;
    // otherwise keep the menu and ask for a Call/Event.
    async afterCreate(msg) {
        this.toast('Success', msg, 'success');
        try {
            const flags = await getOpenFlags({
                parentId: this.ctx.parentId,
                parentType: this.ctx.parentType,
                excludeId: this.recordId
            });
            this.applyFlags(flags);
        } catch (err) {
            // ignore - fall through
        }
        if (this.mustCreate) {
            this.saving = false;
            this.view = 'menu';
            this.toast('Action needed', 'Create an open Call or Event to continue.', 'warning');
            return;
        }
        await this.finalizeClose();
    }

    // Done (only shown when the invariant already holds).
    // Done without creating a follow-up: exit WITHOUT completing/updating the
    // current activity. (Creating a Call/Event auto-completes and closes, so Done
    // is only reached when no activity was created.)
    doneAndClose() {
        this.fireClose();
    }

    async finalizeClose() {
        try {
            await this.completeCurrent();
            this.saving = false;
            this.fireClose();
        } catch (err) {
            this.fail(err);
        }
    }

    applyFlags(flags) {
        if (flags) {
            this.callOpen = flags.callOpen;
            this.eventOpen = flags.eventOpen;
            this.visitOpen = flags.visitOpen;
        }
    }

    // ---------- helpers ----------
    fireClose() {
        this.dispatchEvent(new FlowNavigationFinishEvent());
        this.dispatchEvent(new CustomEvent('close'));
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    fail(err) {
        this.saving = false;
        this.toast('Error', this.msgOf(err), 'error');
    }
    msgOf(err) {
        return err && err.body && err.body.message ? err.body.message : 'Unexpected error';
    }
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    // Cancel on the close step: nothing has been closed yet, so just exit.
    closeAction() { this.fireClose(); }
}