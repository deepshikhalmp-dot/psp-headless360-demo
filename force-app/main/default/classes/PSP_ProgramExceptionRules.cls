/**
 * Zenthera Patient Support Program (fictional demo data): applies the Program Exceptions rules
 * (plan section 5.3) to ONE enrollment with its dispenses and open cases. Pure logic: no SOQL,
 * no DML. PSP_ProgramExceptionsService loads the records and calls evaluate().
 *
 * Refill rule is the same as PSP_RefillHistoryTool: latest Delivered dispense that has a date and
 * days supply; due = date + days supply; overdue when the as-of date is after the due date; due soon
 * within 7 days. Missing data never becomes an exception: it is returned as DATA_INCOMPLETE.
 * Free text is never interpreted and nothing is said about whether the patient took the medication.
 */
public with sharing class PSP_ProgramExceptionRules {

    public static final String PROGRAM_ZENTHERA = 'Zenthera Patient Support Program';

    public static final String TYPE_REFILL_OVERDUE = 'REFILL_OVERDUE';
    public static final String TYPE_REFILL_DUE_SOON = 'REFILL_DUE_SOON';
    public static final String TYPE_SHIPMENT_DELAYED = 'SHIPMENT_DELAYED';
    public static final String TYPE_SHIPPED_NOT_DELIVERED = 'SHIPPED_NOT_DELIVERED';
    public static final String TYPE_NO_SHIPMENT_RECORDED = 'NO_SHIPMENT_RECORDED';
    public static final String TYPE_CONSENT_PENDING = 'CONSENT_PENDING';
    public static final String TYPE_SAFETY_REVIEW_OPEN = 'SAFETY_REVIEW_OPEN';
    public static final String TYPE_DUPLICATE_OPEN_CASES = 'DUPLICATE_OPEN_CASES';
    public static final String TYPE_UNCATEGORISED_OPEN_CASE = 'UNCATEGORISED_OPEN_CASE';
    public static final String TYPE_DATA_INCOMPLETE = 'DATA_INCOMPLETE';

    public static final String SEVERITY_HIGH = 'HIGH';
    public static final String SEVERITY_MEDIUM = 'MEDIUM';
    public static final String SEVERITY_LOW = 'LOW';
    public static final String SEVERITY_INFO = 'INFO';

    public static final String ACTION_PREPARE_HANDOFF = 'PREPARE_HANDOFF';
    public static final String ACTION_CREATE_CASE = 'CREATE_CASE';
    public static final String ACTION_SKIP_EXISTING_CASE = 'SKIP_EXISTING_CASE';
    public static final String ACTION_REVIEW_POSSIBLE_DUPLICATE = 'REVIEW_POSSIBLE_DUPLICATE';
    public static final String ACTION_FOLLOW_UP_CONSENT = 'FOLLOW_UP_CONSENT';
    public static final String ACTION_TRIAGE_CASE = 'TRIAGE_CASE';
    public static final String ACTION_REVIEW_DATA = 'REVIEW_DATA';
    public static final String ACTION_NONE = 'NONE';

    public static final Integer DUE_SOON_DAYS = 7;
    public static final Integer HIGH_OVERDUE_DAYS = 7;
    public static final Integer SHIPPED_NOT_DELIVERED_DAYS = 7;
    public static final Integer NO_SHIPMENT_DAYS = 14;

    private static final String STATUS_ENROLLED = 'Enrolled';
    private static final String STATUS_ACTIVE = 'Active';
    private static final String STATUS_DISCONTINUED = 'Discontinued';
    private static final String DISPENSE_DELIVERED = 'Delivered';
    private static final String DISPENSE_DELAYED = 'Delayed';
    private static final String DISPENSE_SHIPPED = 'Shipped';
    private static final String CATEGORY_SHIPMENT_DELAY = 'Shipment Delay';
    private static final String CATEGORY_ADVERSE_EVENT = 'Possible Adverse Event';

    private static final Map<String, Integer> SEVERITY_RANK = new Map<String, Integer>{
        SEVERITY_HIGH => 0, SEVERITY_MEDIUM => 1, SEVERITY_LOW => 2, SEVERITY_INFO => 3
    };

    /** One exception or data gap for one patient. */
    public class ExceptionItem implements Comparable {
        public String exceptionType;
        public String severity;
        public Id patientId;
        public String patientName;
        public String enrollmentNumber;
        public String dispenseNumber;
        public String caseNumbers;
        public String fact;
        public String suggestedAction;

        /**
         * Sorts by severity (HIGH first), then patient name, then type.
         * @param other another ExceptionItem
         * @return negative, zero or positive
         */
        public Integer compareTo(Object other) {
            ExceptionItem that = (ExceptionItem) other;
            Integer bySeverity = rank(severity) - rank(that.severity);
            if (bySeverity != 0) {
                return bySeverity;
            }
            Integer byPatient = (patientName ?? '').compareTo(that.patientName ?? '');
            return byPatient != 0 ? byPatient : (exceptionType ?? '').compareTo(that.exceptionType ?? '');
        }
    }

    /**
     * @param enrollment enrollment with Name, Patient__c, Patient__r.Name, Program__c, Status__c, Enrollment_Date__c, Consent_Given__c, Consent_Date__c
     * @param dispenses the enrollment's dispenses (Id, Name, Status__c, Dispense_Date__c, Days_Supply__c); may be null
     * @param openCases the patient's open cases (CaseNumber, PSP_Issue_Category__c, PSP_Dispense__c); may be null
     * @param asOfDate date to evaluate on; today when null
     * @return exception items sorted by severity; empty when the patient has no exceptions
     */
    public static List<ExceptionItem> evaluate(Program_Enrollment__c enrollment, List<Dispense__c> dispenses, List<Case> openCases, Date asOfDate) {
        List<ExceptionItem> items = new List<ExceptionItem>();
        if (enrollment == null) {
            return items;
        }
        Context ctx = new Context(enrollment, dispenses, openCases, asOfDate ?? Date.today());

        if (enrollment.Patient__c == null) {
            items.add(ctx.item(TYPE_DATA_INCOMPLETE, SEVERITY_INFO, null, null, 'Enrollment has no patient, so it was not evaluated.', ACTION_REVIEW_DATA));
            return items;
        }
        if (String.isBlank(enrollment.Program__c)) {
            items.add(ctx.item(TYPE_DATA_INCOMPLETE, SEVERITY_INFO, null, null, 'Program is not set on the enrollment, so it was not evaluated.', ACTION_REVIEW_DATA));
            return items;
        }
        if (enrollment.Program__c != PROGRAM_ZENTHERA) {
            return items;
        }

        String status = enrollment.Status__c;
        Boolean isActive = status == STATUS_ENROLLED || status == STATUS_ACTIVE;
        Boolean isDiscontinued = status == STATUS_DISCONTINUED;

        if (isActive) {
            addRefillItems(ctx, items);
            addShipmentItems(ctx, items);
            addNoShipmentItem(ctx, items);
        }
        if (!isDiscontinued) {
            addConsentItems(ctx, items);
        }
        addCaseItems(ctx, items);
        items.sort();
        return items;
    }

    private static void addRefillItems(Context ctx, List<ExceptionItem> items) {
        Dispense__c lastDelivered = null;
        for (Dispense__c dispense : ctx.dispenses) {
            if (dispense.Status__c != DISPENSE_DELIVERED) {
                continue;
            }
            if (dispense.Dispense_Date__c == null || dispense.Days_Supply__c == null) {
                items.add(ctx.item(TYPE_DATA_INCOMPLETE, SEVERITY_INFO, dispense.Name, null,
                    'Delivered shipment ' + dispense.Name + ' has no ' + (dispense.Dispense_Date__c == null ? 'dispense date' : 'days supply') + ', so it is not used for refill dates.',
                    ACTION_REVIEW_DATA));
                continue;
            }
            if (lastDelivered == null || dispense.Dispense_Date__c > lastDelivered.Dispense_Date__c) {
                lastDelivered = dispense;
            }
        }
        if (lastDelivered == null) {
            return;
        }
        Date dueDate = lastDelivered.Dispense_Date__c.addDays(lastDelivered.Days_Supply__c.intValue());
        Integer daysUntilDue = ctx.asOfDate.daysBetween(dueDate);
        String basis = 'last delivered shipment ' + lastDelivered.Name + ' on ' + String.valueOf(lastDelivered.Dispense_Date__c)
            + ' for ' + lastDelivered.Days_Supply__c.intValue() + ' days, due ' + String.valueOf(dueDate);
        if (daysUntilDue < 0) {
            Integer daysOverdue = -daysUntilDue;
            items.add(ctx.item(TYPE_REFILL_OVERDUE, daysOverdue > HIGH_OVERDUE_DAYS ? SEVERITY_HIGH : SEVERITY_MEDIUM, lastDelivered.Name, null,
                'Refill overdue by ' + daysOverdue + ' day(s) based on recorded shipments only (' + basis + ').', ACTION_PREPARE_HANDOFF));
        } else if (daysUntilDue <= DUE_SOON_DAYS) {
            items.add(ctx.item(TYPE_REFILL_DUE_SOON, SEVERITY_LOW, lastDelivered.Name, null,
                'Refill due in ' + daysUntilDue + ' day(s) (' + basis + ').', ACTION_NONE));
        }
    }

    private static void addShipmentItems(Context ctx, List<ExceptionItem> items) {
        for (Dispense__c dispense : ctx.dispenses) {
            if (dispense.Status__c == DISPENSE_DELAYED) {
                items.add(delayedShipmentItem(ctx, dispense));
            } else if (dispense.Status__c == DISPENSE_SHIPPED) {
                if (dispense.Dispense_Date__c == null) {
                    items.add(ctx.item(TYPE_DATA_INCOMPLETE, SEVERITY_INFO, dispense.Name, null,
                        'Shipped shipment ' + dispense.Name + ' has no dispense date, so its delivery time cannot be checked.', ACTION_REVIEW_DATA));
                } else if (dispense.Dispense_Date__c.daysBetween(ctx.asOfDate) > SHIPPED_NOT_DELIVERED_DAYS) {
                    items.add(ctx.item(TYPE_SHIPPED_NOT_DELIVERED, SEVERITY_LOW, dispense.Name, null,
                        'Shipment ' + dispense.Name + ' was shipped on ' + String.valueOf(dispense.Dispense_Date__c) + ' and is not recorded as delivered after '
                        + dispense.Dispense_Date__c.daysBetween(ctx.asOfDate) + ' days.', ACTION_NONE));
                }
            }
        }
    }

    private static ExceptionItem delayedShipmentItem(Context ctx, Dispense__c dispense) {
        List<String> linked = new List<String>();
        List<String> unlinked = new List<String>();
        for (Case openCase : ctx.openCases) {
            if (openCase.PSP_Issue_Category__c != CATEGORY_SHIPMENT_DELAY) {
                continue;
            }
            if (openCase.PSP_Dispense__c == dispense.Id) {
                linked.add(openCase.CaseNumber);
            } else if (openCase.PSP_Dispense__c == null) {
                unlinked.add(openCase.CaseNumber);
            }
        }
        String fact = 'Shipment ' + dispense.Name + ' is Delayed';
        if (!linked.isEmpty()) {
            return ctx.item(TYPE_SHIPMENT_DELAYED, SEVERITY_MEDIUM, dispense.Name, String.join(linked, ', '),
                fact + '; open Shipment Delay case(s) already cover it: ' + String.join(linked, ', ') + '.', ACTION_SKIP_EXISTING_CASE);
        }
        if (!unlinked.isEmpty()) {
            return ctx.item(TYPE_SHIPMENT_DELAYED, SEVERITY_MEDIUM, dispense.Name, String.join(unlinked, ', '),
                fact + '; open Shipment Delay case(s) without a shipment link exist: ' + String.join(unlinked, ', ') + '. A person should check them.', ACTION_REVIEW_POSSIBLE_DUPLICATE);
        }
        return ctx.item(TYPE_SHIPMENT_DELAYED, SEVERITY_MEDIUM, dispense.Name, null,
            fact + '; no open Shipment Delay case covers it.', ACTION_CREATE_CASE);
    }

    private static void addNoShipmentItem(Context ctx, List<ExceptionItem> items) {
        if (!ctx.dispenses.isEmpty()) {
            return;
        }
        Date enrollmentDate = ctx.enrollment.Enrollment_Date__c;
        if (enrollmentDate == null) {
            items.add(ctx.item(TYPE_DATA_INCOMPLETE, SEVERITY_INFO, null, null,
                'Enrollment date is missing and no shipment is recorded, so the first-shipment check cannot run.', ACTION_REVIEW_DATA));
        } else if (enrollmentDate.daysBetween(ctx.asOfDate) > NO_SHIPMENT_DAYS) {
            items.add(ctx.item(TYPE_NO_SHIPMENT_RECORDED, SEVERITY_LOW, null, null,
                'No shipment is recorded ' + enrollmentDate.daysBetween(ctx.asOfDate) + ' days after enrollment on ' + String.valueOf(enrollmentDate) + '.', ACTION_NONE));
        }
    }

    private static void addConsentItems(Context ctx, List<ExceptionItem> items) {
        if (ctx.enrollment.Consent_Given__c != true) {
            items.add(ctx.item(TYPE_CONSENT_PENDING, SEVERITY_MEDIUM, null, null,
                'Program consent is not recorded as given.', ACTION_FOLLOW_UP_CONSENT));
        } else if (ctx.enrollment.Consent_Date__c == null) {
            items.add(ctx.item(TYPE_DATA_INCOMPLETE, SEVERITY_INFO, null, null,
                'Consent is recorded as given but the consent date is missing.', ACTION_REVIEW_DATA));
        }
    }

    private static void addCaseItems(Context ctx, List<ExceptionItem> items) {
        List<String> safetyCases = new List<String>();
        Map<String, List<String>> casesByCategoryAndDispense = new Map<String, List<String>>();
        Map<String, String> dispenseNameByKey = new Map<String, String>();

        for (Case openCase : ctx.openCases) {
            String category = openCase.PSP_Issue_Category__c;
            if (String.isBlank(category)) {
                items.add(ctx.item(TYPE_UNCATEGORISED_OPEN_CASE, SEVERITY_MEDIUM, null, openCase.CaseNumber,
                    'Open case ' + openCase.CaseNumber + ' has no PSP issue category; a person needs to review it.', ACTION_TRIAGE_CASE));
                continue;
            }
            if (category == CATEGORY_ADVERSE_EVENT) {
                safetyCases.add(openCase.CaseNumber);
            }
            String key = category + '|' + (openCase.PSP_Dispense__c == null ? '' : String.valueOf(openCase.PSP_Dispense__c));
            if (!casesByCategoryAndDispense.containsKey(key)) {
                casesByCategoryAndDispense.put(key, new List<String>());
            }
            casesByCategoryAndDispense.get(key).add(openCase.CaseNumber);
            dispenseNameByKey.put(key, ctx.dispenseName(openCase.PSP_Dispense__c));
        }

        if (!safetyCases.isEmpty()) {
            items.add(ctx.item(TYPE_SAFETY_REVIEW_OPEN, SEVERITY_HIGH, null, String.join(safetyCases, ', '),
                'Open Possible Adverse Event case(s) waiting for human safety review: ' + String.join(safetyCases, ', ') + '.', ACTION_PREPARE_HANDOFF));
        }
        for (String key : casesByCategoryAndDispense.keySet()) {
            List<String> caseNumbers = casesByCategoryAndDispense.get(key);
            if (caseNumbers.size() < 2) {
                continue;
            }
            String category = key.substringBefore('|');
            String dispenseName = dispenseNameByKey.get(key);
            items.add(ctx.item(TYPE_DUPLICATE_OPEN_CASES, SEVERITY_LOW, dispenseName, String.join(caseNumbers, ', '),
                caseNumbers.size() + ' open ' + category + ' cases' + (dispenseName == null ? ' without a shipment link' : ' for shipment ' + dispenseName)
                + ': ' + String.join(caseNumbers, ', ') + '.', ACTION_NONE));
        }
    }

    private static Integer rank(String severity) {
        return SEVERITY_RANK.containsKey(severity) ? SEVERITY_RANK.get(severity) : SEVERITY_RANK.size();
    }

    /** Records for one enrollment plus a small item builder. */
    private class Context {
        public Program_Enrollment__c enrollment;
        public List<Dispense__c> dispenses;
        public List<Case> openCases;
        public Date asOfDate;
        public Map<Id, String> dispenseNamesById = new Map<Id, String>();

        public Context(Program_Enrollment__c enrollment, List<Dispense__c> dispenses, List<Case> openCases, Date asOfDate) {
            this.enrollment = enrollment;
            this.dispenses = dispenses ?? new List<Dispense__c>();
            this.openCases = openCases ?? new List<Case>();
            this.asOfDate = asOfDate;
            for (Dispense__c dispense : this.dispenses) {
                if (dispense.Id != null) {
                    dispenseNamesById.put(dispense.Id, dispense.Name);
                }
            }
        }

        public String dispenseName(Id dispenseId) {
            return dispenseId == null ? null : dispenseNamesById.get(dispenseId);
        }

        public ExceptionItem item(String exceptionType, String severity, String dispenseNumber, String caseNumbers, String fact, String action) {
            ExceptionItem item = new ExceptionItem();
            item.exceptionType = exceptionType;
            item.severity = severity;
            item.patientId = enrollment.Patient__c;
            item.patientName = enrollment.Patient__r?.Name;
            item.enrollmentNumber = enrollment.Name;
            item.dispenseNumber = dispenseNumber;
            item.caseNumbers = caseNumbers;
            item.fact = fact;
            item.suggestedAction = action;
            return item;
        }
    }
}
