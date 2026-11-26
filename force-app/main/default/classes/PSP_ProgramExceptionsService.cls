/**
 * Zenthera Patient Support Program (fictional demo data): lists program exceptions from real CRM data
 * (Program_Enrollment__c, Dispense__c, Case). Read-only. Used by Coworker and the specialist agents.
 *
 * Per page: query 1 loads enrollments (Program = Zenthera, or blank Program so it can be reported as
 * DATA_INCOMPLETE) with their dispenses; query 2 loads the patients' open cases. The rules live in
 * PSP_ProgramExceptionRules. Keyset paging by enrollment number (no OFFSET). Runs in user mode, so the
 * user only gets patients, shipments and cases they are allowed to see. Patients without exceptions
 * do not appear.
 */
public with sharing class PSP_ProgramExceptionsService {

    public static final String CODE_SUCCESS = 'SUCCESS';
    public static final String CODE_INVALID_INPUT = 'INVALID_INPUT';
    public static final String CODE_NOT_FOUND = 'NOT_FOUND';
    public static final String CODE_ERROR = 'ERROR';

    public static final Integer DEFAULT_PAGE_SIZE = 200;
    public static final Integer MAX_PAGE_SIZE = 500;

    private static final Set<String> KNOWN_TYPES = new Set<String>{
        PSP_ProgramExceptionRules.TYPE_REFILL_OVERDUE, PSP_ProgramExceptionRules.TYPE_REFILL_DUE_SOON,
        PSP_ProgramExceptionRules.TYPE_SHIPMENT_DELAYED, PSP_ProgramExceptionRules.TYPE_SHIPPED_NOT_DELIVERED,
        PSP_ProgramExceptionRules.TYPE_NO_SHIPMENT_RECORDED, PSP_ProgramExceptionRules.TYPE_CONSENT_PENDING,
        PSP_ProgramExceptionRules.TYPE_SAFETY_REVIEW_OPEN, PSP_ProgramExceptionRules.TYPE_DUPLICATE_OPEN_CASES,
        PSP_ProgramExceptionRules.TYPE_UNCATEGORISED_OPEN_CASE, PSP_ProgramExceptionRules.TYPE_DATA_INCOMPLETE
    };

    /** Input. All fields are optional. */
    public class Request {
        @InvocableVariable(label='As Of Date' description='Date to evaluate on. Default: today.')
        public Date asOfDate;

        @InvocableVariable(label='Enrollment Number' description='Only this enrollment, for example ENR-0007. Leave empty for all patients.')
        public String enrollmentNumber;

        @InvocableVariable(label='Exception Types' description='Comma separated filter, for example SHIPMENT_DELAYED,REFILL_OVERDUE. Leave empty for all types.')
        public String exceptionTypes;

        @InvocableVariable(label='Page Size' description='Enrollments per page, 1 to 500. Default 200.')
        public Integer pageSize;

        @InvocableVariable(label='After Enrollment Number' description='For the next page: the Next Enrollment Number returned by the previous call.')
        public String afterEnrollmentNumber;
    }

    /** One exception or data gap. */
    public class Item {
        @InvocableVariable(label='Exception Type' description='For example REFILL_OVERDUE, SHIPMENT_DELAYED or DATA_INCOMPLETE.')
        public String exceptionType;
        @InvocableVariable(label='Severity' description='HIGH, MEDIUM, LOW or INFO (data gap).')
        public String severity;
        @InvocableVariable(label='Patient Name' description='Patient (Person Account) name.')
        public String patientName;
        @InvocableVariable(label='Patient Id' description='Patient (Person Account) Id.')
        public Id patientId;
        @InvocableVariable(label='Enrollment Number' description='Program enrollment number.')
        public String enrollmentNumber;
        @InvocableVariable(label='Dispense Number' description='Related shipment, if any.')
        public String dispenseNumber;
        @InvocableVariable(label='Case Numbers' description='Related open case numbers, if any.')
        public String caseNumbers;
        @InvocableVariable(label='Fact' description='One factual sentence. Refill dates are based on recorded shipments only.')
        public String fact;
        @InvocableVariable(label='Suggested Action' description='PREPARE_HANDOFF, CREATE_CASE, SKIP_EXISTING_CASE, REVIEW_POSSIBLE_DUPLICATE, FOLLOW_UP_CONSENT, TRIAGE_CASE, REVIEW_DATA or NONE. Every write needs the user\'s approval.')
        public String suggestedAction;
    }

    /** Output. */
    public class Response {
        @InvocableVariable(label='Result Code' description='SUCCESS, INVALID_INPUT, NOT_FOUND or ERROR.')
        public String resultCode;
        @InvocableVariable(label='Result Message' description='Short summary with counts.')
        public String resultMessage;
        @InvocableVariable(label='Items Text' description='One line per item, most severe first, ready to show to the user.')
        public String itemsText;
        @InvocableVariable(label='Items' description='Exception items, most severe first.')
        public List<Item> items = new List<Item>();
        @InvocableVariable(label='As Of Date' description='Date used for the evaluation.')
        public Date asOfDate;
        @InvocableVariable(label='Enrollments Evaluated' description='Number of enrollments checked on this page.')
        public Integer enrollmentsEvaluated = 0;
        @InvocableVariable(label='Patients With Items' description='Number of patients with at least one item on this page.')
        public Integer patientsWithItems = 0;
        @InvocableVariable(label='High Count' description='Items with severity HIGH.')
        public Integer highCount = 0;
        @InvocableVariable(label='Medium Count' description='Items with severity MEDIUM.')
        public Integer mediumCount = 0;
        @InvocableVariable(label='Low Count' description='Items with severity LOW.')
        public Integer lowCount = 0;
        @InvocableVariable(label='Data Gap Count' description='DATA_INCOMPLETE items (severity INFO).')
        public Integer dataGapCount = 0;
        @InvocableVariable(label='Has More' description='True when more enrollments remain; call again with After Enrollment Number.')
        public Boolean hasMore = false;
        @InvocableVariable(label='Next Enrollment Number' description='Pass as After Enrollment Number to get the next page.')
        public String nextEnrollmentNumber;
    }

    /**
     * Each request is one independent page (two queries). Agents and flows normally send one request.
     * @param requests list of requests
     * @return one response per request
     */
    @InvocableMethod(label='PSP Get Program Exceptions' description='Zenthera Patient Support Program: lists today\'s program exceptions from CRM data: refill overdue or due soon (recorded shipments only), delayed or long-shipped shipments, no shipment after enrollment, consent pending, open safety reviews, duplicate open cases, uncategorised cases and missing data. Optional filters: as-of date, one enrollment, exception types, paging. Read only; patients without exceptions are not listed.' category='Patient Support Program')
    public static List<Response> getExceptions(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }
        for (Request request : requests) {
            responses.add(getPage(request ?? new Request()));
        }
        return responses;
    }

    private static Response getPage(Request request) {
        Response response = new Response();
        response.asOfDate = request.asOfDate ?? Date.today();
        try {
            Integer pageSize = request.pageSize ?? DEFAULT_PAGE_SIZE;
            if (pageSize < 1 || pageSize > MAX_PAGE_SIZE) {
                return fail(response, CODE_INVALID_INPUT, 'Page Size must be between 1 and ' + MAX_PAGE_SIZE + '.');
            }
            Set<String> typeFilter = parseTypes(request.exceptionTypes);
            if (typeFilter == null) {
                return fail(response, CODE_INVALID_INPUT, 'Exception Types must be a comma separated list of: ' + String.join(new List<String>(KNOWN_TYPES), ', ') + '.');
            }

            List<Program_Enrollment__c> enrollments = queryEnrollments(request, pageSize);
            if (String.isNotBlank(request.enrollmentNumber) && enrollments.isEmpty()) {
                return fail(response, CODE_NOT_FOUND, 'Enrollment ' + request.enrollmentNumber.trim() + ' was not found in the Zenthera program.');
            }
            if (enrollments.size() > pageSize) {
                response.hasMore = true;
                enrollments.remove(enrollments.size() - 1);
                response.nextEnrollmentNumber = enrollments[enrollments.size() - 1].Name;
            }
            response.enrollmentsEvaluated = enrollments.size();

            Map<Id, List<Case>> openCasesByPatient = queryOpenCases(enrollments);
            List<PSP_ProgramExceptionRules.ExceptionItem> found = new List<PSP_ProgramExceptionRules.ExceptionItem>();
            for (Program_Enrollment__c enrollment : enrollments) {
                for (PSP_ProgramExceptionRules.ExceptionItem item : PSP_ProgramExceptionRules.evaluate(
                        enrollment, enrollment.Dispenses__r, openCasesByPatient.get(enrollment.Patient__c), response.asOfDate)) {
                    if (typeFilter.isEmpty() || typeFilter.contains(item.exceptionType)) {
                        found.add(item);
                    }
                }
            }
            found.sort();
            fillResponse(response, found);
        } catch (Exception e) {
            return fail(response, CODE_ERROR, 'Program exceptions could not be loaded: ' + e.getMessage());
        }
        return response;
    }

    private static List<Program_Enrollment__c> queryEnrollments(Request request, Integer pageSize) {
        Integer rowLimit = pageSize + 1;
        String program = PSP_ProgramExceptionRules.PROGRAM_ZENTHERA;
        if (String.isNotBlank(request.enrollmentNumber)) {
            String enrollmentNumber = request.enrollmentNumber.trim();
            return [
                SELECT Id, Name, Patient__c, Patient__r.Name, Program__c, Status__c, Enrollment_Date__c, Consent_Given__c, Consent_Date__c,
                    (SELECT Id, Name, Status__c, Dispense_Date__c, Days_Supply__c FROM Dispenses__r ORDER BY Dispense_Date__c DESC)
                FROM Program_Enrollment__c
                WHERE Name = :enrollmentNumber AND (Program__c = :program OR Program__c = null)
                WITH USER_MODE
                LIMIT 1
            ];
        }
        String afterKey = String.isBlank(request.afterEnrollmentNumber) ? '' : request.afterEnrollmentNumber.trim();
        return [
            SELECT Id, Name, Patient__c, Patient__r.Name, Program__c, Status__c, Enrollment_Date__c, Consent_Given__c, Consent_Date__c,
                (SELECT Id, Name, Status__c, Dispense_Date__c, Days_Supply__c FROM Dispenses__r ORDER BY Dispense_Date__c DESC)
            FROM Program_Enrollment__c
            WHERE (Program__c = :program OR Program__c = null) AND Name > :afterKey
            WITH USER_MODE
            ORDER BY Name
            LIMIT :rowLimit
        ];
    }

    private static Map<Id, List<Case>> queryOpenCases(List<Program_Enrollment__c> enrollments) {
        Map<Id, List<Case>> openCasesByPatient = new Map<Id, List<Case>>();
        Set<Id> patientIds = new Set<Id>();
        for (Program_Enrollment__c enrollment : enrollments) {
            if (enrollment.Patient__c != null) {
                patientIds.add(enrollment.Patient__c);
            }
        }
        if (patientIds.isEmpty()) {
            return openCasesByPatient;
        }
        for (Case openCase : [
            SELECT Id, CaseNumber, AccountId, PSP_Issue_Category__c, PSP_Dispense__c
            FROM Case
            WHERE AccountId IN :patientIds AND IsClosed = false
            WITH USER_MODE
            ORDER BY CaseNumber
        ]) {
            if (!openCasesByPatient.containsKey(openCase.AccountId)) {
                openCasesByPatient.put(openCase.AccountId, new List<Case>());
            }
            openCasesByPatient.get(openCase.AccountId).add(openCase);
        }
        return openCasesByPatient;
    }

    /** @return empty set for no filter, null when an unknown type is given */
    private static Set<String> parseTypes(String exceptionTypes) {
        Set<String> types = new Set<String>();
        if (String.isBlank(exceptionTypes)) {
            return types;
        }
        for (String part : exceptionTypes.split(',')) {
            String value = part.trim().toUpperCase();
            if (String.isBlank(value)) {
                continue;
            }
            if (!KNOWN_TYPES.contains(value)) {
                return null;
            }
            types.add(value);
        }
        return types;
    }

    private static void fillResponse(Response response, List<PSP_ProgramExceptionRules.ExceptionItem> found) {
        Set<Id> patients = new Set<Id>();
        List<String> lines = new List<String>();
        for (PSP_ProgramExceptionRules.ExceptionItem source : found) {
            Item item = new Item();
            item.exceptionType = source.exceptionType;
            item.severity = source.severity;
            item.patientName = source.patientName;
            item.patientId = source.patientId;
            item.enrollmentNumber = source.enrollmentNumber;
            item.dispenseNumber = source.dispenseNumber;
            item.caseNumbers = source.caseNumbers;
            item.fact = source.fact;
            item.suggestedAction = source.suggestedAction;
            response.items.add(item);
            countSeverity(response, source.severity);
            if (source.patientId != null) {
                patients.add(source.patientId);
            }
            lines.add(source.severity + ' | ' + (source.patientName ?? 'No patient') + ' (' + source.enrollmentNumber + ') | '
                + source.exceptionType + ' | ' + source.fact + ' | Suggested: ' + source.suggestedAction);
        }
        response.patientsWithItems = patients.size();
        response.itemsText = lines.isEmpty() ? 'No program exceptions found.' : String.join(lines, '\n');
        response.resultCode = CODE_SUCCESS;
        response.resultMessage = 'As of ' + String.valueOf(response.asOfDate) + ': ' + response.items.size() + ' item(s) for '
            + response.patientsWithItems + ' patient(s) out of ' + response.enrollmentsEvaluated + ' enrollment(s) checked ('
            + response.highCount + ' high, ' + response.mediumCount + ' medium, ' + response.lowCount + ' low, '
            + response.dataGapCount + ' data gap(s)). Refill dates are based on recorded shipments only.'
            + (response.hasMore ? ' More enrollments remain: call again with After Enrollment Number ' + response.nextEnrollmentNumber + '.' : '');
    }

    private static void countSeverity(Response response, String severity) {
        if (severity == PSP_ProgramExceptionRules.SEVERITY_HIGH) {
            response.highCount++;
        } else if (severity == PSP_ProgramExceptionRules.SEVERITY_MEDIUM) {
            response.mediumCount++;
        } else if (severity == PSP_ProgramExceptionRules.SEVERITY_LOW) {
            response.lowCount++;
        } else {
            response.dataGapCount++;
        }
    }

    private static Response fail(Response response, String code, String message) {
        response.resultCode = code;
        response.resultMessage = message;
        response.items = new List<Item>();
        response.itemsText = message;
        return response;
    }
}
