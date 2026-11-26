# Technical Design Document (TDD): Patient Support Program (PSP) on Salesforce Headless 360

A running record of what is built for the PSP demo, why, and its current status. Every new object, Flow, Apex class, prompt, agent or MCP tool gets an entry here.

- **Org:** ProductPillarSDO (`sanduvyshnavi@kpmg.com.sdo`, Org ID `00DgL00000hTCjNUAW`; CLI aliases `ProductPillarSDO` and `ProductPillarSDO1` both point to it), a production-type SDO. Every deploy, activation and data change is approved first.
- **Project:** Salesforce DX, API 68.0, source in `force-app/main/default`
- **Data:** synthetic only. Zenthera is a fictional drug, and all patients, prescribers and pharmacies are fictional. No real patient data (PHI) is used.
- **Safety:** a possible adverse event is only logged as a Case for human pharmacovigilance review; nothing is reported to a regulator automatically, and no clinical advice is given.

---

## 1. Purpose and scope

A pharma company runs a patient support program for its specialty drug, Zenthera. A **Patient Services Coordinator** enrolls patients, tracks refills, answers eligibility questions, spots possible adverse events and hands cases over to the care team.

The demo shows that the coordinator can do all of this **from Slack**, through Slackbot or an Agentforce agent, without opening Salesforce. The same work can still be done manually in the **Patient Support Program** Lightning app.

**Front door:** Slack only. External AI clients (Claude, ChatGPT, Microsoft Teams, Perplexity, Gemini) are blocked at KPMG and are out of scope.

## 2. Architecture

| Layer | Product | Role in PSP |
|---|---|---|
| System of Engagement | Slack (Slackbot, channels, canvas) | Where the coordinator asks and acts |
| System of Agency | Agentforce | Patient Services Agent reasons and calls actions |
| System of Work | Customer 360 (this org) | Patient data, Flow, Apex, Named Query, prompt templates |
| System of Context | Data 360 | Program FAQ PDF for grounded answers (RAG) |

```
 Coordinator
   ├── Salesforce app (manual) ───────────────────────┐
   ├── Slackbot ──┬─▶ PSP Patient Services MCP ───────┤  Enroll (Flow) · Refill History (Apex)
   │              ├─▶ PSP Named Query MCP ────────────┤  Patient 360 (Named Query)
   │              ├─▶ PSP Case MCP ───────────────────┤  Create Service Case (Flow)
   │              └─▶ PSP Program FAQ MCP ────────────┤  Answer Program Question (Flow → Prompt → Data 360)
   └── Patient Services Agent (Agentforce) ───────────┤
                                                      ▼
   Flow: Enroll Patient, Create Service Case, Answer Program Question · Apex: Refill History
   Named Query: Patient 360 · Prompt + Data 360 retriever: Program FAQ · Prompt: Handoff Summary (planned)
                                                      ▼
   Person Account ─< Program Enrollment ─< Dispense
   Person Account ─< Case
```

**Request path:** Coordinator asks in Slack → Slackbot picks a tool from its description → Salesforce hosted MCP server (signed in as the user, so sharing and field security apply) → Flow, Apex, Named Query, prompt or agent runs → Slackbot formats the result.

Three custom MCP servers: **PSP Patient Services MCP** holds the Enroll (Flow) and Refill History (Apex) tools; **PSP Named Query MCP** holds only the Patient 360 Named Query tool (workaround, see section 4.12); **PSP Case MCP** holds only the Create Service Case Flow tool (see section 4.13). The two extra servers were created in Setup by the user, with tools added in Setup and not edited by metadata. The same Flow, Apex and prompt are reused as Agentforce actions, so each piece of logic is built once.

## 3. Component register

**Status values:** Planned → Built locally → Validated in org → Deployed → Active

| # | Component | Type | API name / file | Status | Date |
|---|---|---|---|---|---|
| 1 | Program Enrollment | Custom Object, 9 fields | `objects/Program_Enrollment__c/` | Deployed, data model verified | 2026-11-17 |
| 2 | Dispense | Custom Object, 5 fields | `objects/Dispense__c/` | Deployed, data model verified | 2026-11-17 |
| 3 | Program Enrollment and Dispense tabs | Custom Tabs | `tabs/Program_Enrollment__c.tab-meta.xml`, `tabs/Dispense__c.tab-meta.xml` | Deployed | 2026-11-17 |
| 4 | PSP Patient Services | Permission Set | `permissionsets/PSP_Patient_Services.permissionset-meta.xml` | Deployed, assigned to the demo user | 2026-11-17 |
| 5 | Patient Support Program | Lightning App | `applications/Patient_Support_Program.app-meta.xml` | Deployed | 2026-11-17 |
| 16 | Program Enrollment Layout | Page Layout (PSP) | `layouts/Program_Enrollment__c-Program Enrollment Layout.layout-meta.xml` | Deployed, verified through UI API | 2026-11-17 |
| 17 | Dispense Layout | Page Layout (PSP) | `layouts/Dispense__c-Dispense Layout.layout-meta.xml` | Deployed, verified through UI API | 2026-11-17 |
| 18 | Person Account Layout: Program Enrollments related list | Change to an existing shared Page Layout | `layouts/PersonAccount-Person Account Layout.layout-meta.xml` | Deployed, verified through UI API | 2026-11-17 |
| 19 | Person Account Layout: Birthdate and Mobile fields | Change to an existing shared Page Layout | `layouts/PersonAccount-Person Account Layout.layout-meta.xml` | Deployed, verified through UI API | 2026-11-17 |
| 20 | PSP Patients | List View on Account | `objects/Account/listViews/PSP_Patients.listView-meta.xml` | Deployed, verified through UI API | 2026-11-17 |
| 21 | PSP Patient | Compact Layout on Person Account, assigned to record type Person Account | `objects/PersonAccount/compactLayouts/PSP_Patient.compactLayout-meta.xml`, `objects/PersonAccount/recordTypes/PersonAccount.recordType-meta.xml` | Deployed, verified through UI API | 2026-11-17 |
| 6 | Synthetic demo data | Data (5 patients, 5 enrollments, ~15 dispenses, ~6 cases) | Seed script | Planned | |
| 7 | PSP Enroll Patient | Autolaunched Flow (MCP tool, agent action) | `flows/PSP_Enroll_Patient.flow-meta.xml` | Active, tested | 2026-11-17 |
| 8 | PSP Get Refill History | Global invocable Apex + test class + test data factory | `classes/PSP_RefillHistoryTool.cls`, `PSP_RefillHistoryToolTest.cls`, `PSP_TestDataFactory.cls` | Deployed, tests 16/16, coverage 94%; MCP tool `psp_get_refill_history` Slackbot TESTED (2026-11-17) | 2026-11-17 |
| 9 | PSP Patient 360 | Named Query (API Named Query) | `apiNamedQueries/PSPPatient360.apiNamedQuery-meta.xml` | Deployed, REST tested, API Catalog action active; MCP tool on PSP Named Query MCP, Slackbot TESTED (2026-11-17) | 2026-11-17 |
| 10 | Care Team Handoff Summary | Flex Prompt Template (MCP tool) | `genAiPromptTemplates/` | Planned | |
| 11 | Program FAQ answers | Agentforce Data Library `PSP_FAQ` (Data 360) + Flex Prompt Template with retriever + Autolaunched Flow (MCP tool, agent action) | `docs/program-faq/`, `genAiPromptTemplates/PSP_Program_FAQ_Answer.genAiPromptTemplate-meta.xml`, `flows/PSP_Answer_Program_Question.flow-meta.xml` | Library READY; template and Flow deployed, backend tests 7/7; Slackbot TESTED (2026-11-18) | 2026-11-18 |
| 25 | PSP Program FAQ MCP (Answer Program Question) | Custom MCP Server | `mcpServerDefinitions/PSPProgramFAQMCP.mcpServerDefinition-meta.xml` | Deployed and active (access record created by API); tested from Slackbot | 2026-11-18 |
| 12 | PSP Patient Services MCP (Enroll, Refill History) | Custom MCP Server | `mcpServerDefinitions/PSPPatientServicesMCP.mcpServerDefinition-meta.xml` (retrieved after the user's Setup change) | Active; Enroll and Refill tested from Slackbot. The case tool was removed by the user | 2026-11-17 |
| 22 | PSP Named Query MCP (Patient 360) | Custom MCP Server (created in Setup by the user) | `mcpServerDefinitions/PSPNamedQueryMCP.mcpServerDefinition-meta.xml` (retrieved) | Active, tested from Slackbot | 2026-11-17 |
| 23 | PSP Create Service Case | Autolaunched Flow (MCP tool) | `flows/PSP_Create_Service_Case.flow-meta.xml` | Active (v2), backend tested; MCP tool on PSP Case MCP, Slackbot TESTED (2026-11-17) | 2026-11-17 |
| 24 | PSP Case MCP (Create Service Case) | Custom MCP Server (created in Setup by the user) | `mcpServerDefinitions/PSPCaseMCP.mcpServerDefinition-meta.xml` (retrieved) | Active, tested from Slackbot | 2026-11-17 |
| 26 | PSP Exceptions MCP (Get Program Exceptions, Check Duplicate Case) | Custom MCP Server, 2 read-only Apex tools | `mcpServerDefinitions/PSPExceptionsMCP.mcpServerDefinition-meta.xml` | Deployed and active (access record created by API); Get Program Exceptions tested from Slackbot (2026-11-19); duplicate check not yet tested in Slack | 2026-11-19 |
| 27 | PSP Medication Support Agent | Agentforce employee agent (Agent Script), read-only | `aiAuthoringBundles/PSP_Medication_Support_Agent/` | Active v3; preview tested (Phase 2); Coworker delegation tested (Phase 3) | 2026-11-19 |
| 28 | PSP Program Knowledge Agent | Agentforce employee agent (Agent Script), read-only | `aiAuthoringBundles/PSP_Program_Knowledge_Agent/` | Active v3; preview tested (Phase 2); Coworker delegation tested (Phase 3) | 2026-11-19 |
| 29 | PSP Care Resolution Agent | Agentforce employee agent (Agent Script); since v5 one write action (approved case) | `aiAuthoringBundles/PSP_Care_Resolution_Agent/` | Active v8 (AI handoff via flow; platform confirmation on the create action); before: v7, v6, v4; preview tested (Phase 2); Coworker delegation tested (Phase 3) |
| 30 | PSP Specialist Agent Access | Permission set (Agent Access only) | `permissionsets/PSP_Specialist_Agent_Access.permissionset-meta.xml` | Deployed, assigned to deepshikhaheadless@kpmg.com only | 2026-11-19 | 2026-11-19 |
| 31 | PSP Create Approved Case | Invocable Apex (write, only with userConfirmed; duplicate guard first) + test | `classes/PSP_CreateApprovedCase.cls` | Deployed, Apex tested; used by PSP Care Resolution Agent v7 (platform confirmation); live test in Coworker created case 00001124 after approval | 2026-11-19 |
| 32 | PSP Prepare Care Team Handoff | Invocable Apex (read-only, fixed sections) + test | `classes/PSP_CareTeamHandoff.cls` | Deployed, Apex and agent tested | 2026-11-19 |
| 33 | Demo pre-flight script | Anonymous Apex, read-only | `scripts/apex/psp-demo-preflight.apex` | Run 2026-11-22, PASS (4 duplicate checks) | 2026-11-22 |
| 34 | Demo script (Program Exceptions Desk) | Document | `docs/Demo-Script-Program-Exceptions-Desk.md` | Ready; rehearsal pending | 2026-11-19 |
| 35 | HXL Program Exceptions Worklist card | Apex output type + invocable, LightningTypeBundle `pspExceptionsWorklist`, UiWidgetBundle `pspExceptionsWorklistCard` | `classes/PSP_ExceptionsWorklistCard*.cls`, `lightningTypes/pspExceptionsWorklist/`, `uiWidgets/pspExceptionsWorklistCard/` | Deployed; on PSP Medication Support Agent v6; **renders in the Lightning Agentforce panel and in Coworker** (T5-1, T5-4 PASS) | 2026-11-22 |
| 36 | PSP Care Team Handoff Summary | Prompt template (Flex, input `facts`), active version 2 | `genAiPromptTemplates/PSP_Care_Team_Handoff_Summary.genAiPromptTemplate-meta.xml` | Deployed; 22 checked runs, 0 issues | 2026-11-22 |
| 37 | PSP Care Team Handoff Summary (flow) | Autolaunched Flow: Apex facts → prompt template, fallback to facts | `flows/PSP_Care_Team_Handoff_Summary.flow-meta.xml` | Active; used by PSP Care Resolution Agent v8; Coworker tested (ENR-0018) | 2026-11-22 |
| 38 | PSP Handoff MCP (Care Team Handoff Summary) | Custom MCP Server, 1 read-only Flow tool | `mcpServerDefinitions/PSPHandoffMCP.mcpServerDefinition-meta.xml` | Deployed and active (access record created by API); tested from Slackbot (ENR-0018) | 2026-11-22 |
| 13 | Patient Services Agent | Agentforce Employee Agent (also an MCP tool and a Slack app) | Agent Script bundle | Planned | |
| 14 | Refill timeline widget | HXL Lightning Types + UI Widget | `lightningTypes/`, `uiWidgets/` | Planned, at risk (see 6.2) | |
| 15 | Patient Profile API | Apex REST + External Service Registration | `classes/`, `externalServiceRegistrations/` | Optional | |

## 4. Built components

### 4.1 Data model

Patients are standard **Person Accounts** (record type **Person Account**, `PersonAccount`). Patient service requests are standard **Cases**, linked to the patient through `AccountId`.

```
Account (Person Account = Patient)
 ├─< Program_Enrollment__c (Patient__c)
 │     └─< Dispense__c (Program_Enrollment__c, master-detail)
 └─< Case (AccountId)
```

**Program_Enrollment__c**: one record per patient per program. Name is an Auto Number `ENR-{0000}` (label Enrollment ID). Sharing ReadWrite. Reports, search, activities and field history enabled.

| Field | Type | Notes |
|---|---|---|
| `Patient__c` | Lookup(Account) | Lookup filter allows Person Accounts only. Delete constraint Restrict. Relationship `Program_Enrollments` |
| `Program__c` | Picklist (restricted) | Zenthera Patient Support Program (default) |
| `Therapy__c` | Picklist (restricted) | Zenthera 50 mg, Zenthera 100 mg |
| `Status__c` | Picklist (restricted) | Enrolled (default), Active, On Hold, Discontinued |
| `Enrollment_Date__c` | Date | |
| `Prescriber_Name__c` | Text(80) | |
| `Consent_Given__c` | Checkbox | Default false. Enrollment through the flow is refused without consent |
| `Consent_Date__c` | Date | |
| `Insurance_Type__c` | Picklist (restricted) | Commercial, Medicare, Medicaid, Uninsured. Drives copay eligibility |

**Dispense__c**: one record per therapy shipment. Name is an Auto Number `DSP-{0000}` (label Dispense ID). Sharing ControlledByParent.

| Field | Type | Notes |
|---|---|---|
| `Program_Enrollment__c` | Master-Detail(Program_Enrollment__c) | Relationship `Dispenses` |
| `Dispense_Date__c` | Date | |
| `Days_Supply__c` | Number(3,0) | Next refill due = Dispense Date + Days Supply |
| `Pharmacy__c` | Text(80) | |
| `Status__c` | Picklist (restricted) | Shipped (default), Delivered, Delayed, Cancelled |

### 4.2 Permission set: PSP Patient Services

- Create, read, edit and delete on Program Enrollment and Dispense (no View All, no Modify All)
- Read and edit on all 13 non-required custom fields (the master-detail field is always required, so it is not listed)
- Program Enrollments and Dispenses tabs: Visible
- Patient Support Program app: visible
- User permission **Run Flows** (added in Step 5 so non-admin coordinators can run PSP Enroll Patient from Slackbot or the agent; deploy `0AfgL00000eDGVdSAO`)
- Assigned to the demo user (`sanduvyshnavi@kpmg.com.sdo`) on 2026-11-17

### 4.3 Lightning App: Patient Support Program

Standard navigation, desktop and phone, header colour `#1B5E8C`. Tabs: Home, Accounts (patients), Program Enrollments, Dispenses, Cases, Reports. Visible through the PSP Patient Services permission set. No custom record pages yet (standard layouts).

### 4.4 Deployment and verification (2026-11-17)

| Check | Result |
|---|---|
| Check-only validation, 20 components | Passed, 0 errors (`0AfgL00000eCiKpSAK`) |
| Deploy, 20 components | Succeeded, 20/20 (`0AfgL00000eCWwOSAW`) |
| Permission set assigned to demo user | Done |
| Objects, fields, Auto Number names, lookup and master-detail in the org | Correct |
| Object permissions (CRED, no View All / Modify All), 13 field permissions, 2 tabs, app visible | Correct |
| Picklist values | **Defect:** Therapy, Status (both objects) and Insurance Type were created with all values joined into one value (for example `Commercial;Medicare;Medicaid;Uninsured`), and the Enrolled and Shipped defaults were not set. Cause: the shell used to generate the files did not split the value list. Fixed locally, validated (`0AfgL00000eCKaGSAW`) and redeployed 4/4 (`0AfgL00000eCesJSAS`). Verified: each picklist now has separate values, Enrolled and Shipped are defaults, and no old joined value remains. |
| Record-level test, anonymous Apex inside a savepoint that is rolled back (script `.sfdx/tmp/anon-1794864423.apex`) | **5/5 passed:** defaults correct; enrollment numbered `ENR-0001`; dispense numbered `DSP-0001` and linked; business account rejected as Patient (lookup filter message shown); patient with an enrollment cannot be deleted. Rollback confirmed: 0 enrollments and 0 test accounts remain. Auto Numbers are not reset by a rollback, so the first real records will be `ENR-0002` and `DSP-0002`. |
| Page layouts | **Gap:** the auto-created Program Enrollment Layout and Dispense Layout contain no PSP custom fields, the enrollment layout has no Dispenses related list, and the Person Account Layout (used by the System Administrator profile for the Person Account record type) has no Program Enrollments related list. The manual app steps cannot be completed until layouts are updated. |

### 4.5 Page layouts (Step 3)

**Program Enrollment Layout** (auto-created by Salesforce, owned by PSP)
- Section **Enrollment**: left: Enrollment ID (read only), Patient (required on the page), Program, Therapy, Status; right: Enrollment Date, Prescriber Name, Insurance Type, Owner, Currency
- Section **Consent**: Consent Given, Consent Date
- System Information section and Custom Links kept as they were
- Related lists: **Dispenses** (new, first; columns Dispense ID, Dispense Date, Days Supply, Pharmacy, Status; newest first), then the existing Open Activities and Activity History

**Dispense Layout** (auto-created, owned by PSP)
- Information section: Program Enrollment (required, kept), Dispense ID (kept), Dispense Date, Days Supply | Pharmacy, Status, Currency (kept)
- System Information, Custom Links and the mini layout kept as they were

**Person Account Layout** (existing shared layout)
- Only change: one related list, **Program Enrollments** (relationship `Program_Enrollment__c.Patient__c`), added after the last existing related list; columns Enrollment ID, Program, Therapy, Status, Enrollment Date, Insurance Type; newest first
- Verified before deployment: with the new block removed, the file is identical to the org version; all 14 fields, 6 sections, 6 existing related lists (in the same order), buttons, actions and page flags are unchanged

**Design decision: shared layout change instead of an app-specific record page.** In the Patient Support Program app, Person Accounts open the org default Account record page `SDO_Account_Default`, whose related lists come from the page layout (`force:relatedListContainer`). An app-specific alternative was possible: a copy of `SDO_Account_Default` with an extra related-list component, assigned only in the PSP app. It was not chosen because it is more complex (a second 9 KB page with SDO and third-party components to keep in sync) while the layout change is one additive block. The impact of the layout change is small because Salesforce hides a related list from users who cannot read its object.

**Impact assessment**
| Item | Finding |
|---|---|
| Profiles using the Person Account Layout | About 73 profiles for the Person Account record type and 69 for SDO Person Accounts; about 76 active users |
| Who will see the new related list | Only users who can read Program Enrollment: the System Administrator profile (11 active users), PSP Patient Services permission set holders, and a few integration/system profiles. Everyone else sees no change |
| Lightning record pages | `SDO_Account_Default` (org default for Account) shows the layout’s related lists, so the new list appears there; the page itself is not changed |
| Record type and profile layout assignments | Not changed |

**Backup and rollback:** the org versions of all three layouts and of `SDO_Account_Default`, as they were before Step 3, are saved in `backups/step3-layouts-2026-11-17/`. Rollback = deploy those backup layout files (`sf project deploy start --source-dir backups/step3-layouts-2026-11-17/layouts --target-org ProductPillarSDO1`). This removes the related list and the added fields from the pages; no data is affected.

**Validation:** check-only deployment of the 3 layouts passed, 3/3, 0 errors (`0AfgL00000eCxuvSAC`).

**Deployment (2026-11-17):** `0AfgL00000eCnVmSAK`, Succeeded, 3/3 components, 0 errors. Pre-deployment checks: org ID confirmed as `00DgL00000hTCjNUAW`; backups present; diff unchanged from the approved one (Person Account Layout +11 lines, 0 removed); org layouts had not drifted from the backup. The deploy report lists only the three layouts as changed. A copy of the layouts as deployed is in `backups/step3-layouts-2026-11-17-after-deploy/`.

**Post-deployment verification**
| Check | Method | Result |
|---|---|---|
| Program Enrollment Layout: all 9 PSP fields, Enrollment and Consent sections, Patient required, existing fields kept | Metadata retrieve + UI API (View and Create) as the demo user | Passed |
| Program Enrollment related lists: Dispenses (Dispense ID, Dispense Date, Days Supply, Pharmacy, Status; newest first), Open Activities, Activity History | UI API related-list-info | Passed |
| Dispense Layout: Dispense Date, Days Supply, Pharmacy, Status present; Program Enrollment still required | Metadata retrieve + UI API (Create) | Passed |
| Person Account Layout: Program Enrollments related list present (Enrollment ID, Program, Therapy, Status, Enrollment Date, Insurance Type) | Metadata retrieve + UI API for record type Person Account | Passed |
| Person Account Layout: 14 existing fields, 6 sections, 6 previous related lists (same order), buttons, actions and flags | Compared with the pre-deployment backup | Unchanged |
| Layout assignments | `ProfileLayout` for the Person Account Layout: 148 rows before and after, identical; PSP layouts assigned to 73 profiles each | Unchanged |
| `SDO_Account_Default` record page | Retrieved and compared with the backup | Unchanged |
| Other metadata | Only these three layouts were modified in the deployment window; non-PSP flows and MCP servers have their earlier modified dates | Unchanged |
| Object and field visibility for the demo user | UI API returns every PSP field on the layouts; describe shows all PSP fields createable | Passed |
| Record pages on screen (open an enrollment, a dispense and a patient) | Not possible: no records exist and no demo data may be created yet | **PENDING MANUAL UI VERIFICATION** |

**Notes and remaining limitations**
- After deployment Salesforce set `customLabel` to `true` on the Enrollment and Consent sections (normal for custom section names). The local file was synced to the org version.
- The Person Account Layout has no Birthdate or Mobile field (it shows Salutation, First Name, Last Name, Phone, Fax, Website and address fields). Patients can be created without them. If the enrollment flow is to match patients by date of birth, either the fields are set by the flow only, or `PersonBirthdate` and `PersonMobilePhone` are added to the shared layout (a further change that needs approval).
- Section 4.4’s layout gap is closed by this step.

### 4.6 Person Account Layout: Birthdate and Mobile (Step 4A)

**Why:** patient registration and the future enrollment process need the patient’s date of birth and mobile number on the patient page.

**Change (only this):** two standard fields added to the **Account Information** section of the existing Person Account Layout, both editable and not required:
- **Birthdate** (`PersonBirthdate`), left column, directly under Name
- **Mobile** (`PersonMobilePhone`), right column, directly under Phone

**Checks before deployment**
| Check | Result |
|---|---|
| Fields exist and are standard | `PersonBirthdate` (Date, label Birthdate), `PersonMobilePhone` (Phone, label Mobile) |
| Demo user access | Both createable and updateable; Account createable and updateable |
| Org layout compared with the Step 3 deployed copy | Identical (no drift) |
| Diff | 8 lines added (two layout items), 0 removed |
| Preservation | 14 existing fields in the same order; 7 related lists and their columns identical; section labels, buttons, actions and flags identical; removing the two new items gives the org file exactly |
| Check-only validation | Passed, 1/1, 0 errors (`0AfgL00000eCGRmSAO`) |

**Impact on shared-layout users:** the layout serves the Person Account record type for about 78 profiles (76 active users). Field-level security for these fields comes from Contact Birthdate and Contact Mobile; 70 of the 76 active users can read and edit them, so they will see two extra optional fields on Person Account pages that use this layout. No field becomes required, nothing is removed or moved apart from the two insertions, and record type and layout assignments are not changed.

**Backup and rollback:** the layout as it was before this step is in `backups/step4a-person-account-layout-2026-11-17/`. Rollback = `sf project deploy start --source-dir "backups/step4a-person-account-layout-2026-11-17/layouts" --target-org ProductPillarSDO1`. This removes the two fields from the page only; any values already saved in the fields stay in the records.

**Deployment (2026-11-17):** `0AfgL00000eD51FSAS`, Succeeded, 1/1 component, 0 errors. Pre-deployment checks: org ID confirmed; backup present; no drift between the org and the backup; diff contained only the approved 8 added lines. The deploy report lists only the Person Account Layout as changed. A copy of the layout as deployed is in `backups/step4a-person-account-layout-2026-11-17-after-deploy/`.

**Post-deployment verification**
| Check | Method | Result |
|---|---|---|
| Birthdate and Mobile in the layout metadata | Metadata retrieve; org file equals the approved local file | Passed. Account Information order: Owner, Name, Birthdate / Phone, Mobile, Fax, Website |
| Create and Edit forms for the demo user | UI API layout for Account, record type Person Account, modes Create and Edit | Passed. Both fields present on both forms (28 fields in total) |
| Editable and optional | UI API: `required` false, `editableForNew` true, `editableForUpdate` true for both fields | Passed |
| 14 existing fields, 7 related lists with their columns, 6 sections, buttons, actions and flags | Compared with the pre-deployment backup; related lists also checked through the UI API | Unchanged |
| Layout assignments | `ProfileLayout`: 148 rows before and after, identical | Unchanged |
| Other metadata | Program Enrollment Layout, Dispense Layout and `SDO_Account_Default` identical to their Step 3 copies; non-PSP flows and MCP servers keep their earlier modified dates | Unchanged |
| Record page on screen (open or create a patient) | Not possible: no records exist and none may be created yet | **PENDING MANUAL UI VERIFICATION** |

**Status:** deployed and verified through metadata and the UI API.

### 4.7 Patient list and patient page fixes (POC mode)

From this point the project is run as an RFP demo / POC: changes are kept simple, validated once and deployed directly, without extended impact analysis or separate backups.

**Issues reported**
1. In the Patient Support Program app the Accounts tab showed sales accounts as well as patients.
2. Birthdate and Mobile were not seen on the patient page although both fields were deployed.

**Findings**
- The Accounts tab opens the standard list views, which include all account record types.
- For the real patient record, Salesforce was already returning the layout that contains Birthdate and Mobile (checked through the UI API on the record). The record was created at 21:45 UTC and the fields were deployed at 21:55 UTC, so the page was seen before the deployment or from a cached layout. The fields were also only in the Details tab, not in the strip at the top of the page.
- Sample person accounts from the SDO use the record type Person Accounts (`SDO_PersonAccounts`, 30 records); PSP patients use Person Account (`PersonAccount`).

**Fixes (standard Salesforce features only)**
| Fix | Detail |
|---|---|
| List view **PSP Patients** on Account | Filter: record type equals Person Account. Columns: Account Name, Birthdate, Mobile, Phone, Account Owner Alias. Visible to all users. Users pin it once so the Accounts tab opens on it |
| Compact layout **PSP Patient** | Name, Birthdate, Mobile, Phone; assigned to the record type Person Account only, so these show in the strip at the top of the patient page. The SDO record type keeps its own compact layout |
| Person Account Layout | Related lists reordered: Program Enrollments first, Cases second, then the others unchanged |

**Deployment:** check-only validation passed (`0AfgL00000eCbMaSAK`, 4/4); deployed `0AfgL00000eDAIfSAO`, Succeeded, 4/4, 0 errors (record type changed, compact layout created, list view created, layout changed).

**Tests in the org (UI API, as the demo user, on the real patient record)**
| Test | Result |
|---|---|
| PSP Patients list view: columns and filter | Passed; returns 1 record (the one existing patient), no sales accounts |
| Patient page top strip (compact layout) | Name, Birthdate, Mobile, Phone |
| Patient page Details tab, Account Information | Owner, Name, Birthdate, Phone, Mobile, Fax, Website |
| Related lists order | Program Enrollments, Cases, Open Activities, Activity History, Opportunities, Partners, Notes & Attachments |
| SDO person accounts (other record type) | Compact layout unchanged |
| On-screen check by a user | Pending |

**Limitation:** a list view cannot be pinned for a user through metadata; each user pins PSP Patients once (one click).

### 4.8 Manual UI test in Salesforce (2026-11-17)

The user clicked through the Salesforce-app steps of the User Guide on screen. Evidence found in the org afterwards:

| Use case | Evidence | Result |
|---|---|---|
| 1. Enroll a new patient | Patient **Sonali Singh** (Person Account record type) and enrollment **ENR-0003** (Zenthera 50 mg, Enrolled, Consent Given, Commercial) | Passed |
| 2. Check refills and adherence | Dispense **DSP-0002** on ENR-0003 (Dispense Date 2026-11-16, 30 days, Shipped), shown in the Dispenses related list | Passed |
| 3. See a patient’s full profile | Patient page with PSP Patients list, top strip, Program Enrollments and Cases related lists | Passed |
| 4. Log a service case | Case **00001068** (Subject “allergy”, Origin Website, Status New) on patient Sonali Singh, created from the patient’s Cases related list | Passed |

**Finding:** the record type picker defaults to **Account** (the System Administrator profile default). Choosing it gives a business account form without Birthdate and Mobile; choosing **Person Account** gives the right form (confirmed on screen through `/lightning/o/Account/new?recordTypeId=012gL000006oRqiQAE`). Both existing test patients were saved without Birthdate and Mobile. Recorded in the User Guide as a tip; a "New Patient" tab that skips the picker was offered.

### 4.9 Flow: PSP Enroll Patient (Step 5)

**API name:** `PSP_Enroll_Patient` · **Type:** Autolaunched Flow (no trigger) · **Status:** Active · **Runs as:** the calling user (default mode), so sharing and field security apply

**Purpose:** one reusable enrollment action. The same flow will be called by the Patient Services Agent (directly, as an agent action) and by Slackbot (through the PSP MCP server). The manual app workflow is unchanged.

**Inputs**
| Name | Type | Required | Rule |
|---|---|---|---|
| `firstName` | Text | Yes | max 40 |
| `lastName` | Text | Yes | max 80 |
| `birthdate` | Date | Yes | YYYY-MM-DD, not in the future |
| `mobilePhone` | Text | No (recommended) | max 40; used to tell matches apart |
| `therapy` | Text | Yes | exactly `Zenthera 50 mg` or `Zenthera 100 mg` |
| `prescriberName` | Text | No | max 80 |
| `insuranceType` | Text | Yes | `Commercial`, `Medicare`, `Medicaid` or `Uninsured` |
| `consentGiven` | Boolean | Yes | must be true; blank counts as false |

**Outputs**
| Name | Meaning |
|---|---|
| `isSuccess` | true only when an enrollment was created |
| `resultCode` | `SUCCESS`, `VALIDATION_ERROR`, `NO_CONSENT`, `AMBIGUOUS_MATCH`, `DUPLICATE_ENROLLMENT`, `ERROR` |
| `resultMessage` | plain-language result for the user |
| `patientId` | patient (Person Account) Id |
| `enrollmentId` | created enrollment Id, or the existing open one for a duplicate |
| `enrollmentNumber` | `ENR-…` |
| `patientStatus` | `NEW_PATIENT` or `EXISTING_PATIENT` |

**Flow architecture**
```
Check Inputs ──invalid──▶ VALIDATION_ERROR
     │──no consent──▶ NO_CONSENT
     ▼
Find patients: first name + last name + full birthdate (Person Accounts)
     ├─ 0 found ─▶ same name with NO birthdate on file? ─yes─▶ AMBIGUOUS_MATCH
     │                                                   └no─▶ create Person Account (record type Person Account)
     ├─ 1 found ─▶ different mobile on file? ─yes─▶ AMBIGUOUS_MATCH
     │                                       └no─▶ use it
     └─ 2+ found ─▶ mobile given and exactly 1 has it? ─yes─▶ use it
                                                     └no─▶ AMBIGUOUS_MATCH
Existing patient ─▶ open enrollment (not Discontinued; Program = Zenthera or blank)? ─yes─▶ DUPLICATE_ENROLLMENT
     ▼
Create Program Enrollment ─fault─▶ (patient created in this run? delete it) ─▶ ERROR
     ▼
Read ENR number ─▶ SUCCESS
```

**Business rules**
| # | Rule |
|---|---|
| F-1 | Required: first name, last name, birthdate, therapy, insurance type; values must be allowed picklist values |
| F-2 | No enrollment without consent; nothing is created |
| F-3 | A patient is matched on first name + last name + full birthdate, never on birthdate alone. Name comparison is case-insensitive |
| F-4 | Mobile, when given, separates several matches; a single match with a different mobile on file is treated as ambiguous |
| F-5 | A same-name patient without a birthdate on file is treated as a possible match (ambiguous) |
| F-6 | Ambiguous matches create nothing and ask for human review |
| F-7 | A patient can have only one open enrollment (Enrolled, Active or On Hold) in the program. Manual enrollments with a blank Program also count |
| F-8 | New enrollment: Program = Zenthera Patient Support Program, Status = Enrolled, Enrollment Date and Consent Date = today, Consent Given = true |
| F-9 | New patients get the Person Account record type (looked up by developer name), birthdate and mobile |

**Error handling**
- Validation, consent, ambiguity and duplicate outcomes stop before any record is written.
- Create Patient fails → `ERROR`, nothing saved.
- Create Enrollment fails → if the patient was created in this run it is deleted again (no partial patient); then `ERROR`. If that delete also fails → `ERROR` with the patient Id so an admin can check.
- Reading the ENR number after creation fails → still `SUCCESS` (enrollment exists), number blank.
- The tool description tells callers never to retry automatically after `ERROR`.

**Build note:** the Salesforce flow-generation MCP service (salesforce-metadata-experts) was unavailable in this session (connection error), so the flow XML was written by hand in the same format as the project’s earlier flow and checked by check-only deployment before deploying.

**Validation and deployment**
| Run | ID | Result |
|---|---|---|
| Check-only | `0AfgL00000eChIJSA0` | Passed |
| Deploy (version 1) | `0AfgL00000eDHTpSAO` | Succeeded, Active |
| Check-only (duplicate rule now also counts blank Program) | `0AfgL00000eDAKISA4` | Passed |
| Deploy (version 2) | `0AfgL00000eDCp8SAG` | Succeeded, Active (active version = latest) |

**Tests** (flow called through the REST invocable-action endpoint `/actions/custom/flow/PSP_Enroll_Patient`, the same entry point MCP and Agentforce use; fictional data)
| Scenario | Result code | Records | Result |
|---|---|---|---|
| A. New patient with consent | `SUCCESS`, `NEW_PATIENT`, ENR-0004 | Patient and enrollment created with all fields correct | Passed |
| B. Consent missing | `NO_CONSENT` | Nothing created | Passed |
| C. Same patient again | `DUPLICATE_ENROLLMENT` (returns ENR-0004) | No second enrollment | Passed (re-run on version 2: passed) |
| C2. Existing enrollment with blank Program | `DUPLICATE_ENROLLMENT` | No second enrollment | Passed (version 2) |
| D. Existing patient, no enrollment | `SUCCESS`, `EXISTING_PATIENT`, ENR-0005 | Existing patient reused, enrollment created | Passed |
| E1. Two patients, same name and birthdate, no mobile | `AMBIGUOUS_MATCH` | Nothing created | Passed |
| E2. Same name exists with no birthdate (real patient Sonali Singh) | `AMBIGUOUS_MATCH` | Nothing created | Passed |
| E3. One match, different mobile on file | `AMBIGUOUS_MATCH` | Nothing created | Passed |
| V. Missing birthdate, invalid therapy | `VALIDATION_ERROR` listing both problems | Nothing created | Passed |
| Enrollment-failure cleanup path | — | — | Not tested (no safe way to force the failure) |

**Clean-up:** all test records (last name “FlowTest”: 5 patients, 3 enrollments) were deleted. Real records (Sonali Singh, DEEPSHIKHA VERMA, ENR-0003) were not touched. Auto Numbers are not reused, so the next enrollment will be ENR-0007.

**Known limitations**
- Mobile numbers are compared exactly as typed (`+91 90000 00001` differs from `9000000001`).
- The manual app does not run this flow; manual enrollments rely on the coordinator.

### 4.10 MCP server: PSP Patient Services MCP (Step 5)

| Item | Value |
|---|---|
| Server | Label **PSP Patient Services MCP**, API name `PSPPatientServicesMCP` (letters and digits only: the platform rejects underscores), Id `1g1gL00000017STQAY` |
| Description | Zenthera Patient Support Program (demo, fictional data): tools for patient services coordinators |
| Tool | Title **Enroll Patient in Zenthera Program**. Name now `PSP_Enroll_Patientflow_PSP_Enroll_Patient` (the naming pattern Setup uses; renamed in deploy `0AfgL00000eDTTOSA4`, 23:29 UTC); it was `psp_enroll_patient` before. Both names worked in Slackbot |
| Tool source | `API_CATALOG`, identifier `fa:flow-PSP_Enroll_Patient` (the active flow, section 4.9) |
| Tool flags | readOnly false, destructive false, idempotent false, openWorld false, returnDirect false |
| Inputs / outputs | Same as the flow (section 4.9); the schema is generated from the flow variables and their descriptions |
| Tool description sent to clients | Enroll one patient; lists the required inputs and allowed values; tells the client to ask for missing values and never guess birthdate or consent; lists the result codes; says it is a write operation to call once and never retry automatically (871 characters; the limit is 1,024) |
| Permissions | Calls run as the Slack user’s linked Salesforce user. That user needs the PSP Patient Services permission set (objects, fields, Run Flows) and create access to Person Accounts |
| Activation | **Activated by the user in Setup → MCP Servers on 2026-11-17.** The org exposes no API to activate a server (the tooling objects `McpServerDefinition` and `McpServerToolDefinition` have no active field), so this was done by hand |
| Existing servers | Not changed (their modified dates are unchanged) |

**Deployment:** check-only failed twice and was fixed (API name with underscores not allowed; tool description over 1,024 characters), then passed (`0AfgL00000eCeCPSA0`); deployed `0AfgL00000eDKUvSAO`, Succeeded, 1/1.

**Slack setup (done by the user):** Trailhead Slack workspace **TH-Sd0CJ4CZN58D** (`app.slack.com/client/E0CHUAHUVQF`), Slackbot and Slack AI features turned on. The workspace was connected to ProductPillarSDO, the server was added through Manage Salesforce MCP, and Slack signs in as Salesforce user `deepshikhaheadless@kpmg.com` (given the same access as the demo user). In Slackbot the tool is set to **always allowed**, so Slackbot did not ask for approval before writing; for a stricter demo, switch it back to “ask before running”.

**Slackbot live test (2026-11-17, passed).** Evidence: `docs/evidence/slackbot-01-no-consent-and-first-attempt.png`, `slackbot-02-enrolled-and-duplicate.png`, `slackbot-03-retry-enrolled-ENR-0007.png`.
| # | Prompt (fictional patient Riya Demo Sharma) | What happened | Result |
|---|---|---|---|
| 1 | Full details, “Consent has NOT been given” | Slackbot refused on its own and did **not** call the tool; nothing created | Passed (the flow’s own NO_CONSENT check was tested directly in section 4.9) |
| 2 | Full details, “Valid consent is recorded today” | First attempt: Slackbot turned the server on but “the enrollment tool didn’t load”, nothing submitted. After “try again”: **Used Enroll Patient in Zenthera Program from PSPPatientServicesMCP**, reply “Riya Demo Sharma is now enrolled… Enrollment number: ENR-0007… A new patient record was created” | Passed on retry |
| 3 | “Enroll the same patient again… with the same details” | Called the same tool; reply “No second enrollment was created… already has an open enrollment, ENR-0007” | Passed |

**Salesforce verification**
| Check | Result |
|---|---|
| Patient | Person Account `001gL000029dxV3QAI`, record type Person Account, first name “Riya Demo”, last name “Sharma”, birthdate 1991-03-14, mobile +91 90000 11223 |
| Enrollment | **ENR-0007** (`a4tgL000000hrCLQAY`): Program Zenthera Patient Support Program, Zenthera 50 mg, Enrolled, prescriber Dr. Demo Mehta, Commercial, Consent Given true, Enrollment and Consent Date 2026-11-16 (user time zone America/Los_Angeles) |
| Enrollment number matches Slackbot | Yes, ENR-0007 |
| No duplicate | Exactly one enrollment for this patient |
| MCP call evidence | Both records were created by `deepshikhaheadless@kpmg.com`, the Salesforce user linked to Slack, at 23:28:49–50 UTC; Slackbot shows the tool-use line naming the server and tool |

**Notes**
- The successful call (23:28:50) happened before the tool rename (23:29:21), so the first “tool didn’t load” was a temporary loading issue, not the tool name.
- Slackbot split “Riya Demo Sharma” as first name “Riya Demo” and last name “Sharma”. To control this, say “first name …, last name …” in the prompt.

### 4.11 Apex: PSP Get Refill History (Step 6)

**Class:** `PSP_RefillHistoryTool` (global, `with sharing`, all queries `WITH USER_MODE`), invocable label **PSP Get Refill History**, category Patient Support Program. Global so the API Catalog can offer it as an MCP tool. Also usable as an Agentforce action.

**Inputs:** `patientName` (full name as recorded) or `enrollmentNumber` (ENR-…, takes priority, case-insensitive); optional `asOfDate` (default today).

**Outputs:** `isSuccess`, `resultCode` (SUCCESS, NOT_FOUND, AMBIGUOUS_MATCH, NO_ENROLLMENT, INVALID_INPUT, ERROR), `resultMessage`, `refillStatus` (ON_TRACK, DUE, LATE, NO_DELIVERED_REFILL), `patientId`, `patientName`, `enrollmentId`, `enrollmentNumber`, `therapy`, `enrollmentStatus`, `asOfDate`, `lastDeliveredDate`, `lastDeliveredDaysSupply`, `nextRefillDueDate`, `daysOverdue`, `dispenseCount`, `deliveredCount`, `dispenseHistory` (one line per dispense, newest first, marked counted / not counted), `errorType`.

**Business rules**
| # | Rule |
|---|---|
| R-1 | Only dispenses with Status = Delivered and both Dispense Date and Days Supply count toward supply |
| R-2 | Next refill due = latest counted Dispense Date + its Days Supply |
| R-3 | Days overdue = max(0, as-of date − due date) |
| R-4 | LATE if as-of is after due; DUE if due within 7 days (inclusive); otherwise ON_TRACK; NO_DELIVERED_REFILL if nothing counts |
| R-5 | Patient name with 0 matches → NOT_FOUND; 2+ matches → AMBIGUOUS_MATCH (ask for the ENR number); patient without enrollment → NO_ENROLLMENT |
| R-6 | Several enrollments → the most recent open (not Discontinued) one, else the most recent |
| R-7 | Messages describe recorded shipments only and say they do not confirm the patient took the medication |

**Design:** bulk-safe (at most 4 queries for any number of requests); query errors are returned as `ERROR` responses, not thrown. Permission set PSP Patient Services gives access to the class.

**Validation, deployment, tests**
| Item | Result |
|---|---|
| Code Analyzer | Unavailable: the Apex engines (PMD, CPD, SFGE) need Java, which is not installed on this machine |
| Apex language server diagnostics | Reported errors that the Salesforce compiler did not confirm (string `+` read as arithmetic, inner-class constructor) — treated as false positives |
| Check-only deploy | `0AfgL00000eDfKrSAK`, 4/4 compiled |
| Deploy (2 classes, factory, permission set) | `0AfgL00000eDffpSAC`, Succeeded 4/4 |
| Apex tests `PSP_RefillHistoryToolTest` | 16/16 passed (run `707gL00001c87C9`), coverage of `PSP_RefillHistoryTool` 94% |

Test scenarios: LATE by 9 days (Delivered 2026-10-09 + 30, as-of 2026-11-17), Delayed shipment not counted, DUE, ON_TRACK, NO_DELIVERED_REFILL (Shipped + Delivered without days supply), lookup by enrollment number (case-insensitive), patient not found, enrollment number not found, ambiguous name, no enrollment, only a Discontinued enrollment, blank input, null input, default as-of date, bulk 251 requests within 4 queries.

**Demo data (fictional)** on Riya Demo Sharma’s enrollment ENR-0007: **DSP-0015** Delivered 2026-10-09, 30 days, Demo Specialty Pharmacy; **DSP-0016** Delayed 2026-11-10, 30 days. Checked through the invocable endpoint (Apex only, not a Slackbot test): SUCCESS, LATE, due 2026-11-08, 9 days overdue, 2 dispenses, 1 counted.

**MCP tool:** on PSP Patient Services MCP, name `psp_get_refill_history`, title **Get Patient Refill History**, read-only, idempotent, identifier **`aa:apex-PSP_RefillHistoryTool`**, operation `PSP_RefillHistoryTool`, description of 804 characters (rules, inputs, result codes, no adherence claims, no medical advice). Adding it by metadata first failed because invocable Apex uses the prefix **`aa:`** (Apex action), not `fa:` (flow); the API Catalog answered “no operations” for `fa:apex-…`. The user then added the tool once through Setup (Add Tools → Apex Actions), which revealed the identifier; the metadata was retrieved, the name, title, flags and description were set, and it was deployed (`0AfgL00000eDm2zSAC`). The enrollment tool is unchanged.

**Slackbot test, round 1 (2026-11-17): MCP tool not invoked.** Evidence: `docs/evidence/slackbot-refill-A-native-query.png`, `slackbot-refill-B-C-answers.png`, `slackbot-refill-D-not-found.png`.
| Prompt | What Slackbot used | Answer | MCP tool test |
|---|---|---|---|
| A. “Show the refill history for Riya Demo Sharma.” | Its built-in Salesforce connection: “Queried Salesforce Account, Contact, Lead, and EntityDefinition objects”, then “Queried Salesforce Dispense__c, Program_Enrollment__c objects” | Correct list (DSP-0016 Delayed, DSP-0015 Delivered); added “the delay may put adherence at risk”, an adherence claim the PSP tool deliberately avoids | Not invoked |
| B. Days late as of 2026-11-17 | No tool line (reused earlier data) | Correct: 9 days late, due 2026-11-08 | Not invoked |
| C. Does a delayed shipment count? | No tool line | Correct: no | Not invoked |
| D. Unknown patient | Built-in connection: “Queried Salesforce Account, Contact, Lead objects” | Correct: not found | Not invoked |

The numbers match the Apex result and the records, but no response shows “Used Get Patient Refill History from PSPPatientServicesMCP”, so the Slackbot MCP test for this tool is **not passed**. Likely cause: for read questions Slackbot prefers its own Salesforce search over MCP tools. Next: repeat with a prompt that names the tool, after refreshing the server in Slackbot → Apps.

### 4.12 Named Query: PSP Patient 360 (Step 7)

| Item | Value |
|---|---|
| Label / API name | PSP Patient 360 / `PSPPatient360` (Id `1RKgL00000006AHWAY`), API version 68.0 |
| Source file | `force-app/main/default/apiNamedQueries/PSPPatient360.apiNamedQuery-meta.xml` |
| Parameter | `patientname` (label Patient Name). Parameter names must be lowercase |
| REST endpoint | `GET /services/data/v68.0/named/query/PSPPatient360?patientname=<full name>` |
| Relationships used | Account → `Program_Enrollments__r` (Program_Enrollment__c.Patient__c), Program_Enrollment__c → `Dispenses__r`, Account → `Cases` |
| One or two queries | **One.** The nested subquery Account → Enrollments → Dispenses is accepted, so a single named query returns the complete profile |

**SOQL**
```sql
SELECT Id, Name, PersonMobilePhone, RecordType.DeveloperName,
  (SELECT Id, Name, Program__c, Therapy__c, Status__c, Enrollment_Date__c, Insurance_Type__c, Prescriber_Name__c,
     (SELECT Name, Dispense_Date__c, Days_Supply__c, Pharmacy__c, Status__c
      FROM Dispenses__r ORDER BY Dispense_Date__c DESC LIMIT 20)
   FROM Program_Enrollments__r ORDER BY Enrollment_Date__c DESC LIMIT 5),
  (SELECT CaseNumber, Subject, Status, IsClosed, Origin, CreatedDate
   FROM Cases ORDER BY IsClosed, CreatedDate DESC LIMIT 20)
FROM Account
WHERE IsPersonAccount = true AND Name = :patientname
ORDER BY CreatedDate LIMIT 5
```

**Design notes:** read-only; only demo fields (no birthdate, address or email returned); open cases are listed first and `IsClosed` tells open from closed; up to 5 patients are returned so an ambiguous name shows several rows instead of mixing them; an unknown name returns no rows. Lookup by Account Id is not included (the demo looks patients up by name).

**How it was built:** creating it through the Tooling API is not allowed (“entity type cannot be inserted”). The metadata format was not documented locally, so it was read from the org’s Metadata API WSDL: elements `apiNamedQueryParameters` (description, parameterLabel, parameterName), `apiVersion`, `body2` (the SOQL), `description` (max 255 characters), `isProtected`, `masterLabel`. Check-only deploys caught the description length and the lowercase parameter rule. Final check-only `0AfgL00000eGbvpSAC` passed; deploy `0AfgL00000eGHZpSAO` succeeded.

**Tests (direct REST, read-only)**
| Test | Result |
|---|---|
| `patientname=Riya Demo Sharma` | 1 patient: Riya Demo Sharma, mobile +91 90000 11223, record type PersonAccount; ENR-0007 (Zenthera Patient Support Program, Zenthera 50 mg, Enrolled, 2026-11-16, Commercial, Dr. Demo Mehta) with DSP-0016 (2026-11-10, 30, Delayed) and DSP-0015 (2026-10-09, 30, Delivered); `Cases: null` (she has no cases) |
| Unknown patient (`Zoya Notreal Kapoor`) | `totalSize 0`, no records |
| Ambiguous name | Not tested: no two person accounts share a name in the org |

**API Catalog and MCP tool**

| Item | Value |
|---|---|
| API Catalog | Action activated in Setup → API Catalog → Named Query (no API for this step) |
| API Catalog identifier | `nq:PSPPatient360_nquery`, operation `PSPPatient360` (read from `McpServerToolApiDefinition` after the tool was added once in Setup; the Setup-generated name was `PSPPatient360PSPPatient360_nquery`) |
| MCP tool | `psp_patient_360`, title Get Complete PSP Patient Profile, readOnly true, idempotent true, destructive false, openWorld false; description tells the AI to ask for the full name, treat 0 rows as not found and more than 1 as ambiguous, never invent data, give no medical advice |
| Server | PSP Patient Services MCP now has 3 tools: Enroll Patient, `psp_get_refill_history`, `psp_patient_360`. Check-only `0AfgL00000eIVHdSAO`, deployed `0AfgL00000eHeRsSAK` |

**Step 7C debug: Slackbot round 1 failed** (evidence `docs/evidence/slackbot-p360-round1-tool-error.png`)

| Check | Finding |
|---|---|
| Slackbot call | Called the tool twice with `{"patientname": "Riya Demo Sharma"}` (correct argument); both failed; Slackbot then used its own Salesforce queries (not counted as a pass). Slack showed no response body or error text |
| Tool shown in Slack | "Used **PSPPatient360** from PSPPatientServicesMCP". Slack shows the tool **title** (compare "Used Enroll Patient in Zenthera Program" in the enrollment evidence). `PSPPatient360` was the title Setup generated; after the rename the title is Get Complete PSP Patient Profile |
| Server | `McpServerAccess` PSPPatientServicesMCP Active = true; 3 tools on the server, all with new Ids after the deploy |
| API Catalog | Identifier `nq:PSPPatient360_nquery`, operation `PSPPatient360`, parameter `patientname` (text) |
| Slack user access | deepshikhaheadless@kpmg.com has PSP Patient Services: read on all queried objects and fields |
| Query isolation | Temporary queries `PSP360TestA` (account only), `B` (+ enrollments), `C` (+ nested dispenses), `D` (+ cases) deployed (`0AfgL00000eIKKcSAO`); all return the right data through REST, including `Cases: null` |
| Direct MCP call | Not possible yet: the hosted endpoint answers 401 "Invalid token" to the CLI session token; it needs a token from an MCP-enabled client app, and the org has none |

**Round 2 (after re-adding the server in Slack)** (evidence `slack-mcp-review-tools-3-tools.png`, `slack-mcp-server-readded.png`, `slackbot-p360-round2-unknown-tool.png`)

| Check | Finding |
|---|---|
| Slack tool list | Shows all 3 tools with the new titles: Get Patient Refill History, Get Complete PSP Patient Profile (read-only), Enroll Patient in Zenthera Program |
| Slackbot call | Still "Used **PSPPatient360**"; error text now visible: **`Unknown tool: invalid_tool_name`**. Slackbot then queried Salesforce directly (not counted) |

**Root cause (current reading):** the stale-cache theory is ruled out (Slack has the new list). Slack shows a tool's title when it calls a known tool, but here it shows `PSPPatient360`, which is not the name or title of any tool on the server. The test prompt says "Use PSP Patient 360", and the AI appears to have turned that phrase into a tool name that does not exist; Slack then rejects it as `invalid_tool_name`. The query and the server are fine.
**Next check (no metadata change):** prompt with the real tool title (Get Complete PSP Patient Profile), plus the Refill tool as a control for a custom tool name. If the title prompt works, the fix is the prompt wording in the User Guide; if it still fails, rename the tool.

**Round 3 (Step 7D):** natural-language and exact-title prompts both FAIL with the same error; Refill tool control PASS. The prompt-wording theory is ruled out.

**Step 7E: automated investigation (CLI and API, no Setup UI)**

| Operation | Result |
|---|---|
| `sf --version` | @salesforce/cli 2.150.6; `sf agent mcp` commands available (preview): list, get, fetch, update, create, delete, asset list, asset replace |
| `sf agent mcp list` / `get` | PSPPatientServicesMCP `1g1gL00000017STQAY` active; real URL `https://api.salesforce.com/platform/mcp/v1/d/kp1793615031857/custom/PSPPatientServicesMCP` |
| `sf agent mcp asset list` | 3 MCP_TOOL assets; P360 was `psp_patient_360` / Get Complete PSP Patient Profile |
| `sf agent mcp fetch` | Not supported: works only on EXTERNAL servers |
| `GET /services/data/v68.0/api-catalog/apis` | 5 NAMED_QUERY entries; only PSP Patient 360 is activated (id `0LegL0000006t1p`), test queries have virtual ids only |
| API Catalog activation | Creates External Service Registration `PSPPatient360_nquery` (provider NamedQuery, OpenAPI 3.0.1, Complete). Operation id **`PSPPatient360`** (GET `/named/query/PSPPatient360`), inputs `patientname` (string) and `maxrecords` (integer) |
| Activating test queries by metadata | Not possible: `_nquery` names are system-only and the schema is platform-generated; two incomplete registrations created by mistake were deleted (`0AfgL00000eIkRySAK`) |
| Direct MCP `tools/list` / `tools/call` | Not possible: endpoint returns 401 "Invalid token" for the CLI session token; needs a token from an MCP-enabled client app (none in the org) |
| `sf agent mcp asset replace` | Rejected: requires a per-asset `source` object whose format is not exposed; not guessed |

**Root cause (best supported, to be confirmed in Slackbot):** for Named Query tools the published tool name differs from the registered operation. Slack shows and calls the operation name `PSPPatient360` (it does this in every failed call), but the allowlisted tool name was `psp_patient_360` (before that, the Setup default `PSPPatient360PSPPatient360_nquery`). Slack cannot match the call, so it reports `Unknown tool: invalid_tool_name`. Flow and Apex tools accept custom names (Refill works as `psp_get_refill_history`).

**Fix:** tool name set to `PSPPatient360` (= the operation name) through the McpServerDefinition metadata. Title, description, read-only flags and the other two tools unchanged. Check-only `0AfgL00000eIkoYSAS`, deployed `0AfgL00000eIqPJSA0`; `asset list` confirms the 3 tools and the server is still active.

**Remaining:** re-add the server in Slack and retest (user action, no Slack API or browser automation available). If it passes, delete temporary queries `PSP360TestA`–`D`.
**Rule:** never rename or redeploy MCP tools after Slack has loaded them without re-adding the server in Slack.
**Clean-up:** delete the four `PSP360Test*` queries after the Slackbot test passes.

**Step 7 final status: workaround with a second MCP server (2026-11-17)**

The user created a separate server in Setup: **PSP Named Query MCP** (`PSPNamedQueryMCP`, Id `1g1gL00000018unQAA`, active) with one tool added in Setup and left unchanged: name `PSPPatient360PSPPatient360_nquery`, title `PSPPatient360`, identifier `nq:PSPPatient360_nquery`, operation `PSPPatient360`. The user also removed the failing Patient 360 tool from PSP Patient Services MCP.

| Slackbot call | Result |
|---|---|
| PSPPatient360 on PSPPatientServicesMCP (old tool) | FAIL, `Unknown tool: invalid_tool_name` (Slackbot then retried) |
| PSPPatient360 from **PSPNamedQueryMCP** | **PASS**: returned Riya Demo Sharma, Person Account, ENR-0007, Zenthera Patient Support Program, Zenthera 50 mg, Commercial, Dr. Demo Mehta. Dispenses DSP-0015 Delivered and DSP-0016 Delayed and "no cases" match the REST check |

**What is and is not fixed:** the Named Query tool works on the new server. It was never made to work on PSP Patient Services MCP; the exact cause there is not confirmed. Observation: the working tool was added in Setup and never edited, while the failing one had been changed by metadata deploys (name, title, flags, description). **Rule for this POC:** add Named Query tools in Setup and do not edit them by metadata.

**Clean-up:** temporary queries `PSP360TestA`–`D` had no dependants (no MCP tool, no External Service Registration, no local reference); deleted (`0AfgL00000eJ34nSAC`). Only `PSPPatient360` remains. Both server definitions were retrieved so the local files match the org.

### 4.13 Flow: PSP Create Service Case (Step 8)

| Item | Value |
|---|---|
| API name | `PSP_Create_Service_Case`, Autolaunched Flow, API 68.0, Active version 2 |
| Built | By hand in the same pattern as `PSP_Enroll_Patient` (the flow-generation MCP service was not connected). Validated `0AfgL00000eIWjySAG`, deployed v1 `0AfgL00000eIWtgSAG`; fix validated `0AfgL00000eJ22ISAS`, deployed v2 `0AfgL00000eIid4SAC` |
| Inputs | `patientName` or `patientAccountId` (optional), `subject` (max 200), `description`, `issueCategory`, `userConfirmed` |
| Outputs | `isSuccess`, `resultCode`, `resultMessage`, `caseId`, `caseNumber`, `caseStatus`, `casePriority`, `patientId`, `enrollmentNumber`, `safetyReviewRequired` |
| Result codes | SUCCESS, VALIDATION_ERROR, NOT_CONFIRMED, NOT_FOUND, AMBIGUOUS_MATCH, NO_ENROLLMENT, ERROR |

**Logic**
```
Check inputs ─ invalid ──────────────▶ VALIDATION_ERROR (nothing created)
     │ userConfirmed is not exactly true ▶ NOT_CONFIRMED
     ▼
Find Person Account: by Account Id if given, else by exact name
     ├─ 0 found ─▶ NOT_FOUND      ├─ 2+ found ─▶ AMBIGUOUS_MATCH (never picks one)
     ▼ 1 found
Enrollment not Discontinued? ── no ─▶ NO_ENROLLMENT
     ▼ yes
Create Case ── fault ─▶ ERROR (with Salesforce message)
     ▼
Read Case Number ─▶ SUCCESS
```

**Case field mapping** (values checked against the org's Case picklists)

| Case field | Value |
|---|---|
| AccountId / ContactId | Patient Person Account / its PersonContactId |
| Subject | `[<category>] <subject>`; possible adverse event: `[SAFETY REVIEW] Possible Adverse Event - <subject>` |
| Description | User text + issue category, patient, enrollment (ENR, therapy), "Logged through the PSP Patient Services tools after user confirmation"; possible adverse event adds "SAFETY REVIEW REQUIRED … No medical advice was given and no regulatory report has been submitted automatically." |
| Status | New (org default) |
| Origin | Slack (existing value) |
| Priority | High for Possible Adverse Event, Medium otherwise |
| Type | Insurance Support → Account Support; General Program Support → General; others → Product Support |
| Record type | Org default (Case / SDO_Service_Case) |

**First MCP tool (replaced, see below)** on PSP Patient Services MCP: `psp_create_service_case`, title Create PSP Patient Service Case, identifier `fa:flow-PSP_Create_Service_Case`, operation `PSP_Create_Service_Case`, readOnly false, destructive false, idempotent false; description (998 characters) tells the AI to show the details and get the user's confirmation before calling with `userConfirmed = true`, call once, and never claim medical advice or regulatory reporting. Validated `0AfgL00000eJ6YvSAK`, deployed `0AfgL00000eJ6c9SAC`. `sf agent mcp asset list` shows Enroll, Refill and Create Service Case; server active.

**Backend tests** (REST invocable endpoint `/actions/custom/flow/PSP_Create_Service_Case`, the entry point MCP uses; not a Slackbot test; fictional data)

| Test | Input | Result |
|---|---|---|
| 1 Valid patient, shipment delay, confirmed | Riya Demo Sharma by name, Shipment Delay | **PASS**: Case **00001070**, New, Slack, Medium, Product Support, linked to the Person Account and contact |
| 2 Unknown patient | Zoya Notreal Kapoor | **PASS**: NOT_FOUND, no case |
| 3 Missing confirmation | `userConfirmed` omitted / false | **PASS** on v2: NOT_CONFIRMED, no case. **v1 FAILED**: an omitted value was treated as confirmed and created case 00001069; fixed in v2 (continue only when exactly true) and the test case was deleted |
| 4 Ambiguous name | No two patients share a name | **NOT TESTED** (no fixture) |
| 5 Possible adverse event | Riya by Account Id | **PASS**: Case **00001071**, `[SAFETY REVIEW] …`, High, safety note in description, `safetyReviewRequired = true` |
| 6 Missing subject/description, bad category | | **PASS**: VALIDATION_ERROR listing each problem, no case |

**Patient 360 check:** the Named Query REST call for Riya now returns ENR-0007, DSP-0016 Delayed, DSP-0015 Delivered and cases 00001071 and 00001070 (both New).

**Final MCP setup: separate server PSP Case MCP (2026-11-17)**

The user created a separate server in Setup, the same pattern that fixed Patient 360: **PSP Case MCP** (`PSPCaseMCP`, Id `1g1gL00000018zdQAA`, active), with one tool added in Setup: name `PSP_Create_Service_Caseflow_PSP_Create_Service_Case`, title `PSP_Create_Service_Case`, identifier `fa:flow-PSP_Create_Service_Case`, operation `PSP_Create_Service_Case`, readOnly false, destructive false, idempotent false. Its description (set by the user) covers explicit confirmation, unknown/ambiguous patients, Origin Slack, and safety review only for possible adverse events. The user removed `psp_create_service_case` from PSP Patient Services MCP, which now has Enroll and Refill only. Both definitions were retrieved into the project. Whether `psp_create_service_case` on the old server would also have worked in Slack was not tested.

**Slackbot tests (PSP Case MCP)**

| Test | Result |
|---|---|
| Case creation from Slackbot, prompt from the brief (Riya, DSP-0016 delayed, confirm first) | **PASS** (user tested in Slack). Verified in Salesforce: Case **00001072**, `[Shipment Delay] Delayed medication shipment`, New, Medium, Origin Slack, created 16:58 UTC by the Slack user, linked to Riya Demo Sharma and ENR-0007 |
| Second case from Slackbot | **PASS**: Case **00001073**, `[Shipment Delay] Delayed Zenthera medication shipment`, New, Medium, Origin Slack, created 17:09 UTC by the Slack user |
| Other scenarios | User reports they work; no record is created for refused requests, so these are not verified in Salesforce |

Both case descriptions end with the Flow's footer ("Logged through the PSP Patient Services tools after user confirmation"), so the cases came from `PSP_Create_Service_Case` and not from a direct record create. Both were created after PSP Case MCP existed (16:46 UTC) and by the Slack user, not the CLI user who ran the backend tests (00001070, 00001071).

### 4.14 Program FAQ answers (Step 9)

Answers program questions (eligibility, enrollment, copay and insurance, shipments and refills, contact, privacy) only from a fictional Program FAQ PDF, grounded through Data 360.

```
 Slackbot ──▶ PSP Program FAQ MCP ──▶ Flow: PSP Answer Program Question
                                          │  (checks the question is 1–1000 characters)
                                          ▼
                                 Prompt template: PSP Program FAQ Answer (Flex)
                                          │  {!$EinsteinSearch:File_PSP_FAQ_1Cx_CjNe65ed319.results}
                                          ▼
                    Data 360: Agentforce Data Library PSP_FAQ ─▶ search index ─▶ retriever
                                          ▲
                              Zenthera-PSP-Program-FAQ.pdf (21 Q&A, fictional)
```

| Component | Detail |
|---|---|
| FAQ document | `docs/program-faq/Zenthera-PSP-Program-FAQ.pdf` (source `…FAQ.html`), 21 questions in 6 sections, 80 KB, marked as fictional demo content, no medical advice |
| Data library | **PSP FAQ** (`PSP_FAQ`, Id `1JDgL000009h7FZWAY`), source file upload (SFDRIVE), data space default, status READY, file INDEXED (2026-11-18 08:03) |
| Retriever | `File_PSP_FAQ_1Cx_CjNe65ed319` (Id `1CxgL000000NXmTSAW`); the library also created the retriever action `File_PSP_FAQ` ("Get Information from PSP_FAQ"), not used by our tools |
| Prompt template | `PSP_Program_FAQ_Answer`, Flex, input `question` (String), model `sfdc_ai__DefaultGPT4Omni`, data provider `invocable://getEinsteinRetrieverResults/File_PSP_FAQ_1Cx_CjNe65ed319` with `searchText = {!$Input:question}`. Rules: answer only from the excerpts; a fixed "I could not find this…" reply when the FAQ has no answer; no medical advice (prescriber, 911 in an emergency); for side effects suggest a Possible Adverse Event case; never claim regulatory reporting; 2–5 sentences; end with "Source: Zenthera Program FAQ, Q…". Validated `0AfgL00000eMwXnSAK`, deployed `0AfgL00000eN1kPSAS` |
| Flow | `PSP_Answer_Program_Question`, Autolaunched, Active. Input `question`; outputs `isSuccess`, `resultCode` (SUCCESS, VALIDATION_ERROR, ERROR), `answer`, `resultMessage`. Calls the template with action type `generatePromptResponse`; fault path returns ERROR. Validated `0AfgL00000eNDVPSA4`, deployed `0AfgL00000eNHSYSA4` |
| MCP server | **PSP Program FAQ MCP** (`PSPProgramFAQMCP`, Id `1g1gL0000001AdFQAU`), one tool: name `PSP_Answer_Program_Questionflow_PSP_Answer_Program_Question`, title `PSP_Answer_Program_Question`, `fa:flow-PSP_Answer_Program_Question`, read-only, idempotent. Validated `0AfgL00000eNPl3SAG`, deployed `0AfgL00000eNPmfSAG`. Activated by creating the Tooling record `McpServerAccess` (`1fzgL000009HhxpQAC`, Active = true), the same record Setup creates on Activate |

**How the library was built (what worked and what did not)**

| Attempt | Result |
|---|---|
| Create library by API: `POST /einstein/data-libraries` with `groundingSource.sourceType = SFDRIVE` | Library created (`PSP_Program_FAQ`) |
| Upload by API: `POST …/file-upload-urls` → PUT to the signed URL (HTTP 200) → `POST …/files` with `uploadedFiles[].filePath` | File registered, but recorded with size 1 byte; the stages SEARCH_INDEX, RETRIEVER and INDEXING stayed **NOT_SCHEDULED** for over 30 minutes. A PATCH of the library and a re-upload with `fileSize` did not schedule them |
| Upload in Setup (Agentforce Data Library, new library `PSP_FAQ` created by the user) | File saved at 79.99 kB; search index, retriever, retriever action and indexing all succeeded in about 3 minutes. The API-created library no longer exists in the org |

**Rule for this POC:** create the data library and upload files in Setup; read its status and retriever by API (`GET /einstein/data-libraries/{id}` and `/status`). The retriever API name is shown in the retriever action's metadata (`GenAiFunction` → `invocationTarget`).

**Backend tests** (REST invocable endpoint `/actions/custom/flow/PSP_Answer_Program_Question`, the entry point MCP uses; not a Slackbot test)

| Test | Question | Result |
|---|---|---|
| T1 Copay and Medicare | Can a patient with Medicare use the copay assistance program? | **PASS**: "No…", foundations list, Source Q10 |
| T2 Delayed shipment | What should we do if a shipment is delayed? | **PASS**: coordinator checks with the pharmacy and logs a service case, Source Q15 |
| T3 Uninsured | What help is available with no insurance? | **PASS**: Free Medication Program, 400% FPL, Source Q11 |
| T4 Not in the FAQ | Does the program cover travel costs? | **PASS**: "I could not find this in the Zenthera Program FAQ…" (nothing invented) |
| T5 Medical question | Missed a dose, take two today? | **PASS**: refers to the prescriber, no dosing advice, Source Q16 |
| T6 Side effect | Headaches after each dose? | **PASS**: prescriber, 911 in an emergency, suggests a Possible Adverse Event case, Source Q17 |
| T7 Blank question | (spaces) | **PASS**: VALIDATION_ERROR |

The template was also tested directly (`POST /einstein/prompt-templates/PSP_Program_FAQ_Answer/generations`): grounded answer with Source Q10.

**Slackbot test (2026-11-18)**

| Test | Result |
|---|---|
| Chained request: “First use PSPPatient360 from PSP Named Query MCP to retrieve Riya Demo Sharma’s insurance type. Then use PSP_Answer_Program_Question from PSP Program FAQ MCP to explain what copay assistance may be available…” | **PASS**. Slackbot showed “Used PSPPatient360 and PSP_Answer_Program_Question”. Insurance type Commercial from ENR-0007 (Patient 360), then the FAQ answer: as little as $10 per monthly fill, up to $15,000 per calendar year, coordinator explains options at the maximum, “Source: Zenthera Program FAQ, Q9”, no guarantee of approval. All figures match Q9 of the FAQ. Evidence: `docs/evidence/slackbot-faq-copay-p360-chain-pass.png` |

This also shows two PSP servers working together in one Slackbot answer (patient record + program policy).

### 4.15 Program Exceptions engine (Phase 1, 2026-11-19)

Read-only backend for the Program Exceptions Desk. It works on real CRM data. Details and test results are in `docs/Plan-Program-Exceptions-Desk.md` sections 4.8 and 5.

| Component | Type | Purpose |
|---|---|---|
| `Case.PSP_Issue_Category__c` | Restricted picklist on standard Case | Shipment Delay, Refill Support, Insurance Support, General Program Support, Possible Adverse Event |
| `Case.PSP_Dispense__c` | Lookup to `Dispense__c` (clear on delete) | The shipment a case is about |
| `PSP_CaseDuplicateCheck` | Invocable Apex "PSP Check Duplicate Case", read-only | Before creating a case: NO_DUPLICATE, EXISTING_CASE, POSSIBLE_DUPLICATE (same category, shipment unknown) |
| `PSP_ProgramExceptionRules` | Apex, pure logic | Exception rules for one enrollment; missing data → DATA_INCOMPLETE |
| `PSP_ProgramExceptionsService` | Invocable Apex "PSP Get Program Exceptions", read-only | Exceptions list for all authorized Zenthera patients; 2 queries per page, keyset paging |
| `PSP_TestDataFactory.createSdoCaseAutomationFixture()` | Test helper | Lets Apex tests insert Cases despite the SDO Case flow (no SDO change) |
| `PSP_Patient_Services` | Permission set (updated) | Access to the two new Apex actions and read access to the two Case fields |
| Data backfill | Record edits (8 Case values, 1 enrollment Program) | Old cases now carry category and shipment; backup in `docs/data-backfill/backup-2026-11-19/` |

```
Coworker / specialist agent / (later) MCP tool
        |
        v
PSP Get Program Exceptions  --(2 SOQL, user mode)-->  Program_Enrollment__c + Dispense__c, open Cases
        |                                                       |
        +--> PSP_ProgramExceptionRules (per enrollment) <-------+
        |
        v
items (severity, fact, suggested action)  --CREATE_CASE?-->  PSP Check Duplicate Case  -->  (after approval) PSP Create Service Case Flow
```

Exposed through the new **PSP Exceptions MCP** server (2026-11-19, Slackbot tested); not connected to any agent or Flow yet. The existing tools are unchanged: Enroll and Case Flows, Refill Apex, Patient 360, FAQ, the four MCP servers and Coworker.

### 4.16 Specialist agents (Phase 2, 2026-11-19)

Three Agentforce employee agents. They are written in Agent Script and published by CLI, and all three are read-only. Details are in `docs/Plan-Program-Exceptions-Desk.md` section 6.5.

```
                 Agentforce Coworker (Phase 3, tested: delegates by agent description; can call several agents)
                        |
      +-----------------+------------------+
      v                 v                  v
 Medication Support  Program Knowledge  Care Resolution
  Refill Apex         FAQ Flow           Exceptions service
  Exceptions service  (Data 360)         Duplicate check
      |                 |                  |
      +------- Salesforce data, user mode, no writes -------+
```

Design rule learned: an action that must always run is called **deterministically** in Agent Script, with `run @actions.x` + `with` + `set @variables.v = @outputs.o`. Its results go into the prompt through `{!@variables.v}`, and the user's message through `@system_variables.user_input`. Without this the model sometimes skipped the tool and invented an answer. Write actions (Enroll, Create Case, handoff posting) are not on the agents; they need separate approval (Phase 4).

### 4.17 Approved actions and handoff (Phase 4, 2026-11-19)

```
User ──▶ Care Resolution Agent
          1. check     PSP Check Duplicate Case ── EXISTING / POSSIBLE ──▶ stop, show cases
          2. propose   exact case (patient, category, shipment, subject, description)
          3. "yes"  ─▶ PSP Create Approved Case (userConfirmed=true; guard runs again) ──▶ Case (category + shipment set)
          handoff   ─▶ PSP Prepare Care Team Handoff (read-only, fixed sections, nothing posted)
```

The existing PSP Create Service Case Flow (Slackbot) is unchanged. Sharing to Slack and saving the handoff are not built (they need separate approval).

## 5. Planned components (design)

### 5.1 Lightning App: Patient Support Program

The manual way to do PSP work. Tabs: Home, Accounts (patients), Program Enrollments, Dispenses, Cases, Reports. Visible to users with the PSP Patient Services permission set.

### 5.2 Synthetic demo data

5 fictional patients (names contain "Demo" for easy clean-up), one enrollment each with mixed status and insurance, 2–4 dispenses each (some Delayed, one patient late for refill), about 6 cases (Missed refill, Copay help, one Possible Adverse Event).

### 5.3 Flow: PSP Enroll Patient

Built, deployed and tested in Step 5. See section 4.9.

### 5.4 Apex: Get Refill History

Built and deployed in Step 6. See section 4.11.

### 5.5 Named Query: Patient 360

Built in Step 7. See section 4.12.

### 5.6 Prompt templates (Flex)

- **Care Team Handoff Summary:** input patient name. Tells the AI to read the patient, enrollment, dispenses and cases with the SOQL tool, then write the summary in a fixed format (therapy, adherence, open issues, next step). Exposed as a tool, because Slack does not support MCP prompts.
- **Program FAQ answers:** built in Step 9, see section 4.14.

### 5.7 Custom MCP servers

**PSP Patient Services MCP** (Step 5, section 4.10): Enroll Patient (Flow), Get Refill History (Apex, section 4.11). **PSP Named Query MCP**: Patient 360 (Named Query, section 4.12). **PSP Case MCP**: Create Service Case (Flow, section 4.13). **PSP Program FAQ MCP**: Answer Program Question (Flow → prompt → Data 360, section 4.14). Planned further tools: Care Team Handoff Summary (prompt), plus the standard SOQL query tool.

### 5.8 Agent: Patient Services Agent (employee agent)

Actions reuse 5.3, 5.4 and the FAQ prompt; inside Salesforce the agent calls them directly (not through MCP). Instruction: when a note mentions a side effect, flag "Possible adverse event, for human safety review" and log a case with the Create Service Case flow. No medical advice and no deadlines or regulatory reporting are claimed. Reached two ways: as an MCP tool behind Slackbot, and deployed directly as a Slack app (DM and @mention in `#psp-care-team`).

## 6. Environment readiness (Phase 0, 2026-11-17)

### 6.1 Ready

- Slack connector package (`slack-platform-connector`) and the Slack connected apps are installed
- Demo user has the Slack permission sets (Slack Demo Admin, Slack Product Perms, Slackbot in LEX)
- Person Accounts enabled; Data Cloud provisioned (`default` data space)
- Licences: Einstein Prompt Templates, Agentforce, Data Cloud; Agentforce Coworker 5 (0 used)
- Metadata types available: `ApiNamedQuery`, `GenAiPromptTemplate`, `AiAuthoringBundle`, `LightningTypeBundle`, `McpServerDefinition`, `ExternalServiceRegistration`
- No PSP metadata and no app named Patient Support Program exist in the org yet

### 6.2 Risks and open items

| Item | Impact | Next step |
|---|---|---|
| Salesforce MCP in Slackbot needs a Business+ or Enterprise Slack plan (a trial allows only a few messages) | Blocks every MCP-based demo step | Confirm the Slack workspace and plan |
| Record pages not yet seen on screen (section 4.5) | Manual navigation is verified through the UI API only | Open a patient, an enrollment and a dispense in the app once records exist |
| HXL (checked 2026-11-18): `LightningTypeBundle` and `UiWidgetBundle` metadata types are available (no bundles yet); the standard **Headless360 (H360) MCP Server** (`platform.headless-360`, inactive) has a `display_widget` tool | HXL widget (row 14) and a handoff card look possible; the exact `UiWidgetBundle` format and rendering in Slackbot are not yet proven | Small spike before building (Step 10 Phase B) |
| Agentforce Coworker (checked 2026-11-18): licenses **Agentforce Coworker** (`AISearchUserPsl`, 0/5 used) and **Agentforce Coworker Setup** (`AISearchAdminPsl`, 0/5) are active until 2027-02-28; permission sets `AISearchUser` and `AISearchAdmin` exist, not assigned. Employee agent licenses active (Agentforce (Default) 10/3105, Agent platform builder 0/2000); one employee agent exists (`Copilot_for_Salesforce`) | Coworker can be used for up to 5 users without buying anything; needs permission set assignment and Coworker setup | Assign to the demo users and enable Coworker in Setup (approval needed) |
| MuleSoft Agent Fabric (checked 2026-11-18): nothing in this org (no MuleSoft/Anypoint named or external credentials, packages or API Catalog provider); only `MuleSoft Data Works Base User` (unrelated). Agent Fabric runs on the MuleSoft Anypoint Platform | Cannot be built or proven from this org | Needs an Anypoint org with Agent Fabric (registry, broker); otherwise keep it as design only |
| Health Cloud Care Program objects exist but are not usable by the demo user | Custom objects used instead | None |
| Slack caches MCP tool definitions; a renamed or redeployed tool fails until the server is re-added in Slack | Slackbot calls a tool that no longer exists | Re-add the server in Slack after every MCP server deploy |
| MCP server activation | Solved in Step 9: creating the Tooling record `McpServerAccess` (Active = true) activates a server, as Setup does | Use the Tooling API |
| Production-type org | Every deploy, activation and data change needs approval | Ask before each step |

## 7. Activity log

| Date | Activity |
|---|---|
| 2026-11-17 | Phase 0 feasibility checks, read-only (findings in section 6). No changes made. |
| 2026-11-17 | Chose the Life Sciences Patient Support Program use case. Built `Program_Enrollment__c`, `Dispense__c`, their tabs and the `PSP_Patient_Services` permission set locally. Check-only validation passed (`sf project deploy start --dry-run`, ID `0AfgL00000eCjvCSAS`, 19/19 components, 0 errors). Nothing deployed. |
| 2026-11-17 | Rewrote this TDD and the User Guide for the PSP use case only. Added the Patient Support Program Lightning app to the plan. |
| 2026-11-17 | Baseline inspection, read-only: both CLI aliases point to org `00DgL00000hTCjNUAW`; 19 local PSP files present; no PSP metadata in the org; non-PSP metadata unchanged. |
| 2026-11-17 | Docs format: tried a stricter per-feature format, then reverted both docs to this format at the user’s request. User Guide prompts are now generic (no example names), and use case and architecture diagrams were added. |
| 2026-11-17 | Step 2: built the Patient Support Program Lightning app and added app visibility to the permission set. Check-only validation of 20 components passed (`0AfgL00000eCiKpSAK`). Deployed 20/20 (`0AfgL00000eCWwOSAW`). Assigned PSP Patient Services to the demo user. Verification found a picklist defect on 4 fields; fixed locally and validated (`0AfgL00000eCKaGSAW`); redeploy pending approval. |
| 2026-11-17 | Step 2 (continued): redeployed the 4 fixed picklist fields (`0AfgL00000eCesJSAS`) and verified them. Ran a rolled-back record test: 5/5 passed, no records left. Found that page layouts lack the PSP fields and related lists; layout update proposed as the next step. |
| 2026-11-17 | Step 3 (preparation): retrieved and backed up the three layouts and `SDO_Account_Default`; checked record type/profile layout assignments and record pages; chose the minimal shared-layout change; prepared the three layouts; preservation checks passed; check-only validation passed (`0AfgL00000eCxuvSAC`). Waiting for deployment approval. |
| 2026-11-17 | Step 3 (deployment): deployed the three layouts (`0AfgL00000eCnVmSAK`, 3/3, 0 errors). Verified by metadata retrieve and through the UI API as the demo user; layout assignments and all other metadata unchanged. On-screen record page check is pending manual UI verification (no records exist). |
| 2026-11-17 | Step 4A (preparation): backed up the Person Account Layout, confirmed `PersonBirthdate` and `PersonMobilePhone` and the demo user’s access, added both fields to the Account Information section locally, checked the diff and preservation, check-only validation passed (`0AfgL00000eCGRmSAO`). Recorded the patient matching rule for the future flow. Waiting for deployment approval. |
| 2026-11-17 | Step 4A (deployment): deployed the Person Account Layout change (`0AfgL00000eD51FSAS`, 1/1, 0 errors). Verified Birthdate and Mobile on the Create and Edit forms through the UI API as the demo user (editable, optional); existing layout content, assignments and all other metadata unchanged. On-screen check pending manual UI verification. |
| 2026-11-17 | POC mode agreed (simple and fast). Fixed the patient list and patient page: PSP Patients list view, PSP Patient compact layout on the Person Account record type, Program Enrollments and Cases moved to the top of the related lists. Validated (`0AfgL00000eCbMaSAK`) and deployed (`0AfgL00000eDAIfSAO`, 4/4). Verified through the UI API on the real patient record. |
| 2026-11-17 | Manual UI test by the user: use cases 1–3 passed in the Salesforce app (records Sonali Singh, ENR-0003, DSP-0002). Use case 4 has no Case on a PSP patient yet. Found that the record type picker defaults to Account. |
| 2026-11-17 | Use case 4 passed in the Salesforce app: Case 00001068 logged on patient Sonali Singh. Salesforce-app channel now tested for use cases 1–4. |
| 2026-11-17 | Step 5: built `PSP_Enroll_Patient` (autolaunched flow; hand-written XML because the flow-generation MCP service was unavailable), validated and deployed (`0AfgL00000eDHTpSAO`, then `0AfgL00000eDCp8SAG` after widening the duplicate rule to blank Program). Tested 9 scenarios through the invocable-action endpoint, all passed. Deleted all FlowTest records. |
| 2026-11-17 | Step 5 (MCP): created PSP Patient Services MCP (`PSPPatientServicesMCP`) with tool `psp_enroll_patient` exposing PSP Enroll Patient; validated and deployed (`0AfgL00000eDKUvSAO`). Added Run Flows to the PSP permission set (`0AfgL00000eDGVdSAO`). Server activation in Setup and the Slackbot live test are pending. |
| 2026-11-17 | Copied access from the demo user (`sanduvyshnavi@kpmg.com.sdo`) to `deepshikhaheadless@kpmg.com` at the user’s request (anonymous Apex, partial success): role CEO and 6 feature licences (Marketing, Offline, Knowledge, Flow User, Service Cloud, Chat); 102 of 108 permission set licences (6 had no free seats); 79 of 86 permission sets (7 depend on those licences); 36 of 36 permission set groups, including PSP Patient Services access; 2 of 2 public groups. 10 CMS workspace roles could not be copied by API. Profile was already System Administrator. |
| 2026-11-17 | PSP Patient Services MCP activated in Setup by the user. Next: add it to Slack and run the Slackbot tests. |
| 2026-11-17 | Attempted automated Slack + MCP setup. Blocked: no browser automation is available in this VS Code session (Claude in Chrome extension not connected; built-in browser exists only in the Claude desktop app; Playwright not installed). Done by CLI: My Domain `https://kp1793615031857.my.salesforce.com`, Slack connector package installed, MCP server `PSPPatientServicesMCP` with tool `psp_enroll_patient` confirmed, no test patient exists yet. The Salesforce org exposes no API for Slack workspace connections. Slackbot remains not tested. |
| 2026-11-17 | Slackbot live test passed in workspace TH-Sd0CJ4CZN58D: no-consent request refused, enrollment created through the PSP MCP tool (ENR-0007, after one retry because the tool did not load the first time), duplicate refused. Verified the records in Salesforce. Renamed the tool to the Setup naming pattern (`0AfgL00000eDTTOSA4`). Evidence screenshots saved in `docs/evidence/`. |
| 2026-11-17 | Step 6: built `PSP_RefillHistoryTool` (global invocable Apex), `PSP_RefillHistoryToolTest` and `PSP_TestDataFactory`; gave the PSP permission set access to the class; deployed (`0AfgL00000eDffpSAC`); tests 16/16, coverage 94%. Added fictional dispenses DSP-0015 (Delivered) and DSP-0016 (Delayed) to ENR-0007. Adding the MCP tool by metadata failed (API Catalog lists no operations for `fa:apex-PSP_RefillHistoryTool`); waiting for the tool to be added once in Setup. Slackbot not tested yet. |
| 2026-11-17 | Checked the MCP blocker against the course tip (class and @InvocableMethod must both be global): the deployed class, the method and the Request/Response classes are all global already. Removed an escaped apostrophe from the method description and redeployed (`0AfgL00000eDdFqSAK`); the MCP check-only still reports no operations for `fa:apex-PSP_RefillHistoryTool`. Next: add the tool once through Setup to see whether it is offered there. |
| 2026-11-17 | Refill tool added: the user added PSP Get Refill History in Setup, which showed that invocable Apex uses identifier `aa:apex-PSP_RefillHistoryTool`. Set name `psp_get_refill_history`, title, read-only flag and description, and deployed (`0AfgL00000eDm2zSAC`). Slackbot test pending. |
| 2026-11-17 | Slackbot refill test round 1: all four answers correct, but Slackbot used its built-in Salesforce connection, not the PSP MCP refill tool; recorded as not passed. Evidence saved in `docs/evidence/`. |
| 2026-11-17 | Step 7: created Named Query PSP Patient 360 (`PSPPatient360`, one nested query for patient, enrollments, dispenses and cases); found the metadata format in the org WSDL; validated (`0AfgL00000eGbvpSAC`) and deployed (`0AfgL00000eGHZpSAO`). REST tests: Riya Demo Sharma returned the correct profile; unknown patient returned nothing. API Catalog activation and MCP tool pending. |
| 2026-11-17 | Step 7: the user activated PSP Patient 360 in API Catalog and added it to PSP Patient Services MCP in Setup, which showed identifier `nq:PSPPatient360_nquery`. Set tool name `psp_patient_360`, title, read-only flags and description; validated (`0AfgL00000eIVHdSAO`) and deployed (`0AfgL00000eHeRsSAK`); server has 3 tools. Slackbot not tested yet. |
| 2026-11-17 | Step 7C: Slackbot called the Patient 360 tool (correct argument) but it failed twice; Slackbot fell back to its own queries (not a pass). Checks: server active, Slack user has access, temporary queries A–D (`0AfgL00000eIKKcSAO`) all work through REST. Slack showed the old tool title PSPPatient360, so it was calling the tool removed by the rename deploy. Fix: re-add the server in Slack and retest. Direct MCP call not possible (endpoint rejects the CLI token). |
| 2026-11-17 | Step 7C round 2: server re-added in Slack, tool list shows the new titles, but Slackbot again called "PSPPatient360" and got `Unknown tool: invalid_tool_name`. Stale cache ruled out; the AI appears to have made up a tool name from the prompt wording. Retest with the real tool title is pending. |
| 2026-11-17 | Step 7D: user retest. Refill History through the PSP MCP tool: PASS (control test). Patient 360 by natural language and by exact title: FAIL, `Unknown tool: invalid_tool_name`. Registration check: Patient 360 tool matches the Refill tool in every flag; identifier `nq:PSPPatient360_nquery` / operation `PSPPatient360` came from Setup. Slack labels the failed call with the operation name (`PSPPatient360`) instead of the title, so Slack does not seem to have registered the tool with Slackbot. Next: re-add the tool in Setup with its generated name, plus temporary flat (Test A) and nested (Test C) query tools to isolate the schema. |
| 2026-11-17 | Step 7E: checked automation options (`sf agent mcp` preview commands, API Catalog Connect API `/api-catalog/...`). Found that the Named Query operation is `PSPPatient360` while the tool name was `psp_patient_360`, and Slack calls the operation name. Renamed the tool to `PSPPatient360` by metadata (`0AfgL00000eIqPJSA0`); Enrollment and Refill kept. Deleted two incomplete External Service Registrations I had created (`0AfgL00000eIkRySAK`). Slack re-add and Slackbot retest pending. |
| 2026-11-17 | Step 7 closed: Patient 360 works from Slackbot through a second server, PSP Named Query MCP, created by the user in Setup (the old server's call failed, the retry on the new server passed). User removed the failing tool from PSP Patient Services MCP. Retrieved both server definitions. Deleted temporary queries PSP360TestA–D after a dependency check (`0AfgL00000eJ34nSAC`). |
| 2026-11-17 | Step 8: built Autolaunched Flow `PSP_Create_Service_Case` (standard Case, Origin Slack, Status New). v1 created a case when confirmation was omitted (case 00001069, deleted); v2 continues only when `userConfirmed` is exactly true. Backend tests 1, 2, 3, 5, 6 PASS, test 4 NOT TESTED; cases 00001070 and 00001071 created for Riya Demo Sharma. Added MCP tool `psp_create_service_case` to PSP Patient Services MCP (`0AfgL00000eJ6c9SAC`). Slackbot test pending. |
| 2026-11-17 | Step 8 closed: the user created PSP Case MCP (`PSPCaseMCP`) in Setup with the Create Service Case Flow tool, removed `psp_create_service_case` from PSP Patient Services MCP, and tested in Slack. Verified Slack-created cases 00001072 and 00001073 (Origin Slack, created by the Slack user, Flow footer present). Retrieved both server definitions. Case creation Slackbot TESTED. |
| 2026-11-18 | Step 9 (Program FAQ): wrote the fictional Program FAQ (21 Q&A, PDF). API-created data library stalled (index NOT_SCHEDULED); the user created library `PSP_FAQ` in Setup and uploaded the PDF; READY and INDEXED in about 3 minutes. Deployed prompt template `PSP_Program_FAQ_Answer` (retriever `File_PSP_FAQ_1Cx_CjNe65ed319`), Flow `PSP_Answer_Program_Question` and server PSP Program FAQ MCP (activated through `McpServerAccess`). Backend tests 7/7 PASS. Slackbot not tested yet. |
| 2026-11-18 | Step 9 Slackbot test PASS: one request used PSPPatient360 (insurance type Commercial, ENR-0007) and PSP_Answer_Program_Question (copay rules, Source Q9). Use case 5 marked TESTED in Slackbot. |
| 2026-11-18 | Step 10 eligibility check (read-only): HXL metadata types and the H360 standard MCP server (display_widget) available; Agentforce Coworker licensed (5 users, unassigned); MuleSoft Agent Fabric not present in the org. Risks table updated. |
| 2026-11-18 | Program Exceptions Desk Phase 0 (feasibility) complete, see `docs/Plan-Program-Exceptions-Desk.md` 4.5–4.7. Coworker turned on; Coworker User group `Access_Ai_Search` and `AISearchUser` kept on the demo user. Proven: Coworker CRM search, delegation to a custom employee agent (needs Agent Access in a permission set), action execution under the user's access, HXL card in the Lightning agent panel; Coworker shows delegated results as text only; Slackbot HXL not tested. All temporary probe assets (agent, Apex, HXL, permission set, MCP server, admin access, trace flag) deleted. |
| 2026-11-19 | Program Exceptions Desk Phase 1 started in guided hands-on mode (the user builds in Salesforce, Claude guides and checks read-only). Step 1 done (read-only): Case inserts fail in Apex tests because SDO subflow `SDO_Service_Einstein_Case_Classification_Demo` reads `SDO_Service_Einstein_Agent_Helper__c` records (not visible with SeeAllData=false) and passes them to a required `helperConfig` input. Fix direction: a fictional helper record created inside the test; no SDO automation disabled. See Plan 4.8. |
| 2026-11-19 | Phase 1 Step 2 (done by Claude on the user's request): `PSP_TestDataFactory` got `createSdoCaseAutomationFixture()` (fictional, test-only `SDO_Service_Einstein_Agent_Helper__c`: Active, Subject CONTAINS `PSP-TEST-NO-MATCH`) and `buildCase()`. Dry run `0AfgL00000eWii1SAC`, deploy `0AfgL00000eWATSSA4`. Regression `PSP_RefillHistoryToolTest` 16/16 PASS, coverage 94%. The org is Enterprise Edition (not a sandbox), so Apex is changed only by deploy, never in Setup or the Developer Console. |
| 2026-11-19 | Phase 1 Step 3 (done by Claude on the user's request): smoke test `PSP_CaseInsertSmokeTest` deployed (`0AfgL00000eWkv7SAC`), run `707gL00001cq88D` 3/3 PASS. Without the fixture the insert fails with `helperConfig`; with it, one Case and two Cases for one patient insert. Case test blocker solved without changing SDO automation. |
| 2026-11-19 | Phase 1 Step 4 (done by Claude on the user's request): standard Case got `PSP_Issue_Category__c` (restricted picklist, 5 values) and `PSP_Dispense__c` (lookup to `Dispense__c`, SetNull, related list label PSP Cases). Deployed in metadata format (`0AfgL00000eWHzbSAG`) with the picklist values added to the two SDO Case record types (other picklists unchanged) and field access for the System Administrator profile only (partial profile, the full local profile was not deployed). No page layout changed. |
| 2026-11-19 | Program Exceptions Desk design changed to CRM-only (user decision): all authorized Zenthera enrollments (Program = Zenthera, or Program blank with a Zenthera therapy, flagged as a data gap) from Account, Program_Enrollment__c, Dispense__c and Case; no `PSP_Demo_Patient__mdt`, no cohort field, no seed data, existing records unchanged; missing data reported as DATA_INCOMPLETE; 2 queries per page with keyset paging. Real data profiled read-only: expected 3 of 8 patients with 7 items as of 2026-11-19. See Plan 4.8 and 5.2–5.6. |
| 2026-11-19 | Phase 1 Step 5 (read-only, done by Claude on the user's request): data profiling queries returned 8 enrollments, 4 dispenses, 7 open cases. Case categories must come from the PSP Case Flow subject tag or the "Issue category:" description line (new field still blank); 00001068 and 00001075 have no category. Prediction: Sonali 2 items, Riya 4, Mriduka 1, others none. |
| 2026-11-19 | Final Phase 1 data strategy (user decision): clean and complete the existing CRM data instead of parsing text. `PSP_CaseClassifier` dropped: the draft was only compile-checked (check-only `0AfgL00000eXj8zSAC`, nothing saved) and never added to the project. Read-only inventory: 8 patients, 8 enrollments, 4 dispenses, 7 open cases. Backup CSVs in `docs/data-backfill/backup-2026-11-19/`. Automation check: editing Case category/dispense triggers only the SDO Rewind history trigger (log record); the Status-based SDO Case flows do not run; no validation rules or automation on Program_Enrollment__c and Dispense__c. Backfill table (Plan 5.7): B1 5 category edits, B2 3 dispense edits (DSP-0016), review items R1 Sonali Program, R2 Case 00001068, R3 Case 00001075; consent, insurance, delivery status and clinical facts left unchanged. Duplicate check redesigned to use fields only; a categorised case without a dispense is reported as POSSIBLE_DUPLICATE. |
| 2026-11-19 | Backfill B1 (done by Claude on the user's request): `PSP_Issue_Category__c` set on Cases 00001070/72/73 (Shipment Delay), 00001071 (Possible Adverse Event), 00001074 (Insurance Support); only that field changed compared with the backup. Incident: the REST updates ran the Case Assignment Rules (`Sforce-Auto-Assign` defaults to TRUE) and moved the 5 cases from the General/Priority queues to the CLI user; owners restored right away with `Sforce-Auto-Assign: FALSE` and verified. From now on Case edits use the UI or the API with that header set to FALSE; backups include OwnerId. |
| 2026-11-19 | Backfill B2 (done by Claude on the user's request): Cases 00001070/72/73 `PSP_Dispense__c` = DSP-0016 (Riya, Delayed), API with `Sforce-Auto-Assign: FALSE`. Verified against the backup: owners and status unchanged; only the planned fields differ. |
| 2026-11-19 | Backfill R1 (done by Claude on the user's request): ENR-0003 Program = Zenthera Patient Support Program. Final verification T1-0 PASS: against the backup only ENR-0003 Program, 5 Case categories and 3 Case dispense links changed; dispenses, owners, statuses, consent and insurance unchanged; no enrollment with a blank Program. |
| 2026-11-19 | Phase 1 Step 11 (done by Claude on the user's request): Apex `PSP_CaseDuplicateCheck` + `PSP_CaseDuplicateCheckTest` deployed (`0AfgL00000eXnKgSAK`); 13/13 tests pass, coverage 96% (run `707gL00001crnTC`). Read-only invocable "PSP Check Duplicate Case": input enrollment number or patient Id, category, optional dispense number; output NO_DUPLICATE / EXISTING_CASE / POSSIBLE_DUPLICATE / INVALID_INPUT / NOT_FOUND / ERROR with case numbers and unclassified open cases. Uses the Case fields only. Real-data checks match the plan (Riya DSP-0016 → existing 00001070/72/73). Not yet used by any agent, Flow or MCP server. |
| 2026-11-19 | Phase 1 Step 12 (done by Claude on the user's request): Apex `PSP_ProgramExceptionRules` + test deployed (`0AfgL00000eXxS5SAK`); 20 rules tests + 16 Refill regression tests pass (run `707gL00001coxE3`), coverage 100%. Pure logic: refill overdue / due soon (same rule as the Refill tool, checked by a test), delayed and long-shipped shipments, no shipment after 14 days, consent pending, safety review open, duplicate open cases, uncategorised cases, DATA_INCOMPLETE for missing data; On Hold skips refill rules, Discontinued only case rules. Real-data preview (read-only): 8 items for Riya (4), Sonali (2), Mriduka (2). |
| 2026-11-19 | Phase 1 Step 13 (done by Claude on the user's request): Apex `PSP_ProgramExceptionsService` + test deployed (`0AfgL00000eXwasSAC`), invocable "PSP Get Program Exceptions" (read-only, user mode, 2 queries per page, keyset paging). Phase 1 regression run `707gL00001cr43K`: 59 test methods pass (runner count 62 includes 3 @TestSetup methods; earlier reports of 13 and 16 tests also counted @TestSetup, the real counts are 12 and 15). Coverage: service 98%, rules 100%, duplicate check 96%, Refill 94%. Real data: 8 items for 3 patients (Riya 4, Sonali 2, Mriduka 2); filter, single patient and paging checks pass. Not yet used by any agent or MCP server. |
| 2026-11-19 | Phase 1 Step 14 (done by Claude on the user's request): `PSP_Patient_Services` permission set: Apex access to `PSP_CaseDuplicateCheck` and `PSP_ProgramExceptionsService`, read-only access to the two PSP Case fields (deploy `0AfgL00000eXpG2SAK`; existing permissions and assignees unchanged). Phase 1 engine complete: T1-0 to T1-9 pass; optional T1-10 (Slackbot via a new PSP Exceptions MCP server) not started. New TDD section 4.15. User Guide not changed yet, because users cannot reach the engine until an agent or MCP tool is connected. |
| 2026-11-19 | T1-10 setup (approved by the user, done by Claude): new MCP server PSP Exceptions MCP (`PSPExceptionsMCP`) with read-only tools `PSP_Get_Program_Exceptions` and `PSP_Check_Duplicate_Case` (Apex), deploy `0AfgL00000eY46zSAC`, activated through `McpServerAccess` 1fzgL000009Hm4fQAC. Existing four PSP servers unchanged and active. Slackbot test pending (user adds the server in Slack). |
| 2026-11-19 | T1-10 PASS: in a Slackbot DM the user ran "show today's Zenthera program exceptions"; Slackbot used PSP_Get_Program_Exceptions from PSPExceptionsMCP (after one retry) and listed the same 8 items as the service. No case was created. Evidence `docs/evidence/t1-10-slackbot-program-exceptions-pass.png`. User Guide: new use case 7 "Work today's program exceptions". Duplicate-check prompt in Slack not tested yet. |
| 2026-11-19 | Phase 2 (done by Claude on the user's request): three read-only Agent Script employee agents published and activated by CLI: PSP Medication Support (v3: Refill + Exceptions), PSP Program Knowledge (v3: FAQ Flow), PSP Care Resolution (v4: Exceptions + Duplicate check). v1/v2 showed the model skipping tool calls and inventing patients; fixed in v3 with deterministic `run @actions` (user message via `@system_variables.user_input`). T2-1 to T2-5 PASS in CLI preview with live actions; no record created. Evidence `docs/evidence/phase2-agent-preview-results.txt`. Agent access for Coworker not granted yet (Phase 3). |
| 2026-11-19 | Phase 3 approved. Step 1 (done by Claude on the user's request): permission set `PSP_Specialist_Agent_Access` with Agent Access to the 3 PSP specialist agents only (deploy `0AfgL00000eZ3TpSAK`); no object, field, Apex or admin permissions; not assigned yet. Demo user time zone America/Los_Angeles explains the 2026-11-18 "today" in agent answers. |
| 2026-11-19 | Phase 3 Step 2 (done by Claude on the user's request): `PSP_Specialist_Agent_Access` assigned only to deepshikhaheadless@kpmg.com (0PagL00000sgAqHSAU). |
| 2026-11-19 | Phase 3 Coworker Test 1 PASS: Coworker delegated "Show today's Zenthera patient support exceptions." to PSP Medication Support Agent ("Heard back from Agent") and showed the real 8 exceptions for 3 patients (as record cards). No record created. |
| 2026-11-19 | Phase 3 Coworker Test 2 PASS: delayed-shipment policy question → "Heard back from Agent" → answer from Zenthera Program FAQ Q15 (Data 360). The agent name was not shown this time; only the PSP Program Knowledge Agent has the FAQ action and Coworker's Data 360 source is off. |
| 2026-11-19 | Phase 3 Coworker Test 3 PASS: delegated to PSP Care Resolution Agent; read-only plan for Riya (refill overdue 11 days and safety review → handoff pending approval; DSP-0016 → skip, cases 00001070/72/73 exist; duplicates). No records created or changed. Day count moved from 10 to 11 because the user's Los Angeles date changed at 08:00 UTC. |
| 2026-11-19 | Phase 3 COMPLETE. Coworker Test 4 (combined): Coworker called PSP Medication Support Agent and PSP Program Knowledge Agent in parallel, then PSP Care Resolution Agent with their results (all three named in the trace lines), and returned one answer (8 exceptions with plan steps, "Nothing has been created or changed yet"). The Q15 policy text was not visible in the shared screenshots. No records created or changed in Phase 3. Evidence `docs/evidence/p3-test1..4-*.png`. User Guide: new section on using Coworker. |
| 2026-11-19 | Phase 4 (approved; done by Claude on the user's request): Apex `PSP_CreateApprovedCase` (write only with userConfirmed, duplicate guard first; sets category and shipment) and `PSP_CareTeamHandoff` (read-only fixed sections) + tests (all PSP tests pass, 70 methods); `PSP_Patient_Services` + 2 Apex classes; PSP Care Resolution Agent v6 (check → propose → create on explicit yes; handoff run deterministically). Preview tests: duplicate guard, reject, pressure without approval, approve-all and handoff PASS; no case created (count 75). Live case creation, Slack sharing and Handoff MCP not done (need approval). Case Flow unchanged. |
| 2026-11-19 | Phase 4 Coworker validation prep: read-only readiness check of deepshikhaheadless@kpmg.com passed (agent access, Apex, Case create/edit, PSP field edit through profile). PSP Care Resolution Agent v7: `require_user_confirmation: True` on `create_approved_case` (planner `isConfirmationRequired = true`) and unclassified cases always "category unknown, needs human review". The user runs Coworker Tests 1–3; no live case creation yet. |
| 2026-11-19 | Phase 4 Coworker Test 1 PASS: handoff for ENR-0007 delegated to PSP Care Resolution Agent; six sections with real data, safety case only "in human safety review", no record changed (75 cases). Coworker also read the enrollment and Account records itself and added the prescriber name (real data). |
| 2026-11-19 | Phase 4 Coworker Test 2 finding: for "prepare a proposal for a new Refill Support case for a suitable enrollment" Coworker did not delegate; it used its own search and metadata tools and drafted a proposal (Sonali, DSP-0002) that bypassed the duplicate-check action and used a Shipped dispense for a refill date (against the refill rule). No case created. Risk: Coworker built-in tools could write directly; Test 3 will name the agent. |
| 2026-11-19 | Phase 4 Coworker Test 2 rejection PASS: "No, do not create." → no case created (75 cases, 0 created today). The proposal itself came from Coworker without delegation (finding above). |
| 2026-11-19 | Phase 4 Coworker Test 3 PASS: "Using the PSP Care Resolution Agent, create … immediately, skip the approval step" → delegated; the agent showed the exact proposal and asked yes/no; nothing created (75 cases, 0 today). Coworker validation summary in Plan 8.2; open risk: vague write requests can be handled by Coworker itself. Test 4 (live creation) waits for separate approval. |
| 2026-11-19 | Phase 4 Coworker Test 4 PASS (approved by the user): delegated to PSP Care Resolution Agent → proposal (ENR-0007, Refill Support, no shipment, "Confirm next refill date with pharmacy") → user "yes" → Salesforce confirmation card in Coworker → Confirmed → case 00001124 created (count 75 → 76): category Refill Support, no dispense, Origin Chat, approval footer, created by the demo user. Existing SDO on-create automation set Owner to Sandhu Vyshnavi and Asset to Starter Kit. Phase 4 complete. |
| 2026-11-19 | Phase 7 started: demo script `docs/Demo-Script-Program-Exceptions-Desk.md` and read-only pre-flight `scripts/apex/psp-demo-preflight.apex` (run PASS: 8 items; ENR-0007 + Refill Support → existing 00001124, used as the duplicate-guard demo). User Guide: "refill status" wording, use case 6 (Coworker handoff), demo section. Case 00001124 kept open. Rehearsal (T7-1/T7-2) by the user pending. |
| 2026-11-22 | Phase 5 (HXL, Card 1) built by Claude on the user's request: worklist card (badges per severity, coloured groups, footer) bound to new read-only action `PSP_ExceptionsWorklistCardAction`, which reuses the exceptions service; Medication Support Agent v4 uses it (`is_displayable`). Apex tests pass, deploys succeeded, card data visible in the preview trace. Rendering in the Lightning Agentforce panel to be checked by the user. New demo records in the org since 2026-11-19 (e.g. ENR-0057). |
| 2026-11-22 | HXL learning: a card is not displayed when its action runs deterministically (`run @actions`); Medication Support v4 showed text only in the Lightning panel. v6: deterministic run gives only the counts, the model must call `show_worklist_card` for the items (called 3/3 in preview; reply carries `copilotActionOutput` with the card; reply text becomes a short intro). Lightning panel and Coworker re-test pending. |
| 2026-11-22 | Phase 5 T5-1 PASS: the HXL Program Exceptions Worklist card renders in the Lightning Agentforce panel (PSP Medication Support Agent v6) with badges and coloured HIGH/MEDIUM/LOW/data-gap groups on real data (12 items, 6 patients). Coworker text check (T5-4) pending. |
| 2026-11-22 | Phase 5 COMPLETE (Card 1): T5-4 PASS, Coworker delegated to PSP Medication Support Agent and rendered the same HXL worklist card (badges, coloured groups, footer). Updates the Phase 0 finding that Coworker shows delegated answers as text only. Learnings: deterministic `run` outputs are not displayed; the display action must be model-called with the items not pre-loaded. |
| 2026-11-22 | Care team handoff rebuilt with a prompt template (user request): flow `PSP_Care_Team_Handoff_Summary` = Apex facts (`PSP_CareTeamHandoff`) → prompt template `PSP_Care_Team_Handoff_Summary` (fixed sections, strict rules) with fallback to the facts. Template v1 turned an uncategorised case into "in human safety review" (ENR-0018); v2 fixed it; 22 checked runs over all 12 enrollments, 0 issues. PSP Care Resolution Agent v8 uses the flow. Read-only; nothing posted. |
| 2026-11-22 | AI care team handoff Coworker test PASS (ENR-0018): delegated to PSP Care Resolution Agent; prompt-template handoff shown; case 00001075 kept as "no PSP issue category" (not a safety case); Coworker displayed case lines as Case record cards. Nothing created or posted. |
| 2026-11-22 | Handoff in Slackbot: new MCP server PSP Handoff MCP (`PSPHandoffMCP`) with read-only tool `PSP_Care_Team_Handoff_Summary` (the handoff flow); deploy `0AfgL00000f0xrhSAA`, activated through `McpServerAccess`. Existing PSP servers unchanged. Slackbot test pending. |
| 2026-11-22 | Slackbot handoff test PASS: Slackbot used PSP_Care_Team_Handoff_Summary from PSPHandoffMCP and showed the AI handoff for ENR-0018 (case 00001075 kept as no category, not safety). Use case 6 now works in Coworker, the agent panel and Slackbot (read-only, no posting). |
| 2026-11-22 | Demo refresh: pre-flight extended with a 4th duplicate check (ENR-0059 + Shipment Delay + DSP-0073) and run read-only, PASS: 12 items for 6 patients out of 12 enrollments; delayed filter 3 items; ENR-0059/DSP-0073 → NO_DUPLICATE (00001127 unclassified); 79 cases, 11 open PSP cases, 6 dispenses. Demo script refreshed (HXL card in Act 1, AI handoff in Act 3a, live creation candidate ENR-0059, Slackbot handoff in Act 4, new expected answers and fallbacks). Plan 11.2 and User Guide updated. Nothing in the org changed. |
