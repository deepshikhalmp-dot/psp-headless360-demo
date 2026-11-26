/**
 * Zenthera Patient Support Program (demo, fictional data): returns a patient's refill (dispense)
 * history and whether the next refill is on track, due or late.
 *
 * Reused as an MCP tool (PSP Patient Services MCP) and as an Agentforce action. The class and
 * method are global because the API Catalog only offers global invocable methods as MCP tools.
 *
 * Rules:
 * - Only dispenses with Status = Delivered and both a Dispense Date and Days Supply count.
 * - Next refill due = latest Delivered Dispense Date + its Days Supply.
 * - Days overdue = max(0, as-of date - due date).
 * - Status: LATE (as-of after due), DUE (due within DUE_WINDOW_DAYS), ON_TRACK, or
 *   NO_DELIVERED_REFILL (no countable Delivered dispense).
 * The result describes recorded shipments only; it does not confirm the patient took the medication.
 */
global with sharing class PSP_RefillHistoryTool {

    @TestVisible private static final String DISPENSE_DELIVERED = 'Delivered';
    @TestVisible private static final String ENROLLMENT_DISCONTINUED = 'Discontinued';
    @TestVisible private static final Integer DUE_WINDOW_DAYS = 7;

    @TestVisible private static final String CODE_SUCCESS = 'SUCCESS';
    @TestVisible private static final String CODE_NOT_FOUND = 'NOT_FOUND';
    @TestVisible private static final String CODE_AMBIGUOUS = 'AMBIGUOUS_MATCH';
    @TestVisible private static final String CODE_NO_ENROLLMENT = 'NO_ENROLLMENT';
    @TestVisible private static final String CODE_INVALID = 'INVALID_INPUT';
    @TestVisible private static final String CODE_ERROR = 'ERROR';

    @TestVisible private static final String STATUS_ON_TRACK = 'ON_TRACK';
    @TestVisible private static final String STATUS_DUE = 'DUE';
    @TestVisible private static final String STATUS_LATE = 'LATE';
    @TestVisible private static final String STATUS_NO_DELIVERED = 'NO_DELIVERED_REFILL';

    private static final String DISCLAIMER = ' This reflects recorded shipments only, not whether the patient took the medication.';

    /** Input for one lookup. Give patientName or enrollmentNumber. */
    global class Request {
        @InvocableVariable(label='Patient Name' description='Full name of the patient exactly as recorded, for example Riya Demo Sharma. Use this or enrollmentNumber.')
        global String patientName;

        @InvocableVariable(label='Enrollment Number' description='Enrollment ID such as ENR-0007. Takes priority over patientName when both are given.')
        global String enrollmentNumber;

        @InvocableVariable(label='As-of Date' description='Date to measure against, YYYY-MM-DD. Leave blank for today.')
        global Date asOfDate;
    }

    /** Result for one lookup. */
    global class Response {
        @InvocableVariable(label='Is Success' description='True when the refill history was found and calculated.')
        global Boolean isSuccess = false;

        @InvocableVariable(label='Result Code' description='SUCCESS, NOT_FOUND, AMBIGUOUS_MATCH, NO_ENROLLMENT, INVALID_INPUT or ERROR.')
        global String resultCode;

        @InvocableVariable(label='Result Message' description='Plain-language summary to show the user.')
        global String resultMessage;

        @InvocableVariable(label='Refill Status' description='ON_TRACK, DUE, LATE or NO_DELIVERED_REFILL. Blank when the lookup failed.')
        global String refillStatus;

        @InvocableVariable(label='Patient Id' description='Salesforce Id of the patient (Person Account).')
        global String patientId;

        @InvocableVariable(label='Patient Name' description='Name of the patient as recorded.')
        global String patientName;

        @InvocableVariable(label='Enrollment Id' description='Salesforce Id of the enrollment used.')
        global String enrollmentId;

        @InvocableVariable(label='Enrollment Number' description='Enrollment ID such as ENR-0007.')
        global String enrollmentNumber;

        @InvocableVariable(label='Therapy' description='Therapy on the enrollment.')
        global String therapy;

        @InvocableVariable(label='Enrollment Status' description='Status of the enrollment.')
        global String enrollmentStatus;

        @InvocableVariable(label='As-of Date' description='Date the calculation used.')
        global Date asOfDate;

        @InvocableVariable(label='Last Delivered Date' description='Dispense Date of the latest Delivered shipment.')
        global Date lastDeliveredDate;

        @InvocableVariable(label='Last Delivered Days Supply' description='Days Supply of the latest Delivered shipment.')
        global Integer lastDeliveredDaysSupply;

        @InvocableVariable(label='Next Refill Due Date' description='Latest Delivered Dispense Date plus its Days Supply.')
        global Date nextRefillDueDate;

        @InvocableVariable(label='Days Overdue' description='Days past the due date as of the as-of date; 0 when not late.')
        global Integer daysOverdue = 0;

        @InvocableVariable(label='Dispense Count' description='Number of dispense records on the enrollment.')
        global Integer dispenseCount = 0;

        @InvocableVariable(label='Delivered Count' description='Number of Delivered dispenses that count toward supply.')
        global Integer deliveredCount = 0;

        @InvocableVariable(label='Dispense History' description='One line per dispense, newest first: number | date | days supply | status | pharmacy | counted or not.')
        global String dispenseHistory;

        @InvocableVariable(label='Error Type' description='Technical error type when Result Code is ERROR.')
        global String errorType;
    }

    /**
     * Returns refill history and refill status for each request.
     * @param requests one entry per lookup
     * @return one response per request, in the same order
     */
    @InvocableMethod(label='PSP Get Refill History' description='Zenthera Patient Support Program: shows the dispense history of a patient, the latest Delivered shipment, the next refill due date and whether the refill is ON_TRACK, DUE, LATE or NO_DELIVERED_REFILL. Look up by patient name or enrollment number (ENR-...). Optional as-of date. Read only.' category='Patient Support Program')
    global static List<Response> getRefillHistory(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }
        try {
            responses = new RefillHistoryBuilder(requests).build();
        } catch (QueryException queryError) {
            responses = errorResponses(requests.size(), queryError);
        }
        return responses;
    }

    private static List<Response> errorResponses(Integer count, Exception cause) {
        List<Response> responses = new List<Response>();
        for (Integer index = 0; index < count; index++) {
            Response response = new Response();
            response.resultCode = CODE_ERROR;
            response.errorType = cause.getTypeName();
            response.resultMessage = 'The refill history could not be read. Check that you have access to PSP patients, enrollments and dispenses.';
            responses.add(response);
        }
        return responses;
    }

    /** Resolves requests to enrollments with a fixed number of queries, then calculates each result. */
    private with sharing class RefillHistoryBuilder {
        private final List<Request> requests;
        private final Map<String, Program_Enrollment__c> enrollmentsByNumber = new Map<String, Program_Enrollment__c>();
        private final Map<String, List<Account>> patientsByName = new Map<String, List<Account>>();
        private final Map<Id, List<Program_Enrollment__c>> enrollmentsByPatient = new Map<Id, List<Program_Enrollment__c>>();
        private final Map<Id, List<Dispense__c>> dispensesByEnrollment = new Map<Id, List<Dispense__c>>();

        RefillHistoryBuilder(List<Request> requests) {
            this.requests = requests;
        }

        List<Response> build() {
            loadEnrollmentsByNumber();
            loadPatientsAndEnrollments();
            List<Response> responses = new List<Response>();
            List<Program_Enrollment__c> chosenEnrollments = new List<Program_Enrollment__c>();
            for (Request request : requests) {
                Response response = new Response();
                Program_Enrollment__c enrollment = resolveEnrollment(request, response);
                responses.add(response);
                chosenEnrollments.add(enrollment);
            }
            loadDispenses(chosenEnrollments);
            for (Integer index = 0; index < requests.size(); index++) {
                Program_Enrollment__c enrollment = chosenEnrollments[index];
                if (enrollment != null) {
                    Date asOfDate = requests[index]?.asOfDate ?? Date.today();
                    calculate(responses[index], enrollment, dispensesByEnrollment.get(enrollment.Id) ?? new List<Dispense__c>(), asOfDate);
                }
            }
            return responses;
        }

        private void loadEnrollmentsByNumber() {
            Set<String> numbers = new Set<String>();
            for (Request request : requests) {
                if (request != null && String.isNotBlank(request.enrollmentNumber)) {
                    numbers.add(request.enrollmentNumber.trim());
                }
            }
            if (numbers.isEmpty()) {
                return;
            }
            for (Program_Enrollment__c enrollment : [
                SELECT Id, Name, Therapy__c, Status__c, Patient__c, Patient__r.Name
                FROM Program_Enrollment__c
                WHERE Name IN :numbers
                WITH USER_MODE
            ]) {
                enrollmentsByNumber.put(enrollment.Name.toUpperCase(), enrollment);
            }
        }

        private void loadPatientsAndEnrollments() {
            Set<String> names = new Set<String>();
            for (Request request : requests) {
                if (request != null && String.isBlank(request.enrollmentNumber) && String.isNotBlank(request.patientName)) {
                    names.add(request.patientName.trim());
                }
            }
            if (names.isEmpty()) {
                return;
            }
            Set<Id> patientIds = new Set<Id>();
            for (Account patient : [
                SELECT Id, Name
                FROM Account
                WHERE IsPersonAccount = true AND Name IN :names
                WITH USER_MODE
                ORDER BY CreatedDate
            ]) {
                String key = patient.Name.toLowerCase();
                if (!patientsByName.containsKey(key)) {
                    patientsByName.put(key, new List<Account>());
                }
                patientsByName.get(key).add(patient);
                patientIds.add(patient.Id);
            }
            if (patientIds.isEmpty()) {
                return;
            }
            for (Program_Enrollment__c enrollment : [
                SELECT Id, Name, Therapy__c, Status__c, Patient__c, Patient__r.Name
                FROM Program_Enrollment__c
                WHERE Patient__c IN :patientIds
                WITH USER_MODE
                ORDER BY Enrollment_Date__c DESC NULLS LAST, CreatedDate DESC
            ]) {
                if (!enrollmentsByPatient.containsKey(enrollment.Patient__c)) {
                    enrollmentsByPatient.put(enrollment.Patient__c, new List<Program_Enrollment__c>());
                }
                enrollmentsByPatient.get(enrollment.Patient__c).add(enrollment);
            }
        }

        private void loadDispenses(List<Program_Enrollment__c> enrollments) {
            Set<Id> enrollmentIds = new Set<Id>();
            for (Program_Enrollment__c enrollment : enrollments) {
                if (enrollment != null) {
                    enrollmentIds.add(enrollment.Id);
                }
            }
            if (enrollmentIds.isEmpty()) {
                return;
            }
            for (Dispense__c dispense : [
                SELECT Id, Name, Program_Enrollment__c, Dispense_Date__c, Days_Supply__c, Pharmacy__c, Status__c
                FROM Dispense__c
                WHERE Program_Enrollment__c IN :enrollmentIds
                WITH USER_MODE
                ORDER BY Dispense_Date__c DESC NULLS LAST, Name DESC
            ]) {
                if (!dispensesByEnrollment.containsKey(dispense.Program_Enrollment__c)) {
                    dispensesByEnrollment.put(dispense.Program_Enrollment__c, new List<Dispense__c>());
                }
                dispensesByEnrollment.get(dispense.Program_Enrollment__c).add(dispense);
            }
        }

        private Program_Enrollment__c resolveEnrollment(Request request, Response response) {
            if (request == null || (String.isBlank(request.enrollmentNumber) && String.isBlank(request.patientName))) {
                response.resultCode = CODE_INVALID;
                response.resultMessage = 'Give the patient\'s full name or the enrollment number (ENR-...).';
                return null;
            }
            if (String.isNotBlank(request.enrollmentNumber)) {
                Program_Enrollment__c enrollment = enrollmentsByNumber.get(request.enrollmentNumber.trim().toUpperCase());
                if (enrollment == null) {
                    response.resultCode = CODE_NOT_FOUND;
                    response.resultMessage = 'No enrollment ' + request.enrollmentNumber.trim() + ' was found.';
                }
                return enrollment;
            }
            String name = request.patientName.trim();
            List<Account> patients = patientsByName.get(name.toLowerCase()) ?? new List<Account>();
            if (patients.isEmpty()) {
                response.resultCode = CODE_NOT_FOUND;
                response.resultMessage = 'No patient named ' + name + ' was found. Check the spelling or use the enrollment number.';
                return null;
            }
            if (patients.size() > 1) {
                response.resultCode = CODE_AMBIGUOUS;
                response.resultMessage = patients.size() + ' patients are named ' + name + '. Use the enrollment number (ENR-...) to choose one.';
                return null;
            }
            Account patient = patients[0];
            response.patientId = patient.Id;
            response.patientName = patient.Name;
            List<Program_Enrollment__c> enrollments = enrollmentsByPatient.get(patient.Id) ?? new List<Program_Enrollment__c>();
            if (enrollments.isEmpty()) {
                response.resultCode = CODE_NO_ENROLLMENT;
                response.resultMessage = patient.Name + ' has no Zenthera program enrollment, so there is no refill history.';
                return null;
            }
            return pickEnrollment(enrollments);
        }

        /** Prefers the most recent open enrollment; otherwise the most recent one. Input is already newest first. */
        private Program_Enrollment__c pickEnrollment(List<Program_Enrollment__c> enrollments) {
            for (Program_Enrollment__c enrollment : enrollments) {
                if (enrollment.Status__c != ENROLLMENT_DISCONTINUED) {
                    return enrollment;
                }
            }
            return enrollments[0];
        }
    }

    @TestVisible
    private static void calculate(Response response, Program_Enrollment__c enrollment, List<Dispense__c> dispenses, Date asOfDate) {
        response.patientId = enrollment.Patient__c;
        response.patientName = enrollment.Patient__r?.Name;
        response.enrollmentId = enrollment.Id;
        response.enrollmentNumber = enrollment.Name;
        response.therapy = enrollment.Therapy__c;
        response.enrollmentStatus = enrollment.Status__c;
        response.asOfDate = asOfDate;
        response.dispenseCount = dispenses.size();

        Dispense__c lastDelivered = null;
        Integer notCountedDelivered = 0;
        List<String> historyLines = new List<String>();
        for (Dispense__c dispense : dispenses) {
            Boolean isDelivered = dispense.Status__c == DISPENSE_DELIVERED;
            Boolean isCountable = isDelivered && dispense.Dispense_Date__c != null && dispense.Days_Supply__c != null;
            if (isCountable) {
                response.deliveredCount++;
                if (lastDelivered == null || dispense.Dispense_Date__c > lastDelivered.Dispense_Date__c) {
                    lastDelivered = dispense;
                }
            } else if (isDelivered) {
                notCountedDelivered++;
            }
            historyLines.add(describe(dispense, isCountable, isDelivered));
        }
        response.dispenseHistory = historyLines.isEmpty() ? 'No dispenses recorded.' : String.join(historyLines, '\n');

        String subject = (response.patientName ?? 'The patient') + ' (' + enrollment.Name + ', ' + (enrollment.Therapy__c ?? 'therapy not recorded') + ')';
        String dataNote = notCountedDelivered > 0 ? ' ' + notCountedDelivered + ' Delivered dispense(s) are missing a date or days supply and were not counted.' : '';
        response.isSuccess = true;
        response.resultCode = CODE_SUCCESS;

        if (lastDelivered == null) {
            response.refillStatus = STATUS_NO_DELIVERED;
            response.resultMessage = subject + ': ' + dispenses.size() + ' dispense(s) on record but none Delivered with a date and days supply, so no refill due date can be calculated.' + dataNote + DISCLAIMER;
            return;
        }

        Integer daysSupply = lastDelivered.Days_Supply__c.intValue();
        Date dueDate = lastDelivered.Dispense_Date__c.addDays(daysSupply);
        Integer daysUntilDue = asOfDate.daysBetween(dueDate);
        response.lastDeliveredDate = lastDelivered.Dispense_Date__c;
        response.lastDeliveredDaysSupply = daysSupply;
        response.nextRefillDueDate = dueDate;
        response.daysOverdue = Math.max(0, -daysUntilDue);
        if (daysUntilDue < 0) {
            response.refillStatus = STATUS_LATE;
        } else if (daysUntilDue <= DUE_WINDOW_DAYS) {
            response.refillStatus = STATUS_DUE;
        } else {
            response.refillStatus = STATUS_ON_TRACK;
        }

        String statusText = response.refillStatus == STATUS_LATE
            ? 'LATE by ' + response.daysOverdue + ' day(s)'
            : (response.refillStatus == STATUS_DUE ? 'DUE in ' + daysUntilDue + ' day(s)' : 'ON TRACK (' + daysUntilDue + ' day(s) of supply left)');
        response.resultMessage = subject + ': ' + response.dispenseCount + ' dispense(s), ' + response.deliveredCount + ' counted as Delivered. '
            + 'Last delivered ' + String.valueOf(lastDelivered.Dispense_Date__c) + ' for ' + daysSupply + ' days, so the next refill is due ' + String.valueOf(dueDate) + '. '
            + 'As of ' + String.valueOf(asOfDate) + ' the refill is ' + statusText + '. '
            + 'Only Delivered shipments count; Shipped, Delayed or Cancelled ones do not.' + dataNote + DISCLAIMER;
    }

    private static String describe(Dispense__c dispense, Boolean isCountable, Boolean isDelivered) {
        String countedText = isCountable ? 'counted' : (isDelivered ? 'not counted (missing date or days supply)' : 'not counted (not Delivered)');
        return dispense.Name + ' | ' + (dispense.Dispense_Date__c == null ? 'no date' : String.valueOf(dispense.Dispense_Date__c))
            + ' | ' + (dispense.Days_Supply__c == null ? 'no days supply' : dispense.Days_Supply__c.intValue() + ' days')
            + ' | ' + (dispense.Status__c ?? 'no status')
            + ' | ' + (dispense.Pharmacy__c ?? 'no pharmacy')
            + ' | ' + countedText;
    }
}
