/**
 * Tests for PSP_ProgramExceptionsService (fictional data, rolled back after each test).
 * Four patients: Anna (overdue refill, delayed shipment with 2 linked cases, safety case),
 * Ben (healthy), Cara (consent not given), Dev (enrollment without Program).
 */
@isTest
private class PSP_ProgramExceptionsServiceTest {

    private static final Date AS_OF = Date.newInstance(2026, 11, 19);

    @TestSetup
    static void setupTestData() {
        PSP_TestDataFactory.createSdoCaseAutomationFixture();

        Account anna = PSP_TestDataFactory.createPatient('Anna', 'Svctest', true);
        Account ben = PSP_TestDataFactory.createPatient('Ben', 'Svctest', true);
        Account cara = PSP_TestDataFactory.createPatient('Cara', 'Svctest', true);
        Account dev = PSP_TestDataFactory.createPatient('Dev', 'Svctest', true);

        // Inserted one by one so the enrollment numbers follow the order Anna, Ben, Cara, Dev.
        Program_Enrollment__c annaEnrollment = PSP_TestDataFactory.createEnrollment(anna.Id, 'Enrolled', Date.newInstance(2026, 9, 1), true);
        Program_Enrollment__c benEnrollment = PSP_TestDataFactory.createEnrollment(ben.Id, 'Active', Date.newInstance(2026, 9, 1), true);
        Program_Enrollment__c caraEnrollment = PSP_TestDataFactory.createEnrollment(cara.Id, 'Enrolled', Date.newInstance(2026, 11, 17), false);
        caraEnrollment.Consent_Given__c = false;
        caraEnrollment.Consent_Date__c = null;
        insert caraEnrollment;
        Program_Enrollment__c devEnrollment = PSP_TestDataFactory.createEnrollment(dev.Id, 'Enrolled', Date.newInstance(2026, 11, 1), false);
        devEnrollment.Program__c = null;
        insert devEnrollment;

        Dispense__c annaDelayed = PSP_TestDataFactory.buildDispense(annaEnrollment.Id, Date.newInstance(2026, 11, 10), 30, 'Delayed');
        insert new List<Dispense__c>{
            PSP_TestDataFactory.buildDispense(annaEnrollment.Id, Date.newInstance(2026, 10, 9), 30, 'Delivered'),
            annaDelayed,
            PSP_TestDataFactory.buildDispense(benEnrollment.Id, Date.newInstance(2026, 11, 10), 30, 'Delivered')
        };

        Case delayOne = PSP_TestDataFactory.buildCase(anna.Id, 'Delay one', 'New', 'Medium');
        delayOne.PSP_Issue_Category__c = 'Shipment Delay';
        delayOne.PSP_Dispense__c = annaDelayed.Id;
        Case delayTwo = PSP_TestDataFactory.buildCase(anna.Id, 'Delay two', 'New', 'Medium');
        delayTwo.PSP_Issue_Category__c = 'Shipment Delay';
        delayTwo.PSP_Dispense__c = annaDelayed.Id;
        Case safety = PSP_TestDataFactory.buildCase(anna.Id, 'Possible side effect', 'New', 'High');
        safety.PSP_Issue_Category__c = 'Possible Adverse Event';
        Case benClosed = PSP_TestDataFactory.buildCase(ben.Id, 'Old question', 'Closed', 'Low');
        insert new List<Case>{ delayOne, delayTwo, safety, benClosed };
    }

    private static PSP_ProgramExceptionsService.Response run(PSP_ProgramExceptionsService.Request request) {
        return PSP_ProgramExceptionsService.getExceptions(new List<PSP_ProgramExceptionsService.Request>{ request })[0];
    }

    private static PSP_ProgramExceptionsService.Request request() {
        PSP_ProgramExceptionsService.Request request = new PSP_ProgramExceptionsService.Request();
        request.asOfDate = AS_OF;
        return request;
    }

    private static String enrollmentNumberOf(String patientName) {
        return [SELECT Name FROM Program_Enrollment__c WHERE Patient__r.Name = :patientName LIMIT 1].Name;
    }

    private static Map<String, Integer> countByPatient(List<PSP_ProgramExceptionsService.Item> items) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (PSP_ProgramExceptionsService.Item item : items) {
            counts.put(item.patientName, (counts.get(item.patientName) ?? 0) + 1);
        }
        return counts;
    }

    @isTest
    static void shouldListOnlyPatientsWithExceptions() {
        Test.startTest();
        PSP_ProgramExceptionsService.Response response = run(request());
        Test.stopTest();

        Assert.areEqual(PSP_ProgramExceptionsService.CODE_SUCCESS, response.resultCode, response.resultMessage);
        Assert.areEqual(4, response.enrollmentsEvaluated, 'All four enrollments are checked');
        Assert.areEqual(6, response.items.size(), 'Anna 4 + Cara 1 + Dev 1');
        Map<String, Integer> counts = countByPatient(response.items);
        Assert.areEqual(4, counts.get('Anna Svctest'), 'Anna: overdue, delayed, safety, duplicates');
        Assert.areEqual(1, counts.get('Cara Svctest'), 'Cara: consent pending');
        Assert.areEqual(1, counts.get('Dev Svctest'), 'Dev: program not set');
        Assert.isFalse(counts.containsKey('Ben Svctest'), 'Healthy patient does not appear');
        Assert.areEqual(3, response.patientsWithItems, 'Three patients with items');
        Assert.areEqual(2, response.highCount, 'Overdue + safety');
        Assert.areEqual(2, response.mediumCount, 'Delayed + consent');
        Assert.areEqual(1, response.lowCount, 'Duplicates');
        Assert.areEqual(1, response.dataGapCount, 'Program not set');
        Assert.areEqual(PSP_ProgramExceptionRules.SEVERITY_HIGH, response.items[0].severity, 'Most severe first');
        Assert.isFalse(response.hasMore, 'Single page');
        Assert.isTrue(response.itemsText.contains('REFILL_OVERDUE'), 'Readable text lists the items');
        Assert.isTrue(response.resultMessage.contains('6 item(s) for 3 patient(s) out of 4 enrollment(s)'), response.resultMessage);
    }

    @isTest
    static void shouldFilterByExceptionType() {
        PSP_ProgramExceptionsService.Request filtered = request();
        filtered.exceptionTypes = ' shipment_delayed , ';

        PSP_ProgramExceptionsService.Response response = run(filtered);

        Assert.areEqual(1, response.items.size(), 'Only the delayed shipment');
        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_SHIPMENT_DELAYED, response.items[0].exceptionType, 'Type filter applied');
        Assert.areEqual(PSP_ProgramExceptionRules.ACTION_SKIP_EXISTING_CASE, response.items[0].suggestedAction, 'Linked cases exist');
    }

    @isTest
    static void shouldRejectUnknownExceptionType() {
        PSP_ProgramExceptionsService.Request filtered = request();
        filtered.exceptionTypes = 'SHIPMENT_DELAYED,LATE_PAYMENT';

        PSP_ProgramExceptionsService.Response response = run(filtered);

        Assert.areEqual(PSP_ProgramExceptionsService.CODE_INVALID_INPUT, response.resultCode, 'Unknown type is invalid');
        Assert.isTrue(response.items.isEmpty(), 'No items on error');
    }

    @isTest
    static void shouldReturnOnePatient_WhenEnrollmentNumberGiven() {
        PSP_ProgramExceptionsService.Request single = request();
        single.enrollmentNumber = enrollmentNumberOf('Cara Svctest');

        PSP_ProgramExceptionsService.Response response = run(single);

        Assert.areEqual(1, response.enrollmentsEvaluated, 'Only Cara is checked');
        Assert.areEqual(PSP_ProgramExceptionRules.TYPE_CONSENT_PENDING, response.items[0].exceptionType, 'Cara consent pending');
    }

    @isTest
    static void shouldReturnNotFound_WhenEnrollmentDoesNotExist() {
        PSP_ProgramExceptionsService.Request single = request();
        single.enrollmentNumber = 'ENR-9999';

        PSP_ProgramExceptionsService.Response response = run(single);

        Assert.areEqual(PSP_ProgramExceptionsService.CODE_NOT_FOUND, response.resultCode, 'Unknown enrollment');
    }

    @isTest
    static void shouldPageThroughAllEnrollments() {
        PSP_ProgramExceptionsService.Request first = request();
        first.pageSize = 2;

        Test.startTest();
        PSP_ProgramExceptionsService.Response page1 = run(first);
        PSP_ProgramExceptionsService.Request second = request();
        second.pageSize = 2;
        second.afterEnrollmentNumber = page1.nextEnrollmentNumber;
        PSP_ProgramExceptionsService.Response page2 = run(second);
        Test.stopTest();

        Assert.isTrue(page1.hasMore, 'More enrollments after page 1');
        Assert.areEqual(enrollmentNumberOf('Ben Svctest'), page1.nextEnrollmentNumber, 'Page 1 ends with Ben');
        Assert.areEqual(2, page1.enrollmentsEvaluated, 'Two per page');
        Assert.isFalse(page2.hasMore, 'Page 2 is the last');
        Assert.areEqual(2, page2.enrollmentsEvaluated, 'Cara and Dev on page 2');
        Assert.areEqual(6, page1.items.size() + page2.items.size(), 'Pages together give the full list');
    }

    @isTest
    static void shouldRejectInvalidPageSize() {
        PSP_ProgramExceptionsService.Request tooSmall = request();
        tooSmall.pageSize = 0;
        PSP_ProgramExceptionsService.Request tooBig = request();
        tooBig.pageSize = PSP_ProgramExceptionsService.MAX_PAGE_SIZE + 1;

        Assert.areEqual(PSP_ProgramExceptionsService.CODE_INVALID_INPUT, run(tooSmall).resultCode, 'Page size 0 is invalid');
        Assert.areEqual(PSP_ProgramExceptionsService.CODE_INVALID_INPUT, run(tooBig).resultCode, 'Page size above maximum is invalid');
    }

    @isTest
    static void shouldDefaultToToday_WhenNoInputGiven() {
        List<PSP_ProgramExceptionsService.Response> responses = PSP_ProgramExceptionsService.getExceptions(
            new List<PSP_ProgramExceptionsService.Request>{ null });

        Assert.areEqual(1, responses.size(), 'One response');
        Assert.areEqual(Date.today(), responses[0].asOfDate, 'As-of date defaults to today');
        Assert.areEqual(PSP_ProgramExceptionsService.CODE_SUCCESS, responses[0].resultCode, responses[0].resultMessage);
        Assert.isTrue(PSP_ProgramExceptionsService.getExceptions(null).isEmpty(), 'Null list gives no responses');
    }

    @isTest
    static void shouldSayNoExceptions_WhenFilterMatchesNothing() {
        PSP_ProgramExceptionsService.Request filtered = request();
        filtered.exceptionTypes = 'NO_SHIPMENT_RECORDED';

        PSP_ProgramExceptionsService.Response response = run(filtered);

        Assert.areEqual(PSP_ProgramExceptionsService.CODE_SUCCESS, response.resultCode, 'Still a success');
        Assert.isTrue(response.items.isEmpty(), 'Nothing matches');
        Assert.areEqual('No program exceptions found.', response.itemsText, 'Friendly empty text');
    }
}
