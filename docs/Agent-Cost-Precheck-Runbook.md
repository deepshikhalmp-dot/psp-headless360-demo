# Agent Cost Pre-check Runbook (Salesforce UI only)

**Purpose:** before deploying an Agentforce agent for a client, check that it will not use too many credits or tokens.
**Needs:** only a Salesforce org (sandbox) with Agentforce and Data Cloud (Data 360). No terminal, no other tools.
**Time:** about half a day for one agent with 5–10 use cases.

Menu names were checked in our POC org on 26 Nov 2026. Names can differ slightly between releases.

---

## Step 1: Switch on measurement (in the sandbox)

1. **Setup** → Quick Find: `Einstein Audit` → open **Einstein Audit, Analytics, and Monitoring Setup**.
2. Turn **On**:
   - **Agentforce Session Tracing** (records every session, step and action). Agent Optimization switches on with it.
   - **Audit and Feedback** (records every LLM call with its token counts).
3. Wait 10–15 minutes. The data objects are created in Data 360 in the background.

> If the page says Data Cloud is not enabled, ask the org admin to provision Data Cloud in this sandbox first. Without it, nothing is recorded.

---

## Step 2: Review the agent design (no testing yet)

Open the agent: **Setup** → **Agentforce Studio** → **Agentforce Agents** → click the agent → open it in the builder.

For each subagent, check:

| Check | Why it matters | Good | Bad |
|---|---|---|---|
| Number of subagents and actions | Every extra choice adds reasoning and wrong-tool retries | Only what the use cases need | Many overlapping actions |
| Descriptions of agents, subagents and actions | The model chooses by description | Short, specific, says what it does **not** do | Vague or overlapping |
| Rules in code, not in the prompt | Rules in prompts cost tokens and are unreliable | Apex or Flow computes facts, AI words the answer | Long rule lists in instructions |
| Deterministic `run` steps | A `run` written inside the reasoning instructions repeats on every reasoning pass | Data fetch in `before_reasoning` when the subagent also has model-called actions | `run` in instructions plus model-called actions in the same subagent |
| Action outputs | Every output becomes input tokens for the next call | Only needed fields, limits, summaries | Whole records or long lists |
| Instruction length | Sent on every LLM call | A few short paragraphs | Pages of text |

Also check **automation**: in Setup → Flows and Apex triggers, make sure nothing starts the agent on every record change, and that an agent update cannot start the agent again.

---

## Step 3: Write the test questions

In a sheet, list:

- 5–10 real questions the client's users will ask (the main use cases)
- 2–3 difficult ones: an ambiguous question, wrong input, a follow-up question

Add columns for the results in Step 4 and Step 5 (see the table in Step 6).

---

## Step 4: Test each question in the builder preview

1. In the agent builder, open the **Preview** (conversation test) panel.
2. Ask each question from Step 3.
3. For each answer, open the **trace / details** of that turn (the builder shows which subagent ran, which actions ran and the reasoning steps).
4. Write down for each question:
   - which actions ran, and how many times each
   - whether the answer was correct

**Red flags:**

- the same action runs twice for one question
- a simple question uses many reasoning steps
- the agent asks again for information the user already gave

Fix the design (Step 2) and test again until these are gone.

> The exact look of the preview trace depends on the builder version. If you cannot see action details there, use Step 5, which records the same information.

---

## Step 5: Run in the real channel and read the numbers

1. **Activate** the agent in the sandbox. Ask the same questions in the real channel (Agentforce panel, Coworker or Slack). Note the start and end time.
2. Wait **15–60 minutes**. Data reaches Data 360 with a delay.
3. Open the **App Launcher** → **Data Cloud** → **More** → **Query Editor**.
4. Paste and run the queries below. Change the date and time to your test window, in UTC.

**Steps per request (actions and LLM steps):**

```sql
SELECT i.ssot__TopicApiName__c AS subagent,
       st.ssot__AiAgentInteractionStepType__c AS step_type,
       st.SubType__c AS sub_type,
       st.ssot__Name__c AS step_name,
       st.ssot__StartTimestamp__c AS started
FROM ssot__AiAgentInteractionStep__dlm st
JOIN ssot__AiAgentInteraction__dlm i
  ON st.ssot__AiAgentInteractionId__c = i.ssot__Id__c
WHERE st.ssot__StartTimestamp__c > TIMESTAMP '2026-12-01 10:00:00'
ORDER BY st.ssot__StartTimestamp__c
```

- `ACTION_STEP` rows are actions (sub type `apex` or `flow`). The same action name twice in one request means the design repeats work.
- `LLM_STEP` rows are the agent's reasoning calls.

**Tokens for every LLM call:**

```sql
SELECT timestamp__c, feature__c, model__c, promptTemplateDevName__c,
       promptTokens__c, completionTokens__c, totalTokens__c, sessionId__c
FROM GenAIGatewayRequest__dlm
WHERE timestamp__c > TIMESTAMP '2026-12-01 10:00:00'
ORDER BY timestamp__c
```

**Tokens per session (one session ≈ one test question):**

```sql
SELECT sessionId__c, COUNT(*) AS llm_calls, SUM(totalTokens__c) AS tokens
FROM GenAIGatewayRequest__dlm
WHERE timestamp__c > TIMESTAMP '2026-12-01 10:00:00'
GROUP BY sessionId__c
ORDER BY tokens DESC
```

Notes:

- Calls with feature `PromptTemplateGenerationsInvocable` are prompt templates called inside a flow or action. Count them as part of the request.
- Some coordinator models (for example Coworker's main model) are logged with 0 tokens, so real totals can be a little higher.
- If a session has no rows, wait longer. The token data took about 25 minutes in our test.

---

## Step 6: Fill the table and decide pass or fail

Agree the limits with the project lead **before** testing. Example limits (adjust per client):

| Question | Actions (and repeats) | LLM calls | Tokens | Correct? | Pass? |
|---|---|---|---|---|---|
| … | e.g. 1 Apex, no repeat | ≤ 5 | < 15,000 | yes | |

| Check | Example limit |
|---|---|
| LLM calls per request | ≤ 5 |
| Repeated actions | none |
| Tokens per request (largest use case) | < 15,000 |
| Testing Center pass rate | ≥ 90%, not lower than the previous version |

For reference, our POC agents used about 10,000–13,000 tokens per request through Coworker, over 90% of them input context.

If any check fails, go back to Step 2, fix, and repeat Steps 4–6.

---

## Step 7: Run the test suite

1. **Setup** → **Agentforce Studio** → **Testing Center**.
2. Create a test with the questions from Step 3 and the expected subagent, action and answer.
3. Run it and record the pass rate.

Test runs also consume credits. Keep the suite focused.

---

## Step 8: Estimate the production cost

In a sheet:

```
credits per day = requests per day × actions per request × credits per action (client rate card)
```

Example: 500 requests per day × 2 actions × 20 credits = 20,000 credits per day.

- Compare with the client's Flex Credit entitlement.
- Sandbox usage is often charged to the production entitlement, sometimes at a lower rate. Confirm this with the account team.

---

## Step 9: Prepare go-live controls (production org)

1. **Credits view:** App Launcher → **Digital Wallet** → **Consumption Cards**. If Digital Wallet is not set up: Setup → Quick Find `Digital Wallet` → Get Started.
2. **Alerts:** open the Flex Credits consumption card and set alerts, for example at 50%, 80% and 100% of the daily or monthly budget. Alerts need a consumption card; an org without a usage contract shows "No consumption cards available".
3. **Agent breakdown:** Digital Wallet setup → **Consumption Tagging** tab → Install, to see credits by agent and action. It needs the Data Cloud Architect permission set for the installing admin.
4. **Monitoring:** switch on Session Tracing and Audit and Feedback in production as well (Step 1), so the Step 5 queries work there.
5. **Kill switch:** Setup → Agentforce Studio → Agentforce Agents → open the agent → **Deactivate**. Try it once in the sandbox so the team knows how.
6. **Rollout:** start with a pilot group, then all users. Check Digital Wallet and the token query daily in the first week, then weekly. Name an owner.

---

## Sign-off

| Item | Done | By | Date |
|---|---|---|---|
| Measurement on (sandbox) | | | |
| Design review done, issues fixed | | | |
| Steps and tokens measured for all test questions | | | |
| All checks within limits | | | |
| Testing Center pass rate recorded | | | |
| Cost estimate agreed with client | | | |
| Alerts, monitoring and kill switch ready in production | | | |

Related: [Agent Utilization and Cost Guide](Agent-Utilization-and-Cost-Guide.md) (background, KPIs, design rules and POC measurements).
