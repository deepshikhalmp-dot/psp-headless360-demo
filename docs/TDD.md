# Technical Design Document (TDD): Zenthera Patient Support Program on Salesforce Headless 360

**Version:** 2.0, 2026-11-22 (complete rewrite as a self-contained technical reference)
**Status:** all components in this document are deployed and tested in the org unless marked otherwise.

**How to use this document.** It describes every technical component of the demo: what it does, where its source is, its inputs and outputs, its rules, who calls it, how it was tested, and how to deploy or change it. It is written so that a reader, or an AI assistant that this file is uploaded to, can answer questions such as "what does `PSP_CaseDuplicateCheck` do?", "how does Slackbot reach Salesforce?" or "why is a case shown as uncategorised?" from this file alone. Section 23 lists common questions with the section that answers them.

- **Data:** synthetic only. Zenthera is a fictional drug, and all patients, prescribers and pharmacies are fictional. No real patient data (PHI) is used.
- **Safety:** a possible adverse event is only logged as a Case for human pharmacovigilance review. Nothing is reported to a regulator automatically, and no component gives clinical advice.

---

## Contents

1. Purpose and scope
2. Org, project and environment
3. Architecture
4. Component register
5. Data model
6. Security and access
7. Business rules reference
8. Apex classes
9. Flows
10. Named Query: PSP Patient 360
11. Prompt templates
12. Data 360: Program FAQ library
13. MCP servers (Slackbot)
14. Agentforce specialist agents
15. Agentforce Coworker integration
16. HXL card: Program Exceptions Worklist
17. End-to-end request flows
18. Lightning app, layouts and list views
19. Testing
20. Deployment and operations
21. Known limitations, risks and lessons learned
22. Not built (future options)
23. Questions this document answers
24. Glossary
25. Activity log

---

## 1. Purpose and scope

### 1.1 Business story

A pharma company runs a patient support program (PSP) for its specialty drug, Zenthera. A **Patient Services Coordinator** enrolls patients, tracks refills, answers program questions, logs service cases and possible side effects, hands patients over to the care team, and works a daily list of program exceptions.

The demo shows **Salesforce Headless 360**: one set of business logic on standard Salesforce data, reached through several front doors:

| Front door | What the coordinator uses | How it reaches Salesforce |
|---|---|---|
| Salesforce app | **Patient Support Program** Lightning app (manual work) | Standard record pages |
| Slack | **Slackbot** in a direct message | Salesforce-hosted **custom MCP servers** (section 13) |
| Salesforce AI | **Agentforce Coworker** ("Ask") and the **Agentforce panel** | Three **specialist agents** written in Agent Script (section 14) |

### 1.2 Use cases

| # | Use case | Salesforce app | Slackbot (MCP) | Agents / Coworker |
|---|---|---|---|---|
| 1 | Enroll a new patient | Yes | Yes (PSP Patient Services MCP → Enroll flow) | No |
| 2 | Check refill status | Yes (dispenses list) | Yes (PSP Patient Services MCP → Refill Apex) | Yes (Medication Support Agent) |
| 3 | See a patient's full profile | Yes | Yes (PSP Named Query MCP → Patient 360) | No |
| 4 | Log a service case or a possible side effect | Yes | Yes (PSP Case MCP → Create Service Case flow) | Yes, only after approval (Care Resolution Agent → Create Approved Case Apex) |
| 5 | Answer a program question | No | Yes (PSP Program FAQ MCP → FAQ flow) | Yes (Program Knowledge Agent) |
| 6 | Hand over to the care team (read-only summary) | No | Yes (PSP Handoff MCP → Handoff flow) | Yes (Care Resolution Agent) |
| 7 | Work today's program exceptions | No | Yes (PSP Exceptions MCP) | Yes, shown as an HXL card (Medication Support Agent), plus a resolution plan (Care Resolution Agent) |

Use case 7 with its agents is called the **Program Exceptions Desk**. Its phase plan and detailed execution logs are in `docs/Plan-Program-Exceptions-Desk.md`.

### 1.3 Out of scope

- Real patient data, clinical advice, automatic regulatory (adverse event) reporting.
- Posting patient information to Slack channels (only direct-message answers are used).
- MuleSoft Agent Fabric (not available in this org; presented as a next step).
- A custom orchestrator or agent router (Coworker chooses agents by their description).
- External AI clients outside Salesforce and Slack.

### 1.4 Design principles

1. **One logic, many channels.** Each rule lives in one Apex class or Flow. MCP tools and agent actions call the same code.
2. **Rules decide the facts; AI only writes words.** Refill dates, exceptions and duplicates are computed by Apex. AI is used only to word an answer (FAQ answer, handoff summary) from facts it is given.
3. **Read-only by default.** Only three components write: the Enroll flow, the Create Service Case flow and `PSP_CreateApprovedCase`. All three require explicit user approval.
4. **User mode everywhere.** Every query and write runs as the signed-in user (`WITH USER_MODE`, `AccessLevel.USER_MODE`, flows in default user context), so sharing and field security apply.
5. **Never guess.** Missing data is reported as a data gap. A case without a category is never treated as a safety case. Nothing is said about whether a patient takes the medication (refill status reflects recorded shipments only).

---

## 2. Org, project and environment

| Item | Value |
|---|---|
| Org | ProductPillarSDO, Org ID `00DgL00000hTCjNUAW`, My Domain `https://kp1793615031857.my.salesforce.com` |
| Edition | Enterprise Edition (production-type SDO, not a sandbox). Apex can only be changed by deploy, never in Setup. Trial ends 2027-02-28 |
| CLI aliases | `ProductPillarSDO` and `ProductPillarSDO1` (same org) |
| Salesforce CLI | `@salesforce/cli` 2.150.6, `agent` plugin for Agent Script |
| Project | Salesforce DX, `sourceApiVersion` 68.0, source in `force-app/main/default` |
| Demo users | `sanduvyshnavi@kpmg.com.sdo` (admin, PSP Patient Services); `deepshikhaheadless@kpmg.com` (presenter, Slack-linked user and Coworker user: PSP Patient Services, PSP Specialist Agent Access, Coworker group `Access_Ai_Search`). Time zone of the demo user: America/Los_Angeles |
| Slack | Trailhead workspace TH-Sd0CJ4CZN58D, connected to the org; Slack signs in as `deepshikhaheadless@kpmg.com` |
| Licences used | Agentforce (employee agents), Agentforce Coworker (5 seats), Einstein Prompt Templates, Data Cloud (Data 360) |
| Docs | `docs/TDD.md` (this file), `docs/User-Guide.md`, `docs/Plan-Program-Exceptions-Desk.md`, `docs/Demo-Script-Program-Exceptions-Desk.md`, evidence in `docs/evidence/` |
| Scripts | `scripts/apex/psp-demo-preflight.apex` (read-only demo check) |

---

## 3. Architecture

### 3.1 Layers

| Layer | Product | Role |
|---|---|---|
| System of Engagement | Slack (Slackbot), Salesforce UI (Coworker, Agentforce panel, Lightning app) | Where the coordinator asks and acts |
| System of Agency | Agentforce (3 specialist employee agents, Coworker) | Reasoning, choosing actions |
| System of Work | Salesforce CRM (this org) | Data, Apex, Flows, Named Query, prompt templates, MCP servers |
| System of Context | Data 360 | Program FAQ PDF, searched by a retriever (RAG) |
| Experience | HXL (Lightning Type + UI Widget) | Visual worklist card in Coworker and the agent panel |

### 3.2 Overall diagram

```
                          Patient Services Coordinator
          ┌──────────────────────┬──────────────────────┬──────────────────────┐
          ▼                      ▼                      ▼                      │
  Salesforce app          Slackbot (DM)          Agentforce Coworker / panel   │
  (manual records)              │                       │                      │
                                │ MCP (as the user)     │ delegates by agent description
     ┌──────────────┬───────────┼─────────────┬─────────┴──┐                   │
     ▼              ▼           ▼             ▼            ▼                   │
 PSP Patient    PSP Named   PSP Case    PSP Program   PSP Exceptions   PSP Handoff
 Services MCP   Query MCP   MCP         FAQ MCP       MCP              MCP
 Enroll, Refill Patient 360 Create Case Answer FAQ    Exceptions,      Handoff flow
                                                      Duplicate check
                                                                 ┌───────────────┐
                Medication Support Agent ── Refill, Exceptions, HXL card action │
                Program Knowledge Agent  ── FAQ flow                            │
                Care Resolution Agent    ── Exceptions, Duplicate check,        │
                                            Create Approved Case, Handoff flow  │
                                                                 └───────────────┘
                                    │
                                    ▼
   Apex: PSP_RefillHistoryTool · PSP_ProgramExceptionsService (+ PSP_ProgramExceptionRules)
         PSP_CaseDuplicateCheck · PSP_CreateApprovedCase · PSP_CareTeamHandoff
         PSP_ExceptionsWorklistCardAction (+ PSP_ExceptionsWorklistCard)
   Flows: PSP_Enroll_Patient · PSP_Create_Service_Case · PSP_Answer_Program_Question
          PSP_Care_Team_Handoff_Summary
   Named Query: PSPPatient360 · Prompt templates: PSP_Program_FAQ_Answer, PSP_Care_Team_Handoff_Summary
   Data 360: PSP_FAQ data library and retriever
                                    │
                                    ▼
   Account (Person Account = patient) ─< Program_Enrollment__c ─< Dispense__c
   Account ─< Case  (Case.PSP_Issue_Category__c, Case.PSP_Dispense__c → Dispense__c)
```

### 3.3 Request paths

- **Slackbot:** coordinator asks in a Slack DM → Slackbot picks a tool by its title and description → the Salesforce-hosted MCP server runs the Flow, Apex or Named Query **as the linked Salesforce user** → Slackbot formats the result and shows "Used <tool> from <server>".
- **Coworker:** coordinator asks in Coworker → Coworker reads the descriptions of the agents the user has Agent Access to → delegates ("Heard back from <agent>") → the agent runs its actions as the user → Coworker shows the answer (text, record cards or the HXL card).
- **Agentforce panel:** the same agents opened directly in the Lightning Agentforce side panel.

### 3.4 Reuse map (which channel calls which logic)

| Logic | Slackbot tool | Agent action |
|---|---|---|
| `PSP_Enroll_Patient` flow | Enroll Patient in Zenthera Program | none |
| `PSP_RefillHistoryTool` | Get Patient Refill History | Medication Support: `get_refill_history` |
| `PSPPatient360` Named Query | PSPPatient360 | none |
| `PSP_Create_Service_Case` flow | PSP_Create_Service_Case | none |
| `PSP_Answer_Program_Question` flow | PSP_Answer_Program_Question | Program Knowledge: `answer_program_question` |
| `PSP_ProgramExceptionsService` | PSP_Get_Program_Exceptions | Medication Support and Care Resolution: `get_program_exceptions` |
| `PSP_ExceptionsWorklistCardAction` | none | Medication Support: `get_worklist_card` (HXL) |
| `PSP_CaseDuplicateCheck` | PSP_Check_Duplicate_Case | Care Resolution: `check_duplicate_case` |
| `PSP_CreateApprovedCase` | none | Care Resolution: `create_approved_case` (write, confirmation) |
| `PSP_Care_Team_Handoff_Summary` flow | PSP_Care_Team_Handoff_Summary | Care Resolution: `prepare_handoff` |

---

## 4. Component register

**Status values:** Built locally → Validated → Deployed → Active / Tested. Paths are relative to `force-app/main/default/`.

### 4.1 Data model and UI

| Component | Type | Path | Status |
|---|---|---|---|
| Program Enrollment | Custom object, 9 fields | `objects/Program_Enrollment__c/` | Deployed |
| Dispense | Custom object, 5 fields | `objects/Dispense__c/` | Deployed |
| PSP Issue Category | Custom field on Case (restricted picklist) | `objects/Case/fields/PSP_Issue_Category__c.field-meta.xml` | Deployed |
| PSP Dispense | Custom field on Case (lookup to Dispense) | `objects/Case/fields/PSP_Dispense__c.field-meta.xml` | Deployed |
| Program Enrollment and Dispense tabs | Custom tabs | `tabs/Program_Enrollment__c.tab-meta.xml`, `tabs/Dispense__c.tab-meta.xml` | Deployed |
| Patient Support Program | Lightning app | `applications/Patient_Support_Program.app-meta.xml` | Deployed |
| Program Enrollment Layout, Dispense Layout | Page layouts | `layouts/` | Deployed |
| Person Account Layout | Shared layout (PSP additions only) | `layouts/PersonAccount-Person Account Layout.layout-meta.xml` | Deployed |
| PSP Patients | List view on Account | `objects/Account/listViews/PSP_Patients.listView-meta.xml` | Deployed |
| PSP Patient | Compact layout (Person Account record type) | `objects/PersonAccount/compactLayouts/PSP_Patient.compactLayout-meta.xml` | Deployed |

### 4.2 Logic

| Component | Type | Path | Status |
|---|---|---|---|
| `PSP_RefillHistoryTool` | Global invocable Apex, read-only | `classes/PSP_RefillHistoryTool.cls` | Active, Slackbot tested |
| `PSP_ProgramExceptionRules` | Apex, pure rules (no SOQL/DML) | `classes/PSP_ProgramExceptionRules.cls` | Deployed |
| `PSP_ProgramExceptionsService` | Invocable Apex, read-only | `classes/PSP_ProgramExceptionsService.cls` | Active, Slackbot, agents, Coworker tested |
| `PSP_CaseDuplicateCheck` | Invocable Apex, read-only | `classes/PSP_CaseDuplicateCheck.cls` | Active, agents and Coworker tested |
| `PSP_CreateApprovedCase` | Invocable Apex, **write with approval** | `classes/PSP_CreateApprovedCase.cls` | Active; created case 00001124 after approval |
| `PSP_CareTeamHandoff` | Invocable Apex, read-only (facts) | `classes/PSP_CareTeamHandoff.cls` | Active |
| `PSP_ExceptionsWorklistCard` | Global Apex output type for HXL | `classes/PSP_ExceptionsWorklistCard.cls` | Deployed |
| `PSP_ExceptionsWorklistCardAction` | Invocable Apex, read-only, returns the card | `classes/PSP_ExceptionsWorklistCardAction.cls` | Active, card renders in Coworker and panel |
| `PSP_TestDataFactory` | Test helper | `classes/PSP_TestDataFactory.cls` | Deployed |
| 8 test classes | Apex tests | `classes/PSP_*Test.cls` | All pass |
| `PSP_Enroll_Patient` | Autolaunched flow, write | `flows/PSP_Enroll_Patient.flow-meta.xml` | Active v2, Slackbot tested |
| `PSP_Create_Service_Case` | Autolaunched flow, write | `flows/PSP_Create_Service_Case.flow-meta.xml` | Active v2, Slackbot tested |
| `PSP_Answer_Program_Question` | Autolaunched flow, read-only | `flows/PSP_Answer_Program_Question.flow-meta.xml` | Active, Slackbot and agent tested |
| `PSP_Care_Team_Handoff_Summary` | Autolaunched flow, read-only | `flows/PSP_Care_Team_Handoff_Summary.flow-meta.xml` | Active, Coworker and Slackbot tested |
| `PSPPatient360` | API Named Query | `apiNamedQueries/PSPPatient360.apiNamedQuery-meta.xml` | Active, Slackbot tested |
| `PSP_Program_FAQ_Answer` | Flex prompt template with retriever | `genAiPromptTemplates/PSP_Program_FAQ_Answer.genAiPromptTemplate-meta.xml` | Active v1 |
| `PSP_Care_Team_Handoff_Summary` | Flex prompt template | `genAiPromptTemplates/PSP_Care_Team_Handoff_Summary.genAiPromptTemplate-meta.xml` | Active version 2 (`V1_2`) |
| PSP FAQ (`PSP_FAQ`) | Data 360 Agentforce Data Library | Created in Setup; source `docs/program-faq/` | READY, indexed |

### 4.3 Channels, agents and access

| Component | Type | Path | Status |
|---|---|---|---|
| PSP Patient Services MCP | Custom MCP server (Enroll, Refill) | `mcpServerDefinitions/PSPPatientServicesMCP.mcpServerDefinition-meta.xml` | Active, Slackbot tested |
| PSP Named Query MCP | Custom MCP server (Patient 360) | `mcpServerDefinitions/PSPNamedQueryMCP.mcpServerDefinition-meta.xml` | Active, Slackbot tested |
| PSP Case MCP | Custom MCP server (Create Service Case) | `mcpServerDefinitions/PSPCaseMCP.mcpServerDefinition-meta.xml` | Active, Slackbot tested |
| PSP Program FAQ MCP | Custom MCP server (FAQ) | `mcpServerDefinitions/PSPProgramFAQMCP.mcpServerDefinition-meta.xml` | Active, Slackbot tested |
| PSP Exceptions MCP | Custom MCP server (Exceptions, Duplicate check) | `mcpServerDefinitions/PSPExceptionsMCP.mcpServerDefinition-meta.xml` | Active; exceptions tool Slackbot tested; duplicate tool not tested in Slack |
| PSP Handoff MCP | Custom MCP server (Handoff) | `mcpServerDefinitions/PSPHandoffMCP.mcpServerDefinition-meta.xml` | Active, Slackbot tested |
| PSP Medication Support Agent | Agent Script employee agent, read-only | `aiAuthoringBundles/PSP_Medication_Support_Agent/` | Active **v6** |
| PSP Program Knowledge Agent | Agent Script employee agent, read-only | `aiAuthoringBundles/PSP_Program_Knowledge_Agent/` | Active **v3** |
| PSP Care Resolution Agent | Agent Script employee agent, one write action | `aiAuthoringBundles/PSP_Care_Resolution_Agent/` | Active **v8** |
| `pspExceptionsWorklist` | LightningTypeBundle (HXL) | `lightningTypes/pspExceptionsWorklist/` | Deployed |
| `pspExceptionsWorklistCard` | UiWidgetBundle (HXL) | `uiWidgets/pspExceptionsWorklistCard/` | Deployed |
| PSP Patient Services | Permission set | `permissionsets/PSP_Patient_Services.permissionset-meta.xml` | Deployed, assigned to both demo users |
| PSP Specialist Agent Access | Permission set (Agent Access only) | `permissionsets/PSP_Specialist_Agent_Access.permissionset-meta.xml` | Deployed, assigned to `deepshikhaheadless@kpmg.com` only |
| Demo pre-flight | Anonymous Apex, read-only | `scripts/apex/psp-demo-preflight.apex` | Run 2026-11-22, PASS |
| Demo script | Document | `docs/Demo-Script-Program-Exceptions-Desk.md` | Refreshed 2026-11-22 |
| Evidence Guide | Word document with live screenshots (generated). Section 2 "The use case at a glance": use case story, one-page flow diagram, channels table, use case x channel table, guardrails | `docs/PSP-Evidence-Guide.docx`; screenshots `docs/evidence-guide/screens/`; builder `tools/evidence-guide/build_doc.py`; flow diagram source `tools/evidence-guide/usecase_flow.html`, rendered by `render_flow.py` to `screens/U01-use-case-flow.png` | Generated 2026-11-26 |
| Agent Utilization and Cost Guide | How to measure agent usage, cost and effectiveness; design rules for low token/credit use; POC agent footprint; org monitoring status | `docs/Agent-Utilization-and-Cost-Guide.md` | Written 2026-11-26 |

---

## 5. Data model

### 5.1 Overview

Patients are standard **Person Accounts** (record type **Person Account**, developer name `PersonAccount`). Service requests are standard **Cases** linked to the patient through `AccountId`. No custom Case object is used.

```
Account (Person Account = patient)
 ├─< Program_Enrollment__c   (Patient__c, lookup, relationship Program_Enrollments__r)
 │     └─< Dispense__c        (Program_Enrollment__c, master-detail, relationship Dispenses__r)
 └─< Case                     (AccountId; ContactId = PersonContactId)
       └── PSP_Dispense__c ──▶ Dispense__c   (lookup, relationship PSP_Cases)
```

### 5.2 Program_Enrollment__c

One record per patient per program. Name is an Auto Number `ENR-{0000}` (label Enrollment ID). Sharing Read/Write. Reports, search, activities and field history on.

| Field | Type | Values / notes |
|---|---|---|
| `Patient__c` | Lookup(Account) | Lookup filter: Person Accounts only. Delete constraint Restrict |
| `Program__c` | Picklist (restricted) | Zenthera Patient Support Program (default) |
| `Therapy__c` | Picklist (restricted) | Zenthera 50 mg, Zenthera 100 mg |
| `Status__c` | Picklist (restricted) | Enrolled (default), Active, On Hold, Discontinued |
| `Enrollment_Date__c` | Date | |
| `Prescriber_Name__c` | Text(80) | |
| `Consent_Given__c` | Checkbox | Default false. The Enroll flow refuses enrollment without consent |
| `Consent_Date__c` | Date | |
| `Insurance_Type__c` | Picklist (restricted) | Commercial, Medicare, Medicaid, Uninsured (drives copay eligibility in the FAQ) |

### 5.3 Dispense__c

One record per therapy shipment. Name is an Auto Number `DSP-{0000}` (label Dispense ID). Sharing Controlled by Parent.

| Field | Type | Values / notes |
|---|---|---|
| `Program_Enrollment__c` | Master-Detail(Program_Enrollment__c) | |
| `Dispense_Date__c` | Date | |
| `Days_Supply__c` | Number(3,0) | Next refill due = Dispense Date + Days Supply |
| `Pharmacy__c` | Text(80) | |
| `Status__c` | Picklist (restricted) | Shipped (default), Delivered, Delayed, Cancelled |

### 5.4 Case (standard object, two PSP fields)

| Field | Type | Values / notes |
|---|---|---|
| `PSP_Issue_Category__c` | Picklist (restricted) | Shipment Delay, Refill Support, Insurance Support, General Program Support, Possible Adverse Event. Used by the exceptions rules and the duplicate check. Values were added to the two SDO Case record types |
| `PSP_Dispense__c` | Lookup(Dispense__c) | The shipment a case is about. Delete constraint Set Null. Related list label PSP Cases |

Other Case fields set by PSP components: `AccountId`, `ContactId`, `Subject`, `Description`, `Status` (New), `Priority`, `Origin` (Slack or Chat), `Type`. Record type is the org default.

**Data quality note.** Cases created before the two fields existed were backfilled on 2026-11-19 (5 categories, 3 shipment links; backup CSVs in `docs/data-backfill/backup-2026-11-19/`). Cases created through `PSP_Create_Service_Case` (Slackbot) or manually in the UI do **not** get a category automatically, so the exceptions service lists them as `UNCATEGORISED_OPEN_CASE` until a person sets the category (section 21).

### 5.5 Demo data (fictional)

| Patient | Enrollment | Key records (2026-11-22) |
|---|---|---|
| Riya Demo Sharma | ENR-0007 | DSP-0015 Delivered 2026-10-09 (30 days), DSP-0016 Delayed; cases 00001070/72/73 (Shipment Delay, DSP-0016), 00001071 (Possible Adverse Event), 00001124 (Refill Support, created by the agent after approval) |
| Sonali Singh | ENR-0003 | DSP-0002; case 00001068 without category; consent date missing |
| Mriduka Sharma | ENR-0018 | case 00001075 without category; consent date missing |
| Asha Manual Demo | ENR-0057 | DSP-0072 Delayed; case 00001125 (Shipment Delay) |
| Neha Slack Demo | ENR-0058 | case 00001126 without category |
| Ayush Mehta | ENR-0059 | DSP-0073 Delayed, no Shipment Delay case; case 00001127 without category |

Counts on 2026-11-22: 79 cases (all org cases), 11 open PSP cases, 12 enrollments, 6 dispenses. Records ENR-0057 to ENR-0060 were created by other users after 2026-11-19.

---

## 6. Security and access

### 6.1 Permission set: PSP Patient Services (`PSP_Patient_Services`)

| Grant | Detail |
|---|---|
| Objects | Create, read, edit, delete on `Program_Enrollment__c` and `Dispense__c` (no View All / Modify All) |
| Fields | Read and edit on all 13 non-required PSP custom fields; **read only** on `Case.PSP_Issue_Category__c` and `Case.PSP_Dispense__c` |
| Apex classes | `PSP_RefillHistoryTool`, `PSP_ProgramExceptionsService`, `PSP_CaseDuplicateCheck`, `PSP_CreateApprovedCase`, `PSP_CareTeamHandoff`, `PSP_ExceptionsWorklistCardAction` |
| Tabs and app | Program Enrollments and Dispenses tabs visible; Patient Support Program app visible |
| User permission | Run Flows (needed to call the PSP flows from Slackbot and agents) |

Creating Cases and Person Accounts uses the user's existing profile access (the demo users are System Administrators). The PSP Case field edit access for the agent's write comes from the profile.

### 6.2 Permission set: PSP Specialist Agent Access (`PSP_Specialist_Agent_Access`)

Contains only `agentAccesses` for `PSP_Medication_Support_Agent`, `PSP_Program_Knowledge_Agent` and `PSP_Care_Resolution_Agent`. No object, field, Apex or admin permissions. Coworker can only see and delegate to agents the user has Agent Access to. Assigned only to `deepshikhaheadless@kpmg.com`.

### 6.3 Coworker access

Coworker was turned on in Setup. Access comes from the permission set group **`Access_Ai_Search`** (created by Turn On; contains `AISearchUser` and `SentOS_Agent_Access`). The admin permission set `AISearchAdmin` is only needed for setup and is not assigned.

### 6.4 Runtime identity

| Channel | Runs as |
|---|---|
| Slackbot MCP tools | The Salesforce user linked to the Slack user (`deepshikhaheadless@kpmg.com`) |
| Agents in Coworker or the panel | The signed-in Salesforce user |
| Apex | `with sharing`, all SOQL `WITH USER_MODE`, the one insert uses `AccessLevel.USER_MODE` |
| Flows | Default (user) context |

### 6.5 Safety guardrails (where they are enforced)

| Guardrail | Enforced in |
|---|---|
| No write without approval | `PSP_CreateApprovedCase` (`userConfirmed` must be true), `require_user_confirmation: True` on the agent action (Salesforce confirmation card), `PSP_Create_Service_Case` (`userConfirmed` exactly true), Enroll flow (consent must be true), MCP tool descriptions |
| No duplicate cases | `PSP_CaseDuplicateCheck`, called again inside `PSP_CreateApprovedCase` |
| No adherence claims | Refill and exception texts say "based on recorded shipments only"; agent and template instructions |
| No medical advice | Agent system instructions, prompt template rules, prescriber/911 note in the handoff and FAQ |
| Safety cases only as "in human safety review" | `PSP_CareTeamHandoff` writes that wording; handoff template rule 4; agents never add detail |
| Uncategorised case is never a safety case | Rules engine (`UNCATEGORISED_OPEN_CASE`), handoff template rules 5–6, Care Resolution instructions |
| No regulatory reporting | Safety note in case descriptions; all instructions |
| No channel posting | No posting component exists; handoff tool description says DM only |

---

## 7. Business rules reference

### 7.1 Refill rule (shared by `PSP_RefillHistoryTool` and `PSP_ProgramExceptionRules`)

| # | Rule |
|---|---|
| R-1 | Only dispenses with Status = Delivered **and** both Dispense Date and Days Supply count toward supply |
| R-2 | Next refill due = latest counted Dispense Date + its Days Supply |
| R-3 | Days overdue = max(0, as-of date − due date) |
| R-4 | LATE if the as-of date is after the due date; DUE if due within 7 days (inclusive); otherwise ON_TRACK; NO_DELIVERED_REFILL if nothing counts |
| R-5 | Patient name with 0 matches → NOT_FOUND; 2+ → AMBIGUOUS_MATCH (ask for the ENR number); patient without enrollment → NO_ENROLLMENT |
| R-6 | Several enrollments → the most recent open (not Discontinued) one, else the most recent |
| R-7 | Texts describe recorded shipments only and never say whether the patient took the medication |

"Today" is the running user's date (Los Angeles time for the demo user), so day counts change at 08:00 UTC.

### 7.2 Program exception types (`PSP_ProgramExceptionRules`)

Scope: enrollments with Program = Zenthera Patient Support Program, or Program blank (reported as a data gap). Enrollment status Enrolled or Active gets all rules; **On Hold** skips the refill and shipment rules; **Discontinued** gets only the case rules.

| Type | Condition | Severity | Suggested action |
|---|---|---|---|
| `REFILL_OVERDUE` | Due date (R-2) is before the as-of date | HIGH if more than 7 days overdue, else MEDIUM | `PREPARE_HANDOFF` |
| `REFILL_DUE_SOON` | Due within 0–7 days | LOW | `NONE` |
| `SHIPMENT_DELAYED` | A dispense has Status Delayed | MEDIUM | `SKIP_EXISTING_CASE` if an open Shipment Delay case is linked to that dispense; `REVIEW_POSSIBLE_DUPLICATE` if an open Shipment Delay case has no dispense link; otherwise `CREATE_CASE` |
| `SHIPPED_NOT_DELIVERED` | Status Shipped and more than 7 days since the dispense date | LOW | `NONE` |
| `NO_SHIPMENT_RECORDED` | No dispense and more than 14 days since enrollment | LOW | `NONE` |
| `CONSENT_PENDING` | Consent Given is not true (not for Discontinued) | MEDIUM | `FOLLOW_UP_CONSENT` |
| `SAFETY_REVIEW_OPEN` | Open case(s) with category Possible Adverse Event | HIGH | `PREPARE_HANDOFF` |
| `DUPLICATE_OPEN_CASES` | 2+ open cases with the same category and the same dispense (or both without one) | LOW | `NONE` |
| `UNCATEGORISED_OPEN_CASE` | Open case with a blank PSP Issue Category | MEDIUM | `TRIAGE_CASE` |
| `DATA_INCOMPLETE` | Missing data: no patient, blank Program, Delivered dispense without date or days supply, Shipped dispense without date, no enrollment date and no dispense, consent given without consent date | INFO (counted as "data gap") | `REVIEW_DATA` |

Thresholds are constants in the class: `DUE_SOON_DAYS = 7`, `HIGH_OVERDUE_DAYS = 7`, `SHIPPED_NOT_DELIVERED_DAYS = 7`, `NO_SHIPMENT_DAYS = 14`. Items are sorted by severity (HIGH, MEDIUM, LOW, INFO), then patient name, then type. Free text (Subject, Description) is never read.

### 7.3 Duplicate case rules (`PSP_CaseDuplicateCheck`)

Uses only `PSP_Issue_Category__c` and `PSP_Dispense__c` of the patient's **open** cases.

| Situation | Result |
|---|---|
| Open case, same category, same dispense | `EXISTING_CASE` (do not create) |
| Request without a dispense, open case with the same category | `EXISTING_CASE` (category-level match) |
| Open case, same category, no dispense link, request has a dispense | `POSSIBLE_DUPLICATE` (a person decides) |
| Open case, same category, different dispense | Not a duplicate (separate shipment) |
| Open case without a category | Listed in `unclassifiedOpenCaseNumbers`, never blocks |
| Closed cases | Never block |
| Nothing matches | `NO_DUPLICATE`, `canCreate = true` (creation still needs approval) |

### 7.4 Case creation rules

| Rule | `PSP_CreateApprovedCase` (agent) | `PSP_Create_Service_Case` flow (Slackbot) |
|---|---|---|
| Approval | `userConfirmed = true` plus the Salesforce confirmation card | `userConfirmed` exactly true |
| Duplicate check | Yes, runs `PSP_CaseDuplicateCheck` first; EXISTING / POSSIBLE block | No |
| Patient lookup | Enrollment number | Person Account Id or exact name; refuses unknown and ambiguous |
| Subject | `[<category>] <subject>`; safety: `[SAFETY REVIEW] Possible Adverse Event - <subject>` | Same pattern |
| Priority | High for Possible Adverse Event, else Medium | Same |
| Origin | Chat | Slack |
| Type | Insurance Support → Account Support, else Product Support | Insurance Support → Account Support; General Program Support → General; others → Product Support |
| PSP fields | Sets `PSP_Issue_Category__c` and `PSP_Dispense__c` | Does **not** set them |
| Description footer | "Logged by the PSP Care Resolution Agent after explicit user approval." (+ safety note) | "Logged through the PSP Patient Services tools after user confirmation" (+ safety note) |

Safety note text: "SAFETY REVIEW REQUIRED: possible adverse event reported. Route to the safety / pharmacovigilance team for human review. No medical advice was given and no regulatory report has been submitted automatically."

Existing SDO on-create automation also runs on real creates (for example it set Owner to Sandhu Vyshnavi and Asset to Starter Kit on 00001124). PSP does not change or disable it.

### 7.5 Enrollment rules (`PSP_Enroll_Patient`)

| # | Rule |
|---|---|
| F-1 | Required: first name, last name, birthdate, therapy, insurance type; values must be allowed picklist values |
| F-2 | No enrollment without consent; nothing is created |
| F-3 | Patient match = first name + last name + full birthdate (case-insensitive), never birthdate alone |
| F-4 | Mobile, when given, separates several matches; one match with a different mobile on file is ambiguous |
| F-5 | A same-name patient without a birthdate on file is a possible match (ambiguous) |
| F-6 | Ambiguous matches create nothing and ask for human review |
| F-7 | One open enrollment (Enrolled, Active, On Hold) per patient; enrollments with a blank Program also count |
| F-8 | New enrollment: Program Zenthera, Status Enrolled, Enrollment and Consent Date today, Consent Given true |
| F-9 | New patients get the Person Account record type (looked up by developer name), birthdate and mobile |

### 7.6 Handoff rules

Fixed sections from facts (Apex), AI wording from those facts only (prompt template). Safety cases appear only as "Case <n>: in human safety review". Uncategorised cases appear as "Case <n>: no PSP issue category yet (needs review)". Next steps are non-clinical and always end with the prescriber note: "Questions about dosing, missed doses or side effects go to the patient's prescriber (911 in an emergency)."

---

## 8. Apex classes

All classes are `with sharing`, query `WITH USER_MODE`, return errors in the response (they do not throw to the caller), and are bulk-safe (queries outside loops). Invocable classes use the category **Patient Support Program**.

### 8.1 `PSP_RefillHistoryTool` (invocable "PSP Get Refill History")

| Item | Detail |
|---|---|
| Purpose | Refill status for one patient from recorded shipments (rule 7.1) |
| Visibility | `global` (class, method, Request, Response) so the API Catalog can offer it as an MCP tool |
| Inputs | `patientName` (full name as recorded) or `enrollmentNumber` (ENR-…, takes priority, case-insensitive); optional `asOfDate` (default today) |
| Outputs | `isSuccess`, `resultCode` (SUCCESS, NOT_FOUND, AMBIGUOUS_MATCH, NO_ENROLLMENT, INVALID_INPUT, ERROR), `resultMessage`, `refillStatus` (ON_TRACK, DUE, LATE, NO_DELIVERED_REFILL), `patientId`, `patientName`, `enrollmentId`, `enrollmentNumber`, `therapy`, `enrollmentStatus`, `asOfDate`, `lastDeliveredDate`, `lastDeliveredDaysSupply`, `nextRefillDueDate`, `daysOverdue`, `dispenseCount`, `deliveredCount`, `dispenseHistory` (one line per dispense, newest first, marked counted / not counted), `errorType` |
| Queries | At most 4 for any number of requests |
| Called by | MCP tool Get Patient Refill History; Medication Support Agent `get_refill_history`; `PSP_CareTeamHandoff` |
| Tests | `PSP_RefillHistoryToolTest`, 15 methods, coverage 94% |

### 8.2 `PSP_ProgramExceptionRules` (pure rules)

| Item | Detail |
|---|---|
| Purpose | Applies the exception rules (7.2) to **one** enrollment with its dispenses and open cases |
| Entry point | `public static List<ExceptionItem> evaluate(Program_Enrollment__c enrollment, List<Dispense__c> dispenses, List<Case> openCases, Date asOfDate)` |
| Output | `ExceptionItem` (Comparable): `exceptionType`, `severity`, `patientId`, `patientName`, `enrollmentNumber`, `dispenseNumber`, `caseNumbers`, `fact` (one sentence), `suggestedAction` |
| Constants | Type, severity and action names; thresholds (7.2); `PROGRAM_ZENTHERA` |
| SOQL / DML | None. The service loads the records |
| Tests | `PSP_ProgramExceptionRulesTest`, 20 methods, coverage 100% (includes a test that the refill rule matches `PSP_RefillHistoryTool`) |

### 8.3 `PSP_ProgramExceptionsService` (invocable "PSP Get Program Exceptions")

| Item | Detail |
|---|---|
| Purpose | Today's exceptions for all Zenthera patients the user can see. Patients without exceptions are not listed |
| Inputs (all optional) | `asOfDate` (default today), `enrollmentNumber` (one enrollment), `exceptionTypes` (comma separated type names), `pageSize` (1–500, default 200), `afterEnrollmentNumber` (next page) |
| Outputs | `resultCode` (SUCCESS, INVALID_INPUT, NOT_FOUND, ERROR), `resultMessage` (counts sentence), `itemsText` (one line per item: `SEVERITY \| Patient (ENR) \| TYPE \| fact \| Suggested: ACTION`), `items` (list of Item), `asOfDate`, `enrollmentsEvaluated`, `patientsWithItems`, `highCount`, `mediumCount`, `lowCount`, `dataGapCount`, `hasMore`, `nextEnrollmentNumber` |
| Query 1 | `Program_Enrollment__c` with a `Dispenses__r` subquery, `WHERE (Program__c = Zenthera OR Program__c = null) AND Name > :afterKey ORDER BY Name LIMIT pageSize+1` (keyset paging, no OFFSET) |
| Query 2 | Open Cases (`IsClosed = false`) of those patients: `CaseNumber`, `AccountId`, `PSP_Issue_Category__c`, `PSP_Dispense__c` |
| Logic | For each enrollment call `PSP_ProgramExceptionRules.evaluate`, filter by type, sort, count, build texts |
| Result message example | "As of 2026-11-22: 12 item(s) for 6 patient(s) out of 12 enrollment(s) checked (2 high, 7 medium, 1 low, 2 data gap(s)). Refill dates are based on recorded shipments only." |
| Called by | MCP tool PSP_Get_Program_Exceptions; Medication Support and Care Resolution agents; `PSP_ExceptionsWorklistCardAction`; `PSP_CareTeamHandoff`; pre-flight |
| Tests | `PSP_ProgramExceptionsServiceTest`, 9 methods, coverage 98% |

### 8.4 `PSP_CaseDuplicateCheck` (invocable "PSP Check Duplicate Case")

| Item | Detail |
|---|---|
| Purpose | Before a new case: is an open case already covering the same patient, category and shipment? (rules 7.3). Read-only |
| Inputs | `enrollmentNumber` or `patientId` (Id takes priority), `category` (required, one of the 5 values, case-insensitive), optional `dispenseNumber` (must belong to the patient) |
| Outputs | `resultCode` (NO_DUPLICATE, EXISTING_CASE, POSSIBLE_DUPLICATE, INVALID_INPUT, NOT_FOUND, ERROR), `canCreate`, `matchingCaseNumbers`, `possibleDuplicateCaseNumbers`, `unclassifiedOpenCaseNumbers`, `patientName`, `resultMessage` |
| Queries | Enrollments by number, dispenses by number, open cases of the patients, patient names (at most 4 for any batch) |
| Valid categories | Read from the field's active picklist values (describe), cached per transaction |
| Called by | MCP tool PSP_Check_Duplicate_Case; Care Resolution `check_duplicate_case`; `PSP_CreateApprovedCase`; pre-flight |
| Tests | `PSP_CaseDuplicateCheckTest`, 12 methods, coverage 96% |

### 8.5 `PSP_CreateApprovedCase` (invocable "PSP Create Approved Case", WRITE)

| Item | Detail |
|---|---|
| Purpose | Creates one service case per request, only after the user approved that exact case |
| Inputs | `enrollmentNumber`, `category`, `subject` (max 180), `description` (max 4000), `userConfirmed` (all required); optional `dispenseNumber` |
| Outputs | `resultCode` (CREATED, NOT_CONFIRMED, DUPLICATE_OPEN_CASE, NEEDS_REVIEW, INVALID_INPUT, NOT_FOUND, ERROR), `resultMessage`, `caseNumber`, `caseId`, `matchingCaseNumbers`, `safetyReviewRequired` |
| Steps | 1 validate (`userConfirmed` must be true, required fields, lengths) → 2 run `PSP_CaseDuplicateCheck` (EXISTING_CASE → DUPLICATE_OPEN_CASE, POSSIBLE_DUPLICATE → NEEDS_REVIEW) → 3 build the Case (7.4) → 4 `Database.insert(cases, false, AccessLevel.USER_MODE)` → 5 read the case number |
| Partial success | Each request gets its own result in the same order (one refused, another created) |
| Called by | Care Resolution `create_approved_case` only (with `require_user_confirmation: True`) |
| Tests | `PSP_CreateApprovedCaseTest`, 7 methods, coverage 93% |

### 8.6 `PSP_CareTeamHandoff` (invocable "PSP Prepare Care Team Handoff")

| Item | Detail |
|---|---|
| Purpose | Read-only **facts** for one patient in fixed sections. Deterministic text, no AI. Used as grounding for the handoff prompt template and as its fallback |
| Inputs | `enrollmentNumber` (required; a sentence that contains one, such as "handoff for ENR-0007", also works: regex `(?i)\bENR-\d+\b`), optional `asOfDate` |
| Outputs | `resultCode` (SUCCESS, INVALID_INPUT, NOT_FOUND, ERROR), `handoffText`, `resultMessage`, `patientName` |
| Sections | 1 Patient and therapy (name, ENR, therapy, status, insurance, consent) · 2 Refill due status (from `PSP_RefillHistoryTool`) · 3 Open issues (one line per open case; safety → "in human safety review"; blank category → "no PSP issue category yet (needs review)") · 4 Exceptions to note (from `PSP_ProgramExceptionsService`) · 5 Suggested non-clinical next steps (mapped from suggested actions, plus the prescriber note) · 6 Data as of |
| Called by | Flow `PSP_Care_Team_Handoff_Summary`; pre-flight |
| Tests | `PSP_CareTeamHandoffTest`, 5 methods, coverage 95% |

### 8.7 `PSP_ExceptionsWorklistCard` (HXL output type)

`global` class with `@JsonAccess(serializable='always' deserializable='always')` and `@AuraEnabled` global fields: `title`, `summary`, `highLabel`, `mediumLabel`, `lowLabel`, `dataGapLabel`, `hasHigh`, `hasMedium`, `hasLow`, `hasDataGaps`, `hasNoItems`, `highItems`, `mediumItems`, `lowItems`, `dataGapItems`, `footer`. Pure data holder; bound to the Lightning Type `pspExceptionsWorklist` (section 16).

### 8.8 `PSP_ExceptionsWorklistCardAction` (invocable "PSP Get Exceptions Worklist Card")

| Item | Detail |
|---|---|
| Purpose | Same exceptions as 8.3, returned as an HXL card plus text |
| Inputs | Optional `enrollmentNumber`, `exceptionTypes` |
| Outputs | `resultCode`, `resultMessage`, `itemsText`, `card` (`PSP_ExceptionsWorklistCard`, only on SUCCESS) |
| Card build (`toCard`) | Groups items by severity; each line `• Patient (ENR) · TYPE: fact → ACTION`; labels "High n", "Medium n", "Low n", "Data gaps n"; title "Zenthera PSP · Program Exceptions"; footer "Refill dates are based on recorded shipments only. Read-only: nothing was created or changed." |
| Called by | Medication Support Agent `get_worklist_card` (model-called, `is_displayable`) |
| Tests | `PSP_ExceptionsWorklistCardActionTest`, 3 methods, coverage 100% |

### 8.9 `PSP_TestDataFactory` (test only)

| Method | Purpose |
|---|---|
| `createPatient(firstName, lastName, doInsert)` | Person Account with record type `PersonAccount` |
| `createEnrollment(patientId, status, enrollmentDate, doInsert)` | Zenthera enrollment |
| `buildDispense(enrollmentId, dispenseDate, daysSupply, status)` | Dispense (not inserted) |
| `createSdoCaseAutomationFixture()` | Inserts a fictional `SDO_Service_Einstein_Agent_Helper__c` (Active, Subject CONTAINS `PSP-TEST-NO-MATCH`) so that Case inserts work in tests |
| `buildCase(patientId, subject, status, priority)` | Case (not inserted) |

**Why the fixture is needed:** the existing SDO flow "SDO Service - Case - On Create" calls subflow `SDO_Service_Einstein_Case_Classification_Demo`, which reads helper records and passes them to a required `helperConfig` input. In tests (`SeeAllData=false`) no helper record is visible, the subflow fails and the Case insert rolls back. The fixture solves it without changing SDO automation. `PSP_CaseInsertSmokeTest` (3 methods) proves both the failure and the fix.

---

## 9. Flows

All four are Autolaunched flows (no trigger), API 68.0, active, written as XML and deployed with a dry run first. They run in user context.

### 9.1 `PSP_Enroll_Patient` (write)

| Item | Detail |
|---|---|
| Inputs | `firstName` (max 40), `lastName` (max 80), `birthdate` (not future), `mobilePhone` (optional, recommended), `therapy`, `prescriberName` (optional), `insuranceType`, `consentGiven` |
| Outputs | `isSuccess`, `resultCode` (SUCCESS, VALIDATION_ERROR, NO_CONSENT, AMBIGUOUS_MATCH, DUPLICATE_ENROLLMENT, ERROR), `resultMessage`, `patientId`, `enrollmentId`, `enrollmentNumber`, `patientStatus` (NEW_PATIENT / EXISTING_PATIENT) |
| Rules | 7.5 |
| Error handling | Validation, consent, ambiguity and duplicate outcomes stop before any write. If the enrollment insert fails and the patient was created in this run, the patient is deleted again (no partial patient). Reading the ENR number after creation failing still returns SUCCESS |

```
Check Inputs ──invalid──▶ VALIDATION_ERROR
     │──no consent──▶ NO_CONSENT
     ▼
Find patients: first name + last name + full birthdate (Person Accounts)
     ├─ 0 found ─▶ same name with NO birthdate on file? ─yes─▶ AMBIGUOUS_MATCH
     │                                                   └no─▶ create Person Account
     ├─ 1 found ─▶ different mobile on file? ─yes─▶ AMBIGUOUS_MATCH
     │                                       └no─▶ use it
     └─ 2+ found ─▶ mobile given and exactly 1 has it? ─yes─▶ use it
                                                     └no─▶ AMBIGUOUS_MATCH
Existing patient ─▶ open enrollment? ─yes─▶ DUPLICATE_ENROLLMENT
     ▼
Create Program Enrollment ─fault─▶ (patient created in this run? delete it) ─▶ ERROR
     ▼
Read ENR number ─▶ SUCCESS
```

Tests: 9 scenarios through `/services/data/v68.0/actions/custom/flow/PSP_Enroll_Patient` (new patient, no consent, duplicate, duplicate with blank Program, existing patient, three ambiguous cases, validation), all passed. Slackbot test created ENR-0007.

### 9.2 `PSP_Create_Service_Case` (write)

| Item | Detail |
|---|---|
| Inputs | `patientName` or `patientAccountId`, `subject` (max 200), `description`, `issueCategory` (one of the 5 values), `userConfirmed` |
| Outputs | `isSuccess`, `resultCode` (SUCCESS, VALIDATION_ERROR, NOT_CONFIRMED, NOT_FOUND, AMBIGUOUS_MATCH, NO_ENROLLMENT, ERROR), `resultMessage`, `caseId`, `caseNumber`, `caseStatus`, `casePriority`, `patientId`, `enrollmentNumber`, `safetyReviewRequired` |
| Field mapping | 7.4 (Origin Slack; does not set the PSP Case fields) |

```
Check inputs ─ invalid ──────────────▶ VALIDATION_ERROR (nothing created)
     │ userConfirmed is not exactly true ▶ NOT_CONFIRMED
     ▼
Find Person Account: by Account Id if given, else by exact name
     ├─ 0 found ─▶ NOT_FOUND      ├─ 2+ found ─▶ AMBIGUOUS_MATCH
     ▼ 1 found
Enrollment not Discontinued? ── no ─▶ NO_ENROLLMENT
     ▼ yes
Create Case ── fault ─▶ ERROR
     ▼
Read Case Number ─▶ SUCCESS
```

Version 1 treated an omitted `userConfirmed` as confirmed; version 2 continues only when it is exactly true. Backend tests passed (valid case 00001070, unknown patient, missing confirmation, possible adverse event 00001071, validation); Slackbot created 00001072 and 00001073.

### 9.3 `PSP_Answer_Program_Question` (read-only)

Input `question` (1–1000 characters, checked by decision `Check_Question`). Calls the prompt template `PSP_Program_FAQ_Answer` (action type `generatePromptResponse`, input `Input:question`, output `promptResponse`). Outputs `isSuccess`, `resultCode` (SUCCESS, VALIDATION_ERROR, ERROR), `answer`, `resultMessage`. Fault path → ERROR.

### 9.4 `PSP_Care_Team_Handoff_Summary` (read-only)

```
Start ─▶ Get_Handoff_Facts (Apex PSP_CareTeamHandoff, input enrollmentNumber)
           │ fault ─▶ Set_Error (ERROR)
           ▼
         Facts_Found? (factsResultCode = SUCCESS)
           ├─ no ─▶ Set_Facts_Problem (resultCode = INVALID_INPUT / NOT_FOUND, summary = message)
           ▼ yes
         Write_Handoff_Summary (prompt template PSP_Care_Team_Handoff_Summary, Input:facts = facts)
           │ fault ─▶ Set_AI_Fallback (AI_UNAVAILABLE, summary = facts, isSuccess = true)
           ▼
         Set_Success (SUCCESS, summary = AI text)
```

Input: `enrollmentNumber` (or a sentence with it). Outputs: `summary`, `facts`, `patientName`, `resultCode` (SUCCESS, AI_UNAVAILABLE, INVALID_INPUT, NOT_FOUND, ERROR), `resultMessage`, `isSuccess`. Called by the Care Resolution Agent and the PSP Handoff MCP tool.

---

## 10. Named Query: PSP Patient 360

| Item | Value |
|---|---|
| API name | `PSPPatient360` (label PSP Patient 360), API 68.0 |
| Parameter | `patientname` (Named Query parameter names must be lowercase) |
| REST | `GET /services/data/v68.0/named/query/PSPPatient360?patientname=<full name>` |
| API Catalog | Activated in Setup; creates External Service Registration `PSPPatient360_nquery`; identifier `nq:PSPPatient360_nquery`, operation `PSPPatient360` |

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

Design: one nested query returns the whole profile; no birthdate, address or email is returned; open cases first; up to 5 patients so an ambiguous name shows several rows; unknown name returns no rows. Named Queries cannot be created through the Tooling API; the metadata format was taken from the org's Metadata API WSDL.

---

## 11. Prompt templates

Both are Flex templates (`einstein_gpt__flex`), model `sfdc_ai__DefaultGPT4Omni`, visibility Global. To change the wording, add a new `templateVersions` entry and set `activeVersionIdentifier` to it, then deploy.

### 11.1 `PSP_Program_FAQ_Answer` (active `PSPProgramFAQAnswerV1_1`)

- Input `question` (String). Grounding: `{!$EinsteinSearch:File_PSP_FAQ_1Cx_CjNe65ed319.results}` (Data 360 retriever, data provider `invocable://getEinsteinRetrieverResults/File_PSP_FAQ_1Cx_CjNe65ed319` with `searchText = {!$Input:question}`).
- Rules: answer only from the excerpts; never guess amounts, dates, phone numbers, income limits or eligibility; if not found reply exactly "I could not find this in the Zenthera Program FAQ. Please check with the program team."; no medical advice (prescriber, 911); for a possible side effect suggest a Possible Adverse Event case for human safety review; never mention regulator reporting; 2–5 sentences; end with "Source: Zenthera Program FAQ, Q…".

### 11.2 `PSP_Care_Team_Handoff_Summary` (active `PSPCareTeamHandoffSummaryV1_2`)

- Input `facts` (String) = `handoffText` from `PSP_CareTeamHandoff`.
- Version 2 rules: (1) only names, numbers and dates from the facts; (2) no medical advice; (3) recorded shipments only, no adherence claims; (4) a safety case only if the facts literally say "Case [number]: in human safety review"; (5) "no PSP issue category yet (needs review)" is never a safety case and is copied as is; (6) copy each open case line, never reclassify; (7) under 220 words, do not mention the instructions.
- Output format: `CARE TEAM HANDOFF: [patient] ([ENR])`, `Summary:` (2–3 sentences), `1. Patient and therapy`, `2. Refill status (recorded shipments only)`, `3. Open issues`, `4. Points to note`, `5. Suggested non-clinical next steps` (ending with the prescriber note), `6. Data as of [date]. Written by AI from Salesforce facts; nothing was created, changed or posted.`
- Version 1 (kept, inactive) turned an uncategorised case into "in human safety review"; version 2 fixed it (22 checked runs, 0 issues).

---

## 12. Data 360: Program FAQ library

| Item | Value |
|---|---|
| Document | `docs/program-faq/Zenthera-PSP-Program-FAQ.pdf` (source `.html`), 21 fictional Q&A, 80 KB |
| Sections | 1 About the program (Q1–Q3) · 2 Eligibility and enrollment (Q4–Q8) · 3 Cost, insurance and copay assistance (Q9–Q12) · 4 Shipments and refills (Q13–Q16) · 5 Side effects and safety (Q17–Q18) · 6 Contact, privacy and leaving the program (Q19–Q21) |
| Data library | **PSP FAQ** (`PSP_FAQ`, Id `1JDgL000009h7FZWAY`), file upload source, data space `default`, status READY, file INDEXED |
| Retriever | `File_PSP_FAQ_1Cx_CjNe65ed319` (Id `1CxgL000000NXmTSAW`); the library also created retriever action `File_PSP_FAQ` (not used) |
| How it was built | Created and uploaded **in Setup** (Agentforce Data Library). An API-created library stayed in NOT_SCHEDULED and was abandoned. Status can be read by API: `GET /einstein/data-libraries/{id}` and `/status` |

Example answers: Medicare copay → "No…", Q10; delayed shipment → coordinator checks with the pharmacy and a service case tracks the delay, Q15; uninsured → Free Medication Program, Q11.

---

## 13. MCP servers (Slackbot)

### 13.1 How Salesforce-hosted MCP works here

- A **custom MCP server** is metadata `McpServerDefinition` with one or more tools. Each tool points to an **API Catalog** entry through `apiIdentifier` and `operation`.
- Identifier prefixes: `fa:flow-<FlowApiName>` for flows, `aa:apex-<ClassName>` for invocable Apex, `nq:<Name>_nquery` for Named Queries.
- Tool fields: `toolName`, `toolTitle` (shown in Slack as "Used <title> from <server>"), `descriptionOverride` (what the AI reads; max 1,024 characters), flags `readOnly`, `destructive`, `idempotent`, `openWorld`, `returnDirect`.
- Setup-style tool names follow the pattern `<operation><flow_|apex_><apiName>` (for example `PSP_Care_Team_Handoff_Summaryflow_PSP_Care_Team_Handoff_Summary`).
- Server API names must be letters and digits only (no underscores).
- **Activation:** in Setup → MCP Servers → Activate, or by creating the Tooling record `McpServerAccess` (DeveloperName, MasterLabel, Active = true, McpServerId), which is what Setup does.
- **Slack:** an admin adds each server once (Slack → Tools & settings → Manage Salesforce MCP → Add MCP server), then the user turns it on in Slackbot → Apps. Calls run as the linked Salesforce user.
- **Rule:** after renaming or redeploying a tool that Slack has loaded, re-add the server in Slack (Slack caches tool definitions).

### 13.2 Servers and tools

| Server (API name) | Tool title | Tool name | Identifier | Flags | Logic |
|---|---|---|---|---|---|
| PSP Patient Services MCP (`PSPPatientServicesMCP`, Id `1g1gL00000017STQAY`) | Enroll Patient in Zenthera Program | `PSP_Enroll_Patientflow_PSP_Enroll_Patient` | `fa:flow-PSP_Enroll_Patient` | write, not idempotent | 9.1 |
| same | Get Patient Refill History | `psp_get_refill_history` | `aa:apex-PSP_RefillHistoryTool` | read-only, idempotent | 8.1 |
| PSP Named Query MCP (`PSPNamedQueryMCP`, Id `1g1gL00000018unQAA`) | PSPPatient360 | `PSPPatient360PSPPatient360_nquery` | `nq:PSPPatient360_nquery` | (added in Setup, not edited) | 10 |
| PSP Case MCP (`PSPCaseMCP`, Id `1g1gL00000018zdQAA`) | PSP_Create_Service_Case | `PSP_Create_Service_Caseflow_PSP_Create_Service_Case` | `fa:flow-PSP_Create_Service_Case` | write | 9.2 |
| PSP Program FAQ MCP (`PSPProgramFAQMCP`, Id `1g1gL0000001AdFQAU`) | PSP_Answer_Program_Question | `PSP_Answer_Program_Questionflow_PSP_Answer_Program_Question` | `fa:flow-PSP_Answer_Program_Question` | read-only | 9.3 |
| PSP Exceptions MCP (`PSPExceptionsMCP`, access record `1fzgL000009Hm4fQAC`) | PSP_Get_Program_Exceptions | `PSP_ProgramExceptionsServiceapex_PSP_ProgramExceptionsService` | `aa:apex-PSP_ProgramExceptionsService` | read-only | 8.3 |
| same | PSP_Check_Duplicate_Case | `PSP_CaseDuplicateCheckapex_PSP_CaseDuplicateCheck` | `aa:apex-PSP_CaseDuplicateCheck` | read-only | 8.4 |
| PSP Handoff MCP (`PSPHandoffMCP`, Id `1g1gL0000001FWTQA2`, access `1fzgL000009YLWHQA4`) | PSP_Care_Team_Handoff_Summary | `PSP_Care_Team_Handoff_Summaryflow_PSP_Care_Team_Handoff_Summary` | `fa:flow-PSP_Care_Team_Handoff_Summary` | read-only, idempotent | 9.4 |

### 13.3 Tool descriptions (what the AI is told)

- **Enroll Patient:** enroll ONE patient; required inputs and allowed values; ask for missing values, never guess birthdate or consent; lists result codes; write operation, call once, never retry automatically.
- **Get Patient Refill History:** read-only; inputs; only Delivered shipments count; due date and days overdue rule; result codes; recorded shipments only, no medical advice.
- **PSPPatient360:** read-only profile by full name; up to 5 rows: more than one = ambiguous, none = not found.
- **PSP_Create_Service_Case:** ONE case after explicit user confirmation; refuses unknown or ambiguous patients; Status New, Origin Slack; adverse events only flagged for human safety review.
- **PSP_Answer_Program_Question:** read-only; answers only from the FAQ; show the answer with its Source line; no medical advice; not for patient records.
- **PSP_Get_Program_Exceptions:** read-only; all inputs optional (asOfDate, enrollmentNumber, exceptionTypes, pageSize, afterEnrollmentNumber); show resultMessage and itemsText as written; suggested actions need approval; never create cases.
- **PSP_Check_Duplicate_Case:** read-only; inputs; result codes and what to do with each; never creates a case.
- **PSP_Care_Team_Handoff_Summary:** read-only; fixed sections; input enrollment number (a sentence works); show the summary exactly as written; DM only, never posts to a channel.

### 13.4 Why there are six servers

PSP Named Query MCP and PSP Case MCP were created separately in Setup because a Named Query tool edited by metadata on the first server failed in Slack with `Unknown tool: invalid_tool_name` (Slack called the operation name `PSPPatient360`, which did not match the edited tool name). The same tool added in Setup and never edited works. **Rule:** add Named Query tools in Setup and do not edit them by metadata. Flow and Apex tools accept custom names.

---

## 14. Agentforce specialist agents

### 14.1 Common design

- Written in **Agent Script** (`.agent` file in an `aiAuthoringBundle`), `agent_type: "AgentforceEmployeeAgent"`, published and activated by CLI.
- Each agent: `system` instructions (role, read-only, no invention, no adherence claims, no medical advice, who handles what), `config` with a specific **description** (Coworker chooses agents by it), `start_agent agent_router` that transitions to subagents, and an `off_topic` subagent that redirects.
- Action targets: `apex://<Class>` or `flow://<Flow>`.
- **Deterministic run pattern** (used when data must always be fetched): at the top of a subagent's reasoning,
  ```
  run @actions.<action>
      with <input>=<value or @system_variables.user_input>
      set @variables.<v> = @outputs.<o>
  | prompt text that uses {!@variables.<v>}
  ```
  Without it, early versions sometimes skipped the tool and invented patients.
- **Write confirmation:** `require_user_confirmation: True` on an action makes Salesforce show a confirmation card before it runs (planner `isConfirmationRequired = true`).
- **HXL output:** an output with `complex_data_type_name: "c__<lightningType>"` and `is_displayable: True` is shown as a card, but only when the model calls the action (not in a deterministic run).

### 14.2 PSP Medication Support Agent (active v6, read-only)

| Subagent | Actions | Behaviour |
|---|---|---|
| `refill_status` | `get_refill_history` → `apex://PSP_RefillHistoryTool` | Asks for name or ENR; calls once; shows resultMessage; says "recorded shipments only"; AMBIGUOUS → asks for ENR |
| `program_exceptions` | `get_program_exceptions` → `apex://PSP_ProgramExceptionsService` (deterministic, only the counts go into the prompt); `get_worklist_card` → `apex://PSP_ExceptionsWorklistCardAction` (model-called as `show_worklist_card`, output `card` is `c__pspExceptionsWorklist`, displayable) | Must call `show_worklist_card` exactly once (with filters the user asked for: delayed = SHIPMENT_DELAYED, overdue = REFILL_OVERDUE, and so on); shows the items grouped by severity; never names a record not in itemsText; suggested actions are only suggestions |
| `off_topic` | none | Redirects: policy → Program Knowledge Agent; cases and handoffs → Care Resolution Agent; medical → prescriber / 911 |

Description: "PSP specialist for patient medication facts from CRM data, read-only: refill history and next refill due date for one patient (recorded shipments only), delayed or long-shipped shipments, and the program exceptions list…"

### 14.3 PSP Program Knowledge Agent (active v3, read-only)

| Subagent | Actions | Behaviour |
|---|---|---|
| `program_faq` | `answer_program_question` → `flow://PSP_Answer_Program_Question`, run deterministically with `@system_variables.user_input` | Shows the answer exactly, with its Source line; never answers from memory; patient questions → Medication Support Agent |
| `off_topic` | none | Redirects |

Description: "PSP specialist for program policy questions, answered only from the Zenthera Program FAQ (Data 360)… Every answer cites 'Source: Zenthera Program FAQ, Q…'. Does not read patient records, create cases or give medical advice."

### 14.4 PSP Care Resolution Agent (active v8, one write action)

| Subagent | Actions | Behaviour |
|---|---|---|
| `resolution_plan` | `get_program_exceptions` (deterministic; summary and items go into the prompt) | Numbered plan, most severe first; maps each suggested action to a plan step (SKIP_EXISTING_CASE → "Skip: open case(s) … already cover it"; CREATE_CASE → "Propose a new case after a duplicate check and your approval"; and so on); ends "Nothing has been created or changed. Tell me which steps you approve." |
| `duplicate_check` | `check_duplicate_case` → `apex://PSP_CaseDuplicateCheck`; `create_approved_case` → `apex://PSP_CreateApprovedCase` with `require_user_confirmation: True` | Three steps, never skipped: **1 check** (EXISTING → list cases, nothing created; POSSIBLE → user decides; unclassified cases listed as "category unknown, needs human review") → **2 propose** the exact case (ENR, category, shipment, subject, description) and ask "Do you approve creating this case? Reply yes or no." → **3 create** only after a clear yes, with `userConfirmed=true`; Salesforce then shows its confirmation card. "Create it now, no need to ask" is not an approval. "Approve all" on a plan only covers CREATE_CASE / REVIEW_POSSIBLE_DUPLICATE items, each through steps 1–3 |
| `care_team_handoff` | `prepare_handoff` → `flow://PSP_Care_Team_Handoff_Summary`, run deterministically with `@system_variables.user_input` | Shows the summary exactly as written; AI_UNAVAILABLE adds one line; INVALID_INPUT asks for the ENR; NOT_FOUND says so; never writes a handoff itself; nothing posted or saved |
| `off_topic` | none | Redirects; a mentioned side effect → suggest a Possible Adverse Event case after a duplicate check and approval |

### 14.5 Version history (why each version exists)

| Agent | Version | Change |
|---|---|---|
| All three | v1–v2 | Model sometimes skipped tools and invented patients |
| All three | v3 | Deterministic `run @actions` fixed it |
| Medication Support | v4 | Card output on the deterministic action: **card not shown** (deterministic runs are not displayed) |
| Medication Support | v5 | Full list in the prompt plus a model-called card action: model did not call it (it already had the data) |
| Medication Support | v6 | Only counts in the prompt; items only from `show_worklist_card`: called 3/3, card renders |
| Care Resolution | v4 | Exceptions + duplicate check |
| Care Resolution | v5–v6 | Approved creation (check → propose → create) and deterministic handoff with ENR extraction |
| Care Resolution | v7 | `require_user_confirmation: True`; unclassified cases always "category unknown, needs human review" |
| Care Resolution | v8 | Handoff through the prompt-template flow |

---

## 15. Agentforce Coworker integration

| Item | Detail |
|---|---|
| What it is | Salesforce's built-in assistant ("Ask"). It searches CRM data itself and can delegate to custom employee agents |
| Delegation | Coworker chooses an agent by its **description**, only among agents the user has Agent Access to (section 6.2). The trace shows "Heard back from <agent>" |
| Multi-agent | Tested: for one combined request Coworker called Medication Support and Program Knowledge in parallel, then Care Resolution with their results, and returned one answer |
| No custom orchestrator | Nothing routes requests except Coworker itself |
| Rendering | Coworker shows the delegated agent's HXL card when the card action is model-called and displayable; it can turn lines with case numbers into Case record cards |
| Write confirmation | The Salesforce confirmation card for `create_approved_case` appears inside Coworker |
| Known risk | For vague write requests Coworker may answer with its own built-in tools instead of delegating (seen in Phase 4 Test 2: it drafted a case proposal itself). Mitigation: name the agent ("Using the PSP Care Resolution Agent, …"); never approve a proposal that does not come from "Heard back from Agent" |

---

## 16. HXL card: Program Exceptions Worklist

```
PSP_ExceptionsWorklistCardAction ──returns──▶ PSP_ExceptionsWorklistCard (Apex type)
                                                     │  schema.json: "@apexClassType/c__PSP_ExceptionsWorklistCard"
                                                     ▼
                                   LightningTypeBundle pspExceptionsWorklist
                                                     │  renderer.json: "@widget/c/pspExceptionsWorklistCard"
                                                     ▼
                                   UiWidgetBundle pspExceptionsWorklistCard (type lightning__agentforceWidget)
                                                     ▼
                         Agent output "card" (complex_data_type_name c__pspExceptionsWorklist, is_displayable)
                                                     ▼
                         Rendered in Coworker and in the Agentforce panel
```

| File | Content |
|---|---|
| `lightningTypes/pspExceptionsWorklist/schema.json` | Title "PSP Exceptions Worklist", `lightning:type` = `@apexClassType/c__PSP_ExceptionsWorklistCard` |
| `lightningTypes/pspExceptionsWorklist/renderer.json` | `componentOverrides.$` → `@widget/c/pspExceptionsWorklistCard`, every card field mapped as `{!$attrs.<field>}` |
| `uiWidgets/pspExceptionsWorklistCard/pspExceptionsWorklistCard.json` | `tile/widget` → `tile/column`: `tile/text` title (h2), summary (caption); `tile/row` with 4 `tile/badge` (error, warning, info, secondary); 4 `tile/container` (error, warning, info, default) each with `meta.if` on `hasHigh` / `hasMedium` / `hasLow` / `hasDataGaps`, holding a `tile/text` heading (h4) and the item lines; empty-state text (`hasNoItems`); `tile/separator`; footer caption |
| `uiWidgets/pspExceptionsWorklistCard/schema.json` | Attribute types (text, boolean for the `has*` fields) |
| `uiWidgets/pspExceptionsWorklistCard/pspExceptionsWorklistCard.uiwidget-meta.xml` | Label PSP Exceptions Worklist Card, `widgetType` JSON |

Design choice: the HXL list schema (`lightning__listType`) is not published, so the card uses only proven blocks (badges, coloured containers, multi-line text, `meta.if`). No buttons or row links. The card is not used in Slackbot.

---

## 17. End-to-end request flows

### 17.1 Today's exceptions in Coworker (worklist card)

1. User: "Show today's Zenthera patient support exceptions."
2. Coworker delegates to PSP Medication Support Agent (description match).
3. Router → `program_exceptions`. Deterministic run of `PSP_ProgramExceptionsService` puts only the counts in the prompt.
4. The model calls `show_worklist_card` → `PSP_ExceptionsWorklistCardAction` → service again → card + itemsText.
5. Coworker shows a short intro and the HXL card. Nothing is written.

### 17.2 Combined request (three agents)

"Show today's PSP exceptions, consult the delayed shipment policy and prepare a resolution plan." → Coworker runs Medication Support (exceptions) and Program Knowledge (FAQ Q15) in parallel, then Care Resolution (`resolution_plan`) with their results → one plan, "Nothing has been created or changed".

### 17.3 Approved case creation (Coworker)

1. "Using the PSP Care Resolution Agent, prepare a <category> case for <ENR> …"
2. `duplicate_check`: `check_duplicate_case` → EXISTING (stop) / POSSIBLE (user decides) / NO_DUPLICATE.
3. Proposal shown → user replies "yes".
4. Agent calls `create_approved_case` with `userConfirmed=true` → Salesforce confirmation card → user confirms.
5. Apex re-checks duplicates, inserts in user mode, returns the case number. Example: 00001124 (ENR-0007, Refill Support).

### 17.4 Care team handoff (Coworker, panel or Slackbot)

Agent `care_team_handoff` (or the PSP Handoff MCP tool) → flow → Apex facts → prompt template → AI handoff (or the facts if the AI fails). Nothing is created or posted.

### 17.5 Slackbot examples

| Prompt | Tool |
|---|---|
| "Using PSP Exceptions MCP, show today's Zenthera program exceptions." | PSP_Get_Program_Exceptions |
| "Using PSP Handoff MCP, prepare a care team handoff for [ENR]." | PSP_Care_Team_Handoff_Summary |
| "Show the PSP profile of [patient] using PSPPatient360 from PSP Named Query MCP." | PSPPatient360 |
| "Use PSP_Answer_Program_Question from PSP Program FAQ MCP: [question]" | PSP_Answer_Program_Question |
| "What is the refill status of [ENR]?" | Get Patient Refill History |
| "Enroll [first name] [last name], born [date], …, consent given today." | Enroll Patient in Zenthera Program |
| "Create a [category] case for [patient] about …; confirm first." | PSP_Create_Service_Case |

A Slackbot step counts as tested only when Slackbot shows "Used <tool> from <server>". For some read questions Slackbot prefers its own Salesforce search; naming the server or tool in the prompt makes it use the MCP tool.

---

## 18. Lightning app, layouts and list views

| Item | Detail |
|---|---|
| App | Patient Support Program: standard navigation, desktop and phone, colour `#1B5E8C`; tabs Home, Accounts, Program Enrollments, Dispenses, Cases, Reports |
| Program Enrollment Layout | Sections Enrollment (ENR, Patient required, Program, Therapy, Status, Enrollment Date, Prescriber, Insurance, Owner) and Consent; related list Dispenses (newest first) |
| Dispense Layout | Program Enrollment (required), Dispense ID, Dispense Date, Days Supply, Pharmacy, Status |
| Person Account Layout (shared) | PSP additions only: related list Program Enrollments (first) and Cases (second); fields Birthdate (`PersonBirthdate`) and Mobile (`PersonMobilePhone`) in Account Information |
| PSP Patients list view | Accounts with record type Person Account; columns Name, Birthdate, Mobile, Phone, Owner Alias. Each user pins it once |
| PSP Patient compact layout | Name, Birthdate, Mobile, Phone; assigned to the Person Account record type only |
| Tip | The New Account record type picker defaults to Account; choose **Person Account** to get Birthdate and Mobile |

Backups of the layouts before change are in `backups/step3-layouts-2026-11-17/` and `backups/step4a-person-account-layout-2026-11-17/`.

---

## 19. Testing

### 19.1 Apex tests (all pass)

| Test class | Methods | Covers | Coverage |
|---|---|---|---|
| `PSP_RefillHistoryToolTest` | 15 | LATE, DUE, ON_TRACK, NO_DELIVERED_REFILL, Delayed not counted, lookups, not found, ambiguous, no enrollment, Discontinued only, blank/null input, default date, bulk 251 within 4 queries | 94% |
| `PSP_ProgramExceptionRulesTest` | 20 | Every exception type and data gap, On Hold and Discontinued behaviour, sorting, same refill rule as the Refill tool | 100% |
| `PSP_ProgramExceptionsServiceTest` | 9 | Only patients with exceptions listed, type filter, unknown type, single enrollment, not found, paging through all enrollments, invalid page size, default date, filter with no match | 98% |
| `PSP_CaseDuplicateCheckTest` | 12 | Every rule in 7.3, patient Id priority, unknown category, missing patient, not found, shipment of another patient, order kept for several requests, empty request list | 96% |
| `PSP_CreateApprovedCaseTest` | 7 | Created with fields and footer, not confirmed, existing duplicate, possible duplicate, safety flag, missing fields and foreign shipment, mixed batch order | 93% |
| `PSP_CareTeamHandoffTest` | 5 | Fixed sections without clinical text, on track, no delivery, ENR inside a sentence, bad input | 95% |
| `PSP_ExceptionsWorklistCardActionTest` | 3 | Card groups and labels, no card on invalid filter, empty state | 100% |
| `PSP_CaseInsertSmokeTest` | 3 | Case insert fails without the SDO fixture and works with it | n/a |

Total 74 test methods. The test runner's count is higher because it also counts `@TestSetup` methods. Tests use `SeeAllData=false`, fictional data and the fixture from 8.9.

Run all PSP tests:
```
sf apex run test --class-names PSP_RefillHistoryToolTest --class-names PSP_ProgramExceptionRulesTest --class-names PSP_ProgramExceptionsServiceTest --class-names PSP_CaseDuplicateCheckTest --class-names PSP_CreateApprovedCaseTest --class-names PSP_CareTeamHandoffTest --class-names PSP_ExceptionsWorklistCardActionTest --class-names PSP_CaseInsertSmokeTest --code-coverage --result-format human --target-org ProductPillarSDO1 --wait 20
```

### 19.2 Backend tests (REST invocable endpoint, the same entry point MCP and agents use)

- `PSP_Enroll_Patient`: 9 scenarios passed.
- `PSP_Create_Service_Case`: valid, unknown patient, not confirmed, adverse event, validation passed; ambiguous name not tested (no fixture).
- `PSP_Answer_Program_Question`: 7 tests passed (Medicare copay, delayed shipment, uninsured, not in FAQ, missed dose, side effect, blank).
- `PSP_Care_Team_Handoff_Summary`: 22 runs over all enrollments, 0 issues on automated checks (no reclassification, no number outside the facts, no regulator / adherence / dosing wording). Evidence `docs/evidence/p6-ai-care-team-handoff-checks.txt`.

### 19.3 Agent, Coworker and Slackbot tests

| Area | Result | Evidence (`docs/evidence/`) |
|---|---|---|
| Agent previews (Phase 2 and 4) | Pass: exceptions, FAQ, plan, duplicate guard, reject, pressure without approval, approve-all, handoff | `phase2-agent-preview-results.txt`, `phase4-agent-preview-results.txt` |
| Coworker delegation (Phase 3, 4 tests) | Pass, including the three-agent combined request | `p3-test1..4-*.png` |
| Coworker approved creation | Pass: proposal → yes → confirmation card → case 00001124 | `p4-coworker-test4-*.png` |
| Coworker without delegation (finding) | Coworker drafted a proposal itself for a vague request | `p4-coworker-test2-*.png` |
| HXL card in the panel and Coworker | Pass | `p5-t5-1-*.png`, `p5-t5-4-*.png` |
| AI handoff in Coworker and Slackbot | Pass (ENR-0018, 00001075 kept as uncategorised) | `p6-coworker-ai-handoff-*.png`, `p6-slackbot-ai-handoff-enr0018-pass.png` |
| Slackbot: enroll, refill, Patient 360, case, FAQ, exceptions | Pass | `slackbot-*.png`, `t1-10-slackbot-program-exceptions-pass.png` |
| Slackbot: duplicate check tool | Not tested | |

### 19.4 Demo pre-flight

`sf apex run --file scripts/apex/psp-demo-preflight.apex --target-org ProductPillarSDO1` (read-only, no DML). Prints: (1) all exceptions, (2) the delayed-shipment filter, (3) four duplicate checks (ENR-0007 Shipment Delay DSP-0016; ENR-0007 Refill Support; ENR-0018 Refill Support; ENR-0059 Shipment Delay DSP-0073), (4) the ENR-0007 handoff facts, (5) record counts. Result on 2026-11-22 in `docs/evidence/p7-demo-refresh-preflight-2026-11-22.txt`.

---

## 20. Deployment and operations

### 20.1 Rules

- Always deploy with `--dry-run` first, then deploy. The org is production-type: Apex only by deploy.
- Deploying a test class alone runs no tests: run the tests separately (19.1).
- Never disable SDO automation to make tests pass; use the fixture (8.9).
- Case edits through the REST API must send the header **`Sforce-Auto-Assign: FALSE`**, otherwise Case Assignment Rules move the owner (this happened once in the backfill and was restored).
- Never change consent, insurance, shipment status or clinical facts to make a demo work. Do not delete CRM records.

### 20.2 Common commands

```
# Dry run and deploy one component
sf project deploy start --dry-run --metadata ApexClass:PSP_CaseDuplicateCheck --target-org ProductPillarSDO1
sf project deploy start --metadata ApexClass:PSP_CaseDuplicateCheck --target-org ProductPillarSDO1

# Deploy a flow, prompt template or MCP server
sf project deploy start --metadata Flow:PSP_Care_Team_Handoff_Summary --target-org ProductPillarSDO1
sf project deploy start --metadata GenAiPromptTemplate:PSP_Care_Team_Handoff_Summary --target-org ProductPillarSDO1
sf project deploy start --metadata McpServerDefinition:PSPHandoffMCP --target-org ProductPillarSDO1

# Agent Script: validate, publish (new version), activate, preview
sf agent validate authoring-bundle --api-name PSP_Care_Resolution_Agent --target-org ProductPillarSDO1
sf agent publish authoring-bundle --api-name PSP_Care_Resolution_Agent --target-org ProductPillarSDO1
sf agent activate --api-name PSP_Care_Resolution_Agent --target-org ProductPillarSDO1
sf agent preview --api-name PSP_Care_Resolution_Agent --use-live-actions --target-org ProductPillarSDO1

# Call an invocable action directly (same entry point as MCP and agents)
POST /services/data/v68.0/actions/custom/flow/PSP_Care_Team_Handoff_Summary   {"inputs":[{"enrollmentNumber":"ENR-0007"}]}
POST /services/data/v68.0/actions/custom/apex/PSP_ProgramExceptionsService     {"inputs":[{}]}
```

### 20.3 Deployment order for a new environment

1. Objects and fields (Program Enrollment, Dispense, Case PSP fields; add the picklist values to the Case record types), tabs, app, layouts, list view, compact layout.
2. Permission set PSP Patient Services; assign it.
3. Apex classes and tests (rules → service → duplicate check → refill → approved case → handoff → card type and action); run the tests.
4. Data library `PSP_FAQ` in Setup (upload the PDF), note the retriever name; update the FAQ template if it differs.
5. Prompt templates, then flows (a flow that calls a template needs the template first).
6. Named Query, then activate it in API Catalog (Setup).
7. Lightning Type and UI Widget bundles (HXL).
8. MCP servers; activate (Setup or `McpServerAccess`); add Named Query tools in Setup.
9. Agents: publish and activate the three authoring bundles; permission set PSP Specialist Agent Access; assign.
10. Coworker: Turn On in Setup; assign the `Access_Ai_Search` group.
11. Slack: connect the workspace, add each MCP server, turn them on in Slackbot.

### 20.4 How to add a new capability (pattern)

1. Put the logic in an invocable Apex class (read-only unless approved) or an autolaunched flow, `with sharing`, user mode, errors returned in the response.
2. Add class access to PSP Patient Services.
3. For Slack: add a tool to a custom MCP server (identifier `aa:apex-…` or `fa:flow-…`), write a clear `descriptionOverride`, deploy, activate, re-add the server in Slack.
4. For agents: add the action to the right subagent (`target`), decide deterministic run versus model call, publish a new version and activate.
5. Update this TDD, the User Guide and the demo script.

---

## 21. Known limitations, risks and lessons learned

| Item | Impact / note |
|---|---|
| Slack and manual cases have no PSP category | `PSP_Create_Service_Case` and the UI do not set `PSP_Issue_Category__c` / `PSP_Dispense__c`, so these cases appear as `UNCATEGORISED_OPEN_CASE` (for example 00001126) and are not used by the duplicate check until a person sets the category |
| Coworker can answer without delegating | Vague write requests may be handled by Coworker's own tools, bypassing PSP guardrails. Name the agent in the prompt |
| Deterministic runs are not displayed | A card must come from a model-called action; the model calls it reliably only when the items are not already in the prompt |
| Day counts depend on time zone | "Today" is the user's date (Los Angeles for the demo user) |
| Slack caches MCP tools | Re-add the server after tool changes |
| Named Query tools edited by metadata can fail in Slack | Add them in Setup and leave them unchanged |
| Data library by API | Indexing did not start; create libraries in Setup |
| Mobile numbers compared exactly as typed | Enroll matching may miss formatting differences |
| Code Analyzer | Not run locally (Java not installed); Salesforce compiler and tests used instead |
| HXL | No buttons or row links (unverified features); no card in Slackbot |
| Agent Fabric | Not available (no Anypoint access) |
| Demo data changes | Other users add records; always run the pre-flight before a demo |

---

## 22. Not built (future options)

- HXL Card 2 (handoff) and Card 3 (case created); buttons and row links on the card.
- Posting a handoff to a private Slack channel or saving it as a Task (needs separate approval).
- Setting the PSP category in the Slack Create Service Case flow.
- Agent tests with Agentforce Testing Center.
- MuleSoft Agent Fabric registry of the agents and MCP servers.

---

## 23. Questions this document answers

| Question | Section |
|---|---|
| What objects and fields hold patient, enrollment, shipment and case data? | 5 |
| How is "refill overdue" calculated? Does it mean the patient missed doses? | 7.1 (no: recorded shipments only) |
| Which exceptions exist, with what severity and suggested action? | 7.2 |
| When is a case a duplicate? | 7.3, 8.4 |
| How does an agent create a case safely? | 7.4, 8.5, 14.4, 17.3 |
| How is the care team handoff built and why can't AI invent facts? | 7.6, 8.6, 9.4, 11.2 |
| What does each Apex class do, with inputs and outputs? | 8 |
| What does each Flow do? | 9 |
| How does Slackbot call Salesforce? Which MCP server has which tool? | 13 |
| Why are there six MCP servers? | 13.4 |
| How are the agents built and why deterministic runs? | 14 |
| How does Coworker pick an agent? | 15 |
| How is the HXL card defined and why does it show in Coworker? | 16, 14.5 |
| Who can access what? | 6 |
| How do I deploy, test or add a capability? | 19, 20 |
| Why does a case show "no PSP issue category"? | 5.4, 21 |
| What is not built yet? | 22 |

---

## 24. Glossary

| Term | Meaning |
|---|---|
| PSP | Patient Support Program |
| Zenthera | Fictional specialty drug of the demo |
| ENR-#### / DSP-#### | Program Enrollment / Dispense auto numbers |
| Dispense | One shipment of therapy to the patient |
| Headless 360 | Salesforce logic and data reached from any channel (Slack, agents, APIs), not only the Salesforce UI |
| MCP | Model Context Protocol: lets an AI client (Slackbot) call tools; here Salesforce-hosted custom MCP servers |
| API Catalog | Salesforce registry of callable operations (flows, invocable Apex, Named Queries) used by MCP tools |
| Named Query | Saved SOQL exposed as a REST and MCP operation |
| Agent Script | Text language for Agentforce agents (`.agent` files) |
| Subagent | A topic inside an agent with its own actions and instructions |
| Deterministic run | `run @actions…` in Agent Script: the action always runs, not left to the model |
| Coworker | Agentforce Coworker, the Salesforce assistant that can delegate to custom agents |
| Agent Access | Permission (`agentAccesses`) that lets a user, and Coworker, use an agent |
| HXL | Headless Experience Layer: Lightning Type + UI Widget that render structured agent output as a card |
| Flex prompt template | Prompt Builder template with free inputs, called from a flow (`generatePromptResponse`) |
| Data 360 / data library / retriever | Data Cloud storage and search used to ground answers in the FAQ PDF |
| User mode | Queries and DML that enforce the user's sharing and field security |
| SDO | Simple Demo Org: the pre-built demo org with its own automation |
| Possible Adverse Event | A reported possible side effect; only flagged for human safety review |

---

## 25. Activity log

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
| 2026-11-22 | TDD rewritten as a complete, self-contained technical reference (version 2.0) so a colleague, or an AI assistant it is uploaded to, can answer questions about any component: data model, security, business rules, every Apex class, flow, Named Query, prompt template, Data 360 library, MCP server and tool, agent, Coworker, HXL card, end-to-end flows, tests, deployment, limitations and glossary. The previous version (with detailed build and debug notes) is kept in `docs/archive/TDD-before-rewrite-2026-11-22.md`. Nothing in the org changed. |
| 2026-11-26 | Evidence Guide (user request, approved: local Python venv with Playwright and python-docx in `tools/evidence-guide/`; read and write live). Headless Google Chrome signed in as `deepshikhaheadless@kpmg.com` (frontdoor login, no password) ran the UI and took the screenshots. Approved writes, each verified by query: W1 patient Kavya Evidence Demo + ENR-0063; W2 DSP-0078 (Delivered, 30 days); W3 case 00001131 from the app (no PSP category: the field is not on the Case layout, option a); W4 Coworker approved creation ENR-0059 / Shipment Delay / DSP-0073 -> proposal, yes, Salesforce confirmation card, case 00001130. Counts: cases 79 -> 81, enrollments 12 -> 13, dispenses 6 -> 7. Coworker read tests PASS: worklist card (13 items), AI handoff ENR-0007, duplicate guard 00001124, FAQ Q15, resolution plan, ENR-0063 triage. Finding: the combined three-agent request stopped after the card twice (Care Resolution not called); plan asked separately. Slackbot screenshots reused from 17-22 Nov (Slack sign-in cannot be automated). Output `docs/PSP-Evidence-Guide.docx` (54 screenshots). |
| 2026-11-26 | Evidence Guide: added section 2 "The use case at a glance" (user request): use case story, one-page flow diagram (coordinator -> Salesforce app / Slackbot via 6 PSP MCP servers / Agentforce Coworker with 3 specialist agents -> shared Apex, Flows, Named Query, prompt templates -> CRM data and Data 360, plus the coordinator's day in 7 steps), channels table, use case x channel table and guardrails. Diagram source `tools/evidence-guide/usecase_flow.html`, rendered by `render_flow.py`. Later sections renumbered 3-8. Slackbot screenshots kept from 17-22 Nov (user decision). Browser profile folders `tools/evidence-guide/.profile-*` (saved Salesforce session) deleted on user request. Document rebuilt (55 images). |
| 2026-11-26 | Slackbot HXL feasibility check (read-only, user request; nothing in the org or Slack changed). Why the card does not show in Slack today: Slackbot calls `PSP_Get_Program_Exceptions` (data only) and writes text; the card action `PSP_ExceptionsWorklistCardAction` is on no MCP server. Standard server `platform.headless-360` is inactive; tools discover, describe, dispatch (write, destructive), dispatch_readonly, display_widget (renders only in hosts with the MCP Apps UI extension; GitHub forcedotcom/mcp-hosted issue #50, open: display_widget missing from tools/list). Not recommended for PSP because it also exposes write calls. Documented route (HXL beta): custom MCP server tool on the Apex action, linked to the widget, plus two object-based Lightning Types (MCP result wrapper whose renderer maps the output to the widget, and payload), HXL setting on, server active; Slackbot renders HXL as HTML styled like Block Kit. Open risk: Salesforce docs describe connecting Slack with Manual OAuth and an External Client App, while the PSP servers use Slack's Manage Salesforce MCP; whether that path renders widgets is unverified. Proposed changes listed for approval, not made. |
| 2026-11-26 | Agent utilization and cost (user request from the project lead). Read-only org check: Digital Wallet not installed; 0 TenantConsumptionAlert records; Agentforce Session Tracing, Agent Optimization, Agent Optimizer (beta), Agent Platform Tracing, Einstein Audit and Feedback and RAG quality metrics all Off; Agent Analytics app Coworker Insights ready to install; Conversational Memory On; Data Cloud enabled; no session tracing or audit DMOs in Data 360. So no historical usage data exists for the 3 PSP agents. Design footprint from Agent Script: Medication Support 4 subagents / 3 actions / 1 deterministic run; Program Knowledge 3 / 1 / 1; Care Resolution 5 / 4 / 2. Noted trade-off: the card request reads exceptions twice (deterministic counts + model-called card action). New `docs/Agent-Utilization-and-Cost-Guide.md` (measurement tools, KPIs, design rules, runaway controls, go-live checklist, POC status, proposed enablement for approval). Temporary browser profile used for the Setup check was deleted. Nothing in the org changed. |
| 2026-11-26 | Monitoring switched on (user approval: "digital wallet aur session tracing on kar do"). Setup → Digital Wallet → Get Started: installation complete (new Consumption Tagging tab shown, not configured). Setup → Einstein Audit, Analytics, and Monitoring Setup → Agentforce Session Tracing On; Agent Optimization switched on automatically with it. Verified after reload. Left unchanged: Audit and Feedback Off, Agent Platform Tracing Off, Agent Optimizer (beta) Off, Agent Health Monitoring Off, RAG quality Off, Conversational Memory On, Coworker Insights not installed, no consumption alerts. Done in the Setup UI by headless Chrome as the admin user (frontdoor login, temporary profile deleted afterwards). Usage data is collected from now on. Evidence `docs/evidence/monitoring-digital-wallet-installed.png`, `monitoring-session-tracing-on.png`. |
| 2026-11-26 | Measured demo run (user request). 6 read-only Coworker prompts as the presenter user, 13:31-13:42 UTC: exceptions card (C1), refill ENR-0007 (new M1), FAQ delayed shipments (C5), handoff ENR-0007 (C3), resolution plan (C6), exceptions ENR-0063 (C7). Answers checked on screenshots; nothing created. Session Tracing (Data 360 SQL): 12 sessions (6 Coworker + 6 specialist), 15 interactions, 44 steps; C1 had sessions but no turn data. Per request the specialist used 2-3 LLM steps, 1-3 actions, plus a guardrail classifier and an instruction-adherence check; Coworker turn 8-26 s vs specialist 2-12 s; Coworker's own LLM calls and prompt-template calls inside flows are not shown as steps. Finding: the Medication Support program_exceptions subagent ran `get_program_exceptions` twice per card request, because the deterministic `run` in the reasoning instructions repeats on the reasoning pass after the model-called card action (3 Apex actions per request). Digital Wallet app: Consumption Cards 'No data available'; consumption insights 0 rows at 15:15 UTC; agent breakdown needs the Consumption Tagging app. Tokens not visible (Audit and Feedback off). Guide section 6.1 added. Scripts: `ui.py` accepts SHOTS_DIR and PROFILE_DIR, `coworker.py` run M1 added. Temporary browser profiles deleted. Nothing in the org changed. |
