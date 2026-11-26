# User Guide: Patient Support Program (PSP)

How a Patient Services Coordinator does PSP work in three ways: manually in the **Patient Support Program** app in Salesforce, by chatting with **Slackbot**, or by asking the **Patient Services Agent** in Slack. All data is fictional (Zenthera is a made-up drug).

## Use cases at a glance

```
                    Zenthera Patient Support Program
                    ┌───────────────────────────────────────────┐
                    │ 1. Enroll a new patient                   │
 Patient Services   │ 2. Check refill status                    │
 Coordinator ──────▶│ 3. See a patient's full profile           │
   │                │ 4. Log a service case / possible side     │──▶ Pharmacovigilance team
   │ works through  │    effect                                 │    (human review)
   │                │ 5. Answer a program question              │
   ├ Salesforce app │ 6. Hand over to the care team             │──▶ Care team (#psp-care-team)
   ├ Slackbot       │ 7. Work today's program exceptions        │
   │                └───────────────────────────────────────────┘
   └ Patient Services Agent
```

---

## What works today

| Task | In Salesforce | In Slackbot | With the agent |
|---|---|---|---|
| 1. Enroll a new patient | ✅ Works (tested) | ✅ Works (tested) | Coming soon |
| 2. Check refill status | ✅ Works (tested) | ✅ Works (tested) | ✅ Works with Coworker (Medication Support Agent, tested in preview) |
| 3. See a patient’s full profile | ✅ Works (tested) | ✅ Works (tested, PSP Named Query MCP) | Coming soon |
| 4. Log a service case or a possible side effect | ✅ Works (tested) | ✅ Works (tested, PSP Case MCP) | Coming soon |
| 5. Answer a program question | Not applicable | ✅ Works (tested, PSP Program FAQ MCP) | Coming soon |
| 6. Hand over to the care team | Pending manual UI verification | ✅ Works (tested, PSP Handoff MCP; read-only, no posting) | ✅ Works with Coworker (read-only summary, tested) |
| 7. Work today's program exceptions | Not applicable (backend for Slack and agents) | ✅ Works (tested, PSP Exceptions MCP; text) | ✅ Works with Agentforce Coworker and the agent panel, shown as a worklist card (tested) |

This table is updated as each piece goes live.

**Current state:** in the Salesforce app, tasks 1–4 work (task 5 is a Slack and agent feature). In Slackbot, tasks 1–7 work (task 6 is a read-only handoff; posting to a channel is not built). Three read-only specialist agents (Medication Support, Program Knowledge, Care Resolution) work through **Agentforce Coworker** (tested): see “Use Agentforce Coworker” below.

**Tip:** when you click **New** on the Accounts tab, the record type **Account** is selected by default. Change it to **Person Account** (singular), otherwise the form has no Birthdate or Mobile.

---

## Before you start (one time)

1. **Salesforce access:** ask your admin to assign you the **PSP Patient Services** permission set.
2. **Connect Slack to your Salesforce login:** in Slack, click **Log in to Salesforce** on the banner. If there is no banner, open the **Salesforce** app in Slack, choose **Manage Salesforce orgs**, and click **Sign in** next to ProductPillarSDO.
3. **Admin, one time: activate the PSP tools.** Salesforce **Setup** → search **MCP Servers** → open **PSP Patient Services MCP** → **Activate**. Do the same for **PSP Named Query MCP** (patient profile) **PSP Case MCP** (service cases), **PSP Program FAQ MCP** (program questions), **PSP Exceptions MCP** (program exceptions) and **PSP Handoff MCP** (care team handoff).
4. **Admin, one time: add the PSP tools to Slack.** In Slack: **Tools & settings** → **Manage Salesforce MCP** → **Add MCP server** → choose **PSP Patient Services MCP** → **Connect**. Repeat for **PSP Named Query MCP**, **PSP Case MCP**, **PSP Program FAQ MCP**, **PSP Exceptions MCP** and **PSP Handoff MCP**. (Your Slack plan must include Salesforce MCP.) After any change to a server’s tools, remove and re-add that server here so Slack loads the new list.
5. **Turn on the PSP tools in Slackbot:** open **Slackbot** → **Apps** → make sure **PSP Patient Services MCP**, **PSP Named Query MCP**, **PSP Case MCP**, **PSP Program FAQ MCP**, **PSP Exceptions MCP** and **PSP Handoff MCP** are on. For **Enroll Patient in Zenthera Program**, leave approval on (Slackbot asks before it creates records) or choose **Always allow**.
6. **Find the agent:** in the Slack sidebar, open **Agentforce** and select **Patient Services Agent**. To use it in a channel such as `#psp-care-team`, @mention it and click **Add** when Slack asks.

---

## Open the Patient Support Program app

1. Log in to Salesforce.
2. Click the **App Launcher** (9-dot grid, top left) and select **Patient Support Program**.
3. Click the **Accounts** tab. Click the list name at the top left (for example “Recently Viewed”) and choose **PSP Patients**. This list shows only patients.
4. Click the **pin** icon next to the list name. From now on the Accounts tab opens on PSP Patients.
5. Tabs:
   - **Accounts:** patients (use the **PSP Patients** list)
   - **Program Enrollments:** each patient’s enrollment (`ENR-…`)
   - **Dispenses:** each therapy shipment (`DSP-…`)
   - **Cases:** patient service requests
   - **Reports**

---

## 1. Enroll a new patient

**In Salesforce**
1. **Accounts** tab → **PSP Patients** list → **New** → choose **Person Account** (not “Person Accounts”) → **Next**.
2. Enter **Salutation**, **First Name**, **Last Name**, **Birthdate**, **Phone** and **Mobile** → **Save**. Birthdate and Mobile are optional, but enter them: they help identify the patient later. The new patient appears in the **PSP Patients** list.
3. **Program Enrollments** tab → **New**.
4. In the **Enrollment** section, fill in **Patient** (required; the person you just created), **Program**, **Therapy**, **Status** = Enrolled, **Enrollment Date**, **Prescriber Name** and **Insurance Type**. In the **Consent** section, tick **Consent Given** only if the patient agreed and enter **Consent Date** → **Save**.
5. The **Enrollment ID** (`ENR-…`) is filled in automatically.

**What the enrollment service does (used by Slackbot and the agent)**

Slackbot and the agent use the same enrollment service, **PSP Enroll Patient**. It:
1. Checks the required details: first name, last name, birthdate, therapy, insurance type.
2. Refuses if the patient has **not** given consent. Nothing is created.
3. Looks for the patient by **first name, last name and full birthdate**, and uses the mobile number to tell people apart.
   - Patient found → uses that patient.
   - Not found → creates the patient.
   - Could be more than one person → stops and asks a coordinator to check. Nothing is created.
4. Refuses if the patient already has an open enrollment.
5. Creates the enrollment (Status Enrolled, today’s date, consent recorded) and gives back the **Enrollment ID** (`ENR-…`).

| You see | It means |
|---|---|
| “Enrolled … Enrollment number: ENR-…” | Done |
| “Not enrolled: the patient has not given consent” | Get consent first |
| “Not enrolled: … already has an open enrollment (ENR-…)” | The patient is already in the program |
| “Not enrolled: more than one existing patient …” or “… may be the same person” | Open the **PSP Patients** list and check the patient records |
| “Not enrolled. … is required” | Give the missing detail |

**In Slackbot** (tested)
1. Open **Slackbot**.
2. Type the request with all the details, for example:
   > “Enroll Riya Demo Sharma in the Zenthera Patient Support Program. Birthdate: 1991-03-14, Mobile: +91 90000 11223, Therapy: Zenthera 50 mg, Prescriber: Dr. Demo Mehta, Insurance: Commercial. Valid consent is recorded today.”

   This is the exact prompt used in the test. Tip: write “first name …, last name …” if the name has more than two words.
3. Slackbot shows **Used Enroll Patient in Zenthera Program from PSPPatientServicesMCP**. If approval is on, it first asks you to approve: click **Approve**.
4. Slackbot replies, for example: *“Riya Demo Sharma is now enrolled in the Zenthera Patient Support Program. Enrollment number: ENR-0007. Therapy: Zenthera 50 mg. A new record was created, because none existed for this name and birthdate.”*

**Check it in Salesforce:** Patient Support Program app → **Accounts** → **PSP Patients** → open the patient → **Related** → **Program Enrollments** shows the ENR number. Open it: Status Enrolled, Consent Given ticked, Consent Date today.

**Other replies you may see in Slackbot**
| Request | Expected reply |
|---|---|
| Same details, but “Consent has NOT been given” | Slackbot refuses and explains that consent is needed. Nothing is created |
| “Enroll the same patient again in the Zenthera Patient Support Program with the same details.” | “No second enrollment was created. … already has an open … enrollment, ENR-0007” |
| A detail is missing | Slackbot asks for it before calling the tool |

**If something goes wrong in Slackbot**
| Problem | What to do |
|---|---|
| Slackbot says “the enrollment tool didn’t load” | Type **try again**. In the test the tool loaded on the second try |
| Slackbot does not offer the PSP tool | Check steps 3–5 in “Before you start”: the server must be active in Setup, added in Slack, and turned on in Slackbot |
| “Manage Salesforce MCP” is missing in Slack | Your Slack plan does not include Salesforce MCP |
| Permission error | Ask your admin for the **PSP Patient Services** permission set, and check that Slack is signed in to ProductPillarSDO as you |
| “Not enrolled: … may be the same person” | Open **PSP Patients**, check the patient with that name, add the missing birthdate or fix the record, then try again |

**With the agent** (coming soon)
> “@Patient Services Agent please enroll [first name] [last name] in the Zenthera program.”

The agent asks for birthdate, mobile, therapy, prescriber, insurance and consent one by one, then confirms the Enrollment ID.

---

## 2. Check refill status

Refill status is based on recorded shipments only. It never says whether the patient took the medication.

**How the refill check works (same rules everywhere)**
- Only shipments with Status **Delivered** count. Shipped, Delayed and Cancelled do not.
- Next refill due = the latest Delivered **Dispense Date** + its **Days Supply**.
- **LATE** = past the due date (with the number of days); **DUE** = due within 7 days; **ON TRACK** = more than 7 days left; **No delivered refill** = nothing delivered yet.
- This shows recorded shipments only. It does not tell you whether the patient took the medication.

**In Salesforce** (tested)
1. **Program Enrollments** tab → open the patient’s enrollment (or open the patient → **Related** → **Program Enrollments** → click the ENR number).
2. Look at the **Dispenses** related list (columns: Dispense ID, Dispense Date, Days Supply, Pharmacy, Status; newest first).
3. Find the newest row with Status **Delivered**. Add its Days Supply to its Dispense Date: that is the next refill due date.
4. To record a new shipment: **Dispenses** related list → **New** → fill in **Dispense Date**, **Days Supply**, **Pharmacy**, **Status** → **Save**.

Example (fictional patient Riya Demo Sharma, ENR-0007): DSP-0015 Delivered 2026-10-09 for 30 days → due 2026-11-08. DSP-0016 is Delayed, so it does not count. On 2026-11-17 the refill is **9 days late**.

**In Slackbot** (tested through the PSP refill tool)

Prompts to use:
> “Show the refill history for Riya Demo Sharma.”

> “As of November 17, 2026, how many days late is Riya Demo Sharma’s refill?”

> “Does a delayed shipment count as delivered medication?”

> “Show refills for a patient who does not exist.”

Expected: the shipment list, the due date 2026-11-08, **LATE by 9 days**, a clear “no” for delayed shipments, and “No patient named … was found” for an unknown patient.

To make sure Slackbot uses the PSP refill check (with its fixed rules), name the tool:
> “Use the Get Patient Refill History tool from PSP Patient Services MCP to show the refill history for Riya Demo Sharma as of 2026-11-17.”

**With the agent** (planned)
> “Is [patient name]’s refill on time?”

---

## 3. See a patient’s full profile

**In Salesforce** (tested)
1. App Launcher → **Patient Support Program**.
2. **Accounts** tab → **PSP Patients** list → click the patient’s name.
3. The strip at the top shows **Name**, **Birthdate**, **Mobile** and **Phone**. The **Details** tab shows all fields.
4. Click **Related**. **Program Enrollments** (Enrollment ID, Program, Therapy, Status, Enrollment Date, Insurance Type) is first, **Cases** is second.
5. Click an **Enrollment ID** to see its **Dispenses** (Dispense ID, Date, Days Supply, Pharmacy, Status).

**Patient 360 query** (tested directly in Salesforce)
One read-only query, **PSP Patient 360**, returns the whole profile at once: patient details, enrollments, each enrollment’s dispenses, and cases (open first). Slackbot uses it through the tool **PSPPatient360** on the separate server **PSP Named Query MCP**.

**In Slackbot** (tested)

Prompt to use:
> “Use PSPPatient360 from PSP Named Query MCP to show the complete profile of [patient full name], including program enrollment, therapy, insurance, dispense history and service cases.”

Expected: Slackbot shows **Used PSPPatient360 from PSPNamedQueryMCP**, then the patient’s mobile, each enrollment (number, therapy, status, insurance, prescriber), its dispenses (date, days supply, status) and the cases. Lists that are empty are reported as “none”.

**Check it in Salesforce:** open the patient from **PSP Patients** → **Related** and compare the Program Enrollments, the enrollment’s Dispenses, and the Cases list.

**With the agent** (coming soon)
> “Give me the complete profile of [patient name].”

**If something goes wrong**
| Problem | What it means / what to do |
|---|---|
| “No patient found” | The name must match the patient record exactly. Check the spelling in **PSP Patients** |
| The patient shows no enrollments, dispenses or cases | There are none on record; nothing is made up |
| Several patients come back for one name | The name is shared. Ask for the enrollment number (ENR-…) or check **PSP Patients** before acting |
| Access or permission error | Ask your admin for the **PSP Patient Services** permission set |
| Slackbot says the tool does not exist | Slack still has the old tool list: remove and re-add the server in Slack (see “Before you start”) |
| “Unknown tool: invalid_tool_name”, or the answer comes from “direct Salesforce queries” | Slackbot tried a tool on the wrong server. Name the server in the prompt (“from PSP Named Query MCP”). An answer from direct queries is not a tool result |

---

## 4. Log a service case or a possible side effect

**In Salesforce** (tested)
1. Open the patient → **Related** tab → **Cases** related list → **New**.
2. Enter **Subject**, **Description** and **Origin** → **Save**.

**In Slackbot** (tested; tool **PSP_Create_Service_Case** on **PSP Case MCP**)

Prompt to use:
> “Create a patient service case for [patient full name] regarding [issue]. Subject: [subject]. Description: [what happened]. Please confirm before creating the Case.”

Issue categories: **Shipment Delay**, **Refill Support**, **Insurance Support**, **General Program Support**, **Possible Adverse Event**.

Expected:
1. Slackbot shows the patient, category, subject and description and asks you to confirm.
2. After you confirm, it shows **Used PSP_Create_Service_Case from PSPCaseMCP** and returns the **Case Number** and status **New**.
3. Nothing is created if you do not confirm, if the patient is not found, if several patients share the name, or if the patient has no active enrollment.

For a **Possible Adverse Event** the case subject starts with **[SAFETY REVIEW]**, priority is **High**, and the description says it needs human safety review. Slackbot gives no medical advice and does not report anything to a regulator.

**Check it in Salesforce:** open the patient → **Related** → **Cases**. The new case has Origin **Slack**, Status **New**, and the category in the subject. Then ask for the patient’s full profile (use case 3): the new case is listed there too.

**With the agent** (coming soon)
> “Call note: [patient name] reports [side effect] since the last dose.”

The agent logs the case for human safety review. It gives no medical advice and does not report anything to a regulator on its own.

**If something goes wrong**
| Problem | What it means / what to do |
|---|---|
| “No case was created … confirm” | Confirm the details when Slackbot asks |
| “No patient found” | Use the full name exactly as recorded in **PSP Patients** |
| “… patients are named …” | Several patients share the name; give the patient’s Account Id |
| “… has no active enrollment” | Cases are only logged for enrolled patients |
| Slackbot says the tool does not exist | Remove and re-add PSP Case MCP in Slack |
| Slackbot does not use the case tool | Name it in the prompt: “Use PSP_Create_Service_Case from PSP Case MCP to …” |

---

## 5. Answer a program question

Answers come only from the Zenthera Program FAQ document (fictional), not from patient records. Topics: eligibility and enrollment, copay assistance, insurance (Medicare, Medicaid, uninsured), prior authorization, shipments and refills, contact hours, privacy and leaving the program.

**In Slackbot** (tested; tool **PSP_Answer_Program_Question** on **PSP Program FAQ MCP**)

Prompt to use:
> “Use PSP_Answer_Program_Question from PSP Program FAQ MCP: [your question about the program]”

Expected:
1. Slackbot shows **Used PSP_Answer_Program_Question from PSPProgramFAQMCP**.
2. A short answer (2–5 sentences) that ends with **Source: Zenthera Program FAQ, Q…**.
3. If the FAQ does not cover the question: “I could not find this in the Zenthera Program FAQ. Please check with the program team.”
4. You can combine it with the patient profile in one request, for example:
   > “First use PSPPatient360 from PSP Named Query MCP to get [patient full name]’s insurance type. Then use PSP_Answer_Program_Question from PSP Program FAQ MCP to explain what copay assistance may be available. Include the FAQ source and do not guarantee approval.”
5. Medical questions (dosing, missed doses, side effects) are not answered: you are referred to the prescriber (911 in an emergency). For a possible side effect, log a **Possible Adverse Event** case (use case 4).

**With the agent** (coming soon)
> “[Your question about the program]”

**Admin: update the FAQ.** Setup → **Agentforce Data Library** → **PSP FAQ** → **Upload Files** → upload the new PDF → **Save**. The search index refreshes automatically (a few minutes). Upload files in Setup: uploads through the API did not start indexing.

**If something goes wrong**
| Problem | What it means / what to do |
|---|---|
| Slackbot answers without “Used PSP_Answer_Program_Question…” | It used its own search. Name the tool and server in the prompt |
| Slackbot says the tool does not exist | Remove and re-add PSP Program FAQ MCP in Slack |
| “I could not find this in the Zenthera Program FAQ…” | The FAQ has no answer; ask the program team |
| “The program FAQ could not be searched right now…” | Data 360 or the AI model is unavailable; try again later |

---

## 6. Hand over to the care team

**In Salesforce**
Open the patient, read the enrollment, dispenses and cases, and write the summary yourself.

**With Agentforce Coworker** (tested; PSP Care Resolution Agent)
1. In Salesforce click **Ask**, start a **New chat** and type:
   > “Prepare a care team handoff for enrollment [ENR-…]. Do not create, update or share anything.”
2. The handoff is written by AI (prompt template) only from facts read from Salesforce, and ends with “Written by AI from Salesforce facts; nothing was created, changed or posted”. If the AI is unavailable, the factual version is shown instead. It starts with a short summary and always has the same sections:
   1. Patient and therapy
   2. Refill status (recorded shipments only)
   3. Open issues (a safety case shows only as “in human safety review”)
   4. Points to note (exceptions)
   5. Non-clinical next steps
   6. Data as of date
3. It is read-only: nothing is saved or posted. Copy it yourself if you need to share it in a private channel.
4. In Coworker, lines that mention a case number may appear as clickable Case cards (tested).

**In Slackbot** (tested; tool **PSP_Care_Team_Handoff_Summary** on **PSP Handoff MCP**). Use a direct message with Slackbot.
> “Using PSP Handoff MCP, prepare a care team handoff for [ENR-…].”

Expected: **Used PSP_Care_Team_Handoff_Summary from PSPHandoffMCP**, then the same AI handoff as in Coworker. Slackbot only shows it to you; posting to a channel is not built (needs a separate approval).
---

## 7. Work today's program exceptions

Shows what needs attention across all Zenthera patients you are allowed to see, using Salesforce data: overdue or due-soon refills (recorded shipments only), delayed or long-shipped shipments, no shipment after enrollment, consent pending, open safety reviews, duplicate open cases, cases without a category and missing data. Patients without exceptions are not listed. Read only: nothing is created or changed.

**In Slackbot** (tested; tool **PSP_Get_Program_Exceptions** on **PSP Exceptions MCP**). Use a direct message with Slackbot, not a public channel.

Prompts to use:
> “Using PSP Exceptions MCP, show today's Zenthera program exceptions.”

> “Using PSP Exceptions MCP, show only [delayed shipments / overdue refills / open safety reviews].”

> “Using PSP Exceptions MCP, show the exceptions for [enrollment number, ENR-…].”

> “Using PSP Exceptions MCP, before creating a [category] case for [enrollment number] shipment [DSP-…], check for a duplicate.” (duplicate check; not tested in Slack yet)

Expected:
1. Slackbot shows **Used PSP_Get_Program_Exceptions from PSPExceptionsMCP**.
2. A count line, for example "8 items for 3 patients out of 8 enrollments checked (2 high, 3 medium, 1 low, 2 data gaps)", then the items grouped HIGH, MEDIUM, LOW, INFO.
3. Each item has the patient, enrollment number, a fact and a **suggested action**:

| Suggested action | What you do |
|---|---|
| PREPARE_HANDOFF | Prepare a care team handoff (task 6) |
| SKIP_EXISTING_CASE | Nothing new: an open case already covers it |
| CREATE_CASE | Log a case (task 4), after checking for a duplicate |
| REVIEW_POSSIBLE_DUPLICATE | Check the listed cases before creating anything |
| TRIAGE_CASE | Open the case, read it and set **PSP Issue Category** |
| FOLLOW_UP_CONSENT | Follow up the patient's program consent |
| REVIEW_DATA | Fill in the missing value if you know it (for example the consent date); never guess |

Refill dates are based on recorded shipments only. They never say whether the patient took the medication. A case that mentions a side effect but has no category is shown as "needs review", not as a safety case: a person decides.

**With Agentforce Coworker** (tested): ask in Salesforce (**Ask** in the search bar). Coworker hands the request to the PSP specialist agents. See “Use Agentforce Coworker” below.

**If something goes wrong**
| Problem | What it means / what to do |
|---|---|
| First answer says the tool failed, the retry works | Seen in the test: type **try again** |
| Slackbot answers without “Used PSP_Get_Program_Exceptions…” | It used its own search. Name the server in the prompt |
| Slackbot says the tool does not exist | Remove and re-add PSP Exceptions MCP in Slack |
| A patient you expect is missing | The patient has no exception today, or you are not allowed to see the record |

---

## Use Agentforce Coworker (exceptions, policy, resolution plan)

Coworker is the AI assistant in Salesforce. For PSP work it hands your request to three specialist agents, each with one job:

```
You ──▶ Coworker (Ask) ──┬──▶ PSP Medication Support Agent  ── refills, shipments, today's exceptions
                         ├──▶ PSP Program Knowledge Agent    ── program policy (Program FAQ)
                         └──▶ PSP Care Resolution Agent      ── resolution plan, existing-case check
```

They never change or delete records. The only write is a new service case, and only after you approve the exact case (Care Resolution Agent). Handoffs are read-only summaries; nothing is posted to Slack.

**Before you start (admin, one time):** the user needs the **Agentforce Coworker User** group (`Access_Ai_Search`), the **PSP Patient Services** permission set and the **PSP Specialist Agent Access** permission set. Log out and in again after a new assignment.

**How to use**
1. In Salesforce, click **Ask** in the search bar. Start a **New chat** for each new topic.
2. Prompts to use:
   > “Show today's Zenthera patient support exceptions.”

   > “What is the Zenthera PSP process for delayed shipments?”

   > “Review [patient full name]'s delayed shipment [DSP-…] and prepare a resolution plan. Do not create any cases.”

   > “Show today's PSP exceptions, consult the delayed shipment policy and prepare a resolution plan.” (Coworker uses several agents)

   > “Prepare a care team handoff for [enrollment number, ENR-…].” (read-only summary; tested with the Care Resolution Agent)

   > “Create a [category] case for [enrollment number] [shipment DSP-… if any]: [what happened].” The agent first checks for an existing case. If none, it shows the exact case and asks “Do you approve creating this case? Reply yes or no.” Only “yes” creates it. Salesforce then shows a confirmation card with the exact values; the case is created only after you click **Confirm** (tested: case created with category and approval note).

**Expected**
1. Coworker says it delegates to a PSP agent, then shows **Heard back from [agent]**. For a combined request it may call two agents at the same time and then the third.
2. For today's exceptions you get a **worklist card**: badges with the counts (High, Medium, Low, Data gaps) and coloured boxes per severity with each patient, the fact and the suggested action (tested in Coworker and in the agent panel). Other answers show patients as clickable record cards.
3. Policy answers come from the Zenthera Program FAQ, with the question number (for example Q15).
4. Plans end with “Nothing has been created or changed”. A case is created only after you answer “yes” to the exact proposal; if an open case already covers the issue, nothing is created and the existing case numbers are shown.
5. A handoff has fixed sections: patient and therapy, refill due status (recorded shipments only), open issues (safety cases only as “in human safety review”), exceptions, non-clinical next steps, data as of date.
6. Dates follow your Salesforce time zone (Setup → My Personal Information). Near midnight a refill can show one day more or less than in another time zone.

**Important for case actions:** always name the agent, for example “Using the PSP Care Resolution Agent, create a [category] case for [enrollment number] …”. For a vague request (“a suitable enrollment”) Coworker may draft a case itself without the PSP agent. Its draft then skips the duplicate check and the program's refill rules (tested). Never answer “yes” to a draft that did not come from the PSP Care Resolution Agent.

**If something goes wrong**
| Problem | What it means / what to do |
|---|---|
| Coworker answers itself, no “Heard back from …” | You may be missing **PSP Specialist Agent Access**, or you have not logged in again since it was assigned |
| “Heard back from Agent” without a name | Normal when only one agent was used; the first sentence names the agent |
| The answer has no FAQ source line | Ask again, naming the policy topic; policy answers must come from the Program FAQ |
| The plan suggests a new case | Nothing is created; check for an existing case first and create it only after approval |
| A proposal appears without “Heard back from Agent” | Coworker drafted it itself; ask again naming the PSP Care Resolution Agent |
| Salesforce asks you to confirm an action | That is the approval lock on case creation: confirm only if you approved that exact case |

---

## Run the demo (about 20 minutes)

Follow `docs/Demo-Script-Program-Exceptions-Desk.md`. Before the demo, run the read-only pre-flight `scripts/apex/psp-demo-preflight.apex` to see the expected answers for that day.

1. Architecture: one set of PSP logic, reached through Coworker and Slackbot (MCP).
2. **Coworker:** today's exceptions (task 7), shown as the HXL worklist card.
3. **Coworker:** the combined request (exceptions + delayed-shipment policy + resolution plan): three specialist agents work together.
4. **Coworker:** AI care team handoff for ENR-0007 (task 6), then the duplicate guard (“create a Refill Support case for ENR-0007” → existing case 00001124).
5. Open case 00001124 in Salesforce.
6. **Slackbot:** the same exceptions through PSP Exceptions MCP, the AI handoff for ENR-0018 through PSP Handoff MCP, Patient 360, a program question and refill status.
7. Optional, only if agreed beforehand: one live approved case (suggested: ENR-0059, Shipment Delay, DSP-0073; proposal → yes → Salesforce confirmation).
