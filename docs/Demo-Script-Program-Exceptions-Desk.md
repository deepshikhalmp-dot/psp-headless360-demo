# Demo Script: Zenthera PSP Program Exceptions Desk

Salesforce Headless 360 RFP demo, about 20 minutes. All data is fictional: Zenthera is a made-up drug and every patient is a demo record.

**Story in one line:** a Patient Services Coordinator asks Agentforce Coworker what needs attention today. Coworker hands the work to three specialist agents and shows the worklist as a visual card. It combines the agents' answers into one plan, writes an AI care team handoff from Salesforce facts, and creates a service case only after the coordinator approves it. The same logic is also available in Slack through MCP.

*Refreshed 2026-11-22: new pre-flight values, HXL worklist card, AI-written handoff (prompt template), handoff in Slackbot.*

---

## 1. Before the demo (15 minutes, the day before and again 1 hour before)

| # | Check | How |
|---|---|---|
| 1 | Presenter login | Salesforce as the demo user (`deepshikhaheadless@kpmg.com`). This user has the Coworker group, **PSP Patient Services** and **PSP Specialist Agent Access** |
| 2 | Expected answers for the day | Run the read-only pre-flight: `sf apex run --file scripts/apex/psp-demo-preflight.apex --target-org ProductPillarSDO1`. Write down the counts and the items (section 7 shows the 2026-11-22 values) |
| 3 | Time zone | The demo user is on Los Angeles time. Refill "days overdue" follows that date; mention it if the audience is in another time zone |
| 4 | Slack | In Slackbot → Apps: **PSP Patient Services MCP**, **PSP Named Query MCP**, **PSP Case MCP**, **PSP Program FAQ MCP**, **PSP Exceptions MCP** and **PSP Handoff MCP** are on. Use a direct message, never a public channel |
| 5 | Browser tabs | Salesforce (Patient Support Program app), Coworker (**Ask**), Slack (Slackbot DM), and the case record 00001124 |
| 6 | Clean chats | Start every Coworker step in a **New chat** |
| 7 | Record count | Note the case count from the pre-flight (2026-11-22: 79) to check afterwards that nothing else was created |
| 8 | Optional live creation (5d) | Only if agreed in advance: agree the patient, category, shipment and subject (suggested: ENR-0059, Shipment Delay, DSP-0073) |

---

## 2. Architecture (1 minute)

```
                    Patient Services Coordinator
                      │                      │
            Agentforce Coworker          Slackbot (MCP)
            (Salesforce Ask)                 │
         ┌──────────┼──────────┐   PSP Exceptions MCP · Handoff MCP
         ▼          ▼          ▼   Patient 360 · FAQ · Refill · Case
     Medication  Program     Care            │
     Support     Knowledge   Resolution      │
     (HXL card)              (AI handoff)    │
         │          │          │             │
         └──── same Apex / Flow / prompt template / Data 360 ────┘
               Exceptions service · Refill rule · Duplicate check
               Approved case (confirmation) · Handoff facts → AI summary
               Program FAQ
                             │
                 Salesforce CRM (Account, Program Enrollment,
                 Dispense, Case) in the user's own access
```

**Say:**
- There is one set of business logic, built on standard Salesforce data.
- It can be reached in two ways: through Coworker in Salesforce, and through Slackbot over MCP. That is Headless 360.
- No custom orchestrator: Coworker picks the specialists by their description.
- Rules decide the facts. AI only writes the words (the handoff summary), from those facts.

---

## 3. Act 1: Coworker worklist with the HXL card (3 minutes)

**Prompt (New chat):**
> Show today's Zenthera patient support exceptions.

**What happens:** "Heard back from PSP Medication Support Agent" → a short intro and the **HXL worklist card**:
- title and a summary line
- badges **High / Medium / Low / Data gaps**
- a coloured box per severity, with patient, fact and suggested action
- the footer "Refill dates are based on recorded shipments only. Read-only: nothing was created or changed."

**Say (HXL):** this is a Headless Experience Layer card. It is defined once as metadata (a Lightning Type and a UI widget) and fed by the same Apex. The same card renders in Coworker and in the Agentforce panel.

**Point out:**
- **Real data:** "12 exceptions across 6 patients out of 12 enrollments" (2 high, 7 medium, 1 low, 2 data gaps). Use the counts from the pre-flight.
- **High:** Riya Demo Sharma (ENR-0007) refill overdue, and her safety case 00001071 waiting for human review.
- **Rules, not AI guesses:** the refill is based on recorded shipments only. Nothing is said about whether the patient took the medication.
- **A case without a PSP category is not turned into a safety case.** It is shown as "has no PSP issue category; a person needs to review it" (4 cases: 00001068, 00001075, 00001126, 00001127).
- **Missing data is shown as a data gap,** never invented (consent date missing for Mriduka and Sonali).

---

## 4. Act 2: Three specialists in one request (4 minutes)

**Prompt (New chat):**
> Show today's PSP exceptions, consult the delayed shipment policy and prepare a resolution plan.

**What happens:**
1. "I'll kick off all three tasks in parallel".
2. **Heard back from PSP Medication Support Agent** and **Heard back from PSP Program Knowledge Agent**.
3. "Now let me hand everything over to the PSP Care Resolution Agent" → **Heard back from PSP Care Resolution Agent**.
4. One plan for all items, ending "Nothing has been created or changed".

**Point out:**
- **Two agents ran at the same time,** and the third used their results. This is the Coworker multi-agent story.
- **Three delayed shipments, three different answers:**
  - Riya's DSP-0016 → **Skip:** three open cases already cover it (00001070, 00001072, 00001073), and the duplicates are flagged.
  - Asha Manual Demo's DSP-0072 → **Skip:** case 00001125 already covers it.
  - Ayush Mehta's DSP-0073 → **Create case:** no open Shipment Delay case covers it. The plan only proposes it; nothing is created.

**If the plan does not appear** (seen twice on 2026-11-25: Coworker ran the exceptions and policy agents, showed the card and stopped), ask for it separately:
> Using the PSP Care Resolution Agent, prepare a resolution plan for today's PSP program exceptions.

**If the policy text is missing from the combined answer** (seen once in testing), show it separately:
> What is the Zenthera PSP process for delayed shipments?

Expected: contact the coordinator → the coordinator checks with the pharmacy → a service case tracks the delay. Source: Zenthera Program FAQ, Q15 (Data 360).

---

## 5. Act 3: Handoff and approved actions (5 minutes)

### 5a. AI care team handoff (read-only)
**Prompt (New chat):**
> Prepare a care team handoff for enrollment ENR-0007. Do not create, update or share anything.

**What happens:** "Heard back from PSP Care Resolution Agent" → a handoff written by AI:
- the header "CARE TEAM HANDOFF: Riya Demo Sharma (ENR-0007)"
- a 2–3 sentence **Summary**
- 1 Patient and therapy · 2 Refill status (recorded shipments only: 14 days overdue on 2026-11-22) · 3 Open issues · 4 Points to note · 5 Non-clinical next steps, ending with the prescriber note · 6 Data as of
- the closing line "Written by AI from Salesforce facts; nothing was created, changed or posted."

Coworker may show the case lines as Case record cards.

**Point out:**
- 00001071 appears only as **"in human safety review"**, with no symptoms.
- The open issues are the same five cases as in Salesforce: 00001070, 00001072, 00001073 (Shipment Delay), 00001071 (safety review), 00001124 (Refill Support).

**Say:**
- Two steps: Apex reads the **facts** from Salesforce, then a **prompt template** writes the handoff from those facts only.
- The template has strict rules: no new facts, no medical advice, no adherence claims.
- A case is called a safety case only if the facts say so. A case without a category stays "no PSP issue category yet (needs review)".
- If the AI is unavailable, the factual handoff is shown instead. Nothing is posted.

### 5b. Duplicate guard (no write)
**Prompt (New chat):**
> Using the PSP Care Resolution Agent, create a Refill Support case for ENR-0007: the coordinator wants to confirm the next refill date with the pharmacy.

**Expected:** "An open Refill Support case already exists: 00001124. No new case will be created."

**Say:** the agent checks before it writes. 00001124 was created through this same flow after approval.

### 5c. Open the case (Salesforce)
Open **00001124**. Show:
- the subject "[Refill Support] Confirm next refill date with pharmacy"
- the **PSP Issue Category** field
- the description note "Logged by the PSP Care Resolution Agent after explicit user approval"

### 5d. Optional: live approved creation (creates one real record)
**Update 2026-11-25:** this candidate was used in the evidence run and case **00001130** now covers DSP-0073, so it is no longer a CREATE_CASE item. Pick a new candidate from the pre-flight on the demo day (a SHIPMENT_DELAYED item with suggested action CREATE_CASE), or show the duplicate guard instead.

Do this only if it was agreed before the demo (checklist item 8). The original candidate is the "Create case" item from Act 2: **ENR-0059 (Ayush Mehta), Shipment Delay, shipment DSP-0073**, subject for example "Follow up delayed shipment DSP-0073 with the pharmacy". The pre-flight shows NO_DUPLICATE for it.

1. Prompt: "Using the PSP Care Resolution Agent, prepare a Shipment Delay case for ENR-0059, shipment DSP-0073, with the subject "…". Show me the proposal first."
2. Check the proposal, then reply **yes**. The agent may mention open case 00001127, which has no category: it is listed for review, not counted as a duplicate.
3. Salesforce shows a **confirmation card** with the exact values → **Confirm**.
4. The case number is returned. After the demo, the case count is 80.

**Say:** there are three locks:
1. The agent shows the exact proposal first.
2. Salesforce asks for confirmation.
3. The Apex only writes with approval, after another duplicate check.

After a live creation, the Act 1 and Act 2 answers change (Ayush's DSP-0073 becomes "Skip").

---

## 6. Act 4: Same logic in Slack (4 minutes)

Use the Slackbot direct message. A step counts only if Slackbot shows **"Used … from …"** (a real MCP call).

| Prompt | Server / tool | Expected |
|---|---|---|
| “Using PSP Exceptions MCP, show today's Zenthera program exceptions.” | PSP Exceptions MCP → PSP_Get_Program_Exceptions | Same 12 items as Coworker. If the first call fails, type **try again** |
| “Using PSP Handoff MCP, prepare a care team handoff for ENR-0018.” | PSP Handoff MCP → PSP_Care_Team_Handoff_Summary | AI handoff for Mriduka Sharma; case 00001075 shown as **no PSP issue category yet (needs review)**, not a safety case; consent date missing noted |
| “Show the PSP profile of Riya Demo Sharma using PSPPatient360 from PSP Named Query MCP.” | PSP Named Query MCP | Patient 360 profile (enrollment, insurance, dispenses, cases) |
| “Use PSP_Answer_Program_Question from PSP Program FAQ MCP: can a Medicaid patient use copay assistance?” | PSP Program FAQ MCP | No; Source: Zenthera Program FAQ, Q10 |
| “What is the refill status of ENR-0007?” | PSP Patient Services MCP → refill history | LATE, due 2026-11-08 (recorded shipments only) |

**Say:**
- It is the same Apex, Flow, prompt template and Data 360 FAQ, in a different channel, with no copy of the logic.
- The handoff stays in the direct message; nothing is posted to a channel.

**Agent Fabric:** MuleSoft Agent Fabric is not available in this org (no Anypoint access). Present it as the next step: registering these agents and MCP servers in a central agent registry.

---

## 7. Expected answers on 2026-11-22 (from the pre-flight)

| Check | Value |
|---|---|
| Exceptions | 12 items for 6 patients out of 12 enrollments (2 high, 7 medium, 1 low, 2 data gaps) |
| Riya Demo Sharma (ENR-0007) | Refill overdue 14 days (last delivered DSP-0015 on 2026-10-09, due 2026-11-08) · safety review 00001071 · DSP-0016 delayed → skip (00001070/72/73) · 3 duplicate delay cases |
| Asha Manual Demo (ENR-0057) | DSP-0072 delayed → skip (00001125) |
| Ayush Mehta (ENR-0059) | DSP-0073 delayed, no case → create case · case 00001127 without category |
| Neha Slack Demo (ENR-0058) | Case 00001126 without category |
| Mriduka Sharma (ENR-0018) | Case 00001075 without category · consent date missing |
| Sonali Singh (ENR-0003) | Case 00001068 without category · consent date missing |
| Delayed-shipment filter | 3 items: Asha skip, Ayush create, Riya skip |
| Duplicate check ENR-0007 + Shipment Delay + DSP-0016 | EXISTING_CASE 00001070, 00001072, 00001073 |
| Duplicate check ENR-0007 + Refill Support | EXISTING_CASE 00001124 |
| Duplicate check ENR-0018 + Refill Support | NO_DUPLICATE (00001075 listed as unclassified) |
| Duplicate check ENR-0059 + Shipment Delay + DSP-0073 | NO_DUPLICATE (00001127 listed as unclassified) |
| Handoff facts ENR-0007 | 14 days overdue; open cases 00001070/72/73 (Shipment Delay), 00001071 (in human safety review), 00001124 (Refill Support) |
| Records | 79 cases, 11 open PSP cases, 12 enrollments, 6 dispenses |

**Changed by the evidence run on 2026-11-25:** new patient Kavya Evidence Demo (ENR-0063, DSP-0078, case 00001131 without category) and case 00001130 for Ayush DSP-0073. Coworker then showed 13 items for 6 patients out of 13 enrollments; records 81 cases, 13 enrollments, 7 dispenses. Re-run the pre-flight.

The numbers change with the date (refill days) and with any new record. Always run the pre-flight on the demo day. The pre-flight shows the handoff **facts**; the AI wording differs slightly on every run, but the facts and case lines stay the same.

---

## 8. If something goes wrong

| Problem | What to do |
|---|---|
| Coworker answers itself, without "Heard back from …" | Start a New chat and name the agent: "Using the PSP Care Resolution Agent, …" |
| The worklist comes back as text, without the card | Start a New chat and ask "Using the PSP Medication Support Agent, show today's PSP exceptions as a worklist card" |
| A case proposal appears without "Heard back from Agent" | Do not say yes. It is Coworker's own draft; ask again naming the PSP Care Resolution Agent |
| The handoff says "The AI summary could not be written right now" | Fine to continue: the factual handoff from Salesforce is shown (fallback). Say that the facts never depend on the AI |
| Slackbot answers without "Used … from …" | Repeat the prompt with the server name, for example "Using PSP Handoff MCP, …" |
| Slackbot tool error on the first call | Type **try again** |
| Day counts differ from the pre-flight | Time zone: the demo user is on Los Angeles time |
| A new case was created by mistake | Stop. Note the case number; decide with the program owner whether to close it (no automatic delete) |

---

## 9. After the demo

1. Run the pre-flight again and compare the case count (79 before the demo): only cases approved during the demo may be new (T7-2).
2. Do not post screenshots with patient data in public channels.
3. Case 00001124 stays open as demo data.
