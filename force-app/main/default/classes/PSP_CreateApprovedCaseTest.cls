/**
 * Tests for PSP_CreateApprovedCase (fictional data, rolled back after each test).
 */
@isTest
private class PSP_CreateApprovedCaseTest {

    @TestSetup
    static void setupTestData() {
        PSP_TestDataFactory.createSdoCaseAutomationFixture();
        Account kim = PSP_TestDataFactory.createPatient('Kim', 'Createtest', true);
        Account lou = PSP_TestDataFactory.createPatient('Lou', 'Createtest', true);
        Program_Enrollment__c kimEnrollment = PSP_TestDataFactory.createEnrollment(kim.Id, 'Active', Date.newInstance(2026, 9, 1), true);
        Program_Enrollment__c louEnrollment = PSP_TestDataFactory.createEnrollment(lou.Id, 'Active', Date.newInstance(2026, 9, 1), true);
        Dispense__c delayedA = PSP_TestDataFactory.buildDispense(kimEnrollment.Id, Date.newInstance(2026, 11, 10), 30, 'Delayed');
        Dispense__c delayedB = PSP_TestDataFactory.buildDispense(kimEnrollment.Id, Date.newInstance(2026, 11, 12), 30, 'Delayed');
        Dispense__c louShipment = PSP_TestDataFactory.buildDispense(louEnrollment.Id, Date.newInstance(2026, 11, 1), 30, 'Shipped');
        insert new List<Dispense__c>{ delayedA, delayedB, louShipment };

        Case existing = PSP_TestDataFactory.buildCase(kim.Id, '[Shipment Delay] Existing delay', 'New', 'Medium');
        existing.PSP_Issue_Category__c = 'Shipment Delay';
        existing.PSP_Dispense__c = delayedA.Id;
        Case unlinkedInsurance = PSP_TestDataFactory.buildCase(kim.Id, '[Insurance Support] Old question', 'New', 'Medium');
        unlinkedInsurance.PSP_Issue_Category__c = 'Insurance Support';
        insert new List<Case>{ existing, unlinkedInsurance };
    }

    private static String enrollmentOf(String patientName) {
        return [SELECT Name FROM Program_Enrollment__c WHERE Patient__r.Name = :patientName LIMIT 1].Name;
    }

    private static String dispenseOf(String patientName, Date dispenseDate) {
        return [SELECT Name FROM Dispense__c WHERE Program_Enrollment__r.Patient__r.Name = :patientName AND Dispense_Date__c = :dispenseDate LIMIT 1].Name;
    }

    private static PSP_CreateApprovedCase.Request request(String enrollmentNumber, String category, String dispenseNumber, Boolean confirmed) {
        PSP_CreateApprovedCase.Request request = new PSP_CreateApprovedCase.Request();
        request.enrollmentNumber = enrollmentNumber;
        request.category = category;
        request.dispenseNumber = dispenseNumber;
        request.subject = 'Shipment not arrived';
        request.description = 'Coordinator reports that the shipment has not arrived.';
        request.userConfirmed = confirmed;
        return request;
    }

    private static PSP_CreateApprovedCase.Response run(PSP_CreateApprovedCase.Request request) {
        return PSP_CreateApprovedCase.createCases(new List<PSP_CreateApprovedCase.Request>{ request })[0];
    }

    @isTest
    static void shouldCreateCase_WhenApprovedAndNoDuplicate() {
        String shipment = dispenseOf('Kim Createtest', Date.newInstance(2026, 11, 12));

        Test.startTest();
        PSP_CreateApprovedCase.Response response = run(request(enrollmentOf('Kim Createtest'), 'Shipment Delay', shipment, true));
        Test.stopTest();

        Assert.areEqual(PSP_CreateApprovedCase.CODE_CREATED, response.resultCode, response.resultMessage);
        Case created = [SELECT Subject, Description, Status, Priority, Origin, PSP_Issue_Category__c, PSP_Dispense__r.Name, Account.Name, ContactId FROM Case WHERE Id = :response.caseId];
        Assert.areEqual('[Shipment Delay] Shipment not arrived', created.Subject, 'Category tag added to the subject');
        Assert.areEqual('Shipment Delay', created.PSP_Issue_Category__c, 'Category field set');
        Assert.areEqual(shipment, created.PSP_Dispense__r.Name, 'Shipment link set');
        Assert.areEqual('Kim Createtest', created.Account.Name, 'Case belongs to the patient');
        Assert.isNotNull(created.ContactId, 'Person contact linked');
        Assert.areEqual('New', created.Status, 'Status New');
        Assert.isTrue(created.Description.contains('after explicit user approval'), 'Footer records the approval');
        Assert.isNotNull(response.caseNumber, 'Case number returned');
    }

    @isTest
    static void shouldWriteNothing_WhenNotConfirmed() {
        Integer before = [SELECT COUNT() FROM Case];

        PSP_CreateApprovedCase.Response response = run(request(enrollmentOf('Kim Createtest'), 'Refill Support', null, false));

        Assert.areEqual(PSP_CreateApprovedCase.CODE_NOT_CONFIRMED, response.resultCode, 'Approval is required');
        Assert.areEqual(before, [SELECT COUNT() FROM Case], 'No case created');
    }

    @isTest
    static void shouldRefuse_WhenOpenCaseAlreadyCoversShipment() {
        Integer before = [SELECT COUNT() FROM Case];
        String shipment = dispenseOf('Kim Createtest', Date.newInstance(2026, 11, 10));

        PSP_CreateApprovedCase.Response response = run(request(enrollmentOf('Kim Createtest'), 'Shipment Delay', shipment, true));

        Assert.areEqual(PSP_CreateApprovedCase.CODE_DUPLICATE, response.resultCode, 'Duplicate guard blocks the write');
        Assert.isNotNull(response.matchingCaseNumbers, 'Existing case listed');
        Assert.areEqual(before, [SELECT COUNT() FROM Case], 'No case created');
    }

    @isTest
    static void shouldRefuse_WhenPossibleDuplicateNeedsReview() {
        String shipment = dispenseOf('Kim Createtest', Date.newInstance(2026, 11, 12));

        PSP_CreateApprovedCase.Response response = run(request(enrollmentOf('Kim Createtest'), 'Insurance Support', shipment, true));

        Assert.areEqual(PSP_CreateApprovedCase.CODE_NEEDS_REVIEW, response.resultCode, 'Unlinked open case of the same category must be reviewed');
    }

    @isTest
    static void shouldFlagSafetyReview_ForPossibleAdverseEvent() {
        PSP_CreateApprovedCase.Request safety = request(enrollmentOf('Lou Createtest'), 'possible adverse event', null, true);
        safety.subject = 'Patient mentions a rash';

        PSP_CreateApprovedCase.Response response = run(safety);

        Assert.areEqual(PSP_CreateApprovedCase.CODE_CREATED, response.resultCode, response.resultMessage);
        Assert.isTrue(response.safetyReviewRequired, 'Flagged for human safety review');
        Case created = [SELECT Subject, Priority, Description, PSP_Issue_Category__c FROM Case WHERE Id = :response.caseId];
        Assert.isTrue(created.Subject.startsWith('[SAFETY REVIEW] Possible Adverse Event - '), created.Subject);
        Assert.areEqual('High', created.Priority, 'Safety cases are high priority');
        Assert.areEqual('Possible Adverse Event', created.PSP_Issue_Category__c, 'Canonical category value');
        Assert.isTrue(created.Description.contains('no regulatory report has been submitted'), 'No regulatory claim');
    }

    @isTest
    static void shouldRejectMissingFieldsAndForeignShipment() {
        PSP_CreateApprovedCase.Request missing = request(enrollmentOf('Kim Createtest'), 'Refill Support', null, true);
        missing.subject = ' ';
        PSP_CreateApprovedCase.Request foreign = request(enrollmentOf('Kim Createtest'), 'Shipment Delay', dispenseOf('Lou Createtest', Date.newInstance(2026, 11, 1)), true);
        PSP_CreateApprovedCase.Request unknown = request('ENR-9999', 'Refill Support', null, true);

        List<PSP_CreateApprovedCase.Response> responses = PSP_CreateApprovedCase.createCases(
            new List<PSP_CreateApprovedCase.Request>{ missing, foreign, unknown, null });

        Assert.areEqual(PSP_CreateApprovedCase.CODE_INVALID_INPUT, responses[0].resultCode, 'Subject is required');
        Assert.areEqual(PSP_CreateApprovedCase.CODE_INVALID_INPUT, responses[1].resultCode, 'Shipment of another patient');
        Assert.areEqual(PSP_CreateApprovedCase.CODE_NOT_FOUND, responses[2].resultCode, 'Unknown enrollment');
        Assert.areEqual(PSP_CreateApprovedCase.CODE_INVALID_INPUT, responses[3].resultCode, 'Null request');
    }

    @isTest
    static void shouldHandleMixedBatch_InOrder() {
        String newShipment = dispenseOf('Kim Createtest', Date.newInstance(2026, 11, 12));
        String coveredShipment = dispenseOf('Kim Createtest', Date.newInstance(2026, 11, 10));

        Test.startTest();
        List<PSP_CreateApprovedCase.Response> responses = PSP_CreateApprovedCase.createCases(new List<PSP_CreateApprovedCase.Request>{
            request(enrollmentOf('Kim Createtest'), 'Shipment Delay', coveredShipment, true),
            request(enrollmentOf('Kim Createtest'), 'Shipment Delay', newShipment, true)
        });
        Test.stopTest();

        Assert.areEqual(PSP_CreateApprovedCase.CODE_DUPLICATE, responses[0].resultCode, 'First is a duplicate');
        Assert.areEqual(PSP_CreateApprovedCase.CODE_CREATED, responses[1].resultCode, 'Second is created');
        Assert.isTrue(PSP_CreateApprovedCase.createCases(null).isEmpty(), 'Null list gives no responses');
    }
}
