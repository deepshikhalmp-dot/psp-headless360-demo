/**
 * Zenthera Patient Support Program (fictional demo data): read-only action that returns today's program
 * exceptions as an HXL card (PSP_ExceptionsWorklistCard) plus the same content as text (fallback for
 * channels that cannot render the card, such as Coworker). Reuses PSP_ProgramExceptionsService unchanged.
 */
public with sharing class PSP_ExceptionsWorklistCardAction {

    public static final String FOOTER = 'Refill dates are based on recorded shipments only. Read-only: nothing was created or changed.';

    /** Input. All optional. */
    public class Request {
        @InvocableVariable(label='Enrollment Number' description='Optional. Only this enrollment, for example ENR-0007.')
        public String enrollmentNumber;

        @InvocableVariable(label='Exception Types' description='Optional comma separated filter, for example SHIPMENT_DELAYED.')
        public String exceptionTypes;
    }

    /** Output. */
    public class Response {
        @InvocableVariable(label='Result Code' description='SUCCESS, INVALID_INPUT, NOT_FOUND or ERROR.')
        public String resultCode;
        @InvocableVariable(label='Result Message' description='Summary with counts.')
        public String resultMessage;
        @InvocableVariable(label='Items Text' description='One line per item, most severe first (text fallback).')
        public String itemsText;
        @InvocableVariable(label='Worklist Card' description='Program exceptions worklist for the HXL card.')
        public PSP_ExceptionsWorklistCard card;
    }

    /**
     * @param requests requests (agents send one)
     * @return one response per request
     */
    @InvocableMethod(label='PSP Get Exceptions Worklist Card' description='Zenthera Patient Support Program: read-only. Returns today\'s program exceptions as a worklist card (counts by severity and the items grouped HIGH, MEDIUM, LOW, data gaps) plus the same content as text. Optional filters: enrollment number, exception types.' category='Patient Support Program')
    public static List<Response> getWorklistCards(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }
        for (Request request : requests) {
            responses.add(buildOne(request ?? new Request()));
        }
        return responses;
    }

    private static Response buildOne(Request request) {
        PSP_ProgramExceptionsService.Request serviceRequest = new PSP_ProgramExceptionsService.Request();
        serviceRequest.enrollmentNumber = request.enrollmentNumber;
        serviceRequest.exceptionTypes = request.exceptionTypes;
        PSP_ProgramExceptionsService.Response result = PSP_ProgramExceptionsService.getExceptions(
            new List<PSP_ProgramExceptionsService.Request>{ serviceRequest })[0];

        Response response = new Response();
        response.resultCode = result.resultCode;
        response.resultMessage = result.resultMessage;
        response.itemsText = result.itemsText;
        if (result.resultCode == PSP_ProgramExceptionsService.CODE_SUCCESS) {
            response.card = toCard(result);
        }
        return response;
    }

    @TestVisible
    private static PSP_ExceptionsWorklistCard toCard(PSP_ProgramExceptionsService.Response result) {
        Map<String, List<String>> linesBySeverity = new Map<String, List<String>>{
            PSP_ProgramExceptionRules.SEVERITY_HIGH => new List<String>(),
            PSP_ProgramExceptionRules.SEVERITY_MEDIUM => new List<String>(),
            PSP_ProgramExceptionRules.SEVERITY_LOW => new List<String>(),
            PSP_ProgramExceptionRules.SEVERITY_INFO => new List<String>()
        };
        for (PSP_ProgramExceptionsService.Item item : result.items) {
            String key = linesBySeverity.containsKey(item.severity) ? item.severity : PSP_ProgramExceptionRules.SEVERITY_INFO;
            linesBySeverity.get(key).add('• ' + (item.patientName ?? 'No patient') + ' (' + item.enrollmentNumber + ') · '
                + item.exceptionType.replace('_', ' ') + ': ' + item.fact + ' → ' + item.suggestedAction.replace('_', ' '));
        }

        PSP_ExceptionsWorklistCard card = new PSP_ExceptionsWorklistCard();
        card.title = 'Zenthera PSP · Program Exceptions';
        card.summary = result.resultMessage;
        card.highLabel = 'High ' + result.highCount;
        card.mediumLabel = 'Medium ' + result.mediumCount;
        card.lowLabel = 'Low ' + result.lowCount;
        card.dataGapLabel = 'Data gaps ' + result.dataGapCount;
        card.highItems = String.join(linesBySeverity.get(PSP_ProgramExceptionRules.SEVERITY_HIGH), '\n');
        card.mediumItems = String.join(linesBySeverity.get(PSP_ProgramExceptionRules.SEVERITY_MEDIUM), '\n');
        card.lowItems = String.join(linesBySeverity.get(PSP_ProgramExceptionRules.SEVERITY_LOW), '\n');
        card.dataGapItems = String.join(linesBySeverity.get(PSP_ProgramExceptionRules.SEVERITY_INFO), '\n');
        card.hasHigh = !linesBySeverity.get(PSP_ProgramExceptionRules.SEVERITY_HIGH).isEmpty();
        card.hasMedium = !linesBySeverity.get(PSP_ProgramExceptionRules.SEVERITY_MEDIUM).isEmpty();
        card.hasLow = !linesBySeverity.get(PSP_ProgramExceptionRules.SEVERITY_LOW).isEmpty();
        card.hasDataGaps = !linesBySeverity.get(PSP_ProgramExceptionRules.SEVERITY_INFO).isEmpty();
        card.hasNoItems = result.items.isEmpty();
        card.footer = FOOTER;
        return card;
    }
}
