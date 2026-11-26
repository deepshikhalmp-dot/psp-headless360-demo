/**
 * Smoke test: proves that Apex tests can insert PSP Cases when the SDO helper fixture exists
 * (fictional data only). See docs/Plan-Program-Exceptions-Desk.md section 4.8.
 */
@isTest
private class PSP_CaseInsertSmokeTest {

    private static final String SUBJECT = 'Shipment delayed - DSP-0042';

    private static Account createPatient() {
        return PSP_TestDataFactory.createPatient('Neha', 'Smoketest', true);
    }

    @isTest
    static void shouldFailCaseInsert_WhenSdoHelperFixtureMissing() {
        Account patient = createPatient();
        Case newCase = PSP_TestDataFactory.buildCase(patient.Id, SUBJECT, 'New', 'Medium');

        Test.startTest();
        try {
            insert newCase;
            Assert.fail('Without the SDO helper fixture the SDO Case flow should block the insert');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains('helperConfig'),
                'The failure should be the missing helperConfig input, got: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void shouldInsertCase_WhenSdoHelperFixtureExists() {
        PSP_TestDataFactory.createSdoCaseAutomationFixture();
        Account patient = createPatient();
        Case newCase = PSP_TestDataFactory.buildCase(patient.Id, SUBJECT, 'New', 'Medium');

        Test.startTest();
        insert newCase;
        Test.stopTest();

        Case saved = [SELECT Id, Subject, Status, AccountId FROM Case WHERE Id = :newCase.Id];
        Assert.areEqual(SUBJECT, saved.Subject, 'Subject should be saved unchanged');
        Assert.areEqual('New', saved.Status, 'Status should stay New');
        Assert.areEqual(patient.Id, saved.AccountId, 'Case should belong to the patient');
    }

    @isTest
    static void shouldInsertTwoCasesForSamePatient_WhenSdoHelperFixtureExists() {
        PSP_TestDataFactory.createSdoCaseAutomationFixture();
        Account patient = createPatient();
        List<Case> cases = new List<Case>{
            PSP_TestDataFactory.buildCase(patient.Id, 'Shipment delayed - DSP-0042', 'New', 'High'),
            PSP_TestDataFactory.buildCase(patient.Id, 'Shipment delayed - DSP-0043', 'New', 'High')
        };

        Test.startTest();
        insert cases;
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM Case WHERE AccountId = :patient.Id],
            'Both cases should be saved for the patient');
    }
}
