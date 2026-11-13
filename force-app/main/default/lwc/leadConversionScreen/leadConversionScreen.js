import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getInitData from '@salesforce/apex/LeadConversionScreenController.getInitData';
import getContacts from '@salesforce/apex/LeadConversionScreenController.getContacts';
import getAddressBooks from '@salesforce/apex/LeadConversionScreenController.getAddressBooks';
import getOwnerOptions from '@salesforce/apex/LeadConversionScreenController.getOwnerOptions';
import convert from '@salesforce/apex/LeadConversionScreenController.convert';
import searchAccounts from '@salesforce/apex/LeadConversionScreenController.searchAccounts';

let rowKey = 0;
function newProductRow(department) {
    rowKey += 1;
    return { key: 'row-' + rowKey, department: department || '', productCategory: '', uom: '', quantity: null };
}

export default class LeadConversionScreen extends NavigationMixin(LightningElement) {
    @api recordId; // Task Id (same entry point as the flow)

    @track init;
    @track loading = true;
    @track submitting = false;
    @track step = 1; // 1 info, 2 contact, 3 owner, 4 upload (conditional), 5 success

    // step 1 state
    accountMode = 'new'; // 'new' | 'existing'
    selectedAccountId;
    accountSearchText = '';
    accountDropdownOpen = false;
    @track accountSearchResults = null; // null = not searching, show matched accounts
    selectedAddressBookId = '';
    addressBookOptions = [];
    isSite = false;
    parentAccountId;
    note = '';
    tentativeClosureDate;
    country = ''; state = ''; street = ''; city = ''; zone = ''; pin = '';
    companyName = ''; customerCategory = ''; email = '';
    department = '';
    addProductCategory = false;
    @track productRows = [];

    // step 2 state
    createContactChecked = false;
    contactOptions = [];
    selectedContactId;

    // step 3 state
    ownerOptions = [];
    selectedOwnerId;

    result;

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            this.init = await getInitData({ taskId: this.recordId });
            const d = this.init;
            this.country = d.country || '';
            this.state = d.state || '';
            this.street = d.street || '';
            this.city = d.city || '';
            this.zone = d.zone || '';
            this.pin = d.pin || '';
            this.companyName = d.companyName || '';
            this.customerCategory = d.customerCategory || '';
            this.email = d.email || '';
            this.department = d.isEnquiry ? '' : (d.department || '');
            this.tentativeClosureDate = d.defaultClosureDate;
        } catch (e) {
            this.showToast('Error', this.reduceError(e), 'error');
        } finally {
            this.loading = false;
        }
    }

    // ---- getters ----

    // lightning-progress-indicator matches current-step against the step values
    // as strings, so the numeric step must be converted.
    get progressStep() { return String(this.step); }

    get isStep1() { return this.step === 1; }
    get isStep2() { return this.step === 2; }
    get isStep3() { return this.step === 3; }
    get isStep4() { return this.step === 4; }
    get isStep5() { return this.step === 5; }

    get useExistingAccount() { return this.accountMode === 'existing'; }
    get isNewAccount() { return this.accountMode === 'new'; }

    get accountModeOptions() {
        return [
            { label: 'Create New Account', value: 'new' },
            { label: 'Use Existing Account', value: 'existing' }
        ];
    }

    get matchingAccountOptions() {
        return (this.init?.matchingAccounts || []).map((a) => ({ label: a.name, value: a.id }));
    }
    get hasMatchingAccounts() { return (this.init?.matchingAccounts || []).length > 0; }

    // Searchable combobox: dropdown shows the matched accounts until the user
    // types 2+ characters, then it shows server-side search results instead.
    get accountComboOptions() {
        return this.accountSearchResults !== null ? this.accountSearchResults : this.matchingAccountOptions;
    }
    get noAccountComboOptions() { return this.accountComboOptions.length === 0; }
    get accountComboClass() {
        return 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click'
            + (this.accountDropdownOpen ? ' slds-is-open' : '');
    }

    get addressBookComboOptions() {
        return [{ label: '-- New Address (from fields below) --', value: '' }]
            .concat(this.addressBookOptions.map((a) => ({ label: a.label, value: a.id })));
    }
    get showAddressFields() { return !this.selectedAddressBookId; }
    get showIndiaFields() { return this.country === 'India'; }

    get departmentOptions() {
        return (this.init?.departments || [])
            .filter((o) => o.value !== 'Enquiry')
            .map((o) => ({ label: o.label, value: o.value }));
    }
    get customerCategoryOptions() { return this.mapOptions(this.init?.customerCategories); }
    get countryOptions() { return this.mapOptions(this.init?.countries); }
    get stateOptions() { return this.mapOptions(this.init?.states); }
    get zoneOptions() { return this.mapOptions(this.init?.zones); }
    get uomOptions() { return this.mapOptions(this.init?.uoms); }

    get productCategoryOptions() {
        const byDept = this.init?.productCategoriesByDepartment || {};
        return (byDept[this.department] || []).map((v) => ({ label: v, value: v }));
    }

    get hasExistingProductCategories() {
        return (this.init?.existingProductCategories || []).length > 0;
    }
    get existingPcColumns() {
        return [
            { label: 'Product Category', fieldName: 'productCategory' },
            { label: 'UOM', fieldName: 'uom' },
            { label: 'Quantity', fieldName: 'quantity', type: 'number' }
        ];
    }

    get contactComboOptions() {
        return this.contactOptions.map((c) => ({ label: c.name, value: c.id }));
    }
    get ownerComboOptions() {
        return this.ownerOptions.map((o) => ({ label: o.name, value: o.id }));
    }

    get needsUploadStep() {
        return this.init && this.init.docRequired === 'REQUIRED' && !this.init.hasFile;
    }
    get uploadFormats() { return ['.pdf', '.png', '.jpg', '.jpeg', '.doc', '.docx', '.xls', '.xlsx']; }

    get parentAccountFilter() {
        return { criteria: [{ fieldPath: 'ParentId', operator: 'eq', value: null }] };
    }

    mapOptions(list) {
        return (list || []).map((o) => ({ label: o.label, value: o.value }));
    }

    // ---- step 1 handlers ----

    handleAccountMode(e) {
        this.accountMode = e.detail.value;
        this.selectedAccountId = undefined;
        this.selectedAddressBookId = '';
        this.addressBookOptions = [];
        this.accountSearchText = '';
        this.accountSearchResults = null;
        this.accountDropdownOpen = false;
    }
    async handleMatchingAccount(e) {
        this.selectedAccountId = e.detail.value;
        await this.loadAccountRelated();
    }
    async handleAccountPicker(e) {
        this.selectedAccountId = e.detail.recordId;
        await this.loadAccountRelated();
    }
    handleAccountSearchFocus() { this.accountDropdownOpen = true; }
    handleAccountSearchBlur() {
        window.setTimeout(() => { this.accountDropdownOpen = false; }, 250);
    }
    handleAccountSearchInput(e) {
        const text = e.target.value;
        this.accountSearchText = text;
        this.accountDropdownOpen = true;
        if (this.selectedAccountId) {
            this.selectedAccountId = undefined; // typing invalidates the previous pick
            this.selectedAddressBookId = '';
            this.addressBookOptions = [];
        }
        window.clearTimeout(this._acctTimer);
        const term = text.trim();
        // Matches found: searching is restricted to the matched accounts (local filter).
        if (this.hasMatchingAccounts) {
            this.accountSearchResults = term.length === 0
                ? null
                : this.matchingAccountOptions.filter((o) => o.label.toLowerCase().includes(term.toLowerCase()));
            return;
        }
        // No matched accounts: search across all existing accounts (server-side).
        if (term.length < 2) { this.accountSearchResults = null; return; }
        this._acctTimer = window.setTimeout(async () => {
            try {
                const res = await searchAccounts({ searchTerm: term });
                this.accountSearchResults = res.map((a) => ({ label: a.name, value: a.id }));
            } catch (err) {
                this.accountSearchResults = [];
            }
        }, 300);
    }
    async handleAccountOptionPick(e) {
        this.selectedAccountId = e.currentTarget.dataset.value;
        this.accountSearchText = e.currentTarget.dataset.label;
        this.accountDropdownOpen = false;
        await this.loadAccountRelated();
    }
    async loadAccountRelated() {
        if (!this.selectedAccountId) { this.addressBookOptions = []; return; }
        try {
            this.addressBookOptions = await getAddressBooks({ accountId: this.selectedAccountId });
        } catch (e) {
            this.addressBookOptions = [];
        }
    }
    handleAddressBook(e) { this.selectedAddressBookId = e.detail.value; }
    handleSite(e) {
        this.isSite = e.target.checked;
        if (!this.isSite) { this.parentAccountId = undefined; }
    }
    handleParentAccount(e) { this.parentAccountId = e.detail.recordId; }
    handleNote(e) { this.note = e.target.value; }
    handleClosureDate(e) { this.tentativeClosureDate = e.target.value; }
    handleCountry(e) {
        this.country = e.detail.value;
        if (this.country !== 'India') { this.state = ''; this.zone = ''; }
    }
    handleState(e) { this.state = e.detail.value; }
    handleStreet(e) { this.street = e.target.value; }
    handleCity(e) { this.city = e.target.value; }
    handleZone(e) { this.zone = e.detail.value; }
    handlePin(e) { this.pin = e.target.value; }
    handleCustomerCategory(e) { this.customerCategory = e.detail.value; }
    handleCompanyName(e) { this.companyName = e.target.value; }
    handleEmail(e) { this.email = e.target.value; }
    handleDepartment(e) {
        this.department = e.detail.value;
        // reset repeater rows: their PC options depend on department (flow resets these too)
        this.productRows = this.productRows.map(() => newProductRow(this.department));
    }
    handleAddProductCategory(e) {
        this.addProductCategory = e.target.checked;
        if (this.addProductCategory && this.productRows.length === 0) {
            this.productRows = [newProductRow(this.department)];
        }
    }
    addProductRow() {
        this.productRows = [...this.productRows, newProductRow(this.department)];
    }
    removeProductRow(e) {
        const key = e.target.dataset.key;
        this.productRows = this.productRows.filter((r) => r.key !== key);
    }
    handleRowField(e) {
        const key = e.target.dataset.key;
        const field = e.target.dataset.field;
        const value = e.detail?.value ?? e.target.value;
        this.productRows = this.productRows.map((r) => (r.key === key ? { ...r, [field]: value } : r));
    }

    // ---- navigation ----

    async goToStep2() {
        const err = this.validateStep1();
        if (err) { this.showToast('Missing/invalid information', err, 'warning'); return; }
        if (this.useExistingAccount) {
            try {
                this.contactOptions = await getContacts({ accountId: this.selectedAccountId });
            } catch (e) { this.contactOptions = []; }
            if (this.contactOptions.length === 0) {
                // no contacts on the account -> contact auto-created from lead (flow behaviour)
                this.createContactChecked = true;
                this.goToStep3();
                return;
            }
            this.step = 2;
        } else {
            // new account -> contact auto-created from lead (flow behaviour)
            this.createContactChecked = true;
            this.goToStep3();
        }
    }

    handleCreateContact(e) {
        this.createContactChecked = e.target.checked;
        if (this.createContactChecked) { this.selectedContactId = undefined; }
    }
    handleContactSelect(e) { this.selectedContactId = e.detail.value; }

    async contactNext() {
        if (!this.createContactChecked && !this.selectedContactId) {
            this.showToast('Missing selection', 'Select a contact or tick Create Contact.', 'warning');
            return;
        }
        this.goToStep3();
    }

    async goToStep3() {
        try {
            this.ownerOptions = await getOwnerOptions({ department: this.department });
        } catch (e) { this.ownerOptions = []; }
        this.step = 3;
    }

    handleOwnerSelect(e) { this.selectedOwnerId = e.detail.value; }

    ownerNext() {
        if (!this.selectedOwnerId) {
            this.showToast('Missing selection', 'Please select an owner.', 'warning');
            return;
        }
        if (this.needsUploadStep) {
            this.step = 4;
        } else {
            this.submit();
        }
    }

    handleUploadFinished() {
        this.init = { ...this.init, hasFile: true };
    }

    uploadNext() {
        if (!this.init.hasFile) {
            this.showToast('File required',
                'A file is required for Lead Source ' + (this.init.leadSource || '') + '.', 'warning');
            return;
        }
        this.submit();
    }

    backToStep1() { this.step = 1; }
    backToStep2orStep1() {
        this.step = this.useExistingAccount && this.contactOptions.length > 0 ? 2 : 1;
    }

    // ---- validation & submit ----

    validateStep1() {
        if (this.useExistingAccount) {
            if (!this.selectedAccountId) return 'Please select an account.';
        } else {
            if (!this.companyName) return 'Company Name is required.';
            if (this.isSite && !this.parentAccountId) return 'Please select a Parent Account for the site.';
        }
        if (!this.note) return 'Note is required.';
        if (!this.department) return 'Please select a Department (Enquiry is not allowed).';
        if (this.department === 'Enquiry') return "You can't proceed with Department as Enquiry.";
        if (!this.customerCategory) return 'Customer Category is required.';
        if (!this.email) return 'Email is required.';
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(this.email)) {
            return 'Please enter a valid email address (e.g. name@company.com).';
        }
        if (!this.selectedAddressBookId) {
            if (!this.country || !this.street || !this.city || !this.pin) {
                return 'Please complete the address (Country, Street, City, PIN).';
            }
            if (this.country === 'India' && (!this.state || !this.zone)) {
                return 'State and Zone are required for India.';
            }
        }
        const hasExistingPc = this.hasExistingProductCategories;
        const validRows = this.productRows.filter((r) => r.productCategory);
        if (!hasExistingPc && validRows.length === 0) {
            return 'Please select at least one product category to proceed.';
        }
        if (this.addProductCategory) {
            for (const r of validRows) {
                if (!r.uom || !r.quantity) return 'Each product category row needs UOM and Quantity.';
            }
        }
        return null;
    }

    async submit() {
        this.submitting = true;
        const request = {
            taskId: this.recordId,
            useExistingAccount: this.useExistingAccount ? 'true' : 'false',
            accountId: this.selectedAccountId,
            accountName: this.companyName,
            parentAccountId: this.isSite ? this.parentAccountId : null,
            selectedAddressBookId: this.selectedAddressBookId || null,
            street: this.street,
            city: this.city,
            pin: this.pin,
            country: this.country,
            state: this.state,
            zone: this.zone,
            companyName: this.companyName,
            customerCategory: this.customerCategory,
            department: this.department,
            email: this.email,
            note: this.note,
            tentativeClosureDate: this.tentativeClosureDate,
            createContact: this.createContactChecked,
            contactId: this.selectedContactId,
            ownerId: this.selectedOwnerId,
            productRows: this.productRows
                .filter((r) => r.productCategory)
                .map((r) => ({
                    department: r.department || this.department,
                    productCategory: r.productCategory,
                    uom: r.uom,
                    quantity: r.quantity ? Number(r.quantity) : null
                }))
        };
        try {
            const result = await convert({ reqJson: JSON.stringify(request) });
            if (result.status === 'Success') {
                this.result = result;
                this.step = 5;
            } else {
                this.showToast('Conversion failed', result.status, 'error');
            }
        } catch (e) {
            this.showToast('Conversion failed', this.reduceError(e), 'error');
        } finally {
            this.submitting = false;
        }
    }

    // ---- success navigation ----

    openAccount() { this.navigate(this.result.accountId, 'Account'); }
    openContact() { this.navigate(this.result.contactId, 'Contact'); }
    openOpportunity() { this.navigate(this.result.opportunityId, 'Opportunity'); }

    navigate(recordId, objectApiName) {
        // Open in a new tab so the conversion success screen stays put.
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName, actionName: 'view' }
        }).then((url) => {
            window.open(url, '_blank');
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'An unknown error occurred.';
    }
}