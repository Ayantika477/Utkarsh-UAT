import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDepartmentOptions from '@salesforce/apex/OfflineCampaignUploadController.getDepartmentOptions';
import insertOfflineCampaignRows from '@salesforce/apex/OfflineCampaignUploadController.insertOfflineCampaignRows';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export default class UploadOfflineCampaign extends LightningElement {
  @track rows = [];
  @track draftValues = [];
  @track departmentOptions = [];
  @track columns = [];
  @track insertSummary;
  @track errorSummary = [];

  isLoading = false;
  hasUploadedFile = false;
  uploadedFileName;

  connectedCallback() {
    this.buildColumns();
  }

  @wire(getDepartmentOptions)
  wiredDepartmentOptions({ data, error }) {
    if (data) {
      this.departmentOptions = data;
      this.buildColumns();
    } else if (error) {
      this.showToast('Error', this.normalizeError(error), 'error');
    }
  }

  buildColumns() {
    this.columns = [
      { label: 'Name', fieldName: 'recordName', type: 'text', editable: true },
      { label: 'Email', fieldName: 'email', type: 'email', editable: true },
      {
        label: 'Phone',
        fieldName: 'phoneDisplay',
        type: 'text',
        editable: true
      },
      {
        label: 'Department',
        fieldName: 'department',
        type: 'picklist',
        editable: true,
        typeAttributes: {
          placeholder: 'Choose department',
          options: this.departmentOptions || [],
          value: { fieldName: 'department' },
          context: { fieldName: 'department' }
        }
      },
      {
        label: 'Errors',
        fieldName: 'errors',
        type: 'text',
        wrapText: true,
        initialWidth: 260
      }
    ];
  }

  get hasRows() {
    return this.rows && this.rows.length > 0;
  }

  get disableInsert() {
    return this.isLoading || !this.hasRows;
  }

  get showSummary() {
    return this.insertSummary != null;
  }

  handleFileChange(event) {
    const file = event.target.files && event.target.files[0];
    if (!file) {
      return;
    }

    this.uploadedFileName = file.name;
    this.isLoading = true;
    this.insertSummary = null;
    this.errorSummary = [];

    const reader = new FileReader();
    reader.onload = () => {
      try {
        const parsedRows = this.parseCsv(String(reader.result || ''));
        this.rows = parsedRows.map((row) => this.applyValidation(row));
        this.hasUploadedFile = true;
        this.draftValues = [];
        if (!this.rows.length) {
          this.showToast(
            'No data found',
            'The uploaded file did not contain any data rows.',
            'warning'
          );
        }
      } catch (error) {
        this.showToast('Upload failed', error.message, 'error');
        this.rows = [];
        this.hasUploadedFile = false;
      } finally {
        this.isLoading = false;
      }
    };
    reader.onerror = () => {
      this.isLoading = false;
      this.showToast('Upload failed', 'Unable to read the selected file.', 'error');
    };
    reader.readAsText(file);
  }

  handleCellChange(event) {
    this.draftValues = this.consolidateDraftChanges(
      this.draftValues,
      event.detail.draftValues
    );
  }

  handleSaveEdits(event) {
    const applied = this.applyDraftChanges(
      event?.detail?.draftValues,
      this.draftValues
    );
    if (applied) {
      this.showToast('Saved', 'Your changes have been saved.', 'success');
    }
  }

  applyDraftChanges(...draftLists) {
    const changes = this.consolidateDraftChanges(...draftLists);
    if (!changes.length) {
      return false;
    }

    const draftByKey = new Map();
    for (const change of changes) {
      if (!change?.rowKey) {
        continue;
      }
      const existing = draftByKey.get(change.rowKey) || {};
      draftByKey.set(change.rowKey, { ...existing, ...change });
    }

    this.rows = this.rows.map((row) => {
      const change = draftByKey.get(row.rowKey);
      if (!change) {
        return row;
      }

      const merged = { ...row, ...change };
      if (Object.prototype.hasOwnProperty.call(change, 'phoneDisplay')) {
        merged.phone = this.parsePhone(change.phoneDisplay);
      } else if (Object.prototype.hasOwnProperty.call(change, 'phone')) {
        merged.phone = this.parsePhone(change.phone);
        merged.phoneDisplay = change.phone;
      }
      return this.applyValidation(merged);
    });
    this.draftValues = [];
    return true;
  }

  consolidateDraftChanges(...draftLists) {
    const draftByKey = new Map();
    for (const draftList of draftLists) {
      if (!draftList || !draftList.length) {
        continue;
      }
      for (const change of draftList) {
        if (!change?.rowKey) {
          continue;
        }
        const existing = draftByKey.get(change.rowKey) || {};
        draftByKey.set(change.rowKey, { ...existing, ...change });
      }
    }
    return Array.from(draftByKey.values());
  }

  handleCancelEdits() {
    this.draftValues = [];
  }

  async handleInsert() {
    this.isLoading = true;
    this.insertSummary = null;
    this.errorSummary = [];

    try {
      const validatedRows = this.rows.map((row) => this.applyValidation(row));
      const rowsWithErrors = validatedRows.filter((row) => row.errors);
      if (rowsWithErrors.length) {
        this.rows = validatedRows;
        this.showToast(
          'Validation failed',
          'Fix the errors shown in the table before inserting.',
          'error'
        );
        return;
      }

      const payload = validatedRows.map((row) => ({
        rowKey: row.rowKey,
        recordName: row.recordName,
        email: row.email || null,
        phone: row.phone,
        department: row.department || null,
        active: row.active === true
      }));

      const summary = await insertOfflineCampaignRows({
        rowsJson: JSON.stringify(payload)
      });
      this.insertSummary = summary;
      this.errorSummary = (Array.isArray(summary.errorSummary)
        ? summary.errorSummary
        : summary.errorSummary
          ? [summary.errorSummary]
          : []
      ).map((message, index) => ({ key: `error-${index}`, value: message }));

      const resultByKey = new Map(
        (summary.rowResults || []).map((item) => [item.rowKey, item])
      );
      this.rows = this.rows.map((row) => {
        const result = resultByKey.get(row.rowKey);
        if (!result) {
          return row;
        }
        return {
          ...row,
          errors: result.success ? '' : result.errors
        };
      });

      this.showToast(
        'Insert complete',
        `Total: ${summary.totalCount}, Success: ${summary.successCount}, Failed: ${summary.failedCount}`,
        summary.failedCount > 0 ? 'warning' : 'success'
      );
    } catch (error) {
      this.showToast('Insert failed', this.normalizeError(error), 'error');
    } finally {
      this.isLoading = false;
    }
  }

  handleReset() {
    this.rows = [];
    this.draftValues = [];
    this.insertSummary = null;
    this.errorSummary = [];
    this.hasUploadedFile = false;
    this.uploadedFileName = null;
    const fileInput = this.template.querySelector('input[type="file"]');
    if (fileInput) {
      fileInput.value = null;
    }
  }

  parseCsv(content) {
    const normalizedContent = content.replace(/^\uFEFF/, '');
    const lines = normalizedContent
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line.length > 0);

    if (!lines.length) {
      return [];
    }

    const headers = this.parseCsvLine(lines[0]).map((header) =>
      header.trim().toLowerCase()
    );
    const headerIndex = {
      name: headers.indexOf('name'),
      email: headers.indexOf('email'),
      phone: headers.indexOf('phone'),
      department: headers.indexOf('department'),
      active: headers.indexOf('active')
    };

    if (headerIndex.name === -1) {
      throw new Error('CSV must include a Name column.');
    }

    const parsedRows = [];
    for (let lineNumber = 1; lineNumber < lines.length; lineNumber++) {
      const values = this.parseCsvLine(lines[lineNumber]);
      if (values.every((value) => !value || !value.trim())) {
        continue;
      }

      const phoneValue = this.getCsvValue(values, headerIndex.phone);
      parsedRows.push({
        rowKey: `row-${lineNumber}`,
        recordName: this.getCsvValue(values, headerIndex.name),
        email: this.getCsvValue(values, headerIndex.email),
        phone: this.parsePhone(phoneValue),
        phoneDisplay: phoneValue,
        department: this.getCsvValue(values, headerIndex.department),
        active: this.parseActive(this.getCsvValue(values, headerIndex.active)),
        errors: ''
      });
    }

    return parsedRows;
  }

  parseCsvLine(line) {
    const values = [];
    let current = '';
    let inQuotes = false;

    for (let index = 0; index < line.length; index++) {
      const character = line[index];
      if (character === '"') {
        if (inQuotes && line[index + 1] === '"') {
          current += '"';
          index++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (character === ',' && !inQuotes) {
        values.push(current);
        current = '';
      } else {
        current += character;
      }
    }
    values.push(current);
    return values;
  }

  getCsvValue(values, index) {
    if (index === -1 || index >= values.length) {
      return '';
    }
    return (values[index] || '').trim();
  }

  parsePhone(value) {
    if (!value) {
      return null;
    }
    const trimmed = String(value).trim();
    return trimmed ? trimmed : null;
  }

  parseActive(value) {
    if (!value) {
      return false;
    }
    const normalized = value.trim().toLowerCase();
    return ['true', 'yes', '1', 'y'].includes(normalized);
  }

  applyValidation(row) {
    const errors = [];
    const departmentValues = new Set(
      (this.departmentOptions || []).map((option) => option.value)
    );
    const recordName = row.recordName ? String(row.recordName).trim() : '';

    if (!recordName) {
      errors.push('Name: Name is required.');
    } else if (recordName.length > 80) {
      errors.push('Name: Name cannot exceed 80 characters.');
    }

    if (row.email && !EMAIL_PATTERN.test(String(row.email).trim())) {
      errors.push('Email: Invalid email format.');
    }

    if (row.phone && !/^\+?[\d\s\-()]+$/.test(String(row.phone).trim())) {
      errors.push('Phone: Invalid phone format.');
    }

    if (row.department && !departmentValues.has(row.department)) {
      errors.push('Department: Invalid picklist value.');
    }

    const phoneDisplay =
      row.phoneDisplay != null && String(row.phoneDisplay).trim()
        ? String(row.phoneDisplay).trim()
        : row.phone
          ? String(row.phone).trim()
          : '';
    const phone = this.parsePhone(phoneDisplay);

    return {
      ...row,
      recordName,
      email: row.email ? String(row.email).trim() : '',
      department: row.department ? String(row.department).trim() : '',
      phone,
      phoneDisplay,
      errors: errors.join(' ')
    };
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
    return 'Unexpected error while processing offline campaign upload.';
  }
}