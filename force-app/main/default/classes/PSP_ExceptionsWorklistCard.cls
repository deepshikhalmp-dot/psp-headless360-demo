/**
 * Zenthera Patient Support Program (fictional demo data): output type for the HXL "Program Exceptions
 * Worklist" card. Bound to the Lightning Type pspExceptionsWorklist (widget pspExceptionsWorklistCard).
 * Pure data holder; filled by PSP_ExceptionsWorklistCardAction. Read-only content.
 */
@JsonAccess(serializable='always' deserializable='always')
global with sharing class PSP_ExceptionsWorklistCard {
    @AuraEnabled
    global String title;
    @AuraEnabled
    global String summary;
    @AuraEnabled
    global String highLabel;
    @AuraEnabled
    global String mediumLabel;
    @AuraEnabled
    global String lowLabel;
    @AuraEnabled
    global String dataGapLabel;
    @AuraEnabled
    global Boolean hasHigh;
    @AuraEnabled
    global Boolean hasMedium;
    @AuraEnabled
    global Boolean hasLow;
    @AuraEnabled
    global Boolean hasDataGaps;
    @AuraEnabled
    global Boolean hasNoItems;
    @AuraEnabled
    global String highItems;
    @AuraEnabled
    global String mediumItems;
    @AuraEnabled
    global String lowItems;
    @AuraEnabled
    global String dataGapItems;
    @AuraEnabled
    global String footer;
}
