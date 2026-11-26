/**
 * Tests for PSP_ExceptionsWorklistCardAction (fictional data, rolled back after each test).
 */
@isTest
private class PSP_ExceptionsWorklistCardActionTest {

    @TestSetup
    static void setupTestData() {
        PSP_TestDataFactory.createSdoCaseAutomationFixture();
        Account mia = PSP_TestDataFactory.createPatient('Mia', 'Cardtest', true);
        Program_Enrollment__c enrollment = PSP_TestDataFactory.createEnrollment(mia.Id, 'Enrolled', Date.newInstance(2026, 9, 1), true);
        Dispense__c delayed = PSP_TestDataFactory.buildDispense(enrollment.Id, Date.newInstance(2026, 11, 10), 30, 'Delayed');
        insert new List<Dispense__c>{
            PSP_TestDataFactory.buildDispense(enrollment.Id, Date.newInstance(2026, 10, 9), 30, 'Delivered'),
            delayed
        };
        Case safety = PSP_TestDataFactory.buildCase(mia.Id, 'Safety', 'New', 'High');
        safety.PSP_Issue_Category__c = 'Possible Adverse Event';
        insert safety;
    }

    @isTest
    static void shouldBuildCard_WithGroupsAndLabels() {
        Test.startTest();
        PSP_ExceptionsWorklistCardAction.Response response = PSP_ExceptionsWorklistCardAction.getWorklistCards(
            new List<PSP_ExceptionsWorklistCardAction.Request>{ new PSP_ExceptionsWorklistCardAction.Request() })[0];
        Test.stopTest();

        Assert.areEqual(PSP_ProgramExceptionsService.CODE_SUCCESS, response.resultCode, response.resultMessage);
        PSP_ExceptionsWorklistCard card = response.card;
        Assert.isNotNull(card, 'Card returned');
        Assert.isTrue(card.hasHigh, 'Overdue refill and safety review are HIGH');
        Assert.isTrue(card.hasMedium, 'Delayed shipment without a case is MEDIUM');
        Assert.isFalse(card.hasNoItems, 'There are items');
        Assert.isTrue(card.highLabel.startsWith('High '), card.highLabel);
        Assert.isTrue(card.highItems.contains('Mia Cardtest'), card.highItems);
        Assert.isTrue(card.mediumItems.contains('SHIPMENT DELAYED'), card.mediumItems);
        Assert.areEqual(PSP_ExceptionsWorklistCardAction.FOOTER, card.footer, 'Footer states read-only and recorded shipments');
        Assert.areEqual(response.resultMessage, card.summary, 'Summary equals the service message');
        Assert.isTrue(response.itemsText.contains('REFILL_OVERDUE'), 'Text fallback returned');
    }

    @isTest
    static void shouldReturnNoCard_WhenFilterIsInvalid() {
        PSP_ExceptionsWorklistCardAction.Request request = new PSP_ExceptionsWorklistCardAction.Request();
        request.exceptionTypes = 'NOT_A_TYPE';

        PSP_ExceptionsWorklistCardAction.Response response = PSP_ExceptionsWorklistCardAction.getWorklistCards(
            new List<PSP_ExceptionsWorklistCardAction.Request>{ request })[0];

        Assert.areEqual(PSP_ProgramExceptionsService.CODE_INVALID_INPUT, response.resultCode, 'Invalid filter');
        Assert.isNull(response.card, 'No card on error');
    }

    @isTest
    static void shouldShowEmptyState_WhenNothingMatches() {
        PSP_ExceptionsWorklistCardAction.Request request = new PSP_ExceptionsWorklistCardAction.Request();
        request.exceptionTypes = 'NO_SHIPMENT_RECORDED';

        PSP_ExceptionsWorklistCardAction.Response response = PSP_ExceptionsWorklistCardAction.getWorklistCards(
            new List<PSP_ExceptionsWorklistCardAction.Request>{ request, null })[0];

        Assert.isTrue(response.card.hasNoItems, 'Empty state');
        Assert.isFalse(response.card.hasHigh, 'No high group');
        Assert.areEqual('', response.card.highItems, 'No lines');
        Assert.isTrue(PSP_ExceptionsWorklistCardAction.getWorklistCards(null).isEmpty(), 'Null list');
    }
}
