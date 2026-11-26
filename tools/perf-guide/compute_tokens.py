"""Read-only: pulls Session Tracing and Audit data from Data 360 (SQL API) for the guide run and writes
docs/perf-guide/run-data.json. Usage: python compute_tokens.py <org-alias> <raw-shots-dir>"""
import csv, json, os, subprocess, sys
from datetime import datetime, timedelta

ALIAS, RAW = sys.argv[1], sys.argv[2]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "docs", "perf-guide", "run-data.json")


def sql(q):
    out = subprocess.run(["sf", "api", "request", "rest", "/services/data/v68.0/ssot/query-sql", "--method", "POST",
                          "--body", json.dumps({"sql": q}), "--target-org", ALIAS], capture_output=True, text=True).stdout
    d = json.loads(out)
    md = d["metadata"]
    cols = [c["name"] for c in md] if isinstance(md, list) else list(md.keys())
    return [dict(zip(cols, r)) for r in d.get("data", [])]


def ts(v):
    v = v.replace("Z", "+00:00")
    main, _, zone = v.partition("+")
    if "." in main:
        head, frac = main.split(".")
        main = head + "." + (frac + "000000")[:6]
    return datetime.fromisoformat(main + "+" + (zone or "00:00"))


START, END = "2026-11-26 19:30:00", "2026-11-26 20:40:00"
gw = sql(f"SELECT timestamp__c, feature__c, model__c, promptTokens__c, completionTokens__c, totalTokens__c, sessionId__c "
         f"FROM GenAIGatewayRequest__dlm WHERE timestamp__c >= TIMESTAMP '{START}' AND timestamp__c < TIMESTAMP '{END}' ORDER BY timestamp__c")
for r in gw:
    r["sid"] = (r["sessionId__c"] or "").strip('"')
    r["t"] = ts(r["timestamp__c"])
    for k in ("promptTokens__c", "completionTokens__c", "totalTokens__c"):
        r[k] = int(float(r[k] or 0))
sessions = sql(f"SELECT DISTINCT s.ssot__Id__c AS sid, s.ssot__AiAgentChannelType__c AS ch, s.ssot__StartTimestamp__c AS started, "
               f"p.ssot__AiAgentApiName__c AS agent, p.ssot__AiAgentVersionApiName__c AS ver FROM ssot__AiAgentSession__dlm s "
               f"JOIN ssot__AiAgentSessionParticipant__dlm p ON p.ssot__AiAgentSessionId__c = s.ssot__Id__c "
               f"WHERE s.ssot__StartTimestamp__c >= TIMESTAMP '{START}' AND p.ssot__AiAgentApiName__c <> 'NOT_SET' ORDER BY started")
for s in sessions:
    s["t"] = ts(s["started"])
steps = sql(f"SELECT i.ssot__AiAgentSessionId__c AS sid, st.ssot__AiAgentInteractionStepType__c AS type, st.ssot__Name__c AS name, "
            f"st.ssot__StartTimestamp__c AS st, st.ssot__EndTimestamp__c AS et FROM ssot__AiAgentInteractionStep__dlm st "
            f"JOIN ssot__AiAgentInteraction__dlm i ON st.ssot__AiAgentInteractionId__c = i.ssot__Id__c "
            f"WHERE st.ssot__StartTimestamp__c >= TIMESTAMP '{START}' AND st.ssot__AiAgentInteractionStepType__c IN ('ACTION_STEP','LLM_STEP') ORDER BY st")


def session_summary(sid):
    rows = [r for r in gw if r["sid"] == sid]
    st = [x for x in steps if x["sid"] == sid]
    span = None
    if st:
        span = round((ts(st[-1]["et"]) - ts(st[0]["st"])).total_seconds(), 2)
    return {
        "session": sid,
        "tokens": sum(r["totalTokens__c"] for r in rows),
        "input": sum(r["promptTokens__c"] for r in rows),
        "output": sum(r["completionTokens__c"] for r in rows),
        "llm_calls": len([r for r in rows if r["totalTokens__c"] > 0]),
        "calls": [[r["model__c"], r["promptTokens__c"], r["completionTokens__c"], r["totalTokens__c"]] for r in rows],
        "actions": [x["name"] for x in st if x["type"] == "ACTION_STEP"],
        "llm_steps": len([x for x in st if x["type"] == "LLM_STEP"]),
        "agent_seconds": span,
        "audit_complete": bool(rows),
    }


tests = ["T01", "T02", "T03", "T04", "T05", "T06", "T07"]
data = {"window_utc": [START, END], "preview": {}, "coworker": {}, "testing_center": {"6": {}, "7": {}}, "overhead": {}}

# Builder preview: the last 7 Builder sessions before 19:43 are T01..T07 (earlier ones were set-up attempts)
builder = [s for s in sessions if s["ch"] == "Builder" and s["agent"] == "PSP_Medication_Support_Agent" and s["t"] < ts("2026-11-26T19:43:00+00:00")]
builder = builder[-7:]
for i, (tid, s) in enumerate(zip(tests, builder)):
    nxt = builder[i + 1]["t"] if i + 1 < len(builder) else s["t"] + timedelta(minutes=2)
    summ = session_summary(s["sid"])
    authoring = [r for r in gw if r["feature__c"] == "nextGenAuthoring" and s["t"] <= r["t"] < nxt]
    summ["builder_summary_tokens"] = sum(r["totalTokens__c"] for r in authoring)
    data["preview"][tid] = summ

# Coworker: specialist sessions (LEX/LDS) in order; T07 went to the Program Knowledge Agent
cw_specialist = [s for s in sessions if s["ch"] == "LEX/LDS" and ts("2026-11-26T19:43:00+00:00") < s["t"] < ts("2026-11-26T19:55:00+00:00")]
cw_planner = [s for s in sessions if s["ch"] == "MIDAS" and ts("2026-11-26T19:43:00+00:00") < s["t"] < ts("2026-11-26T19:55:00+00:00")]
for tid, s, m in zip(tests, cw_specialist, cw_planner):
    summ = session_summary(s["sid"])
    summ["agent"] = s["agent"]
    haiku = [r for r in gw if r["feature__c"] == "Agentforce Coworker" and not r["sid"] and "haiku" in r["model__c"] and m["t"] - timedelta(seconds=5) <= r["t"] <= s["t"]]
    sonnet = [r for r in gw if r["sid"] == m["sid"]]
    summ["coworker_planner_tokens"] = sum(r["totalTokens__c"] for r in haiku)
    summ["coworker_zero_token_rows"] = len([r for r in sonnet if r["totalTokens__c"] == 0])
    data["coworker"][tid] = summ
for label, start in (("T03-run2", "2026-11-26T20:22:00+00:00"), ("T03-run3", "2026-11-26T20:25:30+00:00")):
    s = next((x for x in sessions if x["ch"] == "LEX/LDS" and x["t"] >= ts(start)), None)
    if s:
        data["coworker"][label] = session_summary(s["sid"])

# Testing Center sessions come from the downloaded results files
for v in ("6", "7"):
    rows = list(csv.DictReader(open(os.path.join(RAW, f"tc_results_v{v}.csv"))))
    utter = [x[0] for x in list(csv.reader(open(os.path.join(RAW, "psp_medsupport_tests.csv"))))[1:]]
    for r in rows:
        tid = tests[utter.index(r["Utterance"])]
        summ = session_summary(r["SessionUUID"])
        summ.update({"action_result": r["Action Test Result Status"], "subagent_result": r["Subagent Test Result Status"],
                     "outcome_result": r["Outcome Test Result Status"], "actual_actions_tc": r["Actual Action"], "actual_subagent_tc": r["Actual Subagent"]})
        data["testing_center"][v][tid] = summ

# Overhead outside the agent: grouped by feature
by_feature = {}
for r in gw:
    f = by_feature.setdefault(r["feature__c"], {"calls": 0, "tokens": 0})
    f["calls"] += 1
    f["tokens"] += r["totalTokens__c"]
data["overhead"]["by_feature"] = by_feature
data["overhead"]["tc_judge_v7"] = sum(r["totalTokens__c"] for r in gw if r["feature__c"] == "agentforce-standard-evals" and ts("2026-11-26T20:08:00+00:00") <= r["t"] < ts("2026-11-26T20:14:00+00:00"))
data["overhead"]["tc_judge_v6"] = sum(r["totalTokens__c"] for r in gw if r["feature__c"] == "agentforce-standard-evals" and ts("2026-11-26T20:14:00+00:00") <= r["t"] < ts("2026-11-26T20:20:00+00:00"))
data["audit_max_timestamp"] = max(r["timestamp__c"] for r in gw) if gw else None
json.dump(data, open(OUT, "w"), indent=1, default=str)
print("written", OUT, "audit max", data["audit_max_timestamp"])
