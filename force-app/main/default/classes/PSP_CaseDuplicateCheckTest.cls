/**
 * Tests for PSP_CaseDuplicateCheck (fictional data, rolled back after each test).
 */
@isTest
private class PSP_CaseDuplicateCheckTest {

    private static final String SHIPMENT_DELAY = 'Shipment Delay';
    private static final String INSURANCE_SUPPORT = 'Insurance Support';
    private static final String REFILL_SUPPORT = 'Refill Support';

    @TestSetup
    static void setupTestData() {
        PSP_TestDataFactory.createSdoCaseAutomationFixture();

        Account lena = PSP_TestDataFactory.createPatient('Lena', 'Duptest', true);
        Account omar = PSP_TestDataFactory.createPatient('Omar', 'Duptest', true);
        Program_Enrollment__c lenaEnrollment = PSP_TestDataFactory.createEnrollment(lena.Id, 'Active', Date.newInstance(2026, 9, 1), true);
        Program_Enrollment__c omarEnrollment = PSP_TestDataFactory.createEnrollment(omar.Id, 'Active', Date.newInstance(2026, 9, 1), true);

        Dispense__c delayed = PSP_TestDataFactory.buildDispense(lenaEnrollment.Id, Date.newInstance(2026, 11, 10), 30, 'Delayed');
        Dispense__c delivered = PSP_TestDataFactory.buildDispense(lenaEnrollment.Id, Date.newInstance(2026, 10, 9), 30, 'Delivered');
        Dispense__c omarDispense = PSP_TestDataFactory.buildDispense(omarEnrollment.Id, Date.newInstance(2026, 11, 1), 30, 'Shipped');
        insert new List<Dispense__c>{ delayed, delivered, omarDispense };

        Case delayOne = PSP_TestDataFactory.buildCase(lena.Id, 'Delay one', 'New', 'Medium');
        delayOne.PSP_Issue_Category__c = SHIPMENT_DELAY;
        delayOne.PSP_Dispense__c = delayed.Id;
        Case delayTwo = PSP_TestDataFactory.buildCase(lena.Id, 'Delay two', 'New', 'Medium');
        delayTwo.PSP_Issue_Category__c = SHIPMENT_DELAY;
        delayTwo.PSP_Dispense__c = delayed.Id;
        Case insurance = PSP_TestDataFactory.buildCase(lena.Id, 'Insurance documents', 'New', 'Medium');
        insurance.PSP_Issue_Category__c = INSURANCE_SUPPORT;
        Case unclassified = PSP_TestDataFactory.buildCase(lena.Id, 'allergy', 'New', 'Medium');
        Case closedRefill = PSP_TestDataFactory.buildCase(lena.Id, 'Old refill question', 'Closed', 'Low');
        closedRefill.PSP_Issue_Category__c = REFILL_SUPPORT;
        closedRefill.PSP_Dispense__c = delayed.Id;
        insert new List<Case>{ delayOne, delayTwo, insurance, unclassified, closedRefill };
    }

    private static Program_Enrollment__c enrollmentOf(String patientName) {
        return [SELECT Id, Name, Patient__c FROM Program_Enrollment__c WHERE Patient__r.Name = :patientName LIMIT 1];
    }

    private static String dispenseNumber(String status, String patientName) {
        return [SELECT Name FROM Dispense__c WHERE Status__c = :status AND Program_Enrollment__r.Patient__r.Name = :patientName LIMIT 1].Name;
    }

    private static Set<String> caseNumbersBySubject(List<String> subjects) {
        Set<String> numbers = new Set<String>();
        for (Case c : [SELECT CaseNumber FROM Case WHERE Subject IN :subjects]) {
            numbers.add(c.CaseNumber);
        }
        return numbers;
    }

    private static Set<String> splitNumbers(String joined) {
        return joined == null ? new Set<String>() : new Set<String>(joined.split(', '));
    }

    private static PSP_CaseDuplicateCheck.Response run(String enrollmentNumber, Id patientId, String category, String dispense) {
        PSP_CaseDuplicateCheck.Request request = new PSP_CaseDuplicateCheck.Request();
        request.enrollmentNumber = enrollmentNumber;
        request.patientId = patientId;
        request.category = category;
        request.dispenseNumber = dispense;
        return PSP_CaseDuplicateCheck.checkDuplicates(new List<PSP_CaseDuplicateCheck.Request>{ request })[0];
    }

    @isTest
    static void shouldReturnExistingCase_WhenSameCategoryAndSameShipment() {
        Program_Enrollment__c lena = enrollmentOf('Lena Duptest');
        String delayed = dispenseNumber('Delayed', 'Lena Duptest');

        Test.startTest();
        PSP_CaseDuplicateCheck.Response response = run(lena.Name, null, SHIPMENT_DELAY, delayed);
        Test.stopTest();

        Assert.areEqual(PSP_CaseDuplicateCheck.CODE_EXISTING_CASE, response.resultCode, 'Two open delay cases exist for this shipment');
        Assert.isFalse(response.canCreate, 'A duplicate must not be created');
        Assert.areEqual(caseNumbersBySubject(new List<String>{ 'Delay one', 'Delay two' }), splitNumbers(response.matchingCaseNumbers), 'Both delay cases should be listed');
        Assert.areEqual(caseNumbersBySubject(new List<String>{ 'allergy' }), splitNumbers(response.unclassifiedOpenCaseNumbers), 'The uncategorised case is listed for review');
        Assert.areEqual('Lena Duptest', response.patientName, 'Patient name should be returned');
    }

    @isTest
    static void shouldAllowCreate_WhenSameCategoryButDifferentShipment() {
        Program_Enrollment__c lena = enrollmentOf('Lena Duptest');
        String delivered = dispenseNumber('Delivered', 'Lena Duptest');

        PSP_CaseDuplicateCheck.Response response = run(lena.Name, null, SHIPMENT_DELAY, delivered);

        Assert.areEqual(PSP_CaseDuplicateCheck.CODE_NO_DUPLICATE, response.resultCode, 'A different shipment is a separate issue');
        Assert.isTrue(response.canCreate, 'Creating is allowed');
        Assert.isNull(response.matchingCaseNumbers, 'No matching case');
    }

    @isTest
    static void shouldReturnPossibleDuplicate_WhenSameCategoryWithoutShipmentLink() {
        Program_Enrollment__c lena = enrollmentOf('Lena Duptest');
        String delivered = dispenseNumber('Delivered', 'Lena Duptest');

        PSP_CaseDuplicateCheck.Response response = run(lena.Name, null, INSURANCE_SUPPORT, delivered);

        Assert.areEqual(PSP_CaseDuplicateCheck.CODE_POSSIBLE_DUPLICATE, response.resultCode, 'The insurance case has no shipment link');
        Assert.isFalse(response.canCreate, 'A person must decide first');
        Assert.areEqual(caseNumbersBySubject(new List<String>{ 'Insurance documents' }), splitNumbers(response.possibleDuplicateCaseNumbers), 'The unlinked case should be listed');
    }

    @isTest
    static void shouldReturnExistingCase_WhenNoShipmentGivenAndCategoryIsOpen() {
        Program_Enrollment__c lena = enrollmentOf('Lena Duptest');

        PSP_CaseDuplicateCheck.Response response = run(lena.Name, null, 'insurance support', null);

        Assert.areEqual(PSP_CaseDuplicateCheck.CODE_EXISTING_CASE, response.resultCode, 'Category-level match (category is case-insensitive)');
        Assert.areEqual(caseNumbersBySubject(new List<String>{ 'Insurance documents' }), splitNumbers(response.matchingCaseNumbers), 'The insurance case should match');
    }

    @isTest
    static void shouldIgnoreClosedCases() {
        Program_Enrollment__c lena = enrollmentOf('Lena Duptest');
        String delayed = dispenseNumber('Delayed', 'Lena Duptest');

        PSP_CaseDuplicateCheck.Response response = run(lena.Name, null, REFILL_SUPPORT, delayed);

        Assert.areEqual(PSP_CaseDuplicateCheck.CODE_NO_DUPLICATE, response.resultCode, 'A closed case never blocks');
        Assert.isTrue(response.canCreate, 'Creating is allowed');
    }

    @isTest
    static void shouldUsePatientId_WhenGiven() {
        Program_Enrollment__c omar = enrollmentOf('Omar Duptest');

        PSP_CaseDuplicateCheck.Response response = run(null, omar.Patient__c, SHIPMENT_DELAY, null);

        Assert.areEqual(PSP_CaseDuplicateCheck.CODE_NO_DUPLICATE, response.resultCode, 'Omar has no open cases');
        Assert.areEqual('Omar Duptest', response.patientName, 'Patient found by Id');
        Assert.isNull(response.unclassifiedOpenCaseNumbers, 'No unclassified cases');
    }

    @isTest
    static void shouldRejectUnknownCategory() {
        Program_Enrollment__c lena = enrollmentOf('Lena Duptest');

        PSP_CaseDuplicateCheck.Response response = run(lena.Name, null, 'Billing', null);

        Assert.areEqual(PSP_CaseDuplicateCheck.CODE_INVALID_INPUT, response.resultCode, 'Unknown category is invalid');
        Assert.isFalse(response.canCreate, 'Nothing may be created');
    }

    @isTest
    static void shouldRejectMissingPatient() {
        PSP_CaseDuplicateCheck.Response response = run(null, null, SHIPMENT_DELAY, null);

        Assert.areEqual(PSP_CaseDuplicateCheck.CODE_INVALID_INPUT, response.resultCode, 'A patient is required');
    }

    @isTest
    static void shouldReturnNotFound_WhenEnrollmentDoesNotExist() {
        PSP_CaseDuplicateCheck.Response response = run('ENR-9999', null, SHIPMENT_DELAY, null);

        Assert.areEqual(PSP_CaseDuplicateCheck.CODE_NOT_FOUND, response.resultCode, 'Unknown enrollment');
    }

    @isTest
    static void shouldRejectShipmentOfAnotherPatient() {
        Program_Enrollment__c lena = enrollmentOf('Lena Duptest');
        String omarShipment = dispenseNumber('Shipped', 'Omar Duptest');

        PSP_CaseDuplicateCheck.Response response = run(lena.Name, null, SHIPMENT_DELAY, omarShipment);

        Assert.areEqual(PSP_CaseDuplicateCheck.CODE_INVALID_INPUT, response.resultCode, 'The shipment belongs to another patient');
    }

    @isTest
    static void shouldKeepOrder_WhenCheckingSeveralRequests() {
        Program_Enrollment__c lena = enrollmentOf('Lena Duptest');
        Program_Enrollment__c omar = enrollmentOf('Omar Duptest');
        PSP_CaseDuplicateCheck.Request first = new PSP_CaseDuplicateCheck.Request();
        first.enrollmentNumber = omar.Name;
        first.category = SHIPMENT_DELAY;
        PSP_CaseDuplicateCheck.Request second = new PSP_CaseDuplicateCheck.Request();
        second.enrollmentNumber = lena.Name;
        second.category = SHIPMENT_DELAY;

        Test.startTest();
        List<PSP_CaseDuplicateCheck.Response> responses = PSP_CaseDuplicateCheck.checkDuplicates(
            new List<PSP_CaseDuplicateCheck.Request>{ first, second, null }
        );
        Test.stopTest();

        Assert.areEqual(3, responses.size(), 'One response per request');
        Assert.areEqual(PSP_CaseDuplicateCheck.CODE_NO_DUPLICATE, responses[0].resultCode, 'Omar first');
        Assert.areEqual(PSP_CaseDuplicateCheck.CODE_EXISTING_CASE, responses[1].resultCode, 'Lena second');
        Assert.areEqual(PSP_CaseDuplicateCheck.CODE_INVALID_INPUT, responses[2].resultCode, 'Null request is invalid');
    }

    @isTest
    static void shouldReturnEmptyList_WhenNoRequests() {
        Assert.isTrue(PSP_CaseDuplicateCheck.checkDuplicates(new List<PSP_CaseDuplicateCheck.Request>()).isEmpty(), 'Empty in, empty out');
        Assert.isTrue(PSP_CaseDuplicateCheck.checkDuplicates(null).isEmpty(), 'Null in, empty out');
    }
}
