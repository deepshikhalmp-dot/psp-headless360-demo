// Zenthera PSP Program Exceptions Desk: READ-ONLY demo pre-flight (no DML, nothing is created or changed).
// Run before the demo to see the expected answers for the demo day:
//   sf apex run --file scripts/apex/psp-demo-preflight.apex --target-org ProductPillarSDO1
// Dates follow the running user's time zone.

PSP_ProgramExceptionsService.Request all = new PSP_ProgramExceptionsService.Request();
PSP_ProgramExceptionsService.Response exceptions = PSP_ProgramExceptionsService.getExceptions(
    new List<PSP_ProgramExceptionsService.Request>{ all })[0];
System.debug('PREFLIGHT 1 EXCEPTIONS ' + exceptions.resultCode + ' | ' + exceptions.resultMessage);
System.debug('PREFLIGHT 1 ITEMS\n' + exceptions.itemsText);

PSP_ProgramExceptionsService.Request delayed = new PSP_ProgramExceptionsService.Request();
delayed.exceptionTypes = 'SHIPMENT_DELAYED';
PSP_ProgramExceptionsService.Response delayedResponse = PSP_ProgramExceptionsService.getExceptions(
    new List<PSP_ProgramExceptionsService.Request>{ delayed })[0];
System.debug('PREFLIGHT 2 DELAYED ' + delayedResponse.items.size() + ' item(s)\n' + delayedResponse.itemsText);

List<PSP_CaseDuplicateCheck.Request> checks = new List<PSP_CaseDuplicateCheck.Request>();
for (List<String> input : new List<List<String>>{
        new List<String>{ 'ENR-0007', 'Shipment Delay', 'DSP-0016' },
        new List<String>{ 'ENR-0007', 'Refill Support', null },
        new List<String>{ 'ENR-0018', 'Refill Support', null },
        new List<String>{ 'ENR-0059', 'Shipment Delay', 'DSP-0073' } }) {
    PSP_CaseDuplicateCheck.Request check = new PSP_CaseDuplicateCheck.Request();
    check.enrollmentNumber = input[0];
    check.category = input[1];
    check.dispenseNumber = input[2];
    checks.add(check);
}
List<PSP_CaseDuplicateCheck.Response> checkResults = PSP_CaseDuplicateCheck.checkDuplicates(checks);
for (Integer i = 0; i < checks.size(); i++) {
    System.debug('PREFLIGHT 3 DUPLICATE ' + checks[i].enrollmentNumber + ' / ' + checks[i].category + ' / ' + checks[i].dispenseNumber
        + ' => ' + checkResults[i].resultCode + ' | matching=' + checkResults[i].matchingCaseNumbers + ' | unclassified=' + checkResults[i].unclassifiedOpenCaseNumbers);
}

PSP_CareTeamHandoff.Request handoff = new PSP_CareTeamHandoff.Request();
handoff.enrollmentNumber = 'ENR-0007';
PSP_CareTeamHandoff.Response handoffResponse = PSP_CareTeamHandoff.prepareHandoffs(
    new List<PSP_CareTeamHandoff.Request>{ handoff })[0];
System.debug('PREFLIGHT 4 HANDOFF ' + handoffResponse.resultCode + '\n' + handoffResponse.handoffText);

System.debug('PREFLIGHT 5 COUNTS cases=' + [SELECT COUNT() FROM Case]
    + ' pspOpenCases=' + [SELECT COUNT() FROM Case WHERE IsClosed = false AND AccountId IN (SELECT Patient__c FROM Program_Enrollment__c)]
    + ' enrollments=' + [SELECT COUNT() FROM Program_Enrollment__c] + ' dispenses=' + [SELECT COUNT() FROM Dispense__c]
    + ' today=' + String.valueOf(Date.today()));
