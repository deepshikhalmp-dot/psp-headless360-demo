/**
 * Test data for the Zenthera Patient Support Program (fictional records only).
 */
@isTest
public class PSP_TestDataFactory {

    /** Developer name of the Person Account record type used for PSP patients. */
    public static final String PATIENT_RECORD_TYPE = 'PersonAccount';

    /** Value used by the test-only SDO helper rule; never appears in a PSP case subject. */
    public static final String SDO_HELPER_NO_MATCH_VALUE = 'PSP-TEST-NO-MATCH';

    /**
     * @param firstName patient first name
     * @param lastName patient last name
     * @param doInsert insert the record when true
     * @return a Person Account patient
     */
    public static Account createPatient(String firstName, String lastName, Boolean doInsert) {
        Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(PATIENT_RECORD_TYPE).getRecordTypeId();
        Account patient = new Account(RecordTypeId = recordTypeId, FirstName = firstName, LastName = lastName);
        if (doInsert) {
            insert patient;
        }
        return patient;
    }

    /**
     * @param patientId patient (Person Account) Id
     * @param status enrollment status
     * @param enrollmentDate enrollment date
     * @param doInsert insert the record when true
     * @return a Zenthera program enrollment
     */
    public static Program_Enrollment__c createEnrollment(Id patientId, String status, Date enrollmentDate, Boolean doInsert) {
        Program_Enrollment__c enrollment = new Program_Enrollment__c(
            Patient__c = patientId,
            Program__c = 'Zenthera Patient Support Program',
            Therapy__c = 'Zenthera 50 mg',
            Status__c = status,
            Enrollment_Date__c = enrollmentDate,
            Insurance_Type__c = 'Commercial',
            Consent_Given__c = true,
            Consent_Date__c = enrollmentDate
        );
        if (doInsert) {
            insert enrollment;
        }
        return enrollment;
    }

    /**
     * @param enrollmentId enrollment Id
     * @param dispenseDate dispense date
     * @param daysSupply days supply
     * @param status dispense status
     * @return an uninserted dispense
     */
    public static Dispense__c buildDispense(Id enrollmentId, Date dispenseDate, Integer daysSupply, String status) {
        return new Dispense__c(
            Program_Enrollment__c = enrollmentId,
            Dispense_Date__c = dispenseDate,
            Days_Supply__c = daysSupply,
            Pharmacy__c = 'Test Specialty Pharmacy',
            Status__c = status
        );
    }

    /**
     * Creates the helper record that the existing SDO Case flow ("SDO Service - Case - On Create")
     * reads before it calls its Einstein demo action. Apex tests cannot see org data, so without
     * this record every Case insert in a test fails with "Missing required input parameter: helperConfig".
     * The rule never matches a PSP case subject, so it changes nothing on the Case.
     * Test data only: it is rolled back after each test. No SDO automation is switched off.
     * @return the inserted helper record
     */
    public static SDO_Service_Einstein_Agent_Helper__c createSdoCaseAutomationFixture() {
        SDO_Service_Einstein_Agent_Helper__c helper = new SDO_Service_Einstein_Agent_Helper__c(
            Active__c = true,
            Field__c = 'Subject',
            Comparator__c = 'CONTAINS',
            Value__c = SDO_HELPER_NO_MATCH_VALUE
        );
        insert helper;
        return helper;
    }

    /**
     * @param patientId patient (Person Account) Id
     * @param subject case subject
     * @param status case status, for example New or Working
     * @param priority case priority, for example Medium or High
     * @return an uninserted Case
     */
    public static Case buildCase(Id patientId, String subject, String status, String priority) {
        return new Case(
            AccountId = patientId,
            Subject = subject,
            Status = status,
            Priority = priority,
            Origin = 'Phone'
        );
    }
}
