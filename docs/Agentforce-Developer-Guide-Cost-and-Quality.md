# Agentforce Developer Guide: Building Agents That Are Accurate and Cheap to Run

**For:** Salesforce developers and consultants who design, build and release Agentforce agents.
**Based on:** measurements from the Zenthera PSP proof of concept (November 2026): 3 Agent Script agents, Agentforce Coworker and Slack. Every rule below either comes from something we measured or is marked as an assumption to confirm.
**Companion documents:**
- [Agent Cost Pre-check Runbook](Agent-Cost-Precheck-Runbook.md): the step-by-step test procedure, Salesforce UI only.
- [Performance and cost run](PSP-Medication-Support-Agent-Performance-Cost-Run.docx): the procedure run on one agent, with screenshots.
- [Agent Utilization and Cost Guide](Agent-Utilization-and-Cost-Guide.md): background, KPIs and org status.

---

## 1. The 12 rules (one-page summary)

1. **Use an agent only where reasoning is needed.** Lists, counts and lookups with fixed inputs belong in a list view, report, Flow or MCP tool, which use no model call.
2. **Code decides the facts; the model writes the words.** Dates, statuses, rules and duplicate checks are computed in Apex or Flow, never in a prompt.
3. **Fetch each piece of data once per request.** In Agent Script, a `run` inside `reasoning.instructions` repeats on every reasoning pass. Put deterministic fetches in `before_reasoning`.
4. **Never compute the same thing twice.** If the model must call an action anyway (for example to display a card), take the counts from that action instead of a separate fetch.
5. **Answer only from action results.** When the user gives an identifier, the agent must call the lookup. It may say "not found" only when the action says NOT_FOUND.
6. **Keep the context small.** Short instructions, few actions, short descriptions, and outputs with only the fields the answer needs. Every reasoning call resends all of it.
7. **Fewer reasoning passes beat everything else.** Each pass costs about 2,600-3,000 input tokens before any data.
8. **Read-only by default.** Writes need an explicit user confirmation step and a duplicate check.
9. **Guard against runaway automation.** Nothing should start the agent on every record change, and an agent update must never start the agent again.
10. **Measure before release.** Switch on Session Tracing and Audit and Feedback in the sandbox, run 5-10 scenarios, and read actions, model calls, tokens and latency per request.
11. **Budget building and testing separately.** Builder Preview and Testing Center use more tokens per question than the agent itself.
12. **Release with controls.** A cost estimate, Digital Wallet alerts, a named owner, a tested kill switch (Deactivate) and a pilot group.

---

## 2. What actually drives cost

### 2.1 Credits and tokens are different things

| | What it counts | What drives it | How to reduce it |
|---|---|---|---|
| **Credits** (Flex Credits, per contract) | Billable agent actions. The team guide's example is 20 credits per action in production; confirm the client's rate card | Number of actions per request x requests per day | Fewer actions per request; no repeated actions; no agent where a Flow would do |
| **Tokens** (model usage) | Input and output text of every model call | Number of reasoning passes x size of the context (instructions, tools, history, action outputs) | Fewer passes; shorter instructions; smaller outputs |

**Measured example.** v6 of our Medication Support Agent read the exceptions list twice per request. The v7 fix cut the actions from 9 to 6 for 3 requests, but the tokens stayed the same (34,444 vs 34,441). The repeated read ran in the same pass, without an extra model call. So a repeated deterministic action costs credits, while an extra reasoning pass costs tokens. Look for both.

### 2.2 Where the tokens go in one request (measured, GPT-4.1 agent)

| Part | Tokens | Can you change it? |
|---|---|---|
| Session-start call (every new session) | about 1,050 | No: platform. Fewer new sessions helps |
| Guardrail classifier (every request) | about 930 | No: platform |
| Each reasoning pass (router, subagent, answer) | 2,600-3,000 base, plus the data it carries | **Yes:** fewer passes, shorter instructions, fewer and shorter action descriptions |
| Final answer with a large action output | 4,800 with 15 list items vs 2,900-3,700 filtered | **Yes:** return counts plus the top items |
| Prompt template with grounding text | 1,800-3,000 | **Yes:** smaller retrieved chunks |
| Channel planner (Coworker) | about 950 logged; the main planning model logs 0 | No: platform. Real totals are higher |

Typical totals per request: 4,700 (a refusal handled in the router) to 13,300 (a full worklist). Over 90% of the tokens are input.

### 2.3 Cost outside the agent

| Activity | Measured | Rule |
|---|---|---|
| Builder Preview | Each preview turn triggered a preview-summary call of 23,600-43,700 tokens, 3-8 times the agent's own tokens | Use Preview for a few spot checks; run scenario sets in Testing Center |
| Testing Center (7 cases) | About 64,000 agent tokens plus 20,600 scoring tokens per suite run | Keep suites focused; select extra quality scorers only when needed; upload cases rather than generating them |
| Session Tracing and Audit | Data 360 storage and queries | Plan Data 360 consumption at the client |
| Coworker | A planner call before each delegation, and about 15 s added to the response time | See Section 7 |

### 2.4 Demo org versus client org

- **Our POC demo org** (Enterprise Edition trial until 28 Feb 2027) has no Agentforce or Flex Credit entitlement and no Digital Wallet consumption cards. Usage is not metered, so it is effectively free for us. It is not unlimited, though: it expires, and fair-use limits may apply.
- **A client org** pays by contract (Flex Credits per action, or per-user Agentforce licences), plus Data 360 credits. Sandbox usage may be charged to the production entitlement, sometimes at a lower rate. Confirm with the account team.
- **Models** run through the Einstein Trust Layer under Salesforce's contracts; no provider account or key is needed. The setting is in Setup > Einstein Audit, Analytics, and Monitoring Setup > Select the Model Option for Agentforce. In our org it is "Salesforce Default": GPT-4.1 for agent reasoning, GPT-4o for prompt templates, and Salesforce's own classifier.

---

## 3. Design before you build

### 3.1 Decide what should not be an agent

| Need | Better tool | Why |
|---|---|---|
| A fixed list, count or report | List view, report, dashboard | No model call |
| A lookup with known inputs from Slack | MCP tool on a Flow or Apex (user mode) | One action, no reasoning loop |
| A rule or calculation (due date, status, duplicates) | Apex or Flow, called by the agent | Correct every time, no prompt tokens |
| Free-text questions, choosing between tasks, explaining results | Agent | This is where reasoning pays off |

### 3.2 Scope

- **One agent per job family.** Our specialists: medication facts, program knowledge, care resolution.
- **Router plus a few subagents.** Use a subagent only for a real boundary (different actions, authority or instructions).
- **Few actions per subagent** (1-2 in our agents). Every action description is sent on every reasoning call.
- **Descriptions say what the agent, subagent or action does not do.** Example: "Not for program policy questions or creating cases." This avoids wrong-tool retries and wrong routing by an orchestrator.

### 3.3 Write the Agent Spec with cost in mind

For each use case, write down: the expected subagent, the expected actions (and that each runs once), the expected answer, and a target for model calls and tokens. These later become the Testing Center file and the pass/fail limits.

---

## 4. Agent Script rules

### 4.1 Deterministic fetches go in `before_reasoning`

```
subagent program_exceptions:
    before_reasoning:
        run @actions.get_program_exceptions          # runs once per turn
            with enrollmentNumber=""
            with exceptionTypes=""
            set @variables.exceptions_summary = @outputs.resultMessage

    reasoning:
        instructions: ->
            | Today's summary (counts only): {!@variables.exceptions_summary}
              ...
```

A `run` written inside `reasoning.instructions` compiles into `before_reasoning_iteration` and repeats on every reasoning pass. In v6 that produced 2 reads plus the card action for every request.

### 4.2 Do not fetch what an action will return anyway

In v7 the subagent still computes the exceptions twice: `before_reasoning` (for the counts) and the card action (for the card), both running the same rules. If the model must call an action, for example because an HXL card is displayed only when the model calls the action, put the counts in that action's output and drop the separate fetch. That saves one action per request.

### 4.3 Ground every answer in an action result

We measured a defect: for an unknown patient name, the agent replied "could not find a patient" without calling the lookup, in 3 of 3 runs. The wording looked right, so Testing Center's response check passed it; only the action check caught it. Write the instruction explicitly:

```
| When the user gives a patient name or enrollment number, call check_refills exactly once before answering.
  Say the patient was not found only when resultCode is NOT_FOUND. Never answer from memory.
```

### 4.4 Keep model-facing text short and literal

- A few short paragraphs per subagent. Keep long rule lists in code.
- Put only counts or summaries in variables injected with `{!@variables.x}`, never whole lists.
- Indentation, numbering or words like "STOP" inside `|` text are model instructions, not control flow. Gate actions with real conditions when the outcome must be deterministic.
- Compile locally, validate against the org, preview and read the trace after every change.

### 4.5 Routing and transitions

- The cheapest path for a refusal is the router answering directly: one reasoning call. Our router refused the medical question itself instead of transitioning to `off_topic`. That is acceptable, but it differs from the design, and Testing Center reports it as a subagent mismatch. Decide which behaviour you want and write the test to match.
- After an HXL card is shown, the platform transitions back to the router. Testing Center then reports the router as the "actual subagent" (42.86% subagent pass for both our versions). Check routing in the trace instead (Section 9, Query B).

---

## 5. Action and output design

| Rule | Why | Our example |
|---|---|---|
| Return a `resultCode` plus a plain `resultMessage` | The model can show the message and branch on the code without guessing | SUCCESS, NOT_FOUND, AMBIGUOUS_MATCH, NO_ENROLLMENT, INVALID_INPUT, ERROR |
| Return only the fields the answer needs | Every output becomes input tokens for the next reasoning call | Full card 4,800 input tokens vs filtered 2,900-3,700 |
| Return counts plus the top items for long lists | Large outputs dominate the final call | Exceptions summary carried as counts only |
| Compute facts in the action | No prompt rules, same answer every time | Refill due date and status in `PSP_RefillHistoryTool` |
| Run in user mode (`WITH USER_MODE`, `AccessLevel.USER_MODE`) | Sharing and field security apply; no extra data exposure | All PSP actions |
| Be read-only unless the use case writes | Fewer risks and simpler tests | Only 3 PSP components write, each after approval |
| One shared implementation for all channels | The same Apex serves the agent action, the MCP tool and the Flow | `PSP_ProgramExceptionsService` |

---

## 6. Prompt templates and grounding

- Use a prompt template only when the text needs generation (FAQ answer, handoff summary). Each call is a separate model call (GPT-4o in our org).
- Keep the grounding small: retrieve a few chunks, not whole documents. Our FAQ template call was about 3,000 tokens and the handoff about 1,850.
- Put fixed policy text in the knowledge source, not in the template instructions.

---

## 7. Channel effects

| Channel | What we measured | Rule |
|---|---|---|
| Builder Preview (Live Test) | Real actions; shows Summary and Trace per turn; expensive summary call per turn | Use for spot checks and debugging |
| Agentforce Coworker | Planner call plus delegation; agent 1-3 s but 12-18 s end to end; each new chat is a new specialist session | Count Coworker's time and planner tokens in the budget; keep follow-ups in the same chat (to confirm) |
| Coworker routing | A medication question with "dose" went to the Program Knowledge Agent | Distinct agent descriptions with "not for"; test which agent Coworker picks |
| Coworker relay | 1 of 3 runs showed text without the card, although the agent produced it | Repeat key scenarios 2-3 times in the real channel |
| Slack (MCP tools) | Tools run as the linked user; no agent reasoning loop | Prefer for simple lookups |

---

## 8. Preventing runaway usage

- **No automatic loops.** No record-triggered Flow or trigger should call an agent on every change. If one must, add entry criteria and a guard field so the agent's own update cannot start it again.
- **No batch calls without limits.** Cap records per run and runs per day.
- **Kill switch.** Setup > Agentforce Agents > open the agent > Deactivate. Practise it in the sandbox. Also know which automation calls the agent, so you can stop it too.
- **Pilot first.** Roll out to a small group and check Digital Wallet and the token query daily in the first week.
- **Alerts.** In Digital Wallet, set alerts on the consumption card (for example 50%, 80% and 100%). This needs a consumption card, which our demo org does not have.
- **Owner.** Name one person who watches usage and can deactivate the agent.

---

## 9. Measuring: setup, queries and pitfalls

### 9.1 Switch on (sandbox first, then production)

Setup > Einstein Audit, Analytics, and Monitoring Setup:
- **Agentforce Session Tracing** records sessions, steps and actions; it switches on Agent Optimization with it.
- **Audit and Feedback** records every model call with its tokens.

Data arrives with a delay: traces in minutes, token rows in 25-60 minutes (batches). Read tokens at least an hour after testing.

### 9.2 Queries (Data Cloud > Query Editor)

**Steps of one session (actions and reasoning):**
```sql
SELECT i.ssot__TopicApiName__c AS subagent, st.ssot__AiAgentInteractionStepType__c AS step_type,
       st.SubType__c AS sub_type, st.ssot__Name__c AS step_name,
       st.ssot__StartTimestamp__c AS started, st.ssot__EndTimestamp__c AS ended
FROM ssot__AiAgentInteractionStep__dlm st
JOIN ssot__AiAgentInteraction__dlm i ON st.ssot__AiAgentInteractionId__c = i.ssot__Id__c
WHERE i.ssot__AiAgentSessionId__c = '<session id>'
ORDER BY started
```

**Repeated actions (any row = waste). Testing Center's action check does not catch these:**
```sql
SELECT st.ssot__AiAgentInteractionId__c AS interaction_id, st.ssot__Name__c AS action, COUNT(*) AS runs
FROM ssot__AiAgentInteractionStep__dlm st
WHERE st.ssot__AiAgentInteractionStepType__c = 'ACTION_STEP'
  AND st.ssot__StartTimestamp__c >= TIMESTAMP '<from, UTC>'
  AND st.ssot__StartTimestamp__c <  TIMESTAMP '<to, UTC>'
GROUP BY st.ssot__AiAgentInteractionId__c, st.ssot__Name__c
HAVING COUNT(*) > 1
```

**Tokens per session (includes the calls that are not linked to a step):**
```sql
SELECT sessionId__c, COUNT(*) AS calls, SUM(totalTokens__c) AS tokens
FROM GenAIGatewayRequest__dlm
WHERE timestamp__c >= TIMESTAMP '<from, UTC>' AND timestamp__c < TIMESTAMP '<to, UTC>'
GROUP BY sessionId__c
ORDER BY tokens DESC
```

**Tokens by feature (shows build and test overhead):**
```sql
SELECT feature__c, model__c, COUNT(*) AS calls, SUM(totalTokens__c) AS tokens
FROM GenAIGatewayRequest__dlm
WHERE timestamp__c >= TIMESTAMP '<from, UTC>' AND timestamp__c < TIMESTAMP '<to, UTC>'
GROUP BY feature__c, model__c
ORDER BY tokens DESC
```

### 9.3 Pitfalls we hit

| Pitfall | Effect | Do this |
|---|---|---|
| Joining the session participant object | Rows appear 2-4 times | Use `DISTINCT` |
| Using only the step-to-request join (Query D) | Misses the session-start and classifier calls, about 2,000 tokens per request | Add the tokens-per-session query |
| Coworker's main planning model and guardrail checks | Logged with 0 tokens | Report Coworker totals as a lower bound |
| Feature names | Agent tokens are labelled by channel ("Agentforce Coworker", "Agentforce Builder Preview", "Testing Center Setup") | Filter by session ID, not by feature |
| One run per scenario | Agents are not deterministic (T03 relay 1 of 3, T05 3 of 3) | Repeat key scenarios 2-3 times |

---

## 10. Metrics and suggested targets

These are suggested targets, not Salesforce limits. Agree them with the project lead before testing.

| Metric | Where to read it | Suggested target |
|---|---|---|
| Repeated actions per request | Repeated-actions query | 0 |
| Actions per request | Steps query | Only what the use case needs (ours: 0-2) |
| Reasoning passes per request | Steps query (LLM_STEP) | <= 3 for simple requests |
| Logged tokens per request | Tokens-per-session query | < 15,000 for the largest use case |
| Agent-side time | Steps query (first start to last end) or Preview Trace | <= 3 s |
| End-to-end time in the real channel | Stopwatch or browser timing | <= 15 s (Coworker adds about 15 s) |
| Answer grounded in an action result | Steps query: the action ran before the answer | 100% where an identifier was given |
| Correct answers | Testing Center response check plus manual review | 100% for critical cases, >= 90% overall |
| Testing Center action pass | Testing Center | >= 90%, never lower than the previous version |
| Testing Center subagent pass | Testing Center | Read with care (Section 4.5); confirm in traces |

---

## 11. Testing economically

- **Builder Preview:** a few spot checks per change. Reset the simulator for independent questions. Remember the summary call per turn.
- **Testing Center:**
  - Upload a CSV with Utterance, Expected Subagent, Expected Actions and Expected Response.
  - Use Live Mode for read-only actions and Simulate Mode when actions would write.
  - Select only the scorers you need.
  - You can test any committed version without activating it, which is the cheapest before/after comparison.
- **Real channel:** run the scenarios once more in the channel users will use, and repeat the key ones 2-3 times.
- **Sandbox:** do all of this in a sandbox. Traces and tokens stay in the sandbox; credits may count against production.

---

## 12. Estimating cost before release

```
credits per day = requests per day x billable actions per request x credits per action
```

- Use a mix of use cases, for example: 40% two-action views, 40% one-action lookups, 20% clarifications (0 actions).
- Our example at 200 requests per day and 20 credits per action: v6 6,400, v7 4,800, and with the single-fetch proposal 3,200 credits per day.
- Add what the formula does not cover: the channel's own orchestration, Data 360, prompt templates if billed separately, and build and test usage.
- Confirm whether deterministic `run` actions are billed like model-selected actions.
- Never present an estimate as actual usage. Reconcile it with Digital Wallet after the pilot.

---

## 13. Anti-patterns (symptom, cause, fix)

| Symptom in the trace | Cause | Fix |
|---|---|---|
| The same action twice in one interaction | `run` inside `reasoning.instructions` | Move it to `before_reasoning` |
| Two different actions computing the same data | A separate fetch for counts plus a display action | One action returns both |
| An answer with no action before it | The instruction allows answering from memory | "Call the action before answering; say not found only on NOT_FOUND" |
| Large input tokens on the final call | A big action output | Return counts plus the top items; trim fields |
| Many reasoning passes for a simple question | Vague or overlapping action descriptions; long instructions | Fewer actions, clear "not for" descriptions |
| The wrong agent chosen by the orchestrator | Overlapping agent descriptions | Distinct scopes; test the orchestrator's choice |
| Usage grows without user activity | Automation calling the agent | Entry criteria, recursion guard, kill switch |
| Build-phase tokens far above runtime | Many Builder Preview turns | Move scenario runs to Testing Center |

---

## 14. Release checklist

| Item | Done |
|---|---|
| Use cases that do not need an agent moved to Flow, report or MCP tool | |
| Each subagent: few actions, short instructions, "not for" in descriptions | |
| Deterministic fetches in `before_reasoning`; no data computed twice | |
| Answers grounded: lookup before answer, "not found" only on NOT_FOUND | |
| Action outputs trimmed; long lists returned as counts plus top items | |
| Read-only by default; writes confirmed by the user and duplicate-checked | |
| No automation can call the agent in a loop | |
| Session Tracing and Audit on; repeated-actions query returns no rows | |
| Tokens, model calls and latency per scenario within the agreed targets | |
| Testing Center suite recorded; action pass not lower than the previous version | |
| Key scenarios repeated 2-3 times in the real channel | |
| Cost estimate agreed with the client (rate card, entitlement, Data 360) | |
| Digital Wallet alerts set; owner named; kill switch practised; pilot group chosen | |
