/**
 * Zenthera Patient Support Program (fictional demo data): read-only duplicate check that runs
 * BEFORE a new service case is created. Uses only Case.PSP_Issue_Category__c and Case.PSP_Dispense__c
 * (no Subject/Description parsing). Rules (plan section 5.5):
 *   - open case, same category, same dispense          -> EXISTING_CASE (do not create)
 *   - open case, same category, different dispense     -> not a duplicate (separate shipment)
 *   - open case, same category, dispense blank         -> POSSIBLE_DUPLICATE (a person decides)
 *   - no dispense in the request, same category open   -> EXISTING_CASE (category-level match)
 *   - open cases without a category                    -> listed as unclassified, never block
 *   - closed cases                                     -> never block
 * Runs in user mode: the user only sees records they are allowed to see. Never writes.
 */
public with sharing class PSP_CaseDuplicateCheck {

    public static final String CODE_NO_DUPLICATE = 'NO_DUPLICATE';
    public static final String CODE_EXISTING_CASE = 'EXISTING_CASE';
    public static final String CODE_POSSIBLE_DUPLICATE = 'POSSIBLE_DUPLICATE';
    public static final String CODE_INVALID_INPUT = 'INVALID_INPUT';
    public static final String CODE_NOT_FOUND = 'NOT_FOUND';
    public static final String CODE_ERROR = 'ERROR';

    /** Input for one check. */
    public class Request {
        @InvocableVariable(label='Enrollment Number' description='Program enrollment number such as ENR-0007. Used when Patient Id is empty.')
        public String enrollmentNumber;

        @InvocableVariable(label='Patient Id' description='Person Account Id of the patient. Takes priority over Enrollment Number.')
        public Id patientId;

        @InvocableVariable(label='Issue Category' description='Shipment Delay, Refill Support, Insurance Support, General Program Support or Possible Adverse Event.' required=true)
        public String category;

        @InvocableVariable(label='Dispense Number' description='Optional shipment number such as DSP-0016. Must belong to the patient.')
        public String dispenseNumber;
    }

    /** Result of one check. */
    public class Response {
        @InvocableVariable(label='Result Code' description='NO_DUPLICATE, EXISTING_CASE, POSSIBLE_DUPLICATE, INVALID_INPUT, NOT_FOUND or ERROR.')
        public String resultCode;

        @InvocableVariable(label='Can Create' description='True only when no open case blocks a new one. Creation still needs the user\'s approval.')
        public Boolean canCreate = false;

        @InvocableVariable(label='Matching Case Numbers' description='Open cases that already cover this issue (comma separated).')
        public String matchingCaseNumbers;

        @InvocableVariable(label='Possible Duplicate Case Numbers' description='Open cases with the same category but no shipment link; a person must decide.')
        public String possibleDuplicateCaseNumbers;

        @InvocableVariable(label='Unclassified Open Case Numbers' description='Open cases of the patient without a category; shown for review, they do not block.')
        public String unclassifiedOpenCaseNumbers;

        @InvocableVariable(label='Patient Name' description='Name of the patient that was checked.')
        public String patientName;

        @InvocableVariable(label='Result Message' description='One plain sentence that explains the result.')
        public String resultMessage;
    }

    /**
     * @param requests one or more checks (bulk-safe: three queries in total)
     * @return one response per request, in the same order
     */
    @InvocableMethod(label='PSP Check Duplicate Case' description='Zenthera Patient Support Program: before creating a service case, checks whether an open case for the same patient, issue category and shipment already exists. Read only. Returns NO_DUPLICATE, EXISTING_CASE (with case numbers), POSSIBLE_DUPLICATE (same category, shipment unknown) or an error code.' category='Patient Support Program')
    public static List<Response> checkDuplicates(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }
        try {
            responses = evaluate(requests);
        } catch (Exception e) {
            responses = new List<Response>();
            for (Integer i = 0; i < requests.size(); i++) {
                responses.add(buildResponse(CODE_ERROR, 'The duplicate check could not run: ' + e.getMessage()));
            }
        }
        return responses;
    }

    private static List<Response> evaluate(List<Request> requests) {
        Set<String> enrollmentNumbers = new Set<String>();
        Set<String> dispenseNumbers = new Set<String>();
        for (Request request : requests) {
            if (request == null) {
                continue;
            }
            if (request.patientId == null && String.isNotBlank(request.enrollmentNumber)) {
                enrollmentNumbers.add(request.enrollmentNumber.trim().toUpperCase());
            }
            if (String.isNotBlank(request.dispenseNumber)) {
                dispenseNumbers.add(request.dispenseNumber.trim().toUpperCase());
            }
        }

        Map<String, Program_Enrollment__c> enrollmentsByNumber = queryEnrollments(enrollmentNumbers);
        Map<String, Dispense__c> dispensesByNumber = queryDispenses(dispenseNumbers);

        Set<Id> patientIds = new Set<Id>();
        for (Request request : requests) {
            Id patientId = resolvePatientId(request, enrollmentsByNumber);
            if (patientId != null) {
                patientIds.add(patientId);
            }
        }
        Map<Id, List<Case>> openCasesByPatient = queryOpenCases(patientIds);
        Map<Id, Account> patientsById = queryPatients(patientIds);

        List<Response> responses = new List<Response>();
        for (Request request : requests) {
            responses.add(checkOne(request, enrollmentsByNumber, dispensesByNumber, openCasesByPatient, patientsById));
        }
        return responses;
    }

    private static Response checkOne(
        Request request,
        Map<String, Program_Enrollment__c> enrollmentsByNumber,
        Map<String, Dispense__c> dispensesByNumber,
        Map<Id, List<Case>> openCasesByPatient,
        Map<Id, Account> patientsById
    ) {
        if (request == null) {
            return buildResponse(CODE_INVALID_INPUT, 'No request was given.');
        }
        String category = toKnownCategory(request.category);
        if (category == null) {
            return buildResponse(CODE_INVALID_INPUT, 'Issue category must be one of: ' + String.join(new List<String>(validCategories()), ', ') + '.');
        }
        if (request.patientId == null && String.isBlank(request.enrollmentNumber)) {
            return buildResponse(CODE_INVALID_INPUT, 'Give a Patient Id or an Enrollment Number.');
        }
        Id patientId = resolvePatientId(request, enrollmentsByNumber);
        if (patientId == null || !patientsById.containsKey(patientId)) {
            return buildResponse(CODE_NOT_FOUND, 'No patient was found for this Patient Id or Enrollment Number.');
        }

        Dispense__c dispense = null;
        if (String.isNotBlank(request.dispenseNumber)) {
            dispense = dispensesByNumber.get(request.dispenseNumber.trim().toUpperCase());
            if (dispense == null || dispense.Program_Enrollment__r?.Patient__c != patientId) {
                return buildResponse(CODE_INVALID_INPUT, 'Shipment ' + request.dispenseNumber.trim() + ' was not found for this patient.');
            }
        }

        Response response = classify(category, dispense, openCasesByPatient.get(patientId));
        response.patientName = patientsById.get(patientId).Name;
        return response;
    }

    private static Response classify(String category, Dispense__c dispense, List<Case> openCases) {
        List<String> matching = new List<String>();
        List<String> possible = new List<String>();
        List<String> unclassified = new List<String>();

        for (Case openCase : openCases == null ? new List<Case>() : openCases) {
            if (String.isBlank(openCase.PSP_Issue_Category__c)) {
                unclassified.add(openCase.CaseNumber);
            } else if (openCase.PSP_Issue_Category__c == category) {
                if (dispense == null || openCase.PSP_Dispense__c == dispense.Id) {
                    matching.add(openCase.CaseNumber);
                } else if (openCase.PSP_Dispense__c == null) {
                    possible.add(openCase.CaseNumber);
                }
                // Same category but a different shipment: a separate issue, not a duplicate.
            }
        }

        Response response;
        String shipmentText = dispense == null ? '' : ' for shipment ' + dispense.Name;
        if (!matching.isEmpty()) {
            response = buildResponse(CODE_EXISTING_CASE, 'An open ' + category + ' case already exists' + shipmentText + ': ' + String.join(matching, ', ') + '. Do not create a new case.');
        } else if (!possible.isEmpty()) {
            response = buildResponse(CODE_POSSIBLE_DUPLICATE, 'Open ' + category + ' case(s) without a shipment link exist: ' + String.join(possible, ', ') + '. Ask the coordinator whether they cover' + shipmentText + ' before creating a case.');
        } else {
            response = buildResponse(CODE_NO_DUPLICATE, 'No open ' + category + ' case' + shipmentText + ' was found. A new case may be created after the user approves it.');
            response.canCreate = true;
        }
        response.matchingCaseNumbers = joinOrNull(matching);
        response.possibleDuplicateCaseNumbers = joinOrNull(possible);
        response.unclassifiedOpenCaseNumbers = joinOrNull(unclassified);
        return response;
    }

    private static Id resolvePatientId(Request request, Map<String, Program_Enrollment__c> enrollmentsByNumber) {
        if (request == null) {
            return null;
        }
        if (request.patientId != null) {
            return request.patientId;
        }
        if (String.isBlank(request.enrollmentNumber)) {
            return null;
        }
        return enrollmentsByNumber.get(request.enrollmentNumber.trim().toUpperCase())?.Patient__c;
    }

    private static Map<String, Program_Enrollment__c> queryEnrollments(Set<String> enrollmentNumbers) {
        Map<String, Program_Enrollment__c> enrollmentsByNumber = new Map<String, Program_Enrollment__c>();
        if (enrollmentNumbers.isEmpty()) {
            return enrollmentsByNumber;
        }
        for (Program_Enrollment__c enrollment : [
            SELECT Id, Name, Patient__c
            FROM Program_Enrollment__c
            WHERE Name IN :enrollmentNumbers
            WITH USER_MODE
        ]) {
            enrollmentsByNumber.put(enrollment.Name.toUpperCase(), enrollment);
        }
        return enrollmentsByNumber;
    }

    private static Map<String, Dispense__c> queryDispenses(Set<String> dispenseNumbers) {
        Map<String, Dispense__c> dispensesByNumber = new Map<String, Dispense__c>();
        if (dispenseNumbers.isEmpty()) {
            return dispensesByNumber;
        }
        for (Dispense__c dispense : [
            SELECT Id, Name, Program_Enrollment__r.Patient__c
            FROM Dispense__c
            WHERE Name IN :dispenseNumbers
            WITH USER_MODE
        ]) {
            dispensesByNumber.put(dispense.Name.toUpperCase(), dispense);
        }
        return dispensesByNumber;
    }

    private static Map<Id, List<Case>> queryOpenCases(Set<Id> patientIds) {
        Map<Id, List<Case>> openCasesByPatient = new Map<Id, List<Case>>();
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

    private static Map<Id, Account> queryPatients(Set<Id> patientIds) {
        if (patientIds.isEmpty()) {
            return new Map<Id, Account>();
        }
        return new Map<Id, Account>([SELECT Id, Name FROM Account WHERE Id IN :patientIds WITH USER_MODE]);
    }

    private static Set<String> cachedCategories;

    private static Set<String> validCategories() {
        if (cachedCategories == null) {
            cachedCategories = new Set<String>();
            for (Schema.PicklistEntry entry : Case.PSP_Issue_Category__c.getDescribe().getPicklistValues()) {
                if (entry.isActive()) {
                    cachedCategories.add(entry.getValue());
                }
            }
        }
        return cachedCategories;
    }

    private static String toKnownCategory(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        for (String category : validCategories()) {
            if (category.equalsIgnoreCase(value.trim())) {
                return category;
            }
        }
        return null;
    }

    private static String joinOrNull(List<String> values) {
        return values.isEmpty() ? null : String.join(values, ', ');
    }

    private static Response buildResponse(String resultCode, String message) {
        Response response = new Response();
        response.resultCode = resultCode;
        response.resultMessage = message;
        return response;
    }
}
