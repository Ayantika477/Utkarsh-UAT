import LightningDatatable from 'lightning/datatable';
import subjectCell from './subjectCell.html';
import coloredCell from './coloredCell.html';

/**
 * Datatable for activityOverview with two custom cell types:
 *  - subjectLink: record link with a red warning icon when the row is overdue
 *  - coloredText: plain text that turns red when the row is overdue
 */
export default class ActivityOverviewDatatable extends LightningDatatable {
    static customTypes = {
        subjectLink: {
            template: subjectCell,
            standardCellLayout: true,
            typeAttributes: ['url', 'overdue', 'cellStyle']
        },
        coloredText: {
            template: coloredCell,
            standardCellLayout: true,
            typeAttributes: ['cellStyle']
        }
    };
}