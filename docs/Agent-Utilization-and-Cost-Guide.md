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
- **In our POC org none of the measurement tools are switched on yet** (section 7). The three agents follow the design rules, but their consumption has not been measured. Section 8 lists the switches needed, for approval.

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

- **Exceptions are read twice per card request.** In the Medication Support Agent the counts are read deterministically and the card action reads them again, because an HXL card is only displayed when the model calls the action. That is two Apex actions per request. It is acceptable for a demo; at scale, measure it and consider a single action.
- **Combined three-agent prompts are expensive and unreliable.** In testing, one Coworker prompt asking for the worklist, a plan and a handoff stopped after the card. Separate prompts were cheaper and complete.
- **Prompt templates are extra LLM calls.** The FAQ answer and the handoff summary each add one call inside their flow.

Estimated footprint per request. These figures come from the design and have **not been measured** (see section 7):

| Request (via Coworker) | Actions | LLM calls (approx.) |
|---|---|---|
| "Show today's program exceptions" | 2 (exceptions read, card) | 4–5: Coworker, router, subagent, answer |
| "When is ENR-0007's next refill due?" | 1 | 3–4 |
| Program FAQ question | 1 flow (retriever + prompt template) | 4: Coworker, router, prompt template, answer |
| Care team handoff | 1 flow (prompt template) | 4 |

---

## 7. What is switched on in the POC org (read-only check, 26 Nov 2026)

| Capability | Status | Effect |
|---|---|---|
| Digital Wallet | **Not installed** (Setup shows "Get Started") | No credit view per agent or action |
| Consumption alerts | **None** (0 records) | No early warning on spikes |
| Agentforce Session Tracing | **Off** | No per-turn trace of LLM calls and actions |
| Agent Optimization / Agent Optimizer (beta) | **Off** | No intent and quality analysis |
| Agent Platform Tracing | **Off** | No Flow/Apex action traces |
| Einstein Audit and Feedback | **Off** | No prompt/response audit data |
| Knowledge/RAG Quality Data and Metrics | **Off** | No retriever quality metrics for the FAQ |
| Agent Analytics app "Coworker Insights" | **Ready to install** | Coworker usage insights not available |
| Conversational Memory for Agentforce | **On** (org setting) | Check which agents use it; memory adds context |
| Data Cloud (Data 360) | Enabled | Required for tracing and audit data |

Result: there is **no historical usage data** for the three POC agents. Measurement can only start from the moment the tools are switched on.

---

## 8. Proposed next steps (for approval, not done)

These changes switch on product features, so each needs approval before it is made:

1. **Install Digital Wallet:** Setup → Digital Wallet → Get Started.
2. **Turn on Agentforce Session Tracing:** Setup → Einstein Audit, Analytics, and Monitoring Setup. This also turns on Agent Optimization.
3. **Optional:**
   - Einstein Audit and Feedback (prompt-level data)
   - Agent Platform Tracing (action traces)
   - Knowledge/RAG Quality metrics (FAQ retriever)
4. **Optional:** install the **Coworker Insights** app (Setup → Agent Analytics).
5. **Set consumption alerts** in Digital Wallet at agreed thresholds.
6. **Run the demo script once** and record the real numbers in section 6:
   - credits per request
   - LLM calls per turn
   - actions per session

Before switching these on, check with the account team whether tracing and audit storage in Data 360, or Agent Optimization, use any Data 360 or Flex Credits.

---

## 9. Sources

- Agentforce pricing and credit examples: https://www.salesforce.com/agentforce/pricing/
- Digital Wallet: https://www.salesforce.com/agentforce/digital-wallet/
- Agentforce Observability: https://www.salesforce.com/agentforce/observability/ and https://www.salesforce.com/blog/agentforce-observability/
- Session Trace export (OTel API, beta): https://developer.salesforce.com/docs/ai/agentforce/guide/otel-api.html
- POC design details: [TDD.md](TDD.md) (sections 7, 8, 13, 14, 21)
