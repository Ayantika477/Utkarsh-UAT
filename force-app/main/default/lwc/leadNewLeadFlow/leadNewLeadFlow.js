import { LightningElement, wire } from 'lwc';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport';
import getInitData from '@salesforce/apex/LeadNewLeadFlowController.getInitData';
import getOwnerOptions from '@salesforce/apex/LeadNewLeadFlowController.getOwnerOptions';
import createAdminLead from '@salesforce/apex/LeadNewLeadFlowController.createAdminLead';
import createOthersLead from '@salesforce/apex/LeadNewLeadFlowController.createOthersLead';
import sendOthersNotifications from '@salesforce/apex/LeadNewLeadFlowController.sendOthersNotifications';

// Checking if System Administrator -> "Admin and CRM User" outcome
const ADMIN_PROFILES = [
    'System Administrator',
    'Utkarsh Admin',
    'Utkarsh CRM',
    'CRM Head',
    'Utkarsh Sales',
    'Utkarsh HOD',
    'Utkarsh Department CRM User'
];

const ENQUIRY = 'Enquiry';
const CRM_RESOURCE = 'CRM RESOURCE';

// Static choices used by the flow screens
const SRC_UTKARSH_CRM_HOD = [
    'INBOUND EMAIL',
    'INBOUND PHONE CALL',
    'EMAIL CAMPAIGNING',
    'OUTBOUND PHONE CALL',
    'EVENT ACTIVATION',
    'OFFLINE CRM',
    'TENDER',
    'CRM RESOURCE',
    'Offline Marketing',
    'WHATSAPP CAMPAIGNING',
    'PROJECTS'
];
const SRC_CRM = [
    'INBOUND EMAIL',
    'INBOUND PHONE CALL',
    'EMAIL CAMPAIGNING',
    'OUTBOUND PHONE CALL',
    'OFFLINE CRM',
    'TENDER',
    'CRM RESOURCE',
    'Offline Marketing',
    'WHATSAPP CAMPAIGNING',
    'PROJECTS'
];
const SRC_SALES = ['TENDER', 'Offline Marketing', 'PROJECTS'];
const SRC_OTHERS_HOD = [
    'INBOUND EMAIL',
    'INBOUND PHONE CALL',
    'EMAIL CAMPAIGNING',
    'OUTBOUND PHONE CALL',
    'EVENT ACTIVATION',
    'OFFLINE CRM',
    'TENDER',
    'CRM RESOURCE',
    'Offline Marketing'
];
const SRC_OTHERS_SALES = ['TENDER', 'Offline Marketing'];
const DEPT_HOD_CRM_HEAD_SALES = [
    'High Mast & Polygonal',
    'Steel Pipes',
    'Crash Barrier',
    'Steel Tubular Poles',
    'Polymer',
    'HDPE',
    'Transmission & Telecom Tower',
    'Pre Engineering Building',
    'Solar Structure',
    'Railway Electrification Structure'
];

// Formulas DocRequiredfor* (only the REQUIRED lead sources; everything else is NOT REQUIRED / blank)
const DOC_REQUIRED_ADMIN = [
    'FACEBOOK',
    'INBOUND EMAIL',
    'INBOUND PHONE CALL',
    'INDIAMART',
    'INDIAMART V2',
    'PAY PER CLICK ADS',
    'WEBSITE',
    'WHATSAPP CAMPAIGNING',
    'EMAIL CAMPAIGNING',
    'OUTBOUND PHONE CALL',
    'TENDER',
    'WEBSITE BOT CHAT',
    'PROJECTS'
];
const DOC_REQUIRED_UTKARSH_CRM_HOD = DOC_REQUIRED_ADMIN;
const DOC_REQUIRED_CRM = [
    'INBOUND EMAIL',
    'INBOUND PHONE CALL',
    'EMAIL CAMPAIGNING',
    'OUTBOUND PHONE CALL',
    'TENDER',
    'WHATSAPP CAMPAIGNING',
    'PROJECTS'
];
const DOC_REQUIRED_SALES = ['TENDER', 'PROJECTS'];
const DOC_REQUIRED_OTHERS = [
    'FACEBOOK',
    'INBOUND EMAIL',
    'INBOUND PHONE CALL',
    'INDIAMART',
    'PAY PER CLICK ADS',
    'WEBSITE',
    'WHATSAPP CAMPAIGNING',
    'EMAIL CAMPAIGNING',
    'OUTBOUND PHONE CALL',
    'TENDER',
    'PROJECTS'
];
const DOC_REQUIRED_OTHERS2 = DOC_REQUIRED_OTHERS.filter((s) => s !== 'PROJECTS');

// Department dropdowns on the "Others" screen, in the order of DepartmentNameFormulaOthers.
// "role" is the text that Get_UserRole.Name must contain for the dropdown to be visible.
const OTHERS_DEPARTMENTS = [
    { name: 'DepartmentHighMastPolygonal', value: 'High Mast & Polygonal', required: true },
    { name: 'DepartmentSteelPipes', value: 'Steel Pipes', required: true },
    { name: 'DepartmentCrashBarrier', value: 'Crash Barrier', required: true },
    { name: 'DepartmentSteelTubularPoles', value: 'Steel Tubular Poles', required: true },
    { name: 'DepartmentHDPE', value: 'HDPE', required: true },
    { name: 'DepartmentPolymer', value: 'Polymer', required: true },
    { name: 'DepartmentTransmissionTelecom', value: 'Transmission & Telecom Tower', required: true },
    { name: 'DepartmentPreEngineeringBuilding', value: 'Pre Engineering Building', required: true },
    { name: 'DepartmentSolarStructure', value: 'Solar Structure', required: true },
    {
        name: 'DepartmentRailwayElectrificationStructure',
        value: 'Railway Electrification Structure',
        required: false
    },
    { name: 'DepartmentEnquiry', value: ENQUIRY, required: false }
];

// Field definitions: label / type / required / picklist source. Visibility is in isVisible().
// optionsKey: 'lead:<field>' -> Lead picklist, 'pc:<field>' -> Product_Category__c picklist, otherwise a static list
const FIELDS = {
    // Personal details
    NameAdmin: { label: 'Name', type: 'text', required: true },
    EmailAdmin: { label: 'Email', type: 'email' },
    PhoneAdmin: { label: 'Phone', type: 'phone', required: true },
    Company_NameAdmin: { label: 'Company Name', type: 'text' },
    NameOthers: { label: 'Name', type: 'text', required: true },
    EmailOthers: { label: 'Email', type: 'email' },
    PhoneOthers: { label: 'Phone', type: 'phone', required: true },
    Company_NameOthers: { label: 'Company Name', type: 'text' },
    // Lead details (admin)
    Lead_StageAdmin: { label: 'Lead Stage', type: 'picklist', options: 'lead:Status', disabled: true },
    LeadSource_Admin: { label: 'Lead Source', type: 'picklist', options: 'lead:LeadSource', required: true },
    LeadSource_UtkarshCRM_HOD: {
        label: 'Lead Source',
        type: 'picklist',
        options: SRC_UTKARSH_CRM_HOD,
        required: true
    },
    LeadSource_CRM: { label: 'Lead Source', type: 'picklist', options: SRC_CRM, required: true },
    LeadSource_Sales: { label: 'Lead Source', type: 'picklist', options: SRC_SALES, required: true },
    Previous_SourceAdmin: {
        label: 'Previous Source',
        type: 'picklist',
        options: 'lead:Previous_Source__c',
        required: true
    },
    RatingAdmin: { label: 'Rating', type: 'picklist', options: 'lead:Rating' },
    Add_Product_Category: { label: 'Add Product Category', type: 'checkbox' },
    IndustryAdmin: { label: 'Industry', type: 'picklist', options: 'lead:Industry' },
    DepartmentAdminCRMUser: {
        label: 'Department',
        type: 'picklist',
        options: 'lead:Department_Name__c',
        required: true
    },
    DepartmentHODCRMHeadSales: {
        label: 'Department',
        type: 'picklist',
        options: DEPT_HOD_CRM_HEAD_SALES,
        required: true
    },
    Customer_CategoryAdmin: { label: 'Customer Category', type: 'picklist', options: 'lead:Customer_Category__c' },
    // Lead details (others)
    Lead_StageOthers: { label: 'Lead Stage', type: 'picklist', options: ['Prospect'], disabled: true },
    Lead_Source_HOD_Dept_Head: {
        label: 'Lead Source',
        type: 'picklist',
        options: SRC_OTHERS_HOD,
        required: true
    },
    Lead_Source_Sales_User: {
        label: 'Lead Source',
        type: 'picklist',
        options: SRC_OTHERS_SALES,
        required: true
    },
    Previous_SourceOthers: {
        label: 'Previous Source',
        type: 'picklist',
        options: 'lead:Previous_Source__c',
        required: true
    },
    RatingOthers: { label: 'Rating', type: 'picklist', options: 'lead:Rating' },
    Add_Product_Category_Others: { label: 'Add Product Category', type: 'checkbox' },
    IndustryOthers: { label: 'Industry', type: 'picklist', options: 'lead:Industry' },
    Customer_CategoryOthers: { label: 'Customer Category', type: 'picklist', options: 'lead:Customer_Category__c' },
    // Address
    CountryAdmin: { label: 'Country', type: 'picklist', options: 'lead:Country__c' },
    StreetAdmin: { label: 'Street', type: 'text' },
    CityAdmin: { label: 'City', type: 'text' },
    ZoneAdmin: { label: 'Zone', type: 'picklist', options: 'lead:Zone__c' },
    StateAdmin1: { label: 'State', type: 'picklist', options: 'lead:State__c' },
    PINAdmin1: { label: 'PIN', type: 'text' },
    CountryOthers: { label: 'Country', type: 'picklist', options: 'lead:Country__c' },
    StreetOthers: { label: 'Street', type: 'text' },
    CityOthers: { label: 'City', type: 'text' },
    ZoneOthers: { label: 'Zone', type: 'picklist', options: 'lead:Zone__c' },
    StateOthers1: { label: 'State', type: 'picklist', options: 'lead:State__c' },
    PINOthers1: { label: 'PIN', type: 'text' }
};
OTHERS_DEPARTMENTS.forEach((d) => {
    FIELDS[d.name] = {
        label: 'Department',
        type: 'picklist',
        options: [d.value],
        required: d.required
    };
});

const ADMIN_LAYOUT = [
    {
        key: 'personal',
        title: 'Personal Details',
        columns: [
            ['NameAdmin', 'EmailAdmin'],
            ['PhoneAdmin', 'Company_NameAdmin']
        ]
    },
    {
        key: 'lead',
        title: 'Lead Details',
        columns: [
            [
                'Lead_StageAdmin',
                'LeadSource_Admin',
                'LeadSource_UtkarshCRM_HOD',
                'LeadSource_CRM',
                'LeadSource_Sales',
                'Previous_SourceAdmin',
                'RatingAdmin',
                'Add_Product_Category'
            ],
            ['IndustryAdmin', 'DepartmentAdminCRMUser', 'DepartmentHODCRMHeadSales', 'Customer_CategoryAdmin']
        ]
    },
    { key: 'repeater', isRepeater: true },
    {
        key: 'address',
        title: 'Address Details',
        columns: [
            ['CountryAdmin', 'StreetAdmin', 'CityAdmin'],
            ['ZoneAdmin', 'StateAdmin1', 'PINAdmin1']
        ]
    }
];

const OTHERS_LAYOUT = [
    {
        key: 'personal',
        title: 'Personal Details',
        columns: [
            ['NameOthers', 'EmailOthers'],
            ['PhoneOthers', 'Company_NameOthers']
        ]
    },
    {
        key: 'lead',
        title: 'Lead Details',
        columns: [
            [
                'Lead_StageOthers',
                'Lead_Source_HOD_Dept_Head',
                'Lead_Source_Sales_User',
                'Previous_SourceOthers',
                'RatingOthers',
                'Add_Product_Category_Others'
            ],
            ['IndustryOthers', ...OTHERS_DEPARTMENTS.map((d) => d.name), 'Customer_CategoryOthers']
        ]
    },
    { key: 'repeater', isRepeater: true },
    {
        key: 'address',
        title: 'Address Details',
        columns: [
            ['CountryOthers', 'StreetOthers', 'CityOthers'],
            ['ZoneOthers', 'StateOthers1', 'PINOthers1']
        ]
    }
];

// Confirm Lead Details Screen (Others): read only
const CONFIRM_LAYOUT = [
    {
        key: 'personal',
        title: 'Personal Details',
        columns: [
            ['NameOthers', 'EmailOthers'],
            ['PhoneOthers', 'Company_NameOthers']
        ]
    },
    {
        key: 'lead',
        title: 'Lead Details',
        columns: [
            [
                'Lead_StageOthers',
                'Lead_Source_Sales_User',
                'Lead_Source_HOD_Dept_Head',
                'Previous_SourceOthers',
                'RatingOthers'
            ],
            ['IndustryOthers', 'DepartmentFormulaOthers', 'Customer_CategoryOthers']
        ]
    },
    { key: 'repeater', isRepeater: true },
    {
        key: 'address',
        title: 'Address Details',
        columns: [
            ['ZoneOthers', 'StreetOthers', 'CityOthers'],
            ['CountryOthers', 'StateOthers1', 'PINOthers1']
        ]
    }
];

const SUMMARY_COLUMNS = [
    { label: 'Product Category', fieldName: 'productCategory', type: 'text', wrapText: true, sortable: false },
    { label: 'UOM', fieldName: 'uom', type: 'text', wrapText: true, sortable: false },
    { label: 'Quantity', fieldName: 'quantity', type: 'number', wrapText: true, sortable: false }
];

const EMAIL_PATTERN = /^[A-Za-z0-9._%+'-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$/;
const isBlank = (v) => v === null || v === undefined || v === '';
const norm = (v) => (isBlank(v) ? null : v);
const containsText = (haystack, needle) =>
    !isBlank(haystack) && !isBlank(needle) && String(haystack).toLowerCase().includes(String(needle).toLowerCase());
const equalsText = (a, b) => String(a ?? '').toLowerCase() === String(b ?? '').toLowerCase();

export default class LeadNewLeadFlow extends LightningElement {
    // current "screen"
    step = 'loading';
    isBusy = false;

    init = {};
    form = { Lead_StageAdmin: 'Prospect', Lead_StageOthers: 'Prospect' };
    rows = [];
    nextRowId = 1;
    summaryRows = [];

    // flow variables
    leadOwnerId;
    leadSourceValue;
    leadSourceValueForNonAdmins;
    departmentVar;
    contentDocumentIds = [];
    uploadedFileNames = [];
    createdLeadId;
    ownerOptions = [];
    ownerId = '';
    uploadedOthersCount = 0;
    uploadError = '';
    faultMessage = '';

    leadRecordTypeId;
    productCategoryRecordTypeId;
    leadPicklists;
    productCategoryPicklists;
    productCategoryInfo;


    // ---------------------------------------------------------------- data loading
    @wire(getObjectInfo, { objectApiName: 'Lead' })
    wiredLeadInfo({ data }) {
        if (data) {
            this.leadRecordTypeId = data.defaultRecordTypeId;
        }
    }

    @wire(getPicklistValuesByRecordType, { objectApiName: 'Lead', recordTypeId: '$leadRecordTypeId' })
    wiredLeadPicklists({ data }) {
        if (data) {
            this.leadPicklists = data.picklistFieldValues;
        }
    }

    @wire(getObjectInfo, { objectApiName: 'Product_Category__c' })
    wiredProductCategoryInfo({ data }) {
        if (data) {
            this.productCategoryRecordTypeId = data.defaultRecordTypeId;
            this.productCategoryInfo = data;
        }
    }

    @wire(getPicklistValuesByRecordType, {
        objectApiName: 'Product_Category__c',
        recordTypeId: '$productCategoryRecordTypeId'
    })
    wiredProductCategoryPicklists({ data }) {
        if (data) {
            this.productCategoryPicklists = data.picklistFieldValues;
        }
    }

    connectedCallback() {
        this.loadInit();
    }

    async loadInit() {
        try {
            this.init = await getInitData();
            this.resetFlow();
        } catch (e) {
            this.showFault(this.errorMessage(e));
        }
    }

    // Start -> Checking if System Administrator
    resetFlow() {
        this.form = { Lead_StageAdmin: 'Prospect', Lead_StageOthers: 'Prospect' };
        this.rows = [this.newRow()];
        this.contentDocumentIds = [];
        this.uploadedFileNames = [];
        this.createdLeadId = null;
        this.uploadedOthersCount = 0;
        this.uploadError = '';
        this.ownerId = '';
        this.step = ADMIN_PROFILES.includes(this.init.profileName) ? 'admin' : 'others';
    }

    // ---------------------------------------------------------------- step flags
    get isAdminStep() {
        return this.step === 'admin';
    }
    get isOthersStep() {
        return this.step === 'others';
    }
    get isOwnerStep() {
        return this.step === 'owner';
    }
    get isAdminFileStep() {
        return this.step === 'adminFile';
    }
    get isConfirmStep() {
        return this.step === 'confirm';
    }
    get isOthersFileStep() {
        return this.step === 'othersFile';
    }
    get isSuccessStep() {
        return this.step === 'success';
    }
    get isFaultStep() {
        return this.step === 'fault';
    }
    get isLoadingStep() {
        return this.step === 'loading';
    }
    get isEntryStep() {
        return this.isAdminStep || this.isOthersStep;
    }

    // ---------------------------------------------------------------- helpers: profile / visibility
    get profileName() {
        return this.init.profileName;
    }

    isProfile(...names) {
        return names.includes(this.profileName);
    }

    get isAdminMode() {
        // 2026-11-12: every profile takes the standard path except Utkarsh Tender
        // (which keeps its auto-TENDER quick path). New profiles are never dead-ended.
        return this.profileName !== 'Utkarsh Tender';
    }

    // A profile with no dedicated branch anywhere - gets the generic CRM-style behavior.
    get isGenericProfile() {
        return !ADMIN_PROFILES.includes(this.profileName) && this.profileName !== 'Utkarsh Tender';
    }

    // visibilityRule of each field
    isVisible(name) {
        const f = this.form;
        switch (name) {
            case 'LeadSource_Admin':
                return this.isProfile('System Administrator', 'Utkarsh Admin');
            case 'LeadSource_UtkarshCRM_HOD':
                return this.isProfile('CRM Head', 'Utkarsh HOD');
            case 'LeadSource_CRM':
                return this.isProfile('Utkarsh CRM', 'Utkarsh Department CRM User') || this.isGenericProfile;
            case 'LeadSource_Sales':
                return this.isProfile('Utkarsh Sales');
            case 'Previous_SourceAdmin':
                return (
                    (this.isVisible('LeadSource_Admin') && f.LeadSource_Admin === CRM_RESOURCE) ||
                    (this.isVisible('LeadSource_UtkarshCRM_HOD') && f.LeadSource_UtkarshCRM_HOD === CRM_RESOURCE) ||
                    (this.isVisible('LeadSource_CRM') && f.LeadSource_CRM === CRM_RESOURCE)
                );
            case 'Add_Product_Category':
                return !equalsText(this.eff('DepartmentAdminCRMUser'), ENQUIRY);
            case 'DepartmentAdminCRMUser':
                return this.isProfile(
                    'System Administrator',
                    'Utkarsh Admin',
                    'Utkarsh CRM',
                    'Utkarsh Department CRM User'
                ) || this.isGenericProfile;
            case 'DepartmentHODCRMHeadSales':
                return this.isProfile('CRM Head', 'Utkarsh Sales', 'Utkarsh HOD');
            case 'ZoneAdmin':
            case 'StateAdmin1':
                return f.CountryAdmin === 'India';
            case 'Lead_Source_HOD_Dept_Head':
                return this.isProfile('Utkarsh HOD', 'CRM Head');
            case 'Lead_Source_Sales_User':
                return this.isProfile('Utkarsh Sales', 'Utkarsh Tender');
            case 'Previous_SourceOthers':
                return (
                    (this.isVisible('Lead_Source_Sales_User') && f.Lead_Source_Sales_User === CRM_RESOURCE) ||
                    (this.isVisible('Lead_Source_HOD_Dept_Head') && f.Lead_Source_HOD_Dept_Head === CRM_RESOURCE)
                );
            case 'Add_Product_Category_Others':
                return !equalsText(this.departmentNameFormulaOthers, ENQUIRY);
            case 'ZoneOthers':
            case 'StateOthers1':
                return f.CountryOthers === 'India';
            default: {
                const dept = OTHERS_DEPARTMENTS.find((d) => d.name === name);
                if (dept) {
                    return containsText(this.init.roleName, dept.value);
                }
                return true;
            }
        }
    }

    // value of a field as the flow sees it (hidden fields are null)
    eff(name) {
        return this.isVisible(name) ? norm(this.form[name]) : null;
    }

    // ---------------------------------------------------------------- formulas
    get departmentNameFormulaOthers() {
        for (const d of OTHERS_DEPARTMENTS) {
            const v = this.eff(d.name);
            if (!isBlank(v)) {
                return v;
            }
        }
        return '';
    }

    // DepartmentFormula1
    get departmentFormula1() {
        const v = this.eff('DepartmentAdminCRMUser');
        return v !== null ? v : this.eff('DepartmentHODCRMHeadSales');
    }

    get repeaterTopValue() {
        return this.isAdminMode ? this.departmentFormula1 : this.departmentNameFormulaOthers;
    }

    firstName(name) {
        const t = (name ?? '').trim();
        return t.includes(' ') ? t.substring(0, t.indexOf(' ')) : null;
    }

    lastNameAdmin(name) {
        const t = (name ?? '').trim();
        return (t.includes(' ') ? t.substring(t.indexOf(' ') + 1) : t).trim();
    }

    lastNameOthers(name, company) {
        const t = (name ?? '').trim();
        const idx = t.indexOf(' ');
        const last = (t.includes(' ') && t.length > idx + 1 ? t.substring(idx + 1).trim() : t).trim();
        if (!isBlank(last)) {
            return last;
        }
        return !isBlank((company ?? '').trim()) ? company.trim() : 'Contact';
    }

    docRequired(list, source) {
        return !isBlank(source) && list.includes(String(source).toUpperCase());
    }

    // Doc_Required_for_Admin
    get isDocRequiredForAdmin() {
        return (
            this.docRequired(DOC_REQUIRED_ADMIN, this.eff('LeadSource_Admin')) ||
            this.docRequired(DOC_REQUIRED_UTKARSH_CRM_HOD, this.eff('LeadSource_UtkarshCRM_HOD')) ||
            this.docRequired(DOC_REQUIRED_CRM, this.eff('LeadSource_CRM')) ||
            this.docRequired(DOC_REQUIRED_SALES, this.eff('LeadSource_Sales'))
        );
    }

    // Doc_Required_for_Others. (The flow's CASE for "Others" contains the typo 'CRM RESOUCE'; kept as is.)
    get isDocRequiredForOthers() {
        return (
            this.docRequired(DOC_REQUIRED_OTHERS, this.eff('Lead_Source_Sales_User')) ||
            this.docRequired(DOC_REQUIRED_OTHERS2, this.eff('Lead_Source_HOD_Dept_Head'))
        );
    }

    // ---------------------------------------------------------------- picklists
    optionsFor(def) {
        let values = [];
        if (Array.isArray(def.options)) {
            values = def.options.map((v) => ({ label: v, value: v }));
        } else if (typeof def.options === 'string') {
            const [obj, field] = def.options.split(':');
            const source = obj === 'lead' ? this.leadPicklists : this.productCategoryPicklists;
            values = (source?.[field]?.values ?? []).map((v) => ({ label: v.label, value: v.value }));
        }
        return def.required ? values : [{ label: '--None--', value: '' }, ...values];
    }

    get departmentRowOptions() {
        const values = this.productCategoryPicklists?.Department_Name__c?.values ?? [];
        return [{ label: '--None--', value: '' }, ...values.map((v) => ({ label: v.label, value: v.value }))];
    }

    get uomRowOptions() {
        const values = this.productCategoryPicklists?.UOM__c?.values ?? [];
        return [{ label: '--None--', value: '' }, ...values.map((v) => ({ label: v.label, value: v.value }))];
    }

    categoryOptionsFor(dept) {
        const field = this.productCategoryPicklists?.Product_Category__c;
        if (!field) {
            return [];
        }
        let values = field.values;
        if (field.controllerValues) {
            const idx = field.controllerValues[dept];
            values = idx === undefined ? [] : values.filter((v) => v.validFor.includes(idx));
        }
        return [{ label: '--None--', value: '' }, ...values.map((v) => ({ label: v.label, value: v.value }))];
    }

    get departmentRowLabel() {
        return this.productCategoryInfo?.fields?.Department_Name__c?.label ?? 'Department Name';
    }

    get categoryRowLabel() {
        return this.productCategoryInfo?.fields?.Product_Category__c?.label ?? 'Product Category';
    }

    // ---------------------------------------------------------------- view models
    buildSections(layout, readOnly) {
        return layout.map((section) => {
            if (section.isRepeater) {
                return { key: section.key, isRepeater: true };
            }
            return {
                key: section.key,
                title: section.title,
                columns: section.columns.map((names, i) => ({
                    key: `${section.key}-${i}`,
                    fields: names
                        .filter((name) => this.isShown(name, readOnly))
                        .map((name) => this.fieldView(name, readOnly))
                }))
            };
        });
    }

    isShown(name, readOnly) {
        if (readOnly) {
            if (name === 'DepartmentFormulaOthers') {
                return true;
            }
            // Confirm screen only checks the Sales user lead source for Previous Source
            if (name === 'Previous_SourceOthers') {
                return this.eff('Lead_Source_Sales_User') === CRM_RESOURCE;
            }
        }
        return this.isVisible(name);
    }

    fieldView(name, readOnly) {
        if (name === 'DepartmentFormulaOthers') {
            return {
                name,
                label: 'Department',
                value: this.departmentNameFormulaOthers,
                isText: true,
                required: true,
                disabled: true
            };
        }
        const def = FIELDS[name];
        const value = this.form[name];
        return {
            name,
            label: def.label,
            value: value ?? '',
            checked: value === true,
            isText: def.type === 'text',
            isEmail: def.type === 'email',
            isPhone: def.type === 'phone',
            isPicklist: def.type === 'picklist',
            isCheckbox: def.type === 'checkbox',
            options: def.type === 'picklist' ? this.optionsFor(def) : undefined,
            required: !!def.required,
            disabled: readOnly || !!def.disabled
        };
    }

    get entrySections() {
        return this.buildSections(this.isAdminMode ? ADMIN_LAYOUT : OTHERS_LAYOUT, false);
    }

    get confirmSections() {
        return this.buildSections(CONFIRM_LAYOUT, true);
    }

    // Repeater is only visible when "Add Product Category" is visible and checked
    get repeaterVisible() {
        if (this.isAdminMode) {
            return this.isVisible('Add_Product_Category') && this.form.Add_Product_Category === true;
        }
        return this.isVisible('Add_Product_Category_Others') && this.form.Add_Product_Category_Others === true;
    }

    get rowViews() {
        const top = this.repeaterTopValue;
        return this.rows.map((r, index) => {
            // 2026-11-12: category rows always follow the lead's department (the row
            // field is disabled); changing the lead's Department above re-syncs rows.
            const dept = top;
            return {
                id: r.id,
                dept: dept ?? '',
                cat: r.cat ?? '',
                uom: r.uom ?? '',
                qty: r.qty ?? '',
                catOptions: this.categoryOptionsFor(dept),
                canRemove: this.rows.length > 1,
                label: index + 1
            };
        });
    }

    get summaryColumns() {
        return SUMMARY_COLUMNS;
    }

    get busyOrLoading() {
        return this.isBusy || this.isLoadingStep;
    }

    get uploadHasError() {
        return !!this.uploadError;
    }

    // ---------------------------------------------------------------- repeater handling
    newRow() {
        return { id: this.nextRowId++, deptTouched: false, dept: '', cat: '', uom: '', qty: '' };
    }

    handleAddRow() {
        this.rows = [...this.rows, this.newRow()];
    }

    handleRemoveRow(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.rows = this.rows.filter((r) => r.id !== id);
    }

    handleRowChange(event) {
        const id = Number(event.target.dataset.id);
        const prop = event.target.dataset.prop;
        const value = event.detail.value;
        this.rows = this.rows.map((r) => {
            if (r.id !== id) {
                return r;
            }
            const updated = { ...r, [prop]: value };
            if (prop === 'dept') {
                updated.deptTouched = true;
                updated.cat = '';
            }
            return updated;
        });
    }

    // rows currently in the repeater -> Product_Category__c payloads (Repeater Assignment)
    buildCategoryRows() {
        if (!this.repeaterVisible) {
            return [];
        }
        const top = this.repeaterTopValue;
        return this.rows.map((r) => ({
            // rows always carry the lead's department (row dept field is disabled)
            department: norm(top),
            productCategory: norm(r.cat),
            uom: norm(r.uom),
            quantity: isBlank(r.qty) ? null : Number(r.qty)
        }));
    }

    // ---------------------------------------------------------------- field handling
    handleChange(event) {
        const name = event.target.dataset.name;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.detail.value;
        this.form = { ...this.form, [name]: value };
    }

    // ---------------------------------------------------------------- validation
    customMessage(el) {
        const name = el.dataset.name;
        const f = this.form;
        switch (name) {
            case 'EmailAdmin':
            case 'EmailOthers':
                // the flow's email component rejects addresses without a valid domain, e.g. name@mail
                return isBlank(f[name]) || EMAIL_PATTERN.test(String(f[name]).trim())
                    ? ''
                    : 'Enter a valid email address.';
            case 'Company_NameOthers':
                // REGEX({!Company_NameAdmin}, "^[a-zA-Z0-9 ]*$") - the flow validates the Admin field here
                return /^[a-zA-Z0-9 ]*$/.test(f.Company_NameAdmin ?? '') ? '' : "Company Name can't have special character";
            case 'PINOthers1':
                return isBlank(f.PINOthers1) || /^[0-9]+$/.test(String(f.PINOthers1).trim())
                    ? ''
                    : 'The PIN must contain only numbers.';
            case 'rowCategory': {
                if (!this.isAdminMode) {
                    return '';
                }
                const row = this.rowViews.find((r) => r.id === Number(el.dataset.id));
                const adminDept = this.eff('DepartmentAdminCRMUser');
                const hodDept = this.eff('DepartmentHODCRMHeadSales');
                const base = adminDept !== null ? adminDept : hodDept;
                const top = row.dept;
                const ok =
                    (isBlank(base) && isBlank(top)) || (base === top && !isBlank(row.cat));
                return ok
                    ? ''
                    : 'Please ensure the Department is unchanged and a Product Category is selected.';
            }
            case 'rowDepartment': {
                if (this.isAdminMode) {
                    return '';
                }
                const row = this.rowViews.find((r) => r.id === Number(el.dataset.id));
                return this.departmentNameFormulaOthers === row.dept ? '' : "You can't change the department.";
            }
            default:
                return '';
        }
    }

    validateScreen() {
        let valid = true;
        this.template.querySelectorAll('[data-validate]').forEach((el) => {
            if (typeof el.setCustomValidity === 'function') {
                el.setCustomValidity(this.customMessage(el));
            }
            if (typeof el.reportValidity === 'function' && !el.reportValidity()) {
                valid = false;
            }
        });
        return valid;
    }

    // ---------------------------------------------------------------- navigation: entry screens
    handleEntryNext() {
        if (!this.validateScreen()) {
            return;
        }
        if (this.isAdminMode) {
            this.decideAdminPath();
        } else {
            this.decideOthersPath();
        }
    }

    // is CRM user with department enquiry
    decideAdminPath() {
        const profile = this.profileName;
        const userDept = this.init.department;
        const adminDept = this.eff('DepartmentAdminCRMUser');
        const hodDept = this.eff('DepartmentHODCRMHeadSales');
        const userId = this.init.userId;

        // returns { source, dept, owner } and whether the owner screen is needed
        let outcome;
        if (profile === 'Utkarsh Admin' || profile === 'System Administrator') {
            outcome = { source: this.eff('LeadSource_Admin'), dept: adminDept, pickOwner: true };
        } else if (profile === 'Utkarsh CRM' && equalsText(adminDept, ENQUIRY)) {
            outcome = { source: this.eff('LeadSource_CRM'), dept: adminDept, owner: userId };
        } else if (profile === 'Utkarsh CRM' && !equalsText(adminDept, ENQUIRY)) {
            outcome = { source: this.eff('LeadSource_CRM'), dept: adminDept, pickOwner: true };
        } else if (profile === 'CRM Head' && containsText(userDept, hodDept)) {
            outcome = { source: this.eff('LeadSource_UtkarshCRM_HOD'), dept: hodDept, owner: userId };
        } else if (profile === 'CRM Head' && !equalsText(hodDept, userDept)) {
            outcome = { source: this.eff('LeadSource_UtkarshCRM_HOD'), dept: hodDept, pickOwner: true };
        } else if (profile === 'Utkarsh HOD' && containsText(userDept, hodDept)) {
            outcome = { source: this.eff('LeadSource_UtkarshCRM_HOD'), dept: hodDept, owner: userId };
        } else if (profile === 'Utkarsh HOD' && !equalsText(hodDept, userDept)) {
            outcome = { source: this.eff('LeadSource_UtkarshCRM_HOD'), dept: hodDept, pickOwner: true };
        } else if (profile === 'Utkarsh Sales' && containsText(userDept, hodDept)) {
            outcome = { source: this.eff('LeadSource_Sales'), dept: hodDept, owner: userId };
        } else if (profile === 'Utkarsh Sales' && !equalsText(hodDept, userDept)) {
            outcome = { source: this.eff('LeadSource_Sales'), dept: hodDept, pickOwner: true };
        } else if (profile === 'Utkarsh Department CRM User' && containsText(userDept, adminDept)) {
            outcome = { source: this.eff('LeadSource_CRM'), dept: adminDept, owner: userId };
        } else if (profile === 'Utkarsh Department CRM User' && !equalsText(adminDept, userDept)) {
            outcome = { source: this.eff('LeadSource_CRM'), dept: adminDept, pickOwner: true };
        } else {
            // 2026-11-12: was a silent dead-end (this.step = 'end') copied from the flow's
            // unconnected Default Outcome. Any profile without a dedicated branch now gets
            // the generic CRM-style behavior: chosen department, own the lead when their
            // department matches, otherwise pick an owner.
            outcome = containsText(userDept, adminDept)
                ? { source: this.eff('LeadSource_CRM'), dept: adminDept, owner: userId }
                : { source: this.eff('LeadSource_CRM'), dept: adminDept, pickOwner: true };
        }

        this.leadSourceValue = outcome.source;
        this.departmentVar = outcome.dept;
        if (outcome.pickOwner) {
            this.openOwnerScreen();
        } else {
            this.leadOwnerId = outcome.owner;
            this.afterAdminLoop();
        }
    }

    // is Sales User
    decideOthersPath() {
        if (this.isProfile('Utkarsh Sales', 'Utkarsh Tender')) {
            this.leadSourceValueForNonAdmins = this.eff('Lead_Source_Sales_User');
        } else if (this.isProfile('Utkarsh HOD', 'CRM Head')) {
            this.leadSourceValueForNonAdmins = this.eff('Lead_Source_HOD_Dept_Head');
        } else {
            this.step = 'end';
            return;
        }
        // Loop for Otheruser Repeater -> Assign Repeter Product category
        this.summaryRows = this.buildCategoryRows().map((r, i) => ({
            id: i,
            productCategory: r.productCategory,
            uom: r.uom,
            quantity: r.quantity
        }));
        // 2026-11-12: the "Confirm Lead details below" review step was removed for the
        // others path (tender users) - save directly, same as the admin/sales path.
        // this.step = 'confirm';
        this.handleSaveLead();
    }

    // ---------------------------------------------------------------- owner screen (admin)
    async openOwnerScreen() {
        this.isBusy = true;
        try {
            this.ownerOptions = await getOwnerOptions({
                department: this.departmentVar,
                tenderProfileId: this.init.tenderProfileId
            });
            this.step = 'owner';
        } catch (e) {
            this.showFault(this.errorMessage(e));
        } finally {
            this.isBusy = false;
        }
    }

    handleOwnerChange(event) {
        this.ownerId = event.detail.value;
    }

    handleOwnerPrevious() {
        this.step = 'admin';
    }

    handleOwnerNext() {
        if (!this.validateScreen()) {
            return;
        }
        this.leadOwnerId = this.ownerId;
        this.afterAdminLoop();
    }

    // AdminLeadRepeter loop finished -> Doc Required for Admin?
    afterAdminLoop() {
        if (this.isDocRequiredForAdmin) {
            this.step = 'adminFile';
        } else {
            this.saveAdminLead();
        }
    }

    // ---------------------------------------------------------------- admin file screen
    handleAdminUploadFinished(event) {
        const files = event.detail.files;
        this.contentDocumentIds = [...this.contentDocumentIds, ...files.map((f) => f.documentId)];
        this.uploadedFileNames = [...this.uploadedFileNames, ...files.map((f) => f.name)];
        this.uploadError = '';
    }

    get uploadedFileNamesText() {
        return this.uploadedFileNames.join(', ');
    }

    get hasUploadedFileNames() {
        return this.uploadedFileNames.length > 0;
    }

    handleAdminFileNext() {
        if (this.contentDocumentIds.length < 1) {
            // the v61 message ends with "Lead source " and no value
            this.uploadError = 'This is a required to upload a file for the Lead source ';
            return;
        }
        this.uploadError = '';
        this.saveAdminLead();
    }

    // ---------------------------------------------------------------- admin: create lead
    buildAdminRequest() {
        const name = this.form.NameAdmin;
        const companyName = this.eff('Company_NameAdmin');
        return {
            city: this.eff('CityAdmin'),
            company: !isBlank(companyName) ? companyName : name,
            companyName,
            country: this.eff('CountryAdmin'),
            customerCategory: this.eff('Customer_CategoryAdmin'),
            departmentName: this.departmentVar,
            email: this.form.EmailAdmin,
            firstName: this.firstName(name),
            industry: this.eff('IndustryAdmin'),
            lastName: this.lastNameAdmin(name),
            leadSource: this.leadSourceValue,
            ownerId: this.leadOwnerId || this.init.userId,
            pin: this.eff('PINAdmin1'),
            phone: this.form.PhoneAdmin,
            previousSource: this.eff('Previous_SourceAdmin'),
            rating: this.eff('RatingAdmin'),
            state: this.eff('StateAdmin1'),
            status: this.form.Lead_StageAdmin,
            street: this.eff('StreetAdmin'),
            zone: this.eff('ZoneAdmin'),
            contentDocumentIds: this.contentDocumentIds,
            categories: this.buildCategoryRows()
        };
    }

    async saveAdminLead() {
        this.isBusy = true;
        try {
            const result = await createAdminLead({ requestJson: JSON.stringify(this.buildAdminRequest()) });
            if (result.success) {
                this.createdLeadId = result.leadId;
                this.step = 'success';
            } else {
                this.showFault(result.message);
            }
        } catch (e) {
            this.showFault(this.errorMessage(e));
        } finally {
            this.isBusy = false;
        }
    }

    // ---------------------------------------------------------------- others: confirm + create
    handleConfirmPrevious() {
        this.step = 'others';
    }

    buildOthersRequest() {
        const name = this.form.NameOthers;
        const companyName = this.eff('Company_NameOthers');
        return {
            city: this.eff('CityOthers'),
            company: !isBlank(companyName) ? companyName : name,
            companyName,
            country: this.eff('CountryOthers'),
            customerCategory: this.eff('Customer_CategoryOthers'),
            departmentName: this.departmentNameFormulaOthers,
            email: this.form.EmailOthers,
            firstName: this.firstName(name),
            industry: this.eff('IndustryOthers'),
            lastName: this.lastNameOthers(name, companyName),
            leadSource: this.leadSourceValueForNonAdmins,
            ownerId: this.init.userId,
            pin: this.eff('PINOthers1'),
            phone: this.form.PhoneOthers,
            previousSource: this.eff('Previous_SourceOthers'),
            rating: this.eff('RatingOthers'),
            state: this.eff('StateOthers1'),
            status: this.form.Lead_StageOthers,
            street: this.eff('StreetOthers'),
            zone: this.eff('ZoneOthers'),
            contentDocumentIds: [],
            categories: this.buildCategoryRows()
        };
    }

    async handleSaveLead() {
        this.isBusy = true;
        try {
            const result = await createOthersLead({ requestJson: JSON.stringify(this.buildOthersRequest()) });
            this.createdLeadId = result.leadId;
            if (!result.success) {
                this.showFault(result.message);
                return;
            }
            // Doc Required for Others?
            if (this.isDocRequiredForOthers) {
                this.step = 'othersFile';
            } else {
                await this.finishOthers();
            }
        } catch (e) {
            this.showFault(this.errorMessage(e));
        } finally {
            this.isBusy = false;
        }
    }

    // ---------------------------------------------------------------- others file screen
    get uploadErrorMessage() {
        // validation message of the flow; {!LeadSource_Admin} is empty on this path
        return `This is a required to upload a file for the Lead source ${this.form.LeadSource_Admin ?? ''}`;
    }

    handleOthersUploadFinished(event) {
        this.uploadedOthersCount += event.detail.files.length;
        this.uploadError = '';
    }

    async handleOthersFileNext() {
        if (this.uploadedOthersCount < 1) {
            this.uploadError = this.uploadErrorMessage;
            return;
        }
        this.isBusy = true;
        try {
            await this.finishOthers();
        } finally {
            this.isBusy = false;
        }
    }

    // Send Prospect Enq Email/Messaging Others -> Success Screen
    async finishOthers() {
        try {
            const result = await sendOthersNotifications({ leadId: this.createdLeadId });
            if (result.success) {
                this.step = 'success';
            } else {
                this.showFault(result.message);
            }
        } catch (e) {
            this.showFault(this.errorMessage(e));
        }
    }

    // ---------------------------------------------------------------- success / fault
    showFault(message) {
        this.faultMessage = message;
        this.step = 'fault';
    }

    errorMessage(e) {
        return e?.body?.message ?? e?.message ?? 'Unknown error';
    }

    handleFinish() {
        this.dispatchEvent(new FlowNavigationFinishEvent());
        this.dispatchEvent(new CustomEvent('finish'));
        this.resetFlow();
    }
}