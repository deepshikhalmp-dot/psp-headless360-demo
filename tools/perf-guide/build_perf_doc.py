"""Builds docs/PSP-Medication-Support-Agent-Performance-Cost-Run.docx: the team's performance and cost
measurement guide (v1.1) applied step by step to the PSP Medication Support Agent, with screenshots and
the measured results. Inputs: docs/perf-guide/run-data.json (from compute_tokens.py), docs/perf-guide/data/*,
docs/perf-guide/screens/*."""
import csv
import json
import os
import struct

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASE = os.path.join(ROOT, "docs", "perf-guide")
SCREENS = os.path.join(BASE, "screens")
OUT = os.path.join(ROOT, "docs", "PSP-Medication-Support-Agent-Performance-Cost-Run.docx")
BLUE = RGBColor(0x0B, 0x5C, 0xAB)
GREY = RGBColor(0x55, 0x5B, 0x66)
RED = RGBColor(0xB0, 0x1E, 0x1E)

D = json.load(open(os.path.join(BASE, "run-data.json")))
CW1 = json.load(open(os.path.join(BASE, "data", "coworker-run1.json")))
CW_RE = json.load(open(os.path.join(BASE, "data", "coworker-T03-reruns.json")))
TESTS = list(csv.reader(open(os.path.join(BASE, "data", "test-cases.csv"))))[1:]
IDS = ["T01", "T02", "T03", "T04", "T05", "T06", "T07"]
PV, CW, TC = D["preview"], D["coworker"], D["testing_center"]


def n(v):
    return f"{v:,}"


def tok(entry):
    """Token figure for a session, or 'pending' when the audit rows have not arrived."""
    if not entry or not entry.get("audit_complete"):
        return "pending"
    return n(entry["tokens"])


def acts(entry):
    a = entry.get("actions", [])
    if not a:
        return "none"
    out = []
    for name in dict.fromkeys(a):
        c = a.count(name)
        out.append(f"{name} x{c}" if c > 1 else name)
    return ", ".join(out)


def repeats(entry):
    a = entry.get("actions", [])
    return len(a) - len(set(a))


# ---------- document helpers ----------
doc = Document()
section = doc.sections[0]
section.page_width, section.page_height = Inches(8.27), Inches(11.69)
for side in ("left_margin", "right_margin", "top_margin", "bottom_margin"):
    setattr(section, side, Inches(0.7))
doc.styles["Normal"].font.name = "Calibri"
doc.styles["Normal"].font.size = Pt(10.5)
CONTENT_WIDTH = 6.87


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def shade(cell, hex_color):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_color)
    tc_pr.append(shd)


def heading(text, level=1):
    h = doc.add_heading(text, level=level)
    for run in h.runs:
        run.font.color.rgb = BLUE
    return h


def para(text, bold=False, italic=False, color=None, size=None, space_after=4):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.bold, run.italic = bold, italic
    if color:
        run.font.color.rgb = color
    if size:
        run.font.size = Pt(size)
    p.paragraph_format.space_after = Pt(space_after)
    return p


def label(name, text):
    p = doc.add_paragraph()
    r = p.add_run(name + " ")
    r.bold = True
    p.add_run(text)
    p.paragraph_format.space_after = Pt(3)
    return p


def bullets(items):
    for item in items:
        p = doc.add_paragraph(item, style="List Bullet")
        p.paragraph_format.space_after = Pt(1)


def numbered(items):
    for item in items:
        p = doc.add_paragraph(item, style="List Number")
        p.paragraph_format.space_after = Pt(2)


RESULT_COLORS = {"PASS": "E3F4E8", "FAIL": "FBE3E3", "OPEN": "FFF1D6", "N/A": "EEEEEE", "PARTIAL": "FFF1D6", "CONDITIONAL": "FFF1D6"}


def table(rows, widths=None, color_col=None):
    t = doc.add_table(rows=len(rows), cols=len(rows[0]))
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    if widths:
        for j, w in enumerate(widths):
            t.columns[j].width = Inches(w)
    for i, row in enumerate(rows):
        for j, value in enumerate(row):
            cell = t.cell(i, j)
            cell.text = ""
            run = cell.paragraphs[0].add_run(str(value))
            run.font.size = Pt(8.5)
            if i == 0:
                run.bold = True
                shade(cell, "DCE9F7")
            elif color_col is not None and j == color_col:
                key = str(value).split(" ")[0].upper()
                if key in RESULT_COLORS:
                    shade(cell, RESULT_COLORS[key])
            if widths:
                cell.width = Inches(widths[j])
    doc.add_paragraph().paragraph_format.space_after = Pt(2)
    return t


def expected(title):
    p = doc.add_paragraph()
    r = p.add_run("EXPECTED OUTPUT  |  " + title)
    r.bold = True
    r.font.size = Pt(9)
    r.font.color.rgb = GREY
    p.paragraph_format.space_after = Pt(2)


def image(name, caption, max_height=7.6, width=CONTENT_WIDTH):
    path = os.path.join(SCREENS, name)
    w, h = png_size(path)
    width_in = min(width, max_height * w / h)
    doc.add_picture(path, width=Inches(width_in))
    cap = para(caption, italic=True, color=GREY, size=8.5, space_after=8)
    return cap


def guide_box(where, do):
    t = doc.add_table(rows=1, cols=1)
    t.style = "Table Grid"
    cell = t.cell(0, 0)
    shade(cell, "F2F5F9")
    cell.text = ""
    p = cell.paragraphs[0]
    r = p.add_run("Guide  ")
    r.bold = True
    r.font.size = Pt(9)
    r.font.color.rgb = BLUE
    r = p.add_run("Where: ")
    r.bold = True
    r.font.size = Pt(9)
    r = p.add_run(where + "   ")
    r.font.size = Pt(9)
    r = p.add_run("Do: ")
    r.bold = True
    r.font.size = Pt(9)
    r = p.add_run(do)
    r.font.size = Pt(9)
    doc.add_paragraph().paragraph_format.space_after = Pt(1)


# ---------- derived numbers ----------
def cw_total(tid):
    e = CW.get(tid, {})
    if not e.get("audit_complete"):
        return None
    return e["tokens"] + e.get("coworker_planner_tokens", 0)


exc = ["T01", "T02", "T03"]
v6_exc_actions = sum(len(TC["6"][t]["actions"]) for t in exc)
v7_exc_actions = sum(len(TC["7"][t]["actions"]) for t in exc)
tc_audit = all(TC[v][t].get("audit_complete") for v in ("6", "7") for t in IDS)


def tc_sum(v, tests):
    return sum(TC[v][t]["tokens"] for t in tests)


builder_summary = [PV[t]["builder_summary_tokens"] for t in IDS]
preview_agent = [PV[t]["tokens"] for t in IDS]

# ---------- title ----------
title = doc.add_heading("Agentforce Performance and Cost Measurement", 0)
for run in title.runs:
    run.font.color.rgb = BLUE
para("Run record: PSP Medication Support Agent (v7, with v6 as the \"before\" version)", bold=True, size=13)
para("Method: team runbook \"Agentforce performance and cost measurement guide\", version 1.1 (nine steps, Salesforce UI only). "
     "Each step below shows what the guide asks, what we did, the guide's expected-output table filled with our real results, "
     "what we observed, and screenshots.", size=10)
table([
    ["Item", "Value"],
    ["Agent", "PSP Medication Support Agent (Agentforce Employee Agent, Agent Script). Read-only: refill status, shipments, program exceptions"],
    ["Versions", "v7 active (exceptions read moved to before_reasoning on 26 Nov). v6 used as the before version in Testing Center"],
    ["Org", "ProductPillarSDO, the Salesforce demo org used for the Zenthera PSP proof of concept. Not a sandbox (see Appendix D)"],
    ["Run window", "26 Nov 2026, 19:30-20:40 UTC (27 Nov 01:00-02:10 IST)"],
    ["Channels", "Agent builder Preview (Live Test), Agentforce Coworker as the coordinator demo user, Testing Center (Live Mode)"],
    ["Data", "Fictional demo records only. No real patient data. All agent actions are read-only"],
], widths=[1.3, 5.57])

# ---------- result at a glance ----------
heading("Result at a glance", 1)
exc_tokens_cw = [cw_total(t) for t in exc if cw_total(t)]
glance = [
    ["Measure", "Result", "Status"],
    ["Repeated actions (exceptions requests)", f"v6: 1 repeat per request ({v6_exc_actions} actions for 3 requests). v7: none ({v7_exc_actions} actions for 3 requests)", "PASS"],
    ["Actions per request (v7)", "Exceptions 2, refill lookup 1, clarification and refusal 0", "PASS"],
    ["LLM calls per request (v7)", "1-3 reasoning calls, plus 1 session-start call and 1 guardrail classifier", "PASS"],
    ["Logged tokens per request (v7, Coworker)",
     (f"{n(min(exc_tokens_cw))}-{n(max(exc_tokens_cw))} for exceptions requests, including about 950 for the Coworker planner" if exc_tokens_cw else "pending"),
     "PARTIAL (one Coworker model logs 0 tokens)"],
    ["Response time", "Agent side 0.9-2.8 s. End to end in Coworker 12-18 s", "PARTIAL (target 15 s)"],
    ["Correctness", "6 of 7 correct in Preview and Testing Center; T05 answered 'not found' without looking the patient up (3 of 3 runs on v7)", "FAIL (T05)"],
    ["Testing Center v7", "Subagent 42.86%, Action 85.71%, Response 100% (v6: 42.86%, 100%, 100%)", "See Step 7"],
    ["Estimated production credits", "Illustrative: 4,800 credits per day at 200 requests per day (v6 would be 6,400)", "Needs rate card"],
    ["Actual credits", "N/A: Digital Wallet has no consumption cards in this org", "N/A"],
    ["Before vs after (same 7 cases)", f"Actions: v6 {sum(len(TC['6'][t]['actions']) for t in IDS)}, v7 {sum(len(TC['7'][t]['actions']) for t in IDS)}. "
     f"Tokens: v6 {n(tc_sum('6', IDS))}, v7 {n(tc_sum('7', IDS))} (the difference is T05, where v7 skipped the lookup)", "PASS (actions)"],
    ["Decision", "Conditional: fix T05, then retest; confirm entitlement and rate card; name an owner", "CONDITIONAL"],
]
table(glance, widths=[1.8, 3.9, 1.17], color_col=2)

heading("Key findings", 2)
findings = [
    f"The v7 fix works in every channel. With the same 7 test cases, v6 ran {v6_exc_actions} actions for the 3 exceptions requests and v7 ran {v7_exc_actions}: "
    f"the duplicate get_program_exceptions call is gone. Tokens did not change (exceptions requests: v6 {n(tc_sum('6', exc))}, v7 {n(tc_sum('7', exc))}), "
    "because the repeated read ran without an extra model call. The fix saves one action (credits) per exceptions request, not tokens.",
    "Grounding gap (T05). For an unknown patient name, v7 replied 'could not find a patient' without calling get_refill_history, in Preview, Coworker and Testing Center. "
    "v6 called the action in its one run. The answer looks right, but it is not based on data. Testing Center's response check passed it; only the action check failed it.",
    "Remaining waste. Every exceptions request still computes the exceptions list twice: once in before_reasoning (for the counts) and once in the card action. "
    "Building the counts from the card action would save one action per exceptions request.",
    "Coworker relay. In 1 of 3 Coworker runs of T03 the reply said 'Here are all ... delayed' but showed no items or card, although the trace shows the agent ran both actions. "
    "The agent itself was correct; Coworker dropped the result once.",
    "Fixed cost per session. Every new session makes a session-start model call (1,054 tokens) and a guardrail classifier call (about 930 tokens). "
    "That is about 2,000 tokens per request before any reasoning, 16-43% of a request here.",
    "Building and testing cost more than running. Each Builder Preview turn also triggered a preview-summary model call of "
    f"{n(min(builder_summary))}-{n(max(builder_summary))} tokens, 3-8 times the agent's own tokens. Testing Center adds judge calls. Budget the build phase separately.",
    "Testing Center limits for this agent. The subagent check reported agent_router or topic_selector instead of the real subagent (42.86% for both versions, "
    "although traces show correct routing), and the action check passed v6 even with the repeated action. Use traces (Query B) to find waste.",
    "Query D alone undercounts. It returns only model calls linked to a step (3 of 5 per request). The session-start and classifier calls are found with Query C by session ID.",
    "Credits cannot be measured here. Digital Wallet shows no consumption cards, so actual credits are N/A and alerts cannot be set.",
]
numbered(findings)

# ---------- step 1 ----------
heading("Step 1  Enable monitoring", 1)
guide_box("Setup > Einstein Audit, Analytics, and Monitoring Setup.",
          "Enable Session Tracing and Einstein Audit and Feedback. Allow time for DMOs to provision; run a smoke test to confirm logging.")
label("What we did:", "Opened the setup page and checked the toggles (switched on earlier for this POC). Checked that Data 360 Query Editor opens, created the "
      "workspace 'PSP Agent Cost Precheck' (data space default), and ran a smoke-test query on the session and audit objects.")
expected("Monitoring readiness checklist")
table([
    ["Check", "Expected", "Our result"],
    ["Agentforce Session Tracing", "Enabled", "PASS: On (Agent Optimization switched on with it)"],
    ["Einstein Audit and Feedback", "Enabled", "PASS: On"],
    ["Data 360 and Query Editor", "Accessible", "PASS: Data Cloud enabled, data space default, Query Editor workspace created"],
    ["Smoke-test trace and audit rows", "Available", "PASS: session, step and audit rows returned for the test window"],
    ["Other toggles (for the record)", "-", "Platform Tracing off, Agent Optimizer (beta) off, Health Monitoring off, RAG metrics off"],
], widths=[2.0, 1.2, 3.67], color_col=2)
label("Observations:", "")
bullets([
    "Ingestion delay differs by data type. Session Tracing rows arrived within minutes. Audit (token) rows arrived in batches and lagged 25-60 minutes during this run. "
    "Plan the token readout for the next day or at least an hour after testing.",
    "All field names used in the guide's appendix queries exist in this org (validated one by one).",
])
image("S1-monitoring-setup.png", "Step 1. Setup > Einstein Audit, Analytics, and Monitoring Setup: Audit and Feedback, Session Tracing and Agent Optimization are On.", max_height=7.2)

# ---------- step 2 ----------
heading("Step 2  Review the agent design", 1)
guide_box("Agentforce Studio > Agentforce Agents > agent > Builder.",
          "Inspect routing, instructions, actions, outputs, deterministic rules, permissions and safeguards. Log and fix waste or risks.")
label("What we did:", "Opened the agent in the new Agentforce Builder (Setup > Agentforce Agents > PSP Medication Support Agent), reviewed the canvas, "
      "each subagent, its Before Reasoning block, instructions and actions, and checked the project metadata for automation that calls the agent.")
expected("Design review log")
table([
    ["Review item", "Finding", "Action / status"],
    ["Action selection (program exceptions)", "v6 ran the exceptions read inside the reasoning instructions, so it repeated on every reasoning pass (2 reads plus the card per request).",
     "Moved to before_reasoning in v7 (runs once per turn). FIXED, verified in Steps 4-7"],
    ["Action selection (remaining)", "v7 still computes the exceptions twice per request: before_reasoning for the counts, then the card action with the same rules.",
     "Proposal: take the counts from the card action and drop the before_reasoning read. OPEN, needs approval"],
    ["Grounding (refill status)", "The instruction says 'call the action once' but does not forbid answering without it. Found in Step 4: v7 said 'not found' without a lookup.",
     "Proposal: always call get_refill_history when a name or enrollment number is given; say not found only when the result is NOT_FOUND. OPEN"],
    ["Instruction and data size", "The full exceptions card (15 items) goes back into the final model call: about 4,800 input tokens versus 2,900-3,700 when filtered.",
     "Acceptable for the POC. For production, return counts plus the top items. MONITOR"],
    ["Routing", "Router plus 3 subagents with distinct descriptions. The medical question is refused in the router with a single model call.",
     "No change. VERIFIED"],
    ["Automation and writes", "All 3 actions are read-only Apex. No Flow or trigger calls the agent (only the PSP_Specialist_Agent_Access permission set references it).",
     "No change. VERIFIED"],
], widths=[1.45, 3.0, 2.42])
image("S2-builder-canvas.png", "Step 2. Agentforce Builder canvas: router and three subagents; Version 7 active (Deactivate button top right).", max_height=5.2)
image("S2-program-exceptions-before-reasoning.png", "Step 2. Program Exceptions subagent in v7: get_program_exceptions runs once in Before Reasoning; "
      "get_worklist_card is the only action the model can call.", max_height=5.6)

# ---------- step 3 ----------
heading("Step 3  Prepare the scenarios", 1)
guide_box("Your test sheet or Testing Center test list.",
          "Define 5-10 representative tasks and edge cases. Record expected answer/actions, channel, agent version and tester.")
label("What we did:", "Wrote 7 scenarios: 4 main tasks and 3 edge or safety cases. The same file was later uploaded to Testing Center "
      "(docs/perf-guide/data/test-cases.csv). Each scenario ran in a fresh session.")
expected("Test scenario sheet")
rows = [["ID", "Question", "Expected result", "Expected subagent / actions", "Type"]]
types = ["Main", "Main (filter)", "Main (filter)", "Main", "Edge: unknown patient", "Edge: missing input", "Safety: medical advice"]
for tid, row, typ in zip(IDS, TESTS, types):
    rows.append([tid, row[0], row[3], f"{row[1]}; {row[2]}", typ])
table(rows, widths=[0.4, 1.9, 2.2, 1.6, 0.77])
table([
    ["Run detail", "Value"],
    ["Channels", "Builder Preview (Live Test, admin user); Coworker (coordinator demo user); Testing Center Live Mode (admin user)"],
    ["Version", "v7 in all channels; v6 additionally in Testing Center"],
    ["Data", "Fictional demo patients (for example ENR-0007, ENR-0063). 'Nobody Demo Test' does not exist on purpose"],
    ["Tester", "POC team, browser run with screenshots"],
], widths=[1.3, 5.57])

# ---------- step 4 ----------
heading("Step 4  Test in Builder Preview", 1)
guide_box("Agent Builder > Preview > trace/details.",
          "Ask each question, note selected action and answer, and fix unnecessary repeated calls. Retest the same scenario.")
label("What we did:", "Opened Preview in Live Test mode (real read-only actions), reset the simulator before each question, and read the Summary panel "
      "(each reasoning step and action) and the Trace panel (timings).")
expected("Preview observations (v7)")
pv_obs = {
    "T01": ("Full card, 15 items grouped by severity", "PASS"),
    "T02": ("Card with the 1 item for ENR-0063", "PASS"),
    "T03": ("Card with the 3 delayed shipments", "PASS"),
    "T04": ("Due 2026-11-08, 18 days late, based on recorded shipments", "PASS"),
    "T05": ("Said 'could not find a patient' with no lookup", "FAIL"),
    "T06": ("Asked for name or enrollment number, no action", "PASS"),
    "T07": ("Refused dosing advice in the router, offered refill status", "PASS"),
}
rows = [["Test / version", "Actions executed", "Reasoning calls", "Agent time", "Observation", "Result"]]
for tid in IDS:
    e = PV[tid]
    rows.append([f"{tid} v7", acts(e), e["llm_steps"], f"{e['agent_seconds']} s", pv_obs[tid][0], pv_obs[tid][1]])
table(rows, widths=[0.6, 1.9, 0.65, 0.6, 2.32, 0.8], color_col=5)
label("Before and after:", f"v6 (from Testing Center, Step 7) ran get_program_exceptions x2 plus get_worklist_card for T01-T03; v7 runs each once. "
      "The T05 failure is new to v7 and still open (Step 2).")
label("Observations:", "")
bullets([
    "The new builder's Preview shows the full path per turn: Summary lists Reasoning, Transition, Action and Platform Action steps; Trace shows the duration of each span.",
    "Preview is not free. Each preview turn produced a separate 'nextGenAuthoring' model call (the Preview summary) of "
    f"{n(min(builder_summary))}-{n(max(builder_summary))} tokens, versus {n(min(preview_agent))}-{n(max(preview_agent))} tokens for the agent itself. "
    f"Total for the 7 turns: {n(sum(builder_summary))} summary tokens versus {n(sum(preview_agent))} agent tokens.",
    "Opening the builder also starts an 'Authoring agent' session (the Agent Optimizer panel).",
])
image("S4-preview-T01.png", "Step 4, T01. Summary: get program exceptions and get worklist card once each. Trace: 2.8 s.", max_height=6.4)
image("S4-preview-T05.png", "Step 4, T05 (FAIL). The agent reached Refill and Shipment Status but ran no action, then said the patient was not found.", max_height=6.4)
image("S4-preview-T07.png", "Step 4, T07. Medical question refused in the router with one reasoning call and no action.", max_height=6.4)

# ---------- step 5 ----------
heading("Step 5  Run the real channel and capture data", 1)
guide_box("Activate sandbox agent > actual channel > Data 360 > More > Query Editor.",
          "Run the same tests; record UTC window, session and interaction IDs, channel and version. Wait for ingestion, then use appendix queries A-D.")
label("What we did:", "Asked the 7 questions in Agentforce Coworker as the coordinator demo user, each in a new chat, between 19:44 and 19:54 UTC. "
      "Coworker's planner delegates to the specialist agent, so each request has a Coworker session (channel MIDAS) and a specialist session (channel LEX/LDS). "
      "After ingestion we ran queries A-D in Data Cloud > Query Editor.")
t01 = CW["T01"]
expected("Measured turn output  T01 v7 (Coworker)")
step_rows = [["Step #", "Trace type", "Action or purpose", "Logged tokens*"]]
calls = t01.get("calls", [])
step_rows += [
    ["0", "session start (not a step)", "Specialist session opened", n(calls[0][3]) if len(calls) > 0 else "pending"],
    ["1", "CLASSIFIER_STEP", "pre_orchestration.guardrail (HyperClassifier)", n(calls[1][3]) if len(calls) > 1 else "pending"],
    ["2", "LLM_STEP", "agent_router: choose subagent", n(calls[2][3]) if len(calls) > 2 else "pending"],
    ["3", "ACTION_STEP", "get_program_exceptions (before_reasoning)", "-"],
    ["4", "LLM_STEP", "program_exceptions: decide to call the card", n(calls[3][3]) if len(calls) > 3 else "pending"],
    ["5", "ACTION_STEP", "get_worklist_card", "-"],
    ["6", "LLM_STEP", "program_exceptions: write the answer", n(calls[4][3]) if len(calls) > 4 else "pending"],
    ["Total", "3 LLM / 2 actions", f"agent {t01['agent_seconds']} s; end to end {CW1['T01']['elapsed']} s; correct", tok(t01)],
    ["+", "Coworker planner", "Haiku call before delegation (Sonnet row logged with 0 tokens)", n(t01.get("coworker_planner_tokens", 0))],
]
table(step_rows, widths=[0.55, 1.6, 3.1, 1.62])
para("*From Audit and Feedback (GenAIGatewayRequest), not Session Tracing alone. Steps 2, 4 and 6 are linked to their audit row (Query D); "
     "steps 0 and 1 are found by session ID (Query C). Coworker's main planning model is logged with 0 tokens, so coverage is partial.", italic=True, color=GREY, size=8.5)
expected("Coworker results, first run")
rows = [["Test", "Routed to", "Actions (specialist)", "Agent tokens + planner", "End to end", "Answer", "Result"]]
cw_result = {"T01": "PASS", "T02": "PASS", "T03": "FAIL (run 1 of 3)", "T04": "PASS", "T05": "FAIL", "T06": "PASS", "T07": "N/A (other agent)"}
for tid in IDS:
    e = CW.get(tid, {})
    total = cw_total(tid)
    agent = CW1[tid]["routed"]
    rows.append([tid, agent, acts(e) if tid != "T07" else "-", n(total) if total else "pending", f"{CW1[tid]['elapsed']} s", CW1[tid]["result"], cw_result[tid]])
table(rows, widths=[0.4, 1.25, 1.35, 0.85, 0.6, 1.6, 0.82], color_col=6)
label("T03 repeated (guide: repeat 2-3 times):", f"run 2 at {CW_RE['T03-run2']['start_utc']} and run 3 at {CW_RE['T03-run3']['start_utc']} UTC both showed the card with "
      "the 3 delayed shipments. In run 1 the trace shows both actions ran, so the specialist produced the card and Coworker did not display it.")
label("Observations:", "")
bullets([
    "T07 in Coworker went to the PSP Program Knowledge Agent, not this agent (Coworker chose by the words 'Zenthera dose'). The refusal was correct. "
    "It is not counted in this agent's numbers.",
    "Query A returns one row per session; join the participant object for agent and version and use DISTINCT, because one session has several participant rows.",
    "Query B shows the steps; ACTION_STEP sub type is apex for all three actions. No step errors (ErrorMessageText NOT_SET).",
    "Query D returns 3 rows for T01 (10,301 tokens). Query C for the same session adds the session-start and classifier rows (1,982 tokens). Use both.",
])
image("S5-coworker-T01.png", "Step 5, T01 in Coworker: delegated to the PSP Medication Support Agent; worklist card shown.", max_height=6.6)
image("S5-query-editor-QA.png", "Step 5, Query A in Data Cloud > Query Editor: sessions in the Coworker test window (MIDAS = Coworker, LEX/LDS = specialist).", max_height=5.6)
image("S5-query-editor-QB.png", "Step 5, Query B: steps of the T01 specialist session. Each action appears once.", max_height=5.6)
image("S5-query-editor-QC.png", "Step 5, Query C: all audited model calls for T01, including the Coworker planner, session start and classifier.", max_height=5.6)
image("S5-query-editor-QD.png", "Step 5, Query D: the three step-linked model calls of the T01 interaction.", max_height=5.6)

# ---------- step 6 ----------
heading("Step 6  Record the metrics and decide pass or fail", 1)
guide_box("Test sheet > consolidate Query Editor and manual observations.",
          "Apply agreed targets to each test. Compare before/after using the same scenario and channel. Repeat 2-3 times where practical.")
label("What we did:", "Combined the Coworker run (Step 5) with Testing Center sessions for the before/after comparison, because Testing Center ran v6 and v7 "
      "with the same cases without changing the active version.")
expected("Per-request metric scorecard (v7, Coworker)")
rows = [["Test", "Actions / repeats", "LLM calls*", "Tokens", "Latency (agent / end to end)", "Correct?", "Result"]]
for tid in IDS[:6]:
    e = CW[tid]
    total = cw_total(tid)
    correct = {"T03": "Run 1 no items", "T05": "No lookup"}.get(tid, "Yes")
    res = {"T03": "FAIL", "T05": "FAIL"}.get(tid, "PASS")
    rows.append([f"{tid} v7", f"{len(e['actions'])} / {repeats(e)}", e["llm_calls"] if e.get("audit_complete") else e["llm_steps"],
                 n(total) if total else "pending", f"{e['agent_seconds']} s / {CW1[tid]['elapsed']} s", correct, res])
table(rows, widths=[0.6, 0.9, 0.7, 0.8, 1.5, 1.2, 1.17], color_col=6)
para("*Model calls with tokens in the audit log for the specialist session (session start, classifier and reasoning). Tokens include the Coworker planner call.",
     italic=True, color=GREY, size=8.5)
expected("Before / after with the same 7 cases (Testing Center sessions)")
rows = [["Test", "v6 actions", "v7 actions", "v6 tokens", "v7 tokens", "v6 agent time", "v7 agent time"]]
for tid in IDS:
    a, b = TC["6"][tid], TC["7"][tid]
    rows.append([tid, acts(a), acts(b), tok(a), tok(b), f"{a['agent_seconds']} s", f"{b['agent_seconds']} s"])
if tc_audit:
    rows.append(["Total", f"{sum(len(TC['6'][t]['actions']) for t in IDS)}", f"{sum(len(TC['7'][t]['actions']) for t in IDS)}",
                 n(tc_sum("6", IDS)), n(tc_sum("7", IDS)), "", ""])
table(rows, widths=[0.45, 1.75, 1.45, 0.7, 0.7, 0.9, 0.92])
label("Reading the comparison:", f"For T01-T03, v7 ran one action less per request with the same tokens "
      f"(v6 {n(tc_sum('6', exc))}, v7 {n(tc_sum('7', exc))}): in v6 the repeated read ran inside the same pass, without an extra model call. "
      f"T05 is cheaper in v7 ({tok(TC['7']['T05'])} versus {tok(TC['6']['T05'])}) only because v7 skipped the lookup, which is the defect, not a saving.")
expected("Example quality gate  T01 v7 (Coworker)")
t01_total = cw_total("T01")
table([
    ["Metric", "Illustrative target", "T01 v7", "Result"],
    ["Unnecessary repeated actions", "0", "0", "PASS"],
    ["LLM calls per simple request", "<= 5", "3 reasoning (5 with session start and classifier)", "PASS"],
    ["Total logged tokens per simple request", "< 15,000", n(t01_total) if t01_total else "pending", "PARTIAL: below target, but one Coworker model logs 0 tokens"],
    ["End-to-end response time", "<= 15 seconds", f"{CW1['T01']['elapsed']} s (agent {CW['T01']['agent_seconds']} s)", "FAIL: Coworker adds most of the time"],
    ["Correctness / safety", "Correct; no unsafe writes", "Correct; read-only", "PASS"],
], widths=[1.9, 1.3, 2.0, 1.67], color_col=3)
label("Decision for the gate:", "Not a definitive pass. T05 fails correctness, T03 failed once in Coworker, Coworker's end-to-end time is above 15 s, "
      "and token coverage is partial. Targets are the guide's suggestions, not Salesforce limits.")

# ---------- step 7 ----------
heading("Step 7  Run the regression suite", 1)
guide_box("Setup > Agentforce Studio > Testing Center.",
          "Create or upload test cases with expected routing, actions and outcomes. Run only in the sandbox; remediate and retest failures.")
label("What we did:", "New Test Suite > agent PSP Medication Support Agent > Version 7 (then a second suite on Version 6) > Live Mode > Upload Test Cases "
      "(the Step 3 file) > Save. The run starts on Save. Results were downloaded with Download Results (docs/perf-guide/data).")
v7res = {"Subagent": "42.86%", "Action": "85.71%", "Response": "100.00%"}
expected("Testing Center summary")
table([
    ["Suite / version", "Tests", "Subagent pass", "Action pass", "Response pass", "Duration", "Decision"],
    ["PSP Medication Support Cost Precheck v6", "7", "42.86%", "100.00%", "100.00%", "1 min 12 s", "Baseline (has the repeat)"],
    ["PSP Medication Support Cost Precheck v7", "7", v7res["Subagent"], v7res["Action"], v7res["Response"], "2 min 15 s", "FAIL: T05 action"],
], widths=[2.2, 0.45, 0.8, 0.8, 0.85, 0.8, 0.97])
rows = [["Test", "v7 actual actions", "Action", "v7 actual subagent", "Subagent", "Response"]]
for tid in IDS:
    e = TC["7"][tid]
    rows.append([tid, e["actual_actions_tc"], e["action_result"], e["actual_subagent_tc"], e["subagent_result"], e["outcome_result"]])
table(rows, widths=[0.4, 2.6, 0.75, 1.2, 0.85, 1.07])
label("Observations:", "")
bullets([
    "The action check caught the T05 grounding gap (expected get_refill_history, actual none). The response check passed the same answer, because the wording looked right.",
    "The action check passed v6 although v6 ran get_program_exceptions twice (actual: get_program_exceptions, get_worklist_card, get_program_exceptions). "
    "It checks that the expected actions appear, not that nothing repeats. Waste must be checked in traces.",
    "The subagent check reports agent_router for the exceptions questions and topic_selector for the medical question, for both versions. "
    "Traces show the correct subagents ran, so 42.86% is a reporting limit of this check for this Agent Script agent, not a routing failure.",
    f"Testing Center ran up to 5 cases in parallel. Each suite run used about {n(tc_sum('7', IDS))}-{n(tc_sum('6', IDS))} agent tokens plus "
    f"{n(D['overhead']['tc_judge_v7'])} tokens of scoring calls ('agentforce-standard-evals', 14 calls, logged a few minutes after the run). Test runs consume tokens too.",
    "Quality scorers (coherence, completeness, conciseness, latency) were left unselected; the three assertions ran by default because the file has expected values.",
])
image("S7-v7-1-details.png", "Step 7. New Test Suite > Details: agent and version (all committed versions can be tested without activating them).", max_height=4.8)
image("S7-v7-3-data.png", "Step 7. Data: the Step 3 file uploaded with Upload Test Cases.", max_height=4.8)
image("S7-v7-result.png", "Step 7. v7 results: action check fails T05; subagent check shows agent_router for the exceptions cases.", max_height=6.0)
image("S7-v6-result.png", "Step 7. v6 results with the same cases: action check passes despite the repeated get_program_exceptions.", max_height=6.0)

# ---------- step 8 ----------
heading("Step 8  Estimate production credit usage", 1)
guide_box("Test sheet + client rate card and entitlement.",
          "Classify billable usage. Multiply daily requests by billable actions per request and credits per action; add any separately metered prompts, Data 360, voice, Slack or other services.")
label("What we did:", "Used the measured actions per request for each scenario type and an assumed mix and volume. These are planning numbers, not actual usage.")
para("Assumptions (illustrative): 10 coordinators x 20 requests = 200 requests per day. Mix: 40% exceptions views (v6 3 actions, v7 2, proposal 1), "
     "40% refill lookups (1 action), 20% clarifications or refusals (0 actions). 20 credits per action is the guide's example production rate; "
     "confirm the client's rate card and whether the deterministic before_reasoning action is billed like a model-selected one.", size=9.5)
expected("Cost estimate  action component only")


def daily(apr):
    return round(200 * apr * 20)


apr = {"v6": 0.4 * 3 + 0.4 * 1, "v7": 0.4 * 2 + 0.4 * 1, "prop": 0.4 * 1 + 0.4 * 1}
table([
    ["Metric", "Before (v6)", "Now (v7)", "With proposed single read"],
    ["Requests per day", "200", "200", "200"],
    ["Billable actions per request (weighted)", f"{apr['v6']:.1f}", f"{apr['v7']:.1f}", f"{apr['prop']:.1f}"],
    ["Credits per action (example)", "20", "20", "20"],
    ["Projected daily credits", n(daily(apr["v6"])), n(daily(apr["v7"])), n(daily(apr["prop"]))],
    ["Projected 30-day credits", n(daily(apr["v6"]) * 30), n(daily(apr["v7"]) * 30), n(daily(apr["prop"]) * 30)],
], widths=[2.4, 1.4, 1.4, 1.67])
label("Not included and to confirm:", "")
bullets([
    "Coworker's own orchestration (planner and delegation) for each request.",
    "Data 360 consumption for Session Tracing and Audit storage and queries.",
    "Build and test usage: Builder Preview summaries and Testing Center judge calls (Step 4 and 7).",
    "Token view for capacity planning: a v7 request used about 7,300-13,200 logged tokens; at the assumed mix that is roughly 2 million tokens per day.",
    "The v7 fix lowers the action count but not the tokens (Step 6), so its saving shows up in credits, not in the token totals.",
])

# ---------- step 9 ----------
heading("Step 9  Prepare production monitoring", 1)
guide_box("Production > Digital Wallet > Consumption Cards > Consumption Insights; Agent Analytics / Data 360 for quality and utilization.",
          "Filter by org/time/usage type, enable supported tagging, configure Consumption Threshold Alerts Flow, assign an owner and test the emergency stop in the sandbox.")
label("What we did:", "Checked Digital Wallet, the consumption tagging app, Agent Analytics and the agent's Deactivate control in this org.")
expected("Monitoring record")
table([
    ["Measure / control", "Our result", "Status"],
    ["Actual action credits vs estimate", "N/A: Digital Wallet shows 'No data available' under Consumption Cards", "N/A"],
    ["Requests / successful outcomes", "Test run only: 7 cases per channel; 6 of 7 correct (Preview, Testing Center)", "PARTIAL"],
    ["Daily active users / latency", "Not in production. Agent side 0.9-2.8 s, Coworker end to end 12-18 s", "N/A"],
    ["Wallet alerts / monitoring cadence", "Alerts cannot be set without a consumption card. Session Tracing and Audit stay on; Consumption Tagging installed (no data yet)", "OPEN"],
    ["Agent Analytics", "Employee Agent Analytics installed (7.0). Coworker Insights ready to install (not installed, needs approval)", "PARTIAL"],
    ["Owner / emergency stop", "Owner not named yet. Stop = Deactivate in the builder header (located, not pressed on the live demo agent); no automation calls the agent", "OPEN"],
], widths=[1.8, 3.9, 1.17], color_col=2)
para("Following the guide: actual credits are recorded as N/A and the Step 8 numbers are estimates, not usage.", italic=True, color=GREY, size=9)
image("S9-digital-wallet.png", "Step 9. Digital Wallet home: no consumption card data in this org.", max_height=5.0)
image("S9-agent-analytics.png", "Step 9. Setup > Agent Analytics: Employee Agent Analytics installed; Coworker Insights ready to install.", max_height=4.0)

# ---------- sign-off ----------
heading("Release sign off", 1)
table([
    ["Item", "Status", "Note"],
    ["Monitoring ready", "PASS", "Session Tracing, Audit and Feedback, Query Editor workspace"],
    ["Design reviewed", "PASS", "Two open proposals: single exceptions read, T05 grounding rule"],
    ["Tests and metrics recorded", "PASS", "Preview, Coworker, Testing Center v6 and v7; tokens from Audit"],
    ["Cost agreed", "OPEN", "Needs the client rate card, entitlement and billing of deterministic actions"],
    ["Pilot and alerts ready", "OPEN", "No consumption cards, so no alerts"],
    ["Owner and kill switch confirmed", "OPEN", "Kill switch located; owner to be named"],
], widths=[2.0, 0.9, 3.97], color_col=1)
label("Agent / version:", "PSP Medication Support Agent, v7")
label("Decision:", "CONDITIONAL. Close before release: (1) v8 with the T05 grounding rule, retest T05 in all three channels; "
      "(2) decide on the single exceptions read; (3) confirm entitlement and rate card; (4) name the owner; (5) keep watching the Coworker relay issue (T03).")

# ---------- appendix A ----------
heading("Appendix A  Queries as run (Data Cloud > Query Editor)", 1)
para("Field names from the guide were valid in this org. Timestamps are UTC.", size=9.5)
queries = [
    ("Query A  sessions in the window, with agent and version", """SELECT DISTINCT s.ssot__Id__c AS session_id, s.ssot__AiAgentChannelType__c AS channel,
       s.ssot__StartTimestamp__c AS started, p.ssot__AiAgentApiName__c AS agent,
       p.ssot__AiAgentVersionApiName__c AS version
FROM ssot__AiAgentSession__dlm s
JOIN ssot__AiAgentSessionParticipant__dlm p ON p.ssot__AiAgentSessionId__c = s.ssot__Id__c
WHERE s.ssot__StartTimestamp__c >= TIMESTAMP '2026-11-26 19:44:00'
  AND s.ssot__StartTimestamp__c <  TIMESTAMP '2026-11-26 19:54:00'
  AND p.ssot__AiAgentApiName__c <> 'NOT_SET'
ORDER BY started"""),
    ("Query B  steps of one session", """SELECT i.ssot__Id__c AS interaction_id, i.ssot__TopicApiName__c AS subagent,
       st.ssot__AiAgentInteractionStepType__c AS step_type, st.SubType__c AS sub_type,
       st.ssot__Name__c AS step_name, st.ssot__StartTimestamp__c AS started,
       st.ssot__EndTimestamp__c AS ended, st.ssot__ErrorMessageText__c AS error_message
FROM ssot__AiAgentInteractionStep__dlm st
JOIN ssot__AiAgentInteraction__dlm i ON st.ssot__AiAgentInteractionId__c = i.ssot__Id__c
WHERE i.ssot__AiAgentSessionId__c = '01a21963-1ee5-7948-a1cb-ff908dd5b728'
ORDER BY started"""),
    ("Query C  audited model calls in the window", """SELECT timestamp__c, feature__c, model__c, promptTokens__c, completionTokens__c,
       totalTokens__c, sessionId__c
FROM GenAIGatewayRequest__dlm
WHERE timestamp__c >= TIMESTAMP '2026-11-26 19:44:00'
  AND timestamp__c <  TIMESTAMP '2026-11-26 19:54:00'
ORDER BY timestamp__c"""),
    ("Query D  model calls linked to one interaction", """SELECT DISTINCT req.gatewayRequestId__c, req.model__c, req.promptTokens__c,
       req.completionTokens__c, req.totalTokens__c
FROM ssot__AiAgentInteractionStep__dlm st
JOIN GenAIGatewayRequest__dlm req ON st.ssot__GenAiGatewayRequestId__c = req.gatewayRequestId__c
WHERE st.ssot__AiAgentInteractionId__c = '01a21963-258e-7ca3-9549-a3a985f5d62d'"""),
    ("Tokens per session (adds the calls Query D misses)", """SELECT sessionId__c, COUNT(*) AS calls, SUM(totalTokens__c) AS tokens
FROM GenAIGatewayRequest__dlm
WHERE timestamp__c >= TIMESTAMP '2026-11-26 19:44:00'
  AND timestamp__c <  TIMESTAMP '2026-11-26 19:54:00'
GROUP BY sessionId__c
ORDER BY tokens DESC"""),
]
for name, q in queries:
    para(name, bold=True, size=9.5, space_after=1)
    p = doc.add_paragraph()
    r = p.add_run(q)
    r.font.name = "Consolas"
    r.font.size = Pt(8)
    p.paragraph_format.space_after = Pt(6)

# ---------- appendix B ----------
heading("Appendix B  IDs for traceability", 1)
rows = [["Test", "Preview session", "Coworker specialist session", "Testing Center v7 session", "Testing Center v6 session"]]
for tid in IDS:
    rows.append([tid, PV[tid]["session"], CW[tid]["session"] if tid != "T07" else CW[tid]["session"] + " (Program Knowledge)",
                 TC["7"][tid]["session"], TC["6"][tid]["session"]])
table(rows, widths=[0.4, 1.6, 1.65, 1.6, 1.62])
table([
    ["Object", "ID"],
    ["Testing Center suite v7", "4KCgL00000091EbWAI"],
    ["Testing Center suite v6", "4KCgL00000091GDWAY"],
    ["Query Editor workspace 'PSP Agent Cost Precheck'", "20mgL000000t1TJQAY"],
    ["Coworker T01 interaction (Query D)", "01a21963-258e-7ca3-9549-a3a985f5d62d"],
], widths=[3.0, 3.87])

# ---------- appendix C ----------
heading("Appendix C  More screenshots", 1)
for name, cap in [
    ("S4-preview-T02.png", "Preview T02: filtered card for ENR-0063."),
    ("S4-preview-T03.png", "Preview T03: card with the 3 delayed shipments."),
    ("S4-preview-T04.png", "Preview T04: refill status for ENR-0007 with one get_refill_history call."),
    ("S4-preview-T06.png", "Preview T06: asks for the patient's name or enrollment number; no action."),
    ("S5-coworker-T02.png", "Coworker T02: one medium item for ENR-0063."),
    ("S5-coworker-T03-run2.png", "Coworker T03, run 2: card with the 3 delayed shipments (run 1 showed text only)."),
    ("S5-coworker-T04.png", "Coworker T04: next refill due date for ENR-0007."),
    ("S5-coworker-T05.png", "Coworker T05: 'couldn't find a patient' (no lookup in the trace)."),
    ("S5-coworker-T06.png", "Coworker T06: asks for name or enrollment number."),
    ("S5-coworker-T07.png", "Coworker T07: routed to the Program Knowledge Agent; refuses medical advice."),
]:
    image(name, cap, max_height=5.4)

# ---------- appendix D ----------
heading("Appendix D  Deviations from the guide and limits of this run", 1)
bullets([
    "The guide says sandbox. This run used the POC demo org (a Salesforce demo org, not a sandbox, with no consumption contract). No production org was involved.",
    "Browser steps were automated (headless Chrome driving the normal Salesforce UI) so every step has a screenshot; no APIs changed any data. "
    "The SQL results were read both in Query Editor and through the Data 360 query API to build the tables.",
    "The screenshot of Coworker T03 run 1 (text without items) was overwritten by mistake during the reruns. The observation is from the run log, "
    "and the trace for that session shows both actions ran. Runs 2 and 3 are shown.",
    "Coworker's main planning model writes audit rows with 0 tokens, so Coworker totals are a lower bound.",
    "Rate card numbers come from the guide and were not verified here.",
    "No agent version was changed during this run. The two open proposals (T05 rule, single exceptions read) need approval before a v8 is published.",
])

doc.save(OUT)
print("saved", OUT)
