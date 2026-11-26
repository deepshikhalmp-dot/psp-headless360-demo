# Agent Utilization and Cost Guide

**Project:** Zenthera Patient Support Program on Salesforce Headless 360 (POC, fictional data)
**Date:** 26 November 2026
**Audience:** project lead and delivery team

This guide answers three questions about the Agentforce agents we build:

1. How do we know how much an agent is used and what it costs?
2. How do we know whether it is effective?
3. What do we do at design time so it uses as few tokens and credits as possible?

The last sections apply this to the three agents built in this POC and list what is needed to measure them.

---

## 1. Summary

- **Agentforce is billed per action, not per token.** Usage is charged in Flex Credits. Salesforce's pricing examples work out at about 20 credits per action (illustrative; confirm against the current rate card and the contract). Tokens still drive cost indirectly: they decide how many reasoning calls a request needs and how big each one is.
- **Measure at three levels:** credits (bill), actions and LLM calls per request (work), and tokens per call (context size).
- **Salesforce provides the tools:**
  - Digital Wallet for credits per agent and action.
  - Agentforce Observability (Session Tracing, Analytics, Optimization) for what each request did.
  - Einstein Audit and Feedback for prompt and response data.
  - Testing Center for quality.
- **Most cost is decided at design time:** deterministic logic before AI, small scope, small action outputs, short conversations.
- **Runaway usage almost always comes from automation, not people:**
  - triggers that start an agent on every record change
  - loops where an agent's update starts the agent again
  - retries and scheduled jobs over many records
- **In our POC org, Digital Wallet and Agentforce Session Tracing were switched on on 26 Nov 2026** (section 7). A measured demo run the same day (section 6.1) showed:
  - Each specialist agent used 2–3 LLM steps and 1–3 actions per request.
  - Coworker added 6–15 seconds on top of each request.
  - One request read the same data three times. This was fixed in Medication Support v7 on the same day: 2 actions instead of 3, card unchanged.
  
  Credits per request are not visible yet: Digital Wallet shows no consumption cards in this org.

---

## 2. What drives cost

| Level | What to measure | Why it matters |
|---|---|---|
| Bill | Flex Credits per agent, per action, per day | Budget, forecasting, spotting spikes |
| Work | Actions per session, LLM (reasoning) calls per turn | Shows whether the agent thinks or calls tools more than the task needs |
| Context | Tokens per LLM call | Driven by instructions, tool descriptions, conversation history and action output size |

One user request usually creates more than one LLM call:

1. the router decides which subagent handles it
2. the subagent decides which action to call
3. the model writes the answer from the action result

Each extra hop adds another call, for example a coordinator agent (such as Coworker) delegating to a specialist agent. Prompt templates called inside a Flow or Apex action, such as a FAQ answer, add their own LLM call.

---

## 3. How to measure utilization (Salesforce tools)

| Tool | What it shows | Notes |
|---|---|---|
| **Digital Wallet** | Flex Credit consumption by agent and drill-down by action; sandbox vs production comparison; consumption alerts | Near-real-time (updated several times a day, not instantly). The monthly statement is the source of truth for billing |
| **Agentforce Session Tracing** | Every turn of every session: user input, planner decisions, LLM calls, action runs, prompt and gateway inputs and outputs, guardrail checks, errors and final answer. Stored in Data 360 | Salesforce states Observability is unmetered across Agentforce SKUs. Traces can be exported through the Session Trace OTel API (beta, Data Cloud required) |
| **Agent Analytics / Agent Optimization** | Sessions, intents, trends, drill-down to subagents and actions; Optimization groups conversations by intent and highlights weak sessions | Agent Optimization uses generative AI itself. Check whether it consumes credits before turning it on at scale |
| **Agent Platform Tracing** | Detailed traces of Flow and Apex actions inside an agent (performance bottlenecks, errors) | Useful when an action is slow or fails |
| **Einstein Audit and Feedback** | Generative AI audit and feedback data in Data 360 (prompts, responses, feedback) | The place to look for prompt-level detail, including prompt templates |
| **Testing Center / `sf agent test`** | Runs a fixed set of test utterances and checks the subagent, action and answer | Quality gate before every release |

---

## 4. KPIs

### Utilization

| KPI | How to read it |
|---|---|
| Sessions per day, active users | Is the agent used at all, and by how many people |
| Actions per session | A sudden rise means loops, retries or a design change |
| LLM calls per turn | Higher than 3–4 for a simple question is a design smell |
| Credits per session | The unit cost of a conversation |
| Tokens per LLM call | Large values point to long instructions, long history or large action outputs |
| **Cost per resolved request** | The most useful single number for management |

### Effectiveness

| KPI | How to read it |
|---|---|
| Task success / resolution rate | Share of requests completed without a human |
| Escalation or handoff rate | High values mean the agent is out of scope or failing |
| Correct action rate (test pass rate) | From Testing Center; should not drop between releases |
| User feedback | Thumbs up / down where the channel supports it |
| Error rate and latency | From Session Tracing and Platform Tracing |
| Repeat requests | Users asking the same thing again suggests the first answer did not help |

---

## 5. Design rules that keep usage low

1. **Deterministic first, AI second.**
   - Put business rules in Apex or Flow, not in the prompt.
   - In Agent Script, run fixed steps deterministically (`run @actions...`) so the model does not have to decide them.
   - Use the LLM only where language is needed: understanding the request and wording the answer.
2. **Keep scope small.** Few subagents per agent, few actions per subagent. Write clear descriptions that do not overlap, because overlap causes wrong tool choices, retries and extra calls.
3. **Keep action outputs small.** Return only the fields needed, use paging and limits, and return a summary rather than raw records. Every output becomes context for the next LLM call.
4. **Keep instructions short and specific.** System instructions and tool descriptions are sent on every call.
5. **Keep conversations short.** History is resent on each turn. Start a new session for a new task, and only enable memory features where they add value.
6. **One request, one job.** Avoid prompts that make one agent coordinate several others in one go. Each delegation adds LLM calls.
7. **Read-only by default.** Writes need explicit approval and a confirmation step, which also prevents repeated writes.
8. **Choose the right model.** Use the default or a smaller model for simple wording tasks, and re-test after changing the model.

### Guarding against runaway usage

| Risk | Control |
|---|---|
| Record-triggered automation starts an agent on every update | Strict entry criteria, run once per record, no agent call from bulk data loads |
| Agent updates a record that starts the same agent again | Recursion guard (field flag or check of the previous value) |
| Failed calls retried without limit | Retry limit and back-off; log and stop |
| Scheduled job runs the agent over all records | Batch limits, run only on changed records, dry run in sandbox first |
| Unexpected adoption or spike | Consumption alerts in Digital Wallet, daily review in the first week, a kill switch (deactivate the agent) |

### Before go-live checklist

- [ ] Estimate load: sessions per day × actions per session × credits per action
- [ ] Measure real consumption in a sandbox with Digital Wallet
- [ ] Session Tracing on; review LLM calls per turn for the main use cases
- [ ] Testing Center suite passes
- [ ] Consumption alerts set at agreed thresholds
- [ ] Rollout in stages (pilot group first)
- [ ] Owner named for the weekly usage and quality review
- [ ] Kill switch tested

---

## 6. How the POC agents follow these rules

| Agent | Subagents (incl. router and off-topic) | Actions | Deterministic steps | What the LLM still does |
|---|---|---|---|---|
| PSP Medication Support Agent | 4 | 3: refill history, program exceptions, worklist card (HXL) | Exceptions counts are run deterministically | Routes the request, calls the card action, words the answer |
| PSP Program Knowledge Agent | 3 | 1: FAQ answer flow | The FAQ flow is run deterministically | Routes; the flow's prompt template writes the answer from the retrieved FAQ text |
| PSP Care Resolution Agent | 5 | 4: program exceptions, duplicate check, create approved case (write, with confirmation), handoff flow | Exceptions list and handoff flow are run deterministically | Routes, proposes the plan, asks for approval; the handoff prompt template writes the summary |

What already keeps usage low:

- **Rules decide the facts.** Refill dates, exceptions and duplicates are computed by Apex (`PSP_RefillHistoryTool`, `PSP_ProgramExceptionsService`, `PSP_CaseDuplicateCheck`). AI only words answers.
- **Bounded outputs.** The exceptions service pages through enrollments with a page size and returns one line per item.
- **Short, specific descriptions.** Agent and tool descriptions stay within the 1,024-character limit and name what each agent does not do, so Coworker routes correctly.
- **Read-only by default.** Only `PSP_CreateApprovedCase` writes. It runs after a duplicate check, an explicit "yes" and a Salesforce confirmation card.

Known trade-offs and lessons:

- **Exceptions were read three times per card request (measured; fixed in v7).** In Medication Support v6 the counts were read by a deterministic `run` inside the reasoning instructions, and the model then called the card action, because an HXL card is only displayed when the model calls the action. After the action, the reasoning instructions were resolved again, so the `run` executed a second time. The trace showed `get_program_exceptions` → LLM → `get_worklist_card` → `get_program_exceptions` → LLM.
  - **Fix (v7, 26 Nov 2026):** the read moved to `before_reasoning`, which runs once before the reasoning loop.
  - **Verified:** the Session Tracing data for the v7 draft preview (15:59 UTC) and a Coworker run on v7 (16:02 UTC) both show `get_program_exceptions` once and `get_worklist_card` once, and the card still renders in Coworker.
  - **Lesson for all agents:** a deterministic `run` placed in a subagent's reasoning instructions repeats on every reasoning pass, including after each action the model calls. When the subagent also has model-called actions, put the fetch in `before_reasoning`.
- **Combined three-agent prompts are expensive and unreliable.** In testing, one Coworker prompt asking for the worklist, a plan and a handoff stopped after the card. Separate prompts were cheaper and complete.
- **Prompt templates are extra LLM calls.** The FAQ answer and the handoff summary each add one call inside their flow.

### 6.1 Measured footprint (Session Tracing, demo run 26 Nov 2026, 13:31–13:42 UTC)

Six read-only prompts were run in Agentforce Coworker as the presenter user. Session Tracing captured five of them completely. The first prompt (exceptions worklist card) created its sessions but no turn data, probably because tracing had only just been switched on.

| Request (via Coworker) | Specialist agent → subagent | LLM steps (specialist) | Actions | Trust and guardrail steps | Specialist time | Total Coworker turn |
|---|---|---|---|---|---|---|
| "When is the next refill due for ENR-0007?" | Medication Support → refill_status | 3 (router, choose action, answer) | 1 Apex (refill history) | 2 | 2.3 s | 10.0 s |
| "What is the PSP process for delayed shipments?" | Program Knowledge → program_faq | 2 (router, answer) | 1 Flow (retriever + prompt template, 5.9 s) | 2 | 7.1 s | 14.1 s |
| "Prepare a care team handoff for ENR-0007" | Care Resolution → care_team_handoff | 2 (router, answer) | 1 Flow (prompt template, 8.4 s) | 2 | 11.6 s | 26.3 s |
| "Prepare a resolution plan for today's exceptions" | Care Resolution → resolution_plan | 2 (router, answer) | 1 Apex (exceptions) + Coworker agent catalog lookup | 2 | 4.6 s | 24.7 s |
| "Show today's exceptions for ENR-0063" (v6) | Medication Support → program_exceptions | 3 (router, choose card, answer) | 3 Apex (exceptions ×2, card) | 2 | 3.2 s | 8.3 s |
| "Show today's exceptions" on **v7** (Coworker, org trace 16:02 UTC) | Medication Support → program_exceptions | 3 (router, choose card, answer) | **2 Apex** (exceptions, card) | 2 | 1.7 s | n/a |

How to read it:

- **LLM steps** are the specialist agent's own reasoning calls. They do not include:
  - Coworker's own reasoning (the trace only shows its `delegate_to_agent` and `agent_catalog` actions)
  - the prompt template call inside the FAQ and handoff flows

  Each request therefore costs at least two more model calls than the column shows.
- **Trust and guardrail steps:** every turn ran a pre-orchestration guardrail classifier and an instruction-adherence check. These are platform checks, not something we designed.
- **Deterministic runs work.** The FAQ and handoff subagents called their flow without an LLM decision: router, then flow, then one LLM step for the answer.
- **Coworker is the main time cost.** It added 6–15 seconds per request on top of the specialist agent.
- **Tokens per call were not visible for this run.** Token counts sit in the Einstein Audit and Feedback data, which was off during the run. It was switched on afterwards (section 7), so later runs can add tokens per call.
- **Credits are not visible yet.** Digital Wallet is installed, but its Consumption Cards show "No data available" and the consumption data object has 0 rows (checked at 15:15 UTC).

---

## 7. What is switched on in the POC org (checked and updated 26 Nov 2026)

| Capability | Status | Effect |
|---|---|---|
| Digital Wallet | **Installed 26 Nov 2026** (approved) | Consumption Cards show "No data available" (checked 15:15 UTC). Agent and action breakdown needs the Consumption Tagging app (separate install). Possibly no Flex Credit consumption is recorded for this demo org; to confirm with the account team |
| Consumption alerts | **Cannot be set** (checked 26 Nov 2026) | Alerts are set on a consumption card, and Digital Wallet shows "No consumption cards available" for this org. Evidence: `docs/evidence/monitoring-no-consumption-cards.png` |
| Agentforce Session Tracing | **On since 26 Nov 2026** (approved) | Per-turn traces of LLM calls and actions are stored in Data 360 from now on |
| Agent Optimization | **On** (switched on automatically with Session Tracing) | Intent and quality analysis; uses generative AI |
| Agent Optimizer in Observability (beta) | Off | Not requested |
| Agent Platform Tracing | **Off** | No Flow/Apex action traces |
| Einstein Audit and Feedback | **On since 26 Nov 2026** (approved) | Prompt/response audit data, including token counts, from now on |
| Consumption Tagging app | **Installed 26 Nov 2026** (approved), data space `default` | Consumption Insights data model and semantic models for credits by agent and action. Data sharing with Salesforce left Disabled. Data appears only once Digital Wallet records consumption for this org |
| Knowledge/RAG Quality Data and Metrics | **Off** | No retriever quality metrics for the FAQ |
| Agent Analytics app "Coworker Insights" | **Ready to install** | Coworker usage insights not available |
| Conversational Memory for Agentforce | **On** (org setting) | Check which agents use it; memory adds context |
| Data Cloud (Data 360) | Enabled | Required for tracing and audit data |

Result: there is **no usage data from before 26 Nov 2026** for the three POC agents. Digital Wallet and Session Tracing collect data from now on. The other settings were left unchanged.

---

## 8. Next steps

Done on 26 Nov 2026 (approved):

1. **Digital Wallet installed:** Setup → Digital Wallet → Get Started. Evidence: `docs/evidence/monitoring-digital-wallet-installed.png`.
2. **Agentforce Session Tracing turned on:** Setup → Einstein Audit, Analytics, and Monitoring Setup. Agent Optimization switched on with it. Evidence: `docs/evidence/monitoring-session-tracing-on.png`.

Measured: one demo run on 26 Nov 2026 (section 6.1).

Also done on 26 Nov 2026 (approved):

- Einstein Audit and Feedback switched on.
- Medication Support Agent v7 published and activated (repeated exceptions read fixed).
- Data Cloud Architect permission set assigned to the admin user.
- Consumption Tagging app installed (data space `default`). Evidence: `docs/evidence/monitoring-consumption-tagging-installed.png`.

Still open. Items 3–5 need approval:

3. **Optional:**
   - Agent Platform Tracing (action traces)
   - Knowledge/RAG Quality metrics (FAQ retriever)
4. **Optional:** install the **Coworker Insights** app (Setup → Agent Analytics).
5. **Set consumption alerts** at agreed thresholds once a consumption card exists. This was tried on 26 Nov 2026: no cards are available in this org, so there is nothing to attach an alert to.
6. **Confirm with the account team** whether this demo org has a Flex Credit (or other usage-based) entitlement. Digital Wallet and Consumption Tagging are installed, but there are no consumption cards. Without one, there are no credit numbers and no alerts. In a customer production org with Agentforce credits, the cards, alerts and agent breakdown work as described in section 3.
7. Re-run the demo prompts and add credits (once visible) and tokens per call (Audit and Feedback is now on) to section 6.1.

Before switching these on, check with the account team whether tracing and audit storage in Data 360, or Agent Optimization, use any Data 360 or Flex Credits.

---

## 9. Building and testing in a sandbox

Most projects build and test agents in a sandbox before production. Two kinds of data behave differently.

### 9.1 Credits (billing): expected to appear in production

- A Salesforce developer guide (written for Agentforce Vibes) states that sandbox usage is charged against the linked production org's Flex Credit entitlement, that there is no separate sandbox pool, and that Digital Wallet flags whether consumption came from a sandbox or from production.
- Third-party guides report that sandbox actions are billed at about 80% of the production rate, for example 16 instead of 20 credits per action. This is not an official figure; check the current rate card.
- The Digital Wallet consumption object has an environment field (`UsageBusinessEnvType__c` on `TenantConsumptionInsights_std__dlm`), so usage can be grouped by sandbox and production.

**What this means:** testing in a sandbox is not free. Load tests and automated test suites (Testing Center) can use production credits. Set a consumption alert in the production Digital Wallet before large test runs.

### 9.2 Traces and tokens: stay in the sandbox

Session Tracing and Einstein Audit and Feedback data are stored in the Data 360 of the org where the agent ran:

- Sandbox sessions, steps and token counts do **not** appear in production.
- To analyse them, turn on Session Tracing and Audit and Feedback **in the sandbox** and run the same queries against the sandbox.
- The sandbox needs Data Cloud (Data 360) provisioned, which is not automatic for every sandbox.
- Local traces from `sf agent preview` (in `.sfdx/agents/<agent>/sessions/`) work against any org and are the cheapest way to check action and LLM step counts while building.

This behaviour was not tested in a sandbox during this POC. It follows from where these features store their data.

### 9.3 Recommended approach

1. In the sandbox, switch on Session Tracing and Audit and Feedback, and measure LLM calls, actions and tokens per request for the main use cases.
2. In production, watch Digital Wallet for sandbox-flagged consumption and set alerts.
3. Before go-live, estimate production cost: credits per request (measured) × expected requests per day.
4. Confirm with the account team whether the contract charges sandbox usage to the production entitlement, and at what rate. Contracts can differ.

---

## 10. Sources

- Agentforce pricing and credit examples: https://www.salesforce.com/agentforce/pricing/
- Digital Wallet: https://www.salesforce.com/agentforce/digital-wallet/
- Agentforce Observability: https://www.salesforce.com/agentforce/observability/ and https://www.salesforce.com/blog/agentforce-observability/
- Session Trace export (OTel API, beta): https://developer.salesforce.com/docs/ai/agentforce/guide/otel-api.html
- Sandbox usage and Flex Credits (Agentforce Vibes): https://developer.salesforce.com/docs/platform/agentforcevibes/guide/afv-flex-credits-estimator.html
- Third-party notes on the sandbox rate: https://www.jitendrazaa.com/blog/salesforce/salesforce-agentforce-credits-cost-model-complete-guide-2026/ and https://vantagepoint.io/blog/sf/salesforce-flex-credits-guide
- POC design details: [TDD.md](TDD.md) (sections 7, 8, 13, 14, 21)
