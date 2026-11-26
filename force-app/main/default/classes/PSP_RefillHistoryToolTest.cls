/**
 * Tests for PSP_RefillHistoryTool (fictional data).
 */
@isTest
private class PSP_RefillHistoryToolTest {

    private static final String LATE_PATIENT = 'Lena Refilltest';
    private static final String NO_DELIVERY_PATIENT = 'Nora Refilltest';
    private static final String TWIN_PATIENT = 'Tara Twintest';
    private static final String NO_ENROLLMENT_PATIENT = 'Omar Refilltest';
    private static final String STOPPED_PATIENT = 'Sam Refilltest';

    private static final Date LAST_DELIVERED = Date.newInstance(2026, 10, 9);
    private static final Integer DAYS_SUPPLY = 30;
    private static final Date DUE_DATE = LAST_DELIVERED.addDays(DAYS_SUPPLY);
    private static final Date AS_OF_LATE = Date.newInstance(2026, 11, 17);

    @TestSetup
    static void setupTestData() {
        Account late = PSP_TestDataFactory.createPatient('Lena', 'Refilltest', true);
        Account noDelivery = PSP_TestDataFactory.createPatient('Nora', 'Refilltest', true);
        PSP_TestDataFactory.createPatient('Tara', 'Twintest', true);
        PSP_TestDataFactory.createPatient('Tara', 'Twintest', true);
        PSP_TestDataFactory.createPatient('Omar', 'Refilltest', true);
        Account stopped = PSP_TestDataFactory.createPatient('Sam', 'Refilltest', true);

        Program_Enrollment__c lateEnrollment = PSP_TestDataFactory.createEnrollment(late.Id, 'Active', Date.newInstance(2026, 9, 1), true);
        Program_Enrollment__c noDeliveryEnrollment = PSP_TestDataFactory.createEnrollment(noDelivery.Id, 'Enrolled', Date.newInstance(2026, 10, 1), true);
        Program_Enrollment__c stoppedEnrollment = PSP_TestDataFactory.createEnrollment(stopped.Id, 'Discontinued', Date.newInstance(2026, 8, 1), true);

        insert new List<Dispense__c>{
            PSP_TestDataFactory.buildDispense(lateEnrollment.Id, Date.newInstance(2026, 9, 9), DAYS_SUPPLY, 'Delivered'),
            PSP_TestDataFactory.buildDispense(lateEnrollment.Id, LAST_DELIVERED, DAYS_SUPPLY, 'Delivered'),
            PSP_TestDataFactory.buildDispense(lateEnrollment.Id, Date.newInstance(2026, 11, 10), DAYS_SUPPLY, 'Delayed'),
            PSP_TestDataFactory.buildDispense(noDeliveryEnrollment.Id, Date.newInstance(2026, 10, 5), DAYS_SUPPLY, 'Shipped'),
            PSP_TestDataFactory.buildDispense(noDeliveryEnrollment.Id, Date.newInstance(2026, 10, 6), null, 'Delivered'),
            PSP_TestDataFactory.buildDispense(stoppedEnrollment.Id, Date.newInstance(2026, 8, 5), DAYS_SUPPLY, 'Delivered')
        };
    }

    private static PSP_RefillHistoryTool.Response runByName(String patientName, Date asOfDate) {
        PSP_RefillHistoryTool.Request request = new PSP_RefillHistoryTool.Request();
        request.patientName = patientName;
        request.asOfDate = asOfDate;
        return PSP_RefillHistoryTool.getRefillHistory(new List<PSP_RefillHistoryTool.Request>{ request })[0];
    }

    @isTest
    static void shouldReturnLate_WhenAsOfDateAfterDueDate() {
        Test.startTest();
        PSP_RefillHistoryTool.Response response = runByName(LATE_PATIENT, AS_OF_LATE);
        Test.stopTest();

        Assert.areEqual(PSP_RefillHistoryTool.CODE_SUCCESS, response.resultCode, 'Lookup should succeed');
        Assert.areEqual(PSP_RefillHistoryTool.STATUS_LATE, response.refillStatus, 'Refill should be late');
        Assert.areEqual(LAST_DELIVERED, response.lastDeliveredDate, 'Latest Delivered dispense should be used');
        Assert.areEqual(DUE_DATE, response.nextRefillDueDate, 'Due date should be last delivered + days supply');
        Assert.areEqual(9, response.daysOverdue, '2026-11-17 is 9 days after 2026-11-08');
    }

    @isTest
    static void shouldIgnoreDelayedShipment_WhenCountingDelivered() {
        Test.startTest();
        PSP_RefillHistoryTool.Response response = runByName(LATE_PATIENT, AS_OF_LATE);
        Test.stopTest();

        Assert.areEqual(3, response.dispenseCount, 'All three dispenses should be listed');
        Assert.areEqual(2, response.deliveredCount, 'Only the two Delivered dispenses should count');
        Assert.isTrue(response.dispenseHistory.contains('Delayed | Test Specialty Pharmacy | not counted (not Delivered)'), 'Delayed dispense should be marked not counted');
        Assert.isTrue(response.resultMessage.contains('not whether the patient took the medication'), 'Message should not claim adherence');
    }

    @isTest
    static void shouldReturnDue_WhenDueDateWithinWindow() {
        Date asOfDate = DUE_DATE.addDays(-5);

        Test.startTest();
        PSP_RefillHistoryTool.Response response = runByName(LATE_PATIENT, asOfDate);
        Test.stopTest();

        Assert.areEqual(PSP_RefillHistoryTool.STATUS_DUE, response.refillStatus, 'Refill due in 5 days should be DUE');
        Assert.areEqual(0, response.daysOverdue, 'A due refill is not overdue');
    }

    @isTest
    static void shouldReturnOnTrack_WhenDueDateBeyondWindow() {
        Date asOfDate = DUE_DATE.addDays(-(PSP_RefillHistoryTool.DUE_WINDOW_DAYS + 1));

        Test.startTest();
        PSP_RefillHistoryTool.Response response = runByName(LATE_PATIENT, asOfDate);
        Test.stopTest();

        Assert.areEqual(PSP_RefillHistoryTool.STATUS_ON_TRACK, response.refillStatus, 'Refill due after the window should be ON_TRACK');
        Assert.areEqual(0, response.daysOverdue, 'An on-track refill is not overdue');
    }

    @isTest
    static void shouldReturnNoDeliveredRefill_WhenNoCountableDelivery() {
        Test.startTest();
        PSP_RefillHistoryTool.Response response = runByName(NO_DELIVERY_PATIENT, AS_OF_LATE);
        Test.stopTest();

        Assert.areEqual(PSP_RefillHistoryTool.STATUS_NO_DELIVERED, response.refillStatus, 'No countable Delivered dispense should give NO_DELIVERED_REFILL');
        Assert.isNull(response.nextRefillDueDate, 'No due date can be calculated');
        Assert.isTrue(response.resultMessage.contains('missing a date or days supply'), 'Message should mention the incomplete Delivered dispense');
    }

    @isTest
    static void shouldFindEnrollment_WhenEnrollmentNumberGiven() {
        Program_Enrollment__c enrollment = [SELECT Name FROM Program_Enrollment__c WHERE Patient__r.Name = :LATE_PATIENT LIMIT 1];
        PSP_RefillHistoryTool.Request request = new PSP_RefillHistoryTool.Request();
        request.enrollmentNumber = enrollment.Name.toLowerCase();
        request.asOfDate = AS_OF_LATE;

        Test.startTest();
        PSP_RefillHistoryTool.Response response = PSP_RefillHistoryTool.getRefillHistory(new List<PSP_RefillHistoryTool.Request>{ request })[0];
        Test.stopTest();

        Assert.areEqual(enrollment.Name, response.enrollmentNumber, 'Lookup by enrollment number should ignore case');
        Assert.areEqual(LATE_PATIENT, response.patientName, 'Patient name should be returned');
    }

    @isTest
    static void shouldReturnNotFound_WhenPatientDoesNotExist() {
        Test.startTest();
        PSP_RefillHistoryTool.Response response = runByName('Nobody Refilltest', AS_OF_LATE);
        Test.stopTest();

        Assert.areEqual(PSP_RefillHistoryTool.CODE_NOT_FOUND, response.resultCode, 'Unknown patient should be NOT_FOUND');
        Assert.isFalse(response.isSuccess, 'Not found is not a success');
    }

    @isTest
    static void shouldReturnNotFound_WhenEnrollmentNumberDoesNotExist() {
        PSP_RefillHistoryTool.Request request = new PSP_RefillHistoryTool.Request();
        request.enrollmentNumber = 'ENR-9999';

        Test.startTest();
        PSP_RefillHistoryTool.Response response = PSP_RefillHistoryTool.getRefillHistory(new List<PSP_RefillHistoryTool.Request>{ request })[0];
        Test.stopTest();

        Assert.areEqual(PSP_RefillHistoryTool.CODE_NOT_FOUND, response.resultCode, 'Unknown enrollment number should be NOT_FOUND');
    }

    @isTest
    static void shouldReturnAmbiguous_WhenTwoPatientsShareName() {
        Test.startTest();
        PSP_RefillHistoryTool.Response response = runByName(TWIN_PATIENT, AS_OF_LATE);
        Test.stopTest();

        Assert.areEqual(PSP_RefillHistoryTool.CODE_AMBIGUOUS, response.resultCode, 'Two patients with the same name should be ambiguous');
        Assert.isNull(response.enrollmentId, 'No enrollment should be chosen');
    }

    @isTest
    static void shouldReturnNoEnrollment_WhenPatientNotEnrolled() {
        Test.startTest();
        PSP_RefillHistoryTool.Response response = runByName(NO_ENROLLMENT_PATIENT, AS_OF_LATE);
        Test.stopTest();

        Assert.areEqual(PSP_RefillHistoryTool.CODE_NO_ENROLLMENT, response.resultCode, 'Patient without enrollment should be NO_ENROLLMENT');
        Assert.isNotNull(response.patientId, 'The patient should still be identified');
    }

    @isTest
    static void shouldUseDiscontinuedEnrollment_WhenNoOpenEnrollment() {
        Test.startTest();
        PSP_RefillHistoryTool.Response response = runByName(STOPPED_PATIENT, AS_OF_LATE);
        Test.stopTest();

        Assert.areEqual('Discontinued', response.enrollmentStatus, 'The only enrollment should be used even if discontinued');
        Assert.areEqual(PSP_RefillHistoryTool.STATUS_LATE, response.refillStatus, 'August supply is long past due');
    }

    @isTest
    static void shouldReturnInvalidInput_WhenNameAndNumberBlank() {
        Test.startTest();
        PSP_RefillHistoryTool.Response response = PSP_RefillHistoryTool.getRefillHistory(
            new List<PSP_RefillHistoryTool.Request>{ new PSP_RefillHistoryTool.Request() })[0];
        Test.stopTest();

        Assert.areEqual(PSP_RefillHistoryTool.CODE_INVALID, response.resultCode, 'Blank input should be INVALID_INPUT');
    }

    @isTest
    static void shouldReturnEmptyList_WhenRequestsNull() {
        Test.startTest();
        List<PSP_RefillHistoryTool.Response> responses = PSP_RefillHistoryTool.getRefillHistory(null);
        Test.stopTest();

        Assert.areEqual(0, responses.size(), 'Null input should return an empty list');
    }

    @isTest
    static void shouldDefaultAsOfDateToToday_WhenNotGiven() {
        Test.startTest();
        PSP_RefillHistoryTool.Response response = runByName(LATE_PATIENT, null);
        Test.stopTest();

        Assert.areEqual(Date.today(), response.asOfDate, 'As-of date should default to today');
    }

    @isTest
    static void shouldProcessAllRequests_WhenCalledInBulk() {
        List<PSP_RefillHistoryTool.Request> requests = new List<PSP_RefillHistoryTool.Request>();
        for (Integer index = 0; index < 251; index++) {
            PSP_RefillHistoryTool.Request request = new PSP_RefillHistoryTool.Request();
            request.patientName = LATE_PATIENT;
            request.asOfDate = AS_OF_LATE;
            requests.add(request);
        }

        Test.startTest();
        List<PSP_RefillHistoryTool.Response> responses = PSP_RefillHistoryTool.getRefillHistory(requests);
        Integer queriesUsed = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(251, responses.size(), 'One response per request');
        Assert.areEqual(PSP_RefillHistoryTool.STATUS_LATE, responses[250].refillStatus, 'Every response should be calculated');
        Assert.isTrue(queriesUsed <= 4, 'Bulk call should use a fixed number of queries, used: ' + queriesUsed);
    }
}
