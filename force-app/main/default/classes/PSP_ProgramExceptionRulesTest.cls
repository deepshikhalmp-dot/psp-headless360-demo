/**
 * Tests for PSP_ProgramExceptionRules (fictional data). Rule tests build records in memory
 * (no DML); one test compares the refill due date with PSP_RefillHistoryTool on inserted records.
 */
@isTest
private class PSP_ProgramExceptionRulesTest {

    private static final Date AS_OF = Date.newInstance(2026, 11, 19);
    private static final String PATIENT_NAME = 'Lena Rulestest';
    private static Integer idCounter = 0;

    // ---------- in-memory builders ----------

    private static Id fakeId(Schema.SObjectType sObjectType) {
        idCounter++;
        return Id.valueOf(sObjectType.getDescribe().getKeyPrefix() + String.valueOf(idCounter).leftPad(12, '0'));
    }

    private static Program_Enrollment__c enrollment(String status, Boolean consentGiven, Date consentDate, Date enrollmentDate) {
        return enrollmentWithProgram(status, consentGiven, consentDate, enrollmentDate, PSP_ProgramExceptionRules.PROGRAM_ZENTHERA, true);
    }

    private static Program_Enrollment__c enrollmentWithProgram(String status, Boolean consentGiven, Date consentDate, Date enrollmentDate, String program, Boolean withPatient) {
        Map<String, Object> fields = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Program_Enrollment__c' },
            'Id' => fakeId(Program_Enrollment__c.SObjectType),
            'Name' => 'ENR-T001',
            'Program__c' => program,
            'Status__c' => status,
            'Consent_Given__c' => consentGiven,
            'Consent_Date__c' => consentDate,
            'Enrollment_Date__c' => enrollmentDate
        };
        if (withPatient) {
            Id patientId = fakeId(Account.SObjectType);
            fields.put('Patient__c', patientId);
            fields.put('Patient__r', new Map<String, Object>{ 'attributes' => new Map<String, Object>{ 'type' => 'Account' }, 'Id' => patientId, 'Name' => PATIENT_NAME });
        }
        return (Program_Enrollment__c) JSON.deserialize(JSON.serialize(fields), Program_Enrollment__c.class);
    }

    private static Program_Enrollment__c activeEnrollment() {
        return enrollment('Active', true, Date.newInstance(2026, 9, 1), Date.newInstance(2026, 9, 1));
    }

    private static Dispense__c dispense(String name, String status, Date dispenseDate, Integer daysSupply) {
        Map<String, Object> fields = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Dispense__c' },
            'Id' => fakeId(Dispense__c.SObjectType),
            'Name' => name,
            'Status__c' => status,
            'Dispense_Date__c' => dispenseDate,
            'Days_Supply__c' => daysSupply
        };
        return (Dispense__c) JSON.deserialize(JSON.serialize(fields), Dispense__c.class);
    }

    private static Case openCase(String caseNumber, String category, Id dispenseId) {
        Map<String, Object> fields = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Case' },
            'Id' => fakeId(Case.SObjectType),
            'CaseNumber' => caseNumber,
            'PSP_Issue_Category__c' => category,
            'PSP_Dispense__c' => dispenseId
        };
        return (Case) JSON.deserialize(JSON.serialize(fields), Case.class);
    }

    private static List<PSP_ProgramExceptionRules.ExceptionItem> run(Program_Enrollment__c e, List<Dispense__c> dispenses, List<Case> cases) {
        return PSP_ProgramExceptionRules.evaluate(e, dispenses, cases, AS_OF);
    }

    private static List<PSP_ProgramExceptionRules.ExceptionItem> ofType(List<PSP_ProgramExceptionRules.ExceptionItem> items, String exceptionType) {
        List<PSP_ProgramExceptionRules.ExceptionItem> matches = new List<PSP_ProgramExceptionRules.ExceptionItem>();
        for (PSP_ProgramExceptionRules.ExceptionItem item : items) {
            if (item.exceptionType == exceptionType) {
                matches.add(item);
            }
        }
        return matches;
    }

    // ---------- refill ----------

    @isTest
    static void shouldFlagHighOverdue_WhenMoreThanSevenDaysLate() {
        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(activeEnrollment(),
            new List<Dispense__c>{ dispense('DSP-T1', 'Delivered', Date.newInstance(2026, 10, 9), 30) }, null);

        Assert.areEqual(1, items.size(), 'Only the refill item is expected');
        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_REFILL_OVERDUE, items[0].exceptionType, 'Due 2026-11-08, so overdue');
        Assert.areEqual(PSP_ProgramExceptionRules.SEVERITY_HIGH, items[0].severity, '11 days late is HIGH');
        Assert.areEqual(PSP_ProgramExceptionRules.ACTION_PREPARE_HANDOFF, items[0].suggestedAction, 'Overdue suggests a handoff');
        Assert.isTrue(items[0].fact.contains('11 day(s)') && items[0].fact.contains('recorded shipments only'), 'Fact states days and basis: ' + items[0].fact);
        Assert.areEqual(PATIENT_NAME, items[0].patientName, 'Patient name is carried');
        Assert.areEqual('ENR-T001', items[0].enrollmentNumber, 'Enrollment number is carried');
    }

    @isTest
    static void shouldFlagMediumOverdue_WhenUpToSevenDaysLate() {
        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(activeEnrollment(),
            new List<Dispense__c>{ dispense('DSP-T1', 'Delivered', Date.newInstance(2026, 10, 17), 30) }, null);

        Assert.areEqual(PSP_ProgramExceptionRules.SEVERITY_MEDIUM, items[0].severity, '3 days late is MEDIUM');
    }

    @isTest
    static void shouldFlagDueSoon_WhenDueWithinSevenDays() {
        List<PSP_ProgramExceptionRules.ExceptionItem> dueToday = run(activeEnrollment(),
            new List<Dispense__c>{ dispense('DSP-T1', 'Delivered', Date.newInstance(2026, 10, 20), 30) }, null);
        List<PSP_ProgramExceptionRules.ExceptionItem> dueInEight = run(activeEnrollment(),
            new List<Dispense__c>{ dispense('DSP-T2', 'Delivered', Date.newInstance(2026, 10, 28), 30) }, null);

        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_REFILL_DUE_SOON, dueToday[0].exceptionType, 'Due today counts as due soon');
        Assert.areEqual(PSP_ProgramExceptionRules.SEVERITY_LOW, dueToday[0].severity, 'Due soon is LOW');
        Assert.isTrue(dueInEight.isEmpty(), 'Due in 8 days is on track, no item');
    }

    @isTest
    static void shouldUseLatestDeliveredShipment() {
        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(activeEnrollment(), new List<Dispense__c>{
            dispense('DSP-NEW', 'Delivered', Date.newInstance(2026, 11, 10), 30),
            dispense('DSP-OLD', 'Delivered', Date.newInstance(2026, 9, 1), 30)
        }, null);

        Assert.isTrue(items.isEmpty(), 'The newer delivery (due 2026-12-10) is on track');
    }

    @isTest
    static void shouldReportDataIncomplete_WhenDeliveredShipmentHasNoDaysSupply() {
        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(activeEnrollment(),
            new List<Dispense__c>{ dispense('DSP-T1', 'Delivered', Date.newInstance(2026, 9, 1), null) }, null);

        Assert.areEqual(1, items.size(), 'Only the data gap is expected');
        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_DATA_INCOMPLETE, items[0].exceptionType, 'Missing days supply is a data gap');
        Assert.areEqual(PSP_ProgramExceptionRules.SEVERITY_INFO, items[0].severity, 'Data gaps are INFO');
        Assert.isTrue(ofType(items, PSP_ProgramExceptionRules.TYPE_REFILL_OVERDUE).isEmpty(), 'No refill exception is invented');
    }

    @isTest
    static void shouldMatchRefillHistoryTool_ForTheSameData() {
        PSP_TestDataFactory.createPatient('Lena', 'Rulestest', true);
        Program_Enrollment__c enrollmentRecord = PSP_TestDataFactory.createEnrollment(
            [SELECT Id FROM Account WHERE Name = :PATIENT_NAME LIMIT 1].Id, 'Active', Date.newInstance(2026, 9, 1), true);
        insert new List<Dispense__c>{
            PSP_TestDataFactory.buildDispense(enrollmentRecord.Id, Date.newInstance(2026, 10, 9), 30, 'Delivered'),
            PSP_TestDataFactory.buildDispense(enrollmentRecord.Id, Date.newInstance(2026, 11, 10), 30, 'Delayed')
        };
        Program_Enrollment__c loaded = [
            SELECT Id, Name, Patient__c, Patient__r.Name, Program__c, Status__c, Enrollment_Date__c, Consent_Given__c, Consent_Date__c,
                (SELECT Id, Name, Status__c, Dispense_Date__c, Days_Supply__c FROM Dispenses__r)
            FROM Program_Enrollment__c WHERE Id = :enrollmentRecord.Id
        ];

        PSP_RefillHistoryTool.Request request = new PSP_RefillHistoryTool.Request();
        request.enrollmentNumber = loaded.Name;
        request.asOfDate = AS_OF;

        Test.startTest();
        PSP_RefillHistoryTool.Response refill = PSP_RefillHistoryTool.getRefillHistory(new List<PSP_RefillHistoryTool.Request>{ request })[0];
        List<PSP_ProgramExceptionRules.ExceptionItem> items = PSP_ProgramExceptionRules.evaluate(loaded, loaded.Dispenses__r, new List<Case>(), AS_OF);
        Test.stopTest();

        List<PSP_ProgramExceptionRules.ExceptionItem> overdue = ofType(items, PSP_ProgramExceptionRules.TYPE_REFILL_OVERDUE);
        Assert.areEqual(PSP_RefillHistoryTool.STATUS_LATE, refill.refillStatus, 'Refill tool says LATE');
        Assert.areEqual(1, overdue.size(), 'Rules also say overdue');
        Assert.isTrue(overdue[0].fact.contains('due ' + String.valueOf(refill.nextRefillDueDate)), 'Same due date as the Refill tool: ' + overdue[0].fact);
        Assert.isTrue(overdue[0].fact.contains(refill.daysOverdue + ' day(s)'), 'Same days overdue as the Refill tool');
    }

    // ---------- shipments ----------

    @isTest
    static void shouldSkip_WhenDelayedShipmentHasLinkedCase() {
        Dispense__c delayed = dispense('DSP-T9', 'Delayed', Date.newInstance(2026, 11, 10), 30);
        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(activeEnrollment(), new List<Dispense__c>{ delayed },
            new List<Case>{ openCase('00009001', 'Shipment Delay', delayed.Id) });

        PSP_ProgramExceptionRules.ExceptionItem item = ofType(items, PSP_ProgramExceptionRules.TYPE_SHIPMENT_DELAYED)[0];
        Assert.areEqual(PSP_ProgramExceptionRules.ACTION_SKIP_EXISTING_CASE, item.suggestedAction, 'A linked case exists');
        Assert.areEqual('00009001', item.caseNumbers, 'Linked case number');
        Assert.areEqual('DSP-T9', item.dispenseNumber, 'Dispense number');
    }

    @isTest
    static void shouldAskForReview_WhenOnlyUnlinkedDelayCaseExists() {
        Dispense__c delayed = dispense('DSP-T9', 'Delayed', Date.newInstance(2026, 11, 10), 30);
        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(activeEnrollment(), new List<Dispense__c>{ delayed },
            new List<Case>{ openCase('00009002', 'Shipment Delay', null) });

        Assert.areEqual(PSP_ProgramExceptionRules.ACTION_REVIEW_POSSIBLE_DUPLICATE,
            ofType(items, PSP_ProgramExceptionRules.TYPE_SHIPMENT_DELAYED)[0].suggestedAction, 'Unlinked case must be reviewed');
    }

    @isTest
    static void shouldSuggestCreate_WhenDelayedShipmentHasNoCase() {
        Dispense__c delayed = dispense('DSP-T9', 'Delayed', Date.newInstance(2026, 11, 10), 30);
        Dispense__c other = dispense('DSP-T8', 'Delivered', Date.newInstance(2026, 11, 1), 30);
        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(activeEnrollment(), new List<Dispense__c>{ delayed, other },
            new List<Case>{ openCase('00009003', 'Shipment Delay', other.Id) });

        Assert.areEqual(PSP_ProgramExceptionRules.ACTION_CREATE_CASE,
            ofType(items, PSP_ProgramExceptionRules.TYPE_SHIPMENT_DELAYED)[0].suggestedAction, 'A case for another shipment does not cover it');
    }

    @isTest
    static void shouldFlagShippedNotDelivered_OnlyAfterSevenDays() {
        List<PSP_ProgramExceptionRules.ExceptionItem> old = run(activeEnrollment(),
            new List<Dispense__c>{ dispense('DSP-T1', 'Shipped', Date.newInstance(2026, 11, 1), 30) }, null);
        List<PSP_ProgramExceptionRules.ExceptionItem> recent = run(activeEnrollment(),
            new List<Dispense__c>{ dispense('DSP-T2', 'Shipped', Date.newInstance(2026, 11, 16), 30) }, null);
        List<PSP_ProgramExceptionRules.ExceptionItem> noDate = run(activeEnrollment(),
            new List<Dispense__c>{ dispense('DSP-T3', 'Shipped', null, 30) }, null);

        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_SHIPPED_NOT_DELIVERED, old[0].exceptionType, '18 days in transit');
        Assert.isTrue(recent.isEmpty(), '3 days in transit is normal');
        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_DATA_INCOMPLETE, noDate[0].exceptionType, 'Shipped without a date is a data gap');
    }

    @isTest
    static void shouldFlagNoShipment_OnlyAfterFourteenDays() {
        List<PSP_ProgramExceptionRules.ExceptionItem> old = run(enrollment('Enrolled', true, Date.newInstance(2026, 10, 1), Date.newInstance(2026, 10, 1)), null, null);
        List<PSP_ProgramExceptionRules.ExceptionItem> recent = run(enrollment('Enrolled', true, Date.newInstance(2026, 11, 17), Date.newInstance(2026, 11, 17)), null, null);
        List<PSP_ProgramExceptionRules.ExceptionItem> noDate = run(enrollment('Enrolled', true, Date.newInstance(2026, 11, 17), null), null, null);

        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_NO_SHIPMENT_RECORDED, old[0].exceptionType, '49 days without a shipment');
        Assert.isTrue(recent.isEmpty(), 'A 2-day-old enrollment is normal');
        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_DATA_INCOMPLETE, noDate[0].exceptionType, 'Missing enrollment date is a data gap');
    }

    // ---------- consent and status ----------

    @isTest
    static void shouldFlagConsentPending_WhenConsentNotGiven() {
        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(enrollment('Enrolled', false, null, Date.newInstance(2026, 11, 17)), null, null);

        Assert.areEqual(1, items.size(), 'Only consent is expected');
        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_CONSENT_PENDING, items[0].exceptionType, 'Consent not given');
        Assert.areEqual(PSP_ProgramExceptionRules.ACTION_FOLLOW_UP_CONSENT, items[0].suggestedAction, 'Follow up consent');
    }

    @isTest
    static void shouldReportDataIncomplete_WhenConsentDateMissing() {
        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(enrollment('Enrolled', true, null, Date.newInstance(2026, 11, 17)), null, null);

        Assert.areEqual(1, items.size(), 'Only the data gap is expected');
        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_DATA_INCOMPLETE, items[0].exceptionType, 'Consent date missing is a data gap, not an exception');
    }

    @isTest
    static void shouldSkipRefillRules_WhenOnHold() {
        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(enrollment('On Hold', false, null, Date.newInstance(2026, 9, 1)),
            new List<Dispense__c>{ dispense('DSP-T1', 'Delivered', Date.newInstance(2026, 9, 1), 30) }, null);

        Assert.isTrue(ofType(items, PSP_ProgramExceptionRules.TYPE_REFILL_OVERDUE).isEmpty(), 'Therapy paused: no refill item');
        Assert.areEqual(1, ofType(items, PSP_ProgramExceptionRules.TYPE_CONSENT_PENDING).size(), 'Consent rule still applies');
    }

    @isTest
    static void shouldOnlyApplyCaseRules_WhenDiscontinued() {
        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(enrollment('Discontinued', false, null, Date.newInstance(2026, 6, 1)),
            new List<Dispense__c>{ dispense('DSP-T1', 'Delivered', Date.newInstance(2026, 6, 1), 30) },
            new List<Case>{ openCase('00009004', 'Possible Adverse Event', null) });

        Assert.areEqual(1, items.size(), 'Only the safety case is expected');
        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_SAFETY_REVIEW_OPEN, items[0].exceptionType, 'Safety review still shows');
    }

    // ---------- cases ----------

    @isTest
    static void shouldReproduceRiyaScenario_SortedBySeverity() {
        Dispense__c delivered = dispense('DSP-0015', 'Delivered', Date.newInstance(2026, 10, 9), 30);
        Dispense__c delayed = dispense('DSP-0016', 'Delayed', Date.newInstance(2026, 11, 10), 30);
        List<Case> cases = new List<Case>{
            openCase('00001070', 'Shipment Delay', delayed.Id),
            openCase('00001071', 'Possible Adverse Event', null),
            openCase('00001072', 'Shipment Delay', delayed.Id),
            openCase('00001073', 'Shipment Delay', delayed.Id)
        };

        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(
            enrollment('Enrolled', true, Date.newInstance(2026, 11, 16), Date.newInstance(2026, 11, 16)),
            new List<Dispense__c>{ delivered, delayed }, cases);

        Assert.areEqual(4, items.size(), 'Overdue, delayed, safety, duplicates');
        Assert.areEqual(PSP_ProgramExceptionRules.SEVERITY_HIGH, items[0].severity, 'HIGH first');
        Assert.areEqual(PSP_ProgramExceptionRules.SEVERITY_LOW, items[3].severity, 'LOW last');
        Assert.areEqual('00001070, 00001072, 00001073', ofType(items, PSP_ProgramExceptionRules.TYPE_SHIPMENT_DELAYED)[0].caseNumbers, 'Linked delay cases');
        Assert.areEqual('00001071', ofType(items, PSP_ProgramExceptionRules.TYPE_SAFETY_REVIEW_OPEN)[0].caseNumbers, 'Safety case');
        PSP_ProgramExceptionRules.ExceptionItem duplicates = ofType(items, PSP_ProgramExceptionRules.TYPE_DUPLICATE_OPEN_CASES)[0];
        Assert.areEqual('DSP-0016', duplicates.dispenseNumber, 'Duplicates are for DSP-0016');
        Assert.isTrue(duplicates.fact.startsWith('3 open Shipment Delay cases for shipment DSP-0016'), duplicates.fact);
    }

    @isTest
    static void shouldFlagUncategorisedCase_WithoutInterpretingText() {
        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(
            enrollment('Enrolled', true, Date.newInstance(2026, 11, 18), Date.newInstance(2026, 11, 18)),
            new List<Dispense__c>{ dispense('DSP-T1', 'Delivered', Date.newInstance(2026, 11, 18), 30) },
            new List<Case>{ openCase('00001075', null, null) });

        Assert.areEqual(1, items.size(), 'Only the uncategorised case');
        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_UNCATEGORISED_OPEN_CASE, items[0].exceptionType, 'Needs review');
        Assert.areEqual(PSP_ProgramExceptionRules.ACTION_TRIAGE_CASE, items[0].suggestedAction, 'A person triages it');
        Assert.isTrue(ofType(items, PSP_ProgramExceptionRules.TYPE_SAFETY_REVIEW_OPEN).isEmpty(), 'Never turned into a safety review');
    }

    @isTest
    static void shouldFlagDuplicates_WhenSameCategoryWithoutShipmentLink() {
        List<PSP_ProgramExceptionRules.ExceptionItem> items = run(
            enrollment('Enrolled', true, Date.newInstance(2026, 11, 17), Date.newInstance(2026, 11, 17)), null,
            new List<Case>{ openCase('00009010', 'Insurance Support', null), openCase('00009011', 'Insurance Support', null) });

        PSP_ProgramExceptionRules.ExceptionItem duplicates = ofType(items, PSP_ProgramExceptionRules.TYPE_DUPLICATE_OPEN_CASES)[0];
        Assert.areEqual('00009010, 00009011', duplicates.caseNumbers, 'Both cases listed');
        Assert.isTrue(duplicates.fact.contains('without a shipment link'), duplicates.fact);
    }

    // ---------- scope and edge cases ----------

    @isTest
    static void shouldNotEvaluate_WhenProgramBlankOrPatientMissing() {
        List<PSP_ProgramExceptionRules.ExceptionItem> noProgram = run(
            enrollmentWithProgram('Enrolled', false, null, Date.newInstance(2026, 1, 1), null, true), null, null);
        List<PSP_ProgramExceptionRules.ExceptionItem> noPatient = run(
            enrollmentWithProgram('Enrolled', false, null, Date.newInstance(2026, 1, 1), PSP_ProgramExceptionRules.PROGRAM_ZENTHERA, false), null, null);
        List<PSP_ProgramExceptionRules.ExceptionItem> otherProgram = run(
            enrollmentWithProgram('Enrolled', false, null, Date.newInstance(2026, 1, 1), 'Other Program', true), null, null);

        Assert.areEqual(1, noProgram.size(), 'Only the data gap');
        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_DATA_INCOMPLETE, noProgram[0].exceptionType, 'Program not set');
        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_DATA_INCOMPLETE, noPatient[0].exceptionType, 'No patient');
        Assert.isTrue(otherProgram.isEmpty(), 'Other programs are out of scope');
    }

    @isTest
    static void shouldReturnNothing_ForHealthyPatientOrNullInput() {
        List<PSP_ProgramExceptionRules.ExceptionItem> healthy = run(activeEnrollment(),
            new List<Dispense__c>{ dispense('DSP-T1', 'Delivered', Date.newInstance(2026, 11, 5), 30) },
            new List<Case>{ openCase('00009020', 'Refill Support', null) });

        Assert.isTrue(healthy.isEmpty(), 'No exceptions: patient does not appear');
        Assert.isTrue(PSP_ProgramExceptionRules.evaluate(null, null, null, AS_OF).isEmpty(), 'Null enrollment gives nothing');
        Assert.isNotNull(PSP_ProgramExceptionRules.evaluate(activeEnrollment(), null, null, null), 'Null as-of date uses today');
    }
}
