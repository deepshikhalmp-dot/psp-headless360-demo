/**
 * Zenthera Patient Support Program (fictional demo data): creates a service case ONLY after the
 * user has explicitly approved it. Used by the PSP Care Resolution Agent (Phase 4).
 *
 * Guard rails:
 *   - userConfirmed must be true, otherwise nothing is written (NOT_CONFIRMED).
 *   - The read-only PSP_CaseDuplicateCheck runs first: EXISTING_CASE and POSSIBLE_DUPLICATE block the
 *     write (DUPLICATE_OPEN_CASE / NEEDS_REVIEW).
 *   - Runs in user mode: the user's own create access and sharing apply.
 *   - Sets Case.PSP_Issue_Category__c and Case.PSP_Dispense__c, so new cases never need a backfill.
 *   - Possible adverse events are only flagged for human safety review; nothing is reported to a regulator.
 * The existing PSP Create Service Case Flow (used by Slackbot) is not changed.
 */
public with sharing class PSP_CreateApprovedCase {

    public static final String CODE_CREATED = 'CREATED';
    public static final String CODE_NOT_CONFIRMED = 'NOT_CONFIRMED';
    public static final String CODE_DUPLICATE = 'DUPLICATE_OPEN_CASE';
    public static final String CODE_NEEDS_REVIEW = 'NEEDS_REVIEW';
    public static final String CODE_INVALID_INPUT = 'INVALID_INPUT';
    public static final String CODE_NOT_FOUND = 'NOT_FOUND';
    public static final String CODE_ERROR = 'ERROR';

    public static final String CATEGORY_ADVERSE_EVENT = 'Possible Adverse Event';
    public static final String CATEGORY_INSURANCE = 'Insurance Support';
    public static final Integer MAX_SUBJECT_LENGTH = 180;
    public static final Integer MAX_DESCRIPTION_LENGTH = 4000;

    private static final String CASE_ORIGIN = 'Chat';
    private static final String CASE_STATUS = 'New';
    private static final String SAFETY_NOTE = 'SAFETY REVIEW REQUIRED: possible adverse event reported. Route to the safety / pharmacovigilance team for human review. No medical advice was given and no regulatory report has been submitted automatically.';

    /** Input for one approved case. */
    public class Request {
        @InvocableVariable(label='Enrollment Number' description='Enrollment number of the patient, for example ENR-0007.' required=true)
        public String enrollmentNumber;

        @InvocableVariable(label='Issue Category' description='Shipment Delay, Refill Support, Insurance Support, General Program Support or Possible Adverse Event.' required=true)
        public String category;

        @InvocableVariable(label='Dispense Number' description='Optional shipment number such as DSP-0016; must belong to the patient.')
        public String dispenseNumber;

        @InvocableVariable(label='Subject' description='Short subject in plain words, without the category tag (added automatically).' required=true)
        public String subject;

        @InvocableVariable(label='Description' description='What the coordinator or patient reported. Facts only, no medical advice.' required=true)
        public String description;

        @InvocableVariable(label='User Confirmed' description='True only when the user explicitly approved creating THIS case in the conversation. Otherwise nothing is created.' required=true)
        public Boolean userConfirmed;
    }

    /** Result for one request. */
    public class Response {
        @InvocableVariable(label='Result Code' description='CREATED, NOT_CONFIRMED, DUPLICATE_OPEN_CASE, NEEDS_REVIEW, INVALID_INPUT, NOT_FOUND or ERROR.')
        public String resultCode;
        @InvocableVariable(label='Result Message' description='One sentence to show the user.')
        public String resultMessage;
        @InvocableVariable(label='Case Number' description='Number of the new case, when created.')
        public String caseNumber;
        @InvocableVariable(label='Case Id' description='Id of the new case, when created.')
        public Id caseId;
        @InvocableVariable(label='Matching Case Numbers' description='Open cases that already cover the issue (when blocked).')
        public String matchingCaseNumbers;
        @InvocableVariable(label='Safety Review Required' description='True for a Possible Adverse Event case.')
        public Boolean safetyReviewRequired = false;
    }

    /**
     * @param requests approved case requests (normally one)
     * @return one response per request, in the same order
     */
    @InvocableMethod(label='PSP Create Approved Case' description='Zenthera Patient Support Program: WRITE action. Creates one service case per request ONLY when userConfirmed is true, after a duplicate check (an existing or possible duplicate open case blocks the write). Sets the PSP issue category and shipment link. Never call without the user\'s explicit approval of that specific case; never retry automatically.' category='Patient Support Program')
    public static List<Response> createCases(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }
        try {
            responses = process(requests);
        } catch (Exception e) {
            responses = new List<Response>();
            for (Integer i = 0; i < requests.size(); i++) {
                responses.add(build(CODE_ERROR, 'The case could not be created: ' + e.getMessage()));
            }
        }
        return responses;
    }

    private static List<Response> process(List<Request> requests) {
        List<Response> responses = new List<Response>();
        List<PSP_CaseDuplicateCheck.Request> checks = new List<PSP_CaseDuplicateCheck.Request>();
        for (Request request : requests) {
            Response early = validate(request);
            responses.add(early);
            if (early == null) {
                PSP_CaseDuplicateCheck.Request check = new PSP_CaseDuplicateCheck.Request();
                check.enrollmentNumber = request.enrollmentNumber.trim();
                check.category = request.category;
                check.dispenseNumber = request.dispenseNumber;
                checks.add(check);
            }
        }
        if (checks.isEmpty()) {
            return responses;
        }

        List<PSP_CaseDuplicateCheck.Response> checkResults = PSP_CaseDuplicateCheck.checkDuplicates(checks);
        Map<String, Program_Enrollment__c> enrollmentsByNumber = queryEnrollments(requests);
        Map<String, Id> dispenseIdsByNumber = queryDispenses(requests);

        List<Case> toInsert = new List<Case>();
        List<Integer> insertPositions = new List<Integer>();
        Integer checkIndex = 0;
        for (Integer i = 0; i < requests.size(); i++) {
            if (responses[i] != null) {
                continue;
            }
            PSP_CaseDuplicateCheck.Response check = checkResults[checkIndex++];
            Response blocked = blockedByCheck(check);
            if (blocked != null) {
                responses[i] = blocked;
                continue;
            }
            Request request = requests[i];
            Program_Enrollment__c enrollment = enrollmentsByNumber.get(request.enrollmentNumber.trim().toUpperCase());
            if (enrollment == null) {
                responses[i] = build(CODE_NOT_FOUND, 'Enrollment ' + request.enrollmentNumber.trim() + ' was not found.');
                continue;
            }
            Id dispenseId = String.isBlank(request.dispenseNumber) ? null : dispenseIdsByNumber.get(request.dispenseNumber.trim().toUpperCase());
            toInsert.add(buildCase(request, enrollment, dispenseId));
            insertPositions.add(i);
        }
        insertCases(toInsert, insertPositions, requests, responses);
        return responses;
    }

    private static Response validate(Request request) {
        if (request == null) {
            return build(CODE_INVALID_INPUT, 'No request was given.');
        }
        if (request.userConfirmed != true) {
            return build(CODE_NOT_CONFIRMED, 'Nothing was created: the user has not explicitly approved this case.');
        }
        if (String.isBlank(request.enrollmentNumber) || String.isBlank(request.category)
                || String.isBlank(request.subject) || String.isBlank(request.description)) {
            return build(CODE_INVALID_INPUT, 'Enrollment number, issue category, subject and description are required.');
        }
        if (request.subject.trim().length() > MAX_SUBJECT_LENGTH || request.description.trim().length() > MAX_DESCRIPTION_LENGTH) {
            return build(CODE_INVALID_INPUT, 'Subject must be at most ' + MAX_SUBJECT_LENGTH + ' and description at most ' + MAX_DESCRIPTION_LENGTH + ' characters.');
        }
        return null;
    }

    private static Response blockedByCheck(PSP_CaseDuplicateCheck.Response check) {
        if (check.resultCode == PSP_CaseDuplicateCheck.CODE_NO_DUPLICATE) {
            return null;
        }
        Response response;
        if (check.resultCode == PSP_CaseDuplicateCheck.CODE_EXISTING_CASE) {
            response = build(CODE_DUPLICATE, 'Nothing was created: ' + check.resultMessage);
            response.matchingCaseNumbers = check.matchingCaseNumbers;
        } else if (check.resultCode == PSP_CaseDuplicateCheck.CODE_POSSIBLE_DUPLICATE) {
            response = build(CODE_NEEDS_REVIEW, 'Nothing was created: ' + check.resultMessage);
            response.matchingCaseNumbers = check.possibleDuplicateCaseNumbers;
        } else if (check.resultCode == PSP_CaseDuplicateCheck.CODE_NOT_FOUND) {
            response = build(CODE_NOT_FOUND, 'Nothing was created: ' + check.resultMessage);
        } else if (check.resultCode == PSP_CaseDuplicateCheck.CODE_INVALID_INPUT) {
            response = build(CODE_INVALID_INPUT, 'Nothing was created: ' + check.resultMessage);
        } else {
            response = build(CODE_ERROR, 'Nothing was created: ' + check.resultMessage);
        }
        return response;
    }

    private static Case buildCase(Request request, Program_Enrollment__c enrollment, Id dispenseId) {
        String category = canonicalCategory(request.category);
        Boolean isSafety = category == CATEGORY_ADVERSE_EVENT;
        String subjectText = request.subject.trim();
        String subjectLine = isSafety ? '[SAFETY REVIEW] Possible Adverse Event - ' + subjectText : '[' + category + '] ' + subjectText;
        String footer = '\n\n---\nIssue category: ' + category
            + '\nPatient: ' + enrollment.Patient__r.Name + ' | Enrollment: ' + enrollment.Name + ' (' + (enrollment.Therapy__c ?? 'therapy not recorded') + ')'
            + '\nLogged by the PSP Care Resolution Agent after explicit user approval.'
            + (isSafety ? '\n' + SAFETY_NOTE : '');
        return new Case(
            AccountId = enrollment.Patient__c,
            ContactId = enrollment.Patient__r.PersonContactId,
            Subject = subjectLine.left(255),
            Description = request.description.trim() + footer,
            Status = CASE_STATUS,
            Priority = isSafety ? 'High' : 'Medium',
            Origin = CASE_ORIGIN,
            Type = category == CATEGORY_INSURANCE ? 'Account Support' : 'Product Support',
            PSP_Issue_Category__c = category,
            PSP_Dispense__c = dispenseId
        );
    }

    private static void insertCases(List<Case> toInsert, List<Integer> positions, List<Request> requests, List<Response> responses) {
        if (toInsert.isEmpty()) {
            return;
        }
        List<Database.SaveResult> results = Database.insert(toInsert, false, AccessLevel.USER_MODE);
        Set<Id> createdIds = new Set<Id>();
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                createdIds.add(result.getId());
            }
        }
        Map<Id, Case> createdById = createdIds.isEmpty() ? new Map<Id, Case>()
            : new Map<Id, Case>([SELECT Id, CaseNumber FROM Case WHERE Id IN :createdIds WITH USER_MODE]);
        for (Integer j = 0; j < results.size(); j++) {
            Integer position = positions[j];
            Database.SaveResult result = results[j];
            if (result.isSuccess()) {
                Case created = createdById.get(result.getId());
                Response response = build(CODE_CREATED, 'Case ' + created?.CaseNumber + ' was created for ' + requests[position].enrollmentNumber.trim()
                    + (toInsert[j].PSP_Issue_Category__c == CATEGORY_ADVERSE_EVENT ? '. It is flagged for human safety review; no regulatory report was submitted.' : '.'));
                response.caseId = result.getId();
                response.caseNumber = created?.CaseNumber;
                response.safetyReviewRequired = toInsert[j].PSP_Issue_Category__c == CATEGORY_ADVERSE_EVENT;
                responses[position] = response;
            } else {
                responses[position] = build(CODE_ERROR, 'The case could not be created: ' + result.getErrors()[0].getMessage());
            }
        }
    }

    private static Map<String, Program_Enrollment__c> queryEnrollments(List<Request> requests) {
        Set<String> numbers = new Set<String>();
        for (Request request : requests) {
            if (request != null && String.isNotBlank(request.enrollmentNumber)) {
                numbers.add(request.enrollmentNumber.trim().toUpperCase());
            }
        }
        Map<String, Program_Enrollment__c> byNumber = new Map<String, Program_Enrollment__c>();
        for (Program_Enrollment__c enrollment : [
            SELECT Id, Name, Therapy__c, Patient__c, Patient__r.Name, Patient__r.PersonContactId
            FROM Program_Enrollment__c
            WHERE Name IN :numbers
            WITH USER_MODE
        ]) {
            byNumber.put(enrollment.Name.toUpperCase(), enrollment);
        }
        return byNumber;
    }

    private static Map<String, Id> queryDispenses(List<Request> requests) {
        Set<String> numbers = new Set<String>();
        for (Request request : requests) {
            if (request != null && String.isNotBlank(request.dispenseNumber)) {
                numbers.add(request.dispenseNumber.trim().toUpperCase());
            }
        }
        Map<String, Id> idsByNumber = new Map<String, Id>();
        if (numbers.isEmpty()) {
            return idsByNumber;
        }
        for (Dispense__c dispense : [SELECT Id, Name FROM Dispense__c WHERE Name IN :numbers WITH USER_MODE]) {
            idsByNumber.put(dispense.Name.toUpperCase(), dispense.Id);
        }
        return idsByNumber;
    }

    private static String canonicalCategory(String value) {
        for (Schema.PicklistEntry entry : Case.PSP_Issue_Category__c.getDescribe().getPicklistValues()) {
            if (entry.getValue().equalsIgnoreCase(value.trim())) {
                return entry.getValue();
            }
        }
        return value.trim();
    }

    private static Response build(String code, String message) {
        Response response = new Response();
        response.resultCode = code;
        response.resultMessage = message;
        return response;
    }
}
