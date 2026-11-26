/**
 * Zenthera Patient Support Program (fictional demo data): read-only care team handoff summary for one
 * patient, in fixed sections. Deterministic text (no AI wording), so it never contains medical advice
 * or adherence claims. Reuses PSP_RefillHistoryTool (refill due status) and PSP_ProgramExceptionsService
 * (exceptions); neither is changed. Safety cases are shown only as "in human safety review", without
 * their subject or description. Nothing is created, changed or posted.
 */
public with sharing class PSP_CareTeamHandoff {

    public static final String CODE_SUCCESS = 'SUCCESS';
    public static final String CODE_INVALID_INPUT = 'INVALID_INPUT';
    public static final String CODE_NOT_FOUND = 'NOT_FOUND';
    public static final String CODE_ERROR = 'ERROR';

    private static final String CATEGORY_ADVERSE_EVENT = 'Possible Adverse Event';
    private static final Pattern ENROLLMENT_NUMBER = Pattern.compile('(?i)\\bENR-\\d+\\b');
    private static final String PRESCRIBER_NOTE = 'Questions about dosing, missed doses or side effects go to the patient\'s prescriber (911 in an emergency).';

    private static final Map<String, String> NEXT_STEP_BY_ACTION = new Map<String, String>{
        PSP_ProgramExceptionRules.ACTION_PREPARE_HANDOFF => 'Review at the care team meeting',
        PSP_ProgramExceptionRules.ACTION_SKIP_EXISTING_CASE => 'Follow up the open case(s); no new case needed',
        PSP_ProgramExceptionRules.ACTION_CREATE_CASE => 'Consider a new case after a duplicate check and the user\'s approval',
        PSP_ProgramExceptionRules.ACTION_REVIEW_POSSIBLE_DUPLICATE => 'Check the listed open cases before creating anything',
        PSP_ProgramExceptionRules.ACTION_FOLLOW_UP_CONSENT => 'Follow up the patient\'s program consent',
        PSP_ProgramExceptionRules.ACTION_TRIAGE_CASE => 'A person reviews the case and sets its PSP issue category',
        PSP_ProgramExceptionRules.ACTION_REVIEW_DATA => 'Complete the missing data if it is known; never guess'
    };

    /** Input. */
    public class Request {
        @InvocableVariable(label='Enrollment Number' description='Enrollment number of the patient, for example ENR-0007. A sentence that contains one ("handoff for ENR-0007") also works.' required=true)
        public String enrollmentNumber;

        @InvocableVariable(label='As Of Date' description='Date for the summary. Default: today.')
        public Date asOfDate;
    }

    /** Output. */
    public class Response {
        @InvocableVariable(label='Result Code' description='SUCCESS, INVALID_INPUT, NOT_FOUND or ERROR.')
        public String resultCode;
        @InvocableVariable(label='Handoff Text' description='Read-only summary in fixed sections; show it as written.')
        public String handoffText;
        @InvocableVariable(label='Result Message' description='Short status sentence.')
        public String resultMessage;
        @InvocableVariable(label='Patient Name' description='Patient name.')
        public String patientName;
    }

    /**
     * Each request builds one summary (a few read-only queries). Agents send one request.
     * @param requests handoff requests
     * @return one response per request
     */
    @InvocableMethod(label='PSP Prepare Care Team Handoff' description='Zenthera Patient Support Program: read-only care team handoff summary for one patient in fixed sections: patient and therapy, refill due status (recorded shipments only), open issues (safety cases only as in human safety review), exceptions, suggested non-clinical next steps, data as of date. Creates, changes or posts nothing.' category='Patient Support Program')
    public static List<Response> prepareHandoffs(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }
        for (Request request : requests) {
            responses.add(prepareOne(request));
        }
        return responses;
    }

    private static Response prepareOne(Request request) {
        String enrollmentNumber = request == null ? null : extractEnrollmentNumber(request.enrollmentNumber);
        if (enrollmentNumber == null) {
            return build(CODE_INVALID_INPUT, 'Give an enrollment number such as ENR-0007.');
        }
        Date asOfDate = request.asOfDate ?? Date.today();
        try {
            List<Program_Enrollment__c> enrollments = [
                SELECT Id, Name, Patient__c, Patient__r.Name, Therapy__c, Status__c, Insurance_Type__c, Consent_Given__c, Consent_Date__c
                FROM Program_Enrollment__c
                WHERE Name = :enrollmentNumber
                WITH USER_MODE
                LIMIT 1
            ];
            if (enrollments.isEmpty()) {
                return build(CODE_NOT_FOUND, 'Enrollment ' + enrollmentNumber + ' was not found.');
            }
            Program_Enrollment__c enrollment = enrollments[0];
            List<Case> openCases = enrollment.Patient__c == null ? new List<Case>() : [
                SELECT CaseNumber, Status, PSP_Issue_Category__c, PSP_Dispense__r.Name
                FROM Case
                WHERE AccountId = :enrollment.Patient__c AND IsClosed = false
                WITH USER_MODE
                ORDER BY CaseNumber
            ];
            PSP_RefillHistoryTool.Response refill = loadRefill(enrollment.Name, asOfDate);
            PSP_ProgramExceptionsService.Response exceptions = loadExceptions(enrollment.Name, asOfDate);

            Response response = build(CODE_SUCCESS, 'Care team handoff prepared for ' + enrollment.Patient__r?.Name + ' (' + enrollment.Name + '). Nothing was created or changed.');
            response.patientName = enrollment.Patient__r?.Name;
            response.handoffText = String.join(new List<String>{
                'CARE TEAM HANDOFF (read-only summary, fictional demo data)',
                '',
                '1. Patient and therapy: ' + patientLine(enrollment),
                '',
                '2. Refill due status (recorded shipments only): ' + refillLine(refill, asOfDate),
                '',
                '3. Open issues:',
                openIssueLines(openCases),
                '',
                '4. Exceptions to note:',
                exceptionLines(exceptions),
                '',
                '5. Suggested non-clinical next steps:',
                nextStepLines(exceptions),
                '',
                '6. Data as of ' + String.valueOf(asOfDate) + '. This summary created, changed or posted nothing.'
            }, '\n');
            return response;
        } catch (Exception e) {
            return build(CODE_ERROR, 'The handoff could not be prepared: ' + e.getMessage());
        }
    }

    /**
     * @param value an enrollment number or a sentence that contains one
     * @return the enrollment number in upper case, or null when none is found
     */
    @TestVisible
    private static String extractEnrollmentNumber(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        Matcher numberMatcher = ENROLLMENT_NUMBER.matcher(value);
        return numberMatcher.find() ? numberMatcher.group().toUpperCase() : null;
    }

    private static PSP_RefillHistoryTool.Response loadRefill(String enrollmentNumber, Date asOfDate) {
        PSP_RefillHistoryTool.Request request = new PSP_RefillHistoryTool.Request();
        request.enrollmentNumber = enrollmentNumber;
        request.asOfDate = asOfDate;
        return PSP_RefillHistoryTool.getRefillHistory(new List<PSP_RefillHistoryTool.Request>{ request })[0];
    }

    private static PSP_ProgramExceptionsService.Response loadExceptions(String enrollmentNumber, Date asOfDate) {
        PSP_ProgramExceptionsService.Request request = new PSP_ProgramExceptionsService.Request();
        request.enrollmentNumber = enrollmentNumber;
        request.asOfDate = asOfDate;
        return PSP_ProgramExceptionsService.getExceptions(new List<PSP_ProgramExceptionsService.Request>{ request })[0];
    }

    private static String patientLine(Program_Enrollment__c enrollment) {
        String consent = enrollment.Consent_Given__c == true
            ? 'consent given' + (enrollment.Consent_Date__c == null ? ' (date not recorded)' : ' on ' + String.valueOf(enrollment.Consent_Date__c))
            : 'consent not recorded';
        return (enrollment.Patient__r?.Name ?? 'No patient') + ' | ' + enrollment.Name + ' | ' + (enrollment.Therapy__c ?? 'therapy not recorded')
            + ' | status ' + (enrollment.Status__c ?? 'not recorded') + ' | insurance ' + (enrollment.Insurance_Type__c ?? 'not recorded') + ' | ' + consent;
    }

    private static String refillLine(PSP_RefillHistoryTool.Response refill, Date asOfDate) {
        String note = ' This reflects recorded shipments only, not whether the patient took the medication.';
        if (refill == null || refill.resultCode != 'SUCCESS') {
            return 'Not available' + (refill == null ? '.' : ': ' + refill.resultMessage) + note;
        }
        String basis = 'last delivered ' + String.valueOf(refill.lastDeliveredDate) + ' for ' + refill.lastDeliveredDaysSupply + ' days';
        switch on refill.refillStatus {
            when 'LATE' {
                return 'next refill was due ' + String.valueOf(refill.nextRefillDueDate) + ' (' + basis + '); ' + refill.daysOverdue + ' day(s) overdue as of ' + String.valueOf(asOfDate) + '.' + note;
            }
            when 'DUE' {
                return 'next refill due ' + String.valueOf(refill.nextRefillDueDate) + ' (' + basis + '), within 7 days.' + note;
            }
            when 'ON_TRACK' {
                return 'next refill due ' + String.valueOf(refill.nextRefillDueDate) + ' (' + basis + '); on track.' + note;
            }
            when else {
                return 'no Delivered shipment with a date and days supply is recorded, so no due date can be calculated.' + note;
            }
        }
    }

    private static String openIssueLines(List<Case> openCases) {
        if (openCases.isEmpty()) {
            return '- No open cases.';
        }
        List<String> lines = new List<String>();
        for (Case openCase : openCases) {
            if (openCase.PSP_Issue_Category__c == CATEGORY_ADVERSE_EVENT) {
                lines.add('- Case ' + openCase.CaseNumber + ': in human safety review.');
            } else if (String.isBlank(openCase.PSP_Issue_Category__c)) {
                lines.add('- Case ' + openCase.CaseNumber + ': no PSP issue category yet (needs review), status ' + openCase.Status + '.');
            } else {
                lines.add('- Case ' + openCase.CaseNumber + ': ' + openCase.PSP_Issue_Category__c
                    + (openCase.PSP_Dispense__r?.Name == null ? '' : ' (shipment ' + openCase.PSP_Dispense__r.Name + ')') + ', status ' + openCase.Status + '.');
            }
        }
        return String.join(lines, '\n');
    }

    private static String exceptionLines(PSP_ProgramExceptionsService.Response exceptions) {
        if (exceptions == null || exceptions.resultCode != PSP_ProgramExceptionsService.CODE_SUCCESS) {
            return '- Not available' + (exceptions == null ? '.' : ': ' + exceptions.resultMessage);
        }
        if (exceptions.items.isEmpty()) {
            return '- None.';
        }
        List<String> lines = new List<String>();
        for (PSP_ProgramExceptionsService.Item item : exceptions.items) {
            lines.add('- ' + item.severity + ' ' + item.exceptionType + ': ' + item.fact);
        }
        return String.join(lines, '\n');
    }

    private static String nextStepLines(PSP_ProgramExceptionsService.Response exceptions) {
        List<String> lines = new List<String>();
        Set<String> seen = new Set<String>();
        if (exceptions != null && exceptions.resultCode == PSP_ProgramExceptionsService.CODE_SUCCESS) {
            for (PSP_ProgramExceptionsService.Item item : exceptions.items) {
                String step = item.exceptionType == PSP_ProgramExceptionRules.TYPE_SAFETY_REVIEW_OPEN
                    ? 'The safety case(s) ' + item.caseNumbers + ' stay with the human safety review team'
                    : NEXT_STEP_BY_ACTION.get(item.suggestedAction);
                if (step == null) {
                    continue;
                }
                String line = '- ' + step + (String.isBlank(item.caseNumbers) || item.exceptionType == PSP_ProgramExceptionRules.TYPE_SAFETY_REVIEW_OPEN ? '' : ' (' + item.caseNumbers + ')') + '.';
                if (seen.add(line)) {
                    lines.add(line);
                }
            }
        }
        lines.add('- ' + PRESCRIBER_NOTE);
        return String.join(lines, '\n');
    }

    private static Response build(String code, String message) {
        Response response = new Response();
        response.resultCode = code;
        response.resultMessage = message;
        response.handoffText = message;
        return response;
    }
}
