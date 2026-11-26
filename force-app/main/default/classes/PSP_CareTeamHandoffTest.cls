/**
 * Tests for PSP_CareTeamHandoff (fictional data, rolled back after each test).
 */
@isTest
private class PSP_CareTeamHandoffTest {

    private static final Date AS_OF = Date.newInstance(2026, 11, 19);

    @TestSetup
    static void setupTestData() {
        PSP_TestDataFactory.createSdoCaseAutomationFixture();
        Account hana = PSP_TestDataFactory.createPatient('Hana', 'Handofftest', true);
        Account ivo = PSP_TestDataFactory.createPatient('Ivo', 'Handofftest', true);
        Account jun = PSP_TestDataFactory.createPatient('Jun', 'Handofftest', true);
        Program_Enrollment__c hanaEnrollment = PSP_TestDataFactory.createEnrollment(hana.Id, 'Enrolled', Date.newInstance(2026, 9, 1), true);
        Program_Enrollment__c ivoEnrollment = PSP_TestDataFactory.createEnrollment(ivo.Id, 'Active', Date.newInstance(2026, 9, 1), true);
        PSP_TestDataFactory.createEnrollment(jun.Id, 'Enrolled', Date.newInstance(2026, 11, 17), true);

        Dispense__c delayed = PSP_TestDataFactory.buildDispense(hanaEnrollment.Id, Date.newInstance(2026, 11, 10), 30, 'Delayed');
        insert new List<Dispense__c>{
            PSP_TestDataFactory.buildDispense(hanaEnrollment.Id, Date.newInstance(2026, 10, 9), 30, 'Delivered'),
            delayed,
            PSP_TestDataFactory.buildDispense(ivoEnrollment.Id, Date.newInstance(2026, 11, 10), 30, 'Delivered')
        };

        Case delay = PSP_TestDataFactory.buildCase(hana.Id, '[Shipment Delay] Late box', 'New', 'Medium');
        delay.PSP_Issue_Category__c = 'Shipment Delay';
        delay.PSP_Dispense__c = delayed.Id;
        Case safety = PSP_TestDataFactory.buildCase(hana.Id, '[SAFETY REVIEW] Possible Adverse Event - headache after dose', 'New', 'High');
        safety.PSP_Issue_Category__c = 'Possible Adverse Event';
        Case uncategorised = PSP_TestDataFactory.buildCase(hana.Id, 'allergy', 'New', 'Medium');
        insert new List<Case>{ delay, safety, uncategorised };
    }

    private static PSP_CareTeamHandoff.Response run(String patientName) {
        PSP_CareTeamHandoff.Request request = new PSP_CareTeamHandoff.Request();
        request.enrollmentNumber = patientName == null ? null
            : [SELECT Name FROM Program_Enrollment__c WHERE Patient__r.Name = :patientName LIMIT 1].Name;
        request.asOfDate = AS_OF;
        return PSP_CareTeamHandoff.prepareHandoffs(new List<PSP_CareTeamHandoff.Request>{ request })[0];
    }

    @isTest
    static void shouldBuildFixedSections_WithoutClinicalText() {
        Test.startTest();
        PSP_CareTeamHandoff.Response response = run('Hana Handofftest');
        Test.stopTest();

        String text = response.handoffText;
        Assert.areEqual(PSP_CareTeamHandoff.CODE_SUCCESS, response.resultCode, response.resultMessage);
        for (String section : new List<String>{ '1. Patient and therapy:', '2. Refill due status (recorded shipments only):', '3. Open issues:', '4. Exceptions to note:', '5. Suggested non-clinical next steps:', '6. Data as of 2026-11-19.' }) {
            Assert.isTrue(text.contains(section), 'Missing section: ' + section);
        }
        Assert.isTrue(text.contains('11 day(s) overdue'), 'Refill overdue from the Refill tool');
        Assert.isTrue(text.contains('not whether the patient took the medication'), 'No adherence claim');
        Assert.isTrue(text.contains('in human safety review'), 'Safety case shown only as in review');
        Assert.isFalse(text.containsIgnoreCase('headache'), 'Safety case subject must not appear');
        Assert.isTrue(text.contains('no PSP issue category yet'), 'Uncategorised case flagged');
        Assert.isTrue(text.contains('prescriber'), 'Medical questions go to the prescriber');
        Assert.isTrue(text.contains('created, changed or posted nothing'), 'Read-only statement');
        Assert.areEqual('Hana Handofftest', response.patientName, 'Patient name returned');
    }

    @isTest
    static void shouldSayOnTrack_ForHealthyPatient() {
        PSP_CareTeamHandoff.Response response = run('Ivo Handofftest');

        Assert.isTrue(response.handoffText.contains('on track'), response.handoffText);
        Assert.isTrue(response.handoffText.contains('- No open cases.'), 'No cases');
        Assert.isTrue(response.handoffText.contains('- None.'), 'No exceptions');
    }

    @isTest
    static void shouldExplainMissingDueDate_WhenNoDelivery() {
        PSP_CareTeamHandoff.Response response = run('Jun Handofftest');

        Assert.isTrue(response.handoffText.contains('no due date can be calculated') || response.handoffText.contains('Not available'), response.handoffText);
    }

    @isTest
    static void shouldFindEnrollmentNumber_InsideASentence() {
        String enrollmentNumber = [SELECT Name FROM Program_Enrollment__c WHERE Patient__r.Name = 'Ivo Handofftest' LIMIT 1].Name;
        PSP_CareTeamHandoff.Request request = new PSP_CareTeamHandoff.Request();
        request.enrollmentNumber = 'Prepare a care team handoff for ' + enrollmentNumber.toLowerCase() + ' please.';
        request.asOfDate = AS_OF;

        PSP_CareTeamHandoff.Response response = PSP_CareTeamHandoff.prepareHandoffs(new List<PSP_CareTeamHandoff.Request>{ request })[0];

        Assert.areEqual(PSP_CareTeamHandoff.CODE_SUCCESS, response.resultCode, response.resultMessage);
        Assert.areEqual('Ivo Handofftest', response.patientName, 'Enrollment number taken from the sentence');
        Assert.isNull(PSP_CareTeamHandoff.extractEnrollmentNumber('handoff for Riya please'), 'No number in the sentence');
    }

    @isTest
    static void shouldReturnErrors_ForBadInput() {
        PSP_CareTeamHandoff.Request unknown = new PSP_CareTeamHandoff.Request();
        unknown.enrollmentNumber = 'ENR-9999';

        List<PSP_CareTeamHandoff.Response> responses = PSP_CareTeamHandoff.prepareHandoffs(
            new List<PSP_CareTeamHandoff.Request>{ unknown, new PSP_CareTeamHandoff.Request(), null });

        Assert.areEqual(PSP_CareTeamHandoff.CODE_NOT_FOUND, responses[0].resultCode, 'Unknown enrollment');
        Assert.areEqual(PSP_CareTeamHandoff.CODE_INVALID_INPUT, responses[1].resultCode, 'Blank enrollment');
        Assert.areEqual(PSP_CareTeamHandoff.CODE_INVALID_INPUT, responses[2].resultCode, 'Null request');
        Assert.isTrue(PSP_CareTeamHandoff.prepareHandoffs(null).isEmpty(), 'Null list');
    }
}
