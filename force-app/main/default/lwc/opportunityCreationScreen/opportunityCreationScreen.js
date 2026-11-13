import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getInitData from '@salesforce/apex/OpportunityCreationScreenController.getInitData';
import getMatchingAccounts from '@salesforce/apex/OpportunityCreationScreenController.getMatchingAccounts';
import getContacts from '@salesforce/apex/OpportunityCreationScreenController.getContacts';
import getAddressBooks from '@salesforce/apex/OpportunityCreationScreenController.getAddressBooks';
import getOwnerOptions from '@salesforce/apex/OpportunityCreationScreenController.getOwnerOptions';
import createOpportunity from '@salesforce/apex/OpportunityCreationScreenController.create';
import searchAccounts from '@salesforce/apex/OpportunityCreationScreenController.searchAccounts';

// LWC/Apex re-implementation of the "Create Opportunity Custom Flow" screen flow.
// The flow stays active and untouched; this component runs in parallel during migration.
// Steps: 1 Record Type, 2 Opportunity Info, 3 Owner (conditional), 4 Document (conditional),
// 5 Account, 6 Contact, 7 Success - the same screen order as the flow's reachable path.
export default class OpportunityCreationScreen extends NavigationMixin(LightningElement) {
    @track init;
    loading = true;
    submitting = false;
    step = '1';

    // Step 1
    recordTypeName = '';

    // Step 2
    email = '';
    phone = '';
    opportunitySource = '';
    previousSource = '';
    expectedClosureDate = '';
    expectedDealValue = null;
    industry = '';
    department = '';
    customerCategory = '';
    @track productRows = [];
    rowKey = 0;

    // Step 3 (owner)
    ownerNeeded = false;
    selectedOwnerId = '';
    @track ownerOptions = [];

    // Step 4 (docs)
    contentDocumentIds = [];
    uploadedFileNames = [];

    // Step 5 (account)
    accountMode = 'existing';
    selectedAccountId = '';
    accountSearchText = '';
    accountDropdownOpen = false;
    @track accountSearchResults = null; // null = not searching, show matched accounts
    accountName = '';
    isSite = false;
    parentAccountId = '';
    selectedAddressBookId = '';
    @track matchingAccounts = [];
    @track addressBooks = [];
    street = '';
    city = '';
    pin = '';
    country = '';
    state = '';
    zone = '';

    // Step 6 (contact)
    createContactChecked = true;
    selectedContactId = '';
    @track contacts = [];
    contactFirstName = '';
    contactLastName = '';
    contactEmail = '';
    contactPhone = '';

    // Result
    result;

    connectedCallback() {
        getInitData()
            .then((data) => {
                this.init = data;
                this.productRows = [this.newProductRow()];
                if (data.recordTypes.length === 1) {
                    this.recordTypeName = data.recordTypes[0].value;
                }
            })
            .catch((e) => this.toastError(e))
            .finally(() => { this.loading = false; });
    }

    // ---------- derived ----------

    get isStep1() { return this.step === '1'; }
    get isStep2() { return this.step === '2'; }
    get isStep3() { return this.step === '3'; }
    get isStep4() { return this.step === '4'; }
    get isStep5() { return this.step === '5'; }
    get isStep6() { return this.step === '6'; }
    get isStep7() { return this.step === '7'; }

    get recordTypeOptions() { return this.init ? this.init.recordTypes : []; }

    get isTenderRecordType() { return this.recordTypeName === 'Tender Opportunity'; }

    // Mirrors the server: tender opportunities are created in Negotiation, the rest in Nurture.
    get lockedStage() { return this.isTenderRecordType ? 'Negotiation' : 'Nurture'; }

    // Flow: Tender Opportunity record type shows a fixed, disabled TENDER source.
    get sourceOptions() {
        if (this.isTenderRecordType) {
            return [{ label: 'TENDER', value: 'TENDER' }];
        }
        return this.init ? this.init.sourceOptions : [];
    }

    // Flow: Previous Source visible only when source is CRM RESOURCE.
    get showPreviousSource() { return this.opportunitySource === 'CRM RESOURCE'; }

    get productCategoryOptions() {
        if (!this.init || !this.department) { return []; }
        const values = this.init.productCategoriesByDepartment[this.department] || [];
        return values.map((v) => ({ label: v, value: v }));
    }

    get uomOptions() { return this.init ? this.init.uoms : []; }
    get industryOptions() { return this.init ? this.init.industries : []; }
    get departmentOptions() { return this.init ? this.init.departments : []; }
    get customerCategoryOptions() { return this.init ? this.init.customerCategories : []; }
    get previousSourceOptions() { return this.init ? this.init.previousSources : []; }
    get countryOptions() { return this.init ? this.init.countries : []; }
    get stateOptions() { return this.init ? this.init.states : []; }
    get zoneOptions() { return this.init ? this.init.zones : []; }

    // Flow: DocRequiredFormula CASE on the selected source.
    get needsUploadStep() {
        if (!this.init || !this.opportunitySource) { return false; }
        return this.init.docRequiredBySource[this.opportunitySource] === 'REQUIRED';
    }

    get useExistingAccount() { return this.accountMode === 'existing'; }
    get isNewAccount() { return this.accountMode === 'new'; }
    get hasMatchingAccounts() { return this.matchingAccounts.length > 0; }

    get accountModeOptions() {
        return [
            { label: 'Use existing Account', value: 'existing' },
            { label: 'Create new Account', value: 'new' }
        ];
    }

    get matchingAccountOptions() {
        return this.matchingAccounts.map((a) => ({ label: a.name, value: a.id }));
    }

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
        const options = [{ label: '-- New address (enter below) --', value: '' }];
        this.addressBooks.forEach((ab) => options.push({ label: ab.label, value: ab.id }));
        return options;
    }

    get contactComboOptions() {
        return this.contacts.map((c) => ({ label: c.name, value: c.id }));
    }

    get ownerComboOptions() {
        return this.ownerOptions.map((o) => ({ label: o.name, value: o.id }));
    }

    get parentAccountFilter() {
        return { criteria: [{ fieldPath: 'ParentId', operator: 'eq', value: null }] };
    }

    // Flow: address section visible when no address book is selected.
    get showAddressFields() { return !this.selectedAddressBookId; }
    get showIndiaFields() { return this.country === 'India'; }

    get accountHasContacts() { return this.contacts.length > 0; }
    get showContactSelect() {
        return this.useExistingAccount && this.accountHasContacts && !this.createContactChecked;
    }
    get showContactForm() {
        return this.createContactChecked || !this.accountHasContacts || this.isNewAccount;
    }

    get uploadFormats() { return ['.pdf', '.png', '.jpg', '.jpeg', '.doc', '.docx', '.xls', '.xlsx', '.csv', '.txt', '.ppt', '.pptx']; }

    get uploadedFileLabel() { return this.uploadedFileNames.join(', '); }
    get hasUploadedFiles() { return this.contentDocumentIds.length > 0; }

    // ---------- step 1 ----------

    handleRecordType(e) { this.recordTypeName = e.detail.value; }

    goToStep2() {
        if (!this.recordTypeName) {
            this.toast('Select a record type', 'Please select a record type.', 'error');
            return;
        }
        if (this.isTenderRecordType) {
            this.opportunitySource = 'TENDER';
        }
        this.step = '2';
    }

    // ---------- step 2 ----------

    handleEmail(e) { this.email = e.target.value; }
    handlePhone(e) { this.phone = e.target.value; }
    handleSource(e) { this.opportunitySource = e.detail.value; }
    handlePreviousSource(e) { this.previousSource = e.detail.value; }
    handleClosureDate(e) { this.expectedClosureDate = e.target.value; }
    handleDealValue(e) { this.expectedDealValue = e.target.value; }
    handleIndustry(e) { this.industry = e.detail.value; }
    handleCustomerCategory(e) { this.customerCategory = e.detail.value; }

    handleDepartment(e) {
        this.department = e.detail.value;
        this.productRows = [this.newProductRow()];
        this.selectedOwnerId = '';
    }

    newProductRow() {
        this.rowKey += 1;
        return { key: 'row' + this.rowKey, productCategory: '', uom: '', quantity: null };
    }

    addProductRow() { this.productRows = [...this.productRows, this.newProductRow()]; }

    removeProductRow(e) {
        const key = e.target.dataset.key;
        if (this.productRows.length > 1) {
            this.productRows = this.productRows.filter((r) => r.key !== key);
        }
    }

    handleRowField(e) {
        const key = e.target.dataset.key;
        const field = e.target.dataset.field;
        const value = field === 'quantity' ? e.target.value : e.detail.value;
        this.productRows = this.productRows.map((r) =>
            r.key === key ? { ...r, [field]: value } : r);
    }

    isValidEmail(value) {
        return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value || '');
    }

    validateStep2() {
        if (!this.email || !this.phone) {
            this.toast('Missing information', 'Email and Phone are required.', 'error');
            return false;
        }
        if (!this.isValidEmail(this.email)) {
            this.toast('Invalid email', 'Please enter a valid email address (e.g. name@company.com).', 'error');
            return false;
        }
        if (!this.opportunitySource) {
            this.toast('Missing information', 'Opportunity Source is required.', 'error');
            return false;
        }
        if (this.showPreviousSource && !this.previousSource) {
            this.toast('Missing information', 'Previous Source is required.', 'error');
            return false;
        }
        if (!this.expectedClosureDate) {
            this.toast('Missing information', 'Expected Closure Date is required.', 'error');
            return false;
        }
        if (!this.department) {
            this.toast('Missing information', 'Department Name is required.', 'error');
            return false;
        }
        // Flow: "Please add atleast one Product Category"
        const complete = this.productRows.filter(
            (r) => r.productCategory && r.uom && r.quantity);
        if (complete.length === 0) {
            this.toast('Product Category required', 'Please add atleast one Product Category.', 'error');
            return false;
        }
        const partial = this.productRows.some(
            (r) => (r.productCategory || r.uom || r.quantity) &&
                   !(r.productCategory && r.uom && r.quantity));
        if (partial) {
            this.toast('Incomplete row', 'Each product row needs a Product Category, UOM and Quantity.', 'error');
            return false;
        }
        return true;
    }

    step2Next() {
        if (!this.validateStep2()) { return; }
        // Flow: Checking Profile and Department - owner defaults to the running user
        // when their department matches; admins always choose.
        const sameDept = (this.init.userDepartment || '').includes(this.department);
        this.ownerNeeded = this.init.alwaysChooseOwner || !sameDept;
        if (this.ownerNeeded) {
            getOwnerOptions({ department: this.department })
                .then((opts) => { this.ownerOptions = opts; })
                .catch((e) => this.toastError(e));
            this.step = '3';
        } else {
            this.selectedOwnerId = '';
            this.afterOwnerStep();
        }
    }

    // ---------- step 3 ----------

    handleOwnerSelect(e) { this.selectedOwnerId = e.detail.value; }

    ownerNext() {
        if (!this.selectedOwnerId) {
            this.toast('Missing information', 'Please choose an Opportunity Owner.', 'error');
            return;
        }
        this.afterOwnerStep();
    }

    afterOwnerStep() {
        this.step = this.needsUploadStep ? '4' : '5';
        if (this.step === '5') { this.loadMatchingAccounts(); }
    }

    backToStep2() { this.step = '2'; }

    // ---------- step 4 ----------

    handleUploadFinished(e) {
        const files = e.detail.files || [];
        files.forEach((f) => {
            this.contentDocumentIds = [...this.contentDocumentIds, f.documentId];
            this.uploadedFileNames = [...this.uploadedFileNames, f.name];
        });
    }

    uploadNext() {
        // Flow: upload is required when the source demands a document.
        if (this.contentDocumentIds.length === 0) {
            this.toast('Document required', 'This is a required to upload a file for the selected source.', 'error');
            return;
        }
        this.step = '5';
        this.loadMatchingAccounts();
    }

    backFromUpload() { this.step = this.ownerNeeded ? '3' : '2'; }

    // ---------- step 5 ----------

    loadMatchingAccounts() {
        getMatchingAccounts({ email: this.email, phone: this.phone })
            .then((accs) => { this.matchingAccounts = accs; })
            .catch((e) => this.toastError(e));
    }

    handleAccountMode(e) {
        this.accountMode = e.detail.value;
        this.selectedAccountId = '';
        this.selectedAddressBookId = '';
        this.addressBooks = [];
        this.isSite = false;
        this.parentAccountId = '';
        this.accountSearchText = '';
        this.accountSearchResults = null;
        this.accountDropdownOpen = false;
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
            this.selectedAccountId = ''; // typing invalidates the previous pick
            this.selectedAddressBookId = '';
            this.addressBooks = [];
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
        this._acctTimer = window.setTimeout(() => {
            searchAccounts({ searchTerm: term })
                .then((res) => {
                    this.accountSearchResults = res.map((a) => ({ label: a.name, value: a.id }));
                })
                .catch(() => { this.accountSearchResults = []; });
        }, 300);
    }
    handleAccountOptionPick(e) {
        this.selectedAccountId = e.currentTarget.dataset.value;
        this.accountSearchText = e.currentTarget.dataset.label;
        this.accountDropdownOpen = false;
        this.onAccountChosen();
    }

    handleMatchingAccount(e) {
        this.selectedAccountId = e.detail.value;
        this.onAccountChosen();
    }

    handleAccountPicker(e) {
        this.selectedAccountId = e.detail.recordId || '';
        this.onAccountChosen();
    }


    onAccountChosen() {
        this.selectedAddressBookId = '';
        this.addressBooks = [];
        if (this.selectedAccountId) {
            getAddressBooks({ accountId: this.selectedAccountId })
                .then((abs) => { this.addressBooks = abs; })
                .catch((e) => this.toastError(e));
        }
    }

    handleAddressBook(e) { this.selectedAddressBookId = e.detail.value; }
    handleAccountName(e) { this.accountName = e.target.value; }
    handleSite(e) { this.isSite = e.target.checked; }
    handleParentAccount(e) { this.parentAccountId = e.detail.recordId || ''; }
    handleStreet(e) { this.street = e.target.value; }
    handleCity(e) { this.city = e.target.value; }
    handlePin(e) { this.pin = e.target.value; }
    handleCountry(e) {
        this.country = e.detail.value;
        if (this.country !== 'India') { this.state = ''; this.zone = ''; }
    }
    handleState(e) { this.state = e.detail.value; }
    handleZone(e) { this.zone = e.detail.value; }

    validateStep5() {
        if (this.useExistingAccount && !this.selectedAccountId) {
            this.toast('Missing information', 'Please select an Account.', 'error');
            return false;
        }
        if (this.isNewAccount && !this.accountName) {
            this.toast('Missing information', 'Please enter the new Account name.', 'error');
            return false;
        }
        if (this.showAddressFields) {
            // Flow: address fields are required when no address book is selected.
            if (!this.country || !this.city || !this.pin || !this.street) {
                this.toast('Missing information', 'Country, Street, City and PIN are required.', 'error');
                return false;
            }
            if (this.showIndiaFields && (!this.state || !this.zone)) {
                this.toast('Missing information', 'State and Zone are required for India.', 'error');
                return false;
            }
        }
        return true;
    }

    step5Next() {
        if (!this.validateStep5()) { return; }
        this.contacts = [];
        if (this.useExistingAccount) {
            getContacts({ accountId: this.selectedAccountId })
                .then((cons) => {
                    this.contacts = cons;
                    this.createContactChecked = cons.length === 0;
                    this.prefillContactForm();
                    this.step = '6';
                })
                .catch((e) => this.toastError(e));
        } else {
            this.createContactChecked = true;
            this.prefillContactForm();
            this.step = '6';
        }
    }

    backToStep5Source() { this.step = this.needsUploadStep ? '4' : (this.ownerNeeded ? '3' : '2'); }

    // ---------- step 6 ----------

    prefillContactForm() {
        // Flow: contact Email/Phone default to the values from the Opportunity Info screen.
        if (!this.contactEmail) { this.contactEmail = this.email; }
        if (!this.contactPhone) { this.contactPhone = this.phone; }
    }

    handleCreateContact(e) { this.createContactChecked = e.target.checked; }
    handleContactSelect(e) { this.selectedContactId = e.detail.value; }
    handleContactFirstName(e) { this.contactFirstName = e.target.value; }
    handleContactLastName(e) { this.contactLastName = e.target.value; }
    handleContactEmail(e) { this.contactEmail = e.target.value; }
    handleContactPhone(e) { this.contactPhone = e.target.value; }

    backToStep5() { this.step = '5'; }

    submit() {
        if (this.showContactForm) {
            if (!this.contactLastName || !this.contactEmail || !this.contactPhone) {
                this.toast('Missing information', 'Last Name, Email and Phone are required for the contact.', 'error');
                return;
            }
            if (!this.isValidEmail(this.contactEmail)) {
                this.toast('Invalid email', 'Please enter a valid contact email address.', 'error');
                return;
            }
        } else if (!this.selectedContactId) {
            this.toast('Missing information', 'Please select a Contact.', 'error');
            return;
        }

        const request = {
            recordTypeName: this.recordTypeName,
            email: this.email,
            phone: this.phone,
            opportunitySource: this.opportunitySource,
            previousSource: this.showPreviousSource ? this.previousSource : '',
            expectedClosureDate: this.expectedClosureDate,
            expectedDealValue: this.expectedDealValue ? Number(this.expectedDealValue) : null,
            industry: this.industry,
            department: this.department,
            customerCategory: this.customerCategory,
            productRows: this.productRows
                .filter((r) => r.productCategory)
                .map((r) => ({
                    productCategory: r.productCategory,
                    uom: r.uom,
                    quantity: r.quantity ? Number(r.quantity) : null
                })),
            contentDocumentIds: this.contentDocumentIds,
            useExistingAccount: this.useExistingAccount ? 'true' : 'false',
            accountId: this.selectedAccountId,
            accountName: this.accountName,
            parentAccountId: this.isSite ? this.parentAccountId : '',
            selectedAddressBookId: this.selectedAddressBookId,
            street: this.showAddressFields ? this.street : '',
            city: this.showAddressFields ? this.city : '',
            state: this.showAddressFields ? this.state : '',
            country: this.showAddressFields ? this.country : '',
            pin: this.showAddressFields ? this.pin : '',
            zone: this.showAddressFields ? this.zone : '',
            createContact: this.showContactForm,
            contactId: this.selectedContactId,
            contactFirstName: this.contactFirstName,
            contactLastName: this.contactLastName,
            contactEmail: this.contactEmail,
            contactPhone: this.contactPhone,
            ownerId: this.selectedOwnerId || ''
        };

        this.submitting = true;
        createOpportunity({ reqJson: JSON.stringify(request) })
            .then((res) => {
                if (res.status === 'Success') {
                    this.result = res;
                    this.step = '7';
                } else {
                    this.toast('Creation failed', res.status, 'error');
                }
            })
            .catch((e) => this.toastError(e))
            .finally(() => { this.submitting = false; });
    }

    // ---------- step 7 ----------

    openOpportunity() { this.navigateTo(this.result.opportunityId); }

    navigateTo(recordId) {
        // Open in a new tab so the success screen stays put.
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        }).then((url) => {
            window.open(url, '_blank');
        });
    }

    // ---------- toasts ----------

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    toastError(e) {
        const message = (e && e.body && e.body.message) ? e.body.message :
            (e && e.message ? e.message : 'An unexpected error occurred.');
        this.toast('Error', message, 'error');
    }
}