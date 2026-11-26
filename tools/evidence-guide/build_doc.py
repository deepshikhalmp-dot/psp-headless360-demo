"""Builds docs/PSP-Evidence-Guide.docx from the screenshots in docs/evidence-guide/screens and docs/evidence."""
import os
import struct

from docx import Document
from docx.enum.section import WD_ORIENT
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SCREENS = os.path.join(ROOT, "docs", "evidence-guide", "screens")
OLD = os.path.join(ROOT, "docs", "evidence")
OUT = os.path.join(ROOT, "docs", "PSP-Evidence-Guide.docx")
BLUE = RGBColor(0x0B, 0x5C, 0xAB)
GREY = RGBColor(0x55, 0x5B, 0x66)


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


doc = Document()
section = doc.sections[0]
section.page_width, section.page_height = Inches(8.27), Inches(11.69)
for side in ("left_margin", "right_margin"):
    setattr(section, side, Inches(0.7))
section.top_margin = section.bottom_margin = Inches(0.7)
style = doc.styles["Normal"]
style.font.name = "Calibri"
style.font.size = Pt(10.5)
CONTENT_WIDTH = 6.87


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


def bullets(items):
    for item in items:
        p = doc.add_paragraph(item, style="List Bullet")
        p.paragraph_format.space_after = Pt(1)


def table(rows, header=True, widths=None):
    t = doc.add_table(rows=len(rows), cols=len(rows[0]))
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, row in enumerate(rows):
        for j, value in enumerate(row):
            cell = t.cell(i, j)
            cell.text = ""
            run = cell.paragraphs[0].add_run(str(value))
            run.font.size = Pt(9)
            if header and i == 0:
                run.bold = True
                shade(cell, "DCE9F7")
            if widths:
                cell.width = Inches(widths[j])
    doc.add_paragraph().paragraph_format.space_after = Pt(2)
    return t


def image(path, caption, max_height=8.3):
    if not os.path.exists(path):
        para("[Screenshot missing: " + os.path.basename(path) + "]", italic=True, color=GREY)
        return
    w, h = png_size(path)
    width = CONTENT_WIDTH
    if h / w * width > max_height:
        width = max_height * w / h
    doc.add_picture(path, width=Inches(width))
    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER
    cap = para(caption, italic=True, color=GREY, size=9, space_after=10)
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER


def s(name):
    return os.path.join(SCREENS, name + ".png")


def evidence(eid, title, channel, kind, result, what, steps, expected, actual, shots, verified=None):
    heading(eid + "  " + title, 2)
    table([["Channel", channel, "Type", kind, "Result", result]], header=False,
          widths=[0.8, 1.8, 0.55, 1.2, 0.65, 1.85])
    para(what)
    para("Steps", bold=True, space_after=1)
    bullets(steps)
    para("Expected", bold=True, space_after=1)
    para(expected)
    para("Actual", bold=True, space_after=1)
    para(actual)
    if verified:
        para("Verified in Salesforce", bold=True, space_after=1)
        para(verified)
    for name, caption in shots:
        image(name if os.path.isabs(name) else s(name), caption)


# ---------------------------------------------------------------- cover
t = doc.add_paragraph()
t.alignment = WD_ALIGN_PARAGRAPH.LEFT
r = t.add_run("Zenthera Patient Support Program on Salesforce Headless 360")
r.bold, r.font.size, r.font.color.rgb = True, Pt(24), BLUE
para("Evidence Guide: live execution with screenshots", bold=True, size=15)
para("Executed 25–26 November 2026 in org ProductPillarSDO (Org ID 00DgL00000hTCjNUAW)", color=GREY)
para("All data is fictional. Zenthera is a made-up drug and every patient is a demo record. "
     "No real patient data (PHI) is used. Do not share screenshots in public channels.", italic=True, color=GREY)

heading("1. About this guide", 1)
para("This guide proves, screen by screen, that the Zenthera Patient Support Program (PSP) demo works in the "
     "Salesforce org. Each evidence item lists what is being shown, the exact steps or prompt, the expected result, "
     "the actual result and the screenshot taken at that moment.")
table([
    ["Item", "Value"],
    ["How the screens were run", "Salesforce screens were opened and operated in a real Google Chrome browser (automated, headless) "
     "signed in as the presenter user deepshikhaheadless@kpmg.com. Each click, form entry and prompt was executed in the "
     "live UI and the screenshot was taken right after."],
    ["Read and write", "Read steps only open pages or ask questions. Write steps created real (fictional) records; each one "
     "was approved in advance with its exact values and then verified with a Salesforce query."],
    ["Slackbot", "Slackbot screenshots come from the live tests run by the user on 17–22 November 2026 (Slack sign-in "
     "cannot be automated). See section 6."],
    ["Related documents", "Technical Design Document (docs/TDD.md), User Guide (docs/User-Guide.md), Demo Script "
     "(docs/Demo-Script-Program-Exceptions-Desk.md)"],
], widths=[1.6, 5.2])

heading("2. The use case at a glance", 1)
para("A pharma company runs a patient support program (PSP) for its specialty drug Zenthera (fictional). A Patient "
     "Services Coordinator enrolls patients, tracks refills, answers program questions, logs service cases and possible "
     "side effects, hands patients over to the care team and works a daily list of program exceptions. The demo shows "
     "Salesforce Headless 360: the data and business rules live once in Salesforce, and the coordinator reaches them "
     "through three front doors (channels).")
image(s("U01-use-case-flow"), "Use case flow: one coordinator, three channels, one shared logic and data layer", max_height=6)

para("Channels used in this demo", bold=True, space_after=2)
table([
    ["Channel", "Where the coordinator works", "How it reaches Salesforce", "Evidence"],
    ["Salesforce app", "Patient Support Program Lightning app (manual work on record pages)",
     "Standard record pages and list views", "Section 4 (A1–A4, W1–W3)"],
    ["Slack: Slackbot", "Direct message to Slackbot in the Slack workspace connected to the org",
     "6 Salesforce-hosted PSP MCP servers; every tool runs as the linked Salesforce user", "Section 6 (S1–S5)"],
    ["Agentforce Coworker", "\"Ask\" in Salesforce (also the Agentforce side panel)",
     "Coworker hands the request to 3 specialist agents (Medication Support, Program Knowledge, Care Resolution); "
     "exceptions are shown as an HXL worklist card", "Section 5 (C1–C7, W4)"],
], widths=[1.15, 2.0, 2.45, 1.2])
para("Not used in this demo: MuleSoft Agent Fabric (optional next step, not available in this org) and AI clients "
     "outside Salesforce and Slack.", italic=True, color=GREY, size=9.5)

para("What each channel can do", bold=True, space_after=2)
table([
    ["#", "Use case", "Salesforce app", "Slackbot", "Coworker"],
    ["1", "Enroll a new patient", "Yes", "Yes", "No"],
    ["2", "Check refill status (from recorded shipments)", "Yes", "Yes", "Yes"],
    ["3", "See a patient's full profile (Patient 360)", "Yes", "Yes", "No"],
    ["4", "Log a service case or a possible side effect", "Yes", "Yes", "Yes, only after approval and confirmation"],
    ["5", "Answer a program question (FAQ in Data 360)", "No", "Yes", "Yes"],
    ["6", "Care team handoff summary (read-only)", "No", "Yes", "Yes"],
    ["7", "Work today's program exceptions", "No", "Yes", "Yes, as an HXL card plus a resolution plan"],
], widths=[0.3, 2.6, 1.0, 0.8, 2.1])

para("Guardrails", bold=True, space_after=1)
bullets([
    "One logic, many channels: Slackbot tools and agent actions call the same Apex classes and Flows.",
    "Rules compute the facts (refill dates, exceptions, duplicates); AI only words the answer.",
    "Read-only by default. Records are written only by enroll, service case and approved case, each after the user approves.",
    "Everything runs as the signed-in user, so Salesforce sharing and field security apply.",
    "No clinical advice, no automatic adverse event reports, no patient data in public Slack channels. "
    "Refill status reflects recorded shipments only, not whether the patient takes the medicine.",
])

heading("3. Summary of results", 1)
table([
    ["ID", "What was shown", "Channel", "Type", "Result"],
    ["A1–A4", "Patient list, patient 360 page, enrollment, dispenses, cases", "Salesforce app", "Read", "PASS"],
    ["W1", "Enroll a new patient (Kavya Evidence Demo, ENR-0063)", "Salesforce app", "Write", "PASS"],
    ["W2", "Record a delivered shipment (DSP-0078)", "Salesforce app", "Write", "PASS"],
    ["W3", "Log a service case (00001131)", "Salesforce app", "Write", "PASS (no PSP category: field not on layout)"],
    ["C1", "Today's exceptions as an HXL worklist card", "Coworker", "Read", "PASS"],
    ["C2", "Combined request to three specialist agents", "Coworker", "Read", "FINDING (two agents ran, plan not returned)"],
    ["C6", "Resolution plan from the Care Resolution Agent", "Coworker", "Read", "PASS"],
    ["C3", "AI care team handoff (prompt template)", "Coworker", "Read", "PASS"],
    ["C4", "Duplicate guard: existing case 00001124", "Coworker", "Read", "PASS"],
    ["C5", "Program question answered from the FAQ (Data 360)", "Coworker", "Read", "PASS"],
    ["W4", "Approved case creation with confirmation (00001130)", "Coworker", "Write", "PASS"],
    ["C7", "New case shown as uncategorised for triage", "Coworker", "Read", "PASS"],
    ["S1–S5", "Slackbot over MCP: enroll, exceptions, profile + FAQ, handoff", "Slackbot", "Read/Write", "PASS (17–22 Nov)"],
    ["B1–B10", "Behind the scenes: MCP servers, agents, flows, Apex, prompts, data library, HXL type, access", "Setup", "Read", "Shown"],
], widths=[0.6, 3.1, 1.1, 0.75, 1.3])

para("Records created by this run (fictional, approved, verified):", bold=True)
table([
    ["Record", "Values", "Created by step"],
    ["Patient Kavya Evidence Demo", "Person Account, birthdate 1990-05-12, mobile +91 90000 22334", "W1"],
    ["Enrollment ENR-0063", "Zenthera 100 mg, Enrolled, Commercial, Dr. Demo Rao, consent given 2026-11-25", "W1"],
    ["Dispense DSP-0078", "ENR-0063, 2026-11-25, 30 days, Demo Specialty Pharmacy, Delivered", "W2"],
    ["Case 00001131", "Kavya Evidence Demo, 'Question about the program welcome kit', New, Phone, no PSP category", "W3"],
    ["Case 00001130", "Ayush Mehta (ENR-0059), [Shipment Delay] Follow up delayed shipment DSP-0073 with the pharmacy, "
     "category Shipment Delay, shipment DSP-0073, Origin Chat", "W4"],
], widths=[1.7, 4.2, 0.9])
para("Record counts: cases 79 → 81, enrollments 12 → 13, dispenses 6 → 7. Only the approved records were created.")

# ---------------------------------------------------------------- Salesforce app
heading("4. Salesforce app (manual work)", 1)
evidence("A1", "PSP patient list", "Salesforce app", "Read", "PASS",
         "The PSP Patients list view shows only patients (Person Accounts), not sales accounts.",
         ["App Launcher → Patient Support Program → Accounts → list view PSP Patients"],
         "Only Person Account patients with Birthdate and Mobile columns.",
         "List shows the demo patients only.",
         [("R01-psp-patients-list", "A1 PSP Patients list view")])
evidence("A2", "Patient 360 page: Riya Demo Sharma", "Salesforce app", "Read", "PASS",
         "The patient page shows the patient details, her program enrollment and her open cases.",
         ["Open patient Riya Demo Sharma", "Open the Related tab"],
         "Birthdate and mobile in the header; Program Enrollments (ENR-0007) and Cases related lists.",
         "ENR-0007 (Zenthera 50 mg, Enrolled) and 5 cases including 00001071 [SAFETY REVIEW] and 00001124 [Refill Support].",
         [("R02-patient-riya", "A2 Patient details"), ("R10-patient-riya-related", "A2 Related tab: enrollment and cases")])
evidence("A3", "Enrollment and shipments: ENR-0007", "Salesforce app", "Read", "PASS",
         "The enrollment holds therapy, consent and insurance; its dispenses are the recorded shipments used for refill dates.",
         ["Open enrollment ENR-0007; open the Related tab", "Open dispenses DSP-0015 and DSP-0016"],
         "DSP-0015 Delivered on 2026-10-09 for 30 days; DSP-0016 Delayed.",
         "As expected. Refill due date = 2026-10-09 + 30 = 2026-11-08 (recorded shipments only).",
         [("R03-enrollment-enr0007", "A3 Enrollment ENR-0007"), ("R11-enrollment-enr0007-related", "A3 Dispenses related list"),
          ("R05-dispense-dsp0015", "A3 DSP-0015 Delivered"), ("R04-dispense-dsp0016", "A3 DSP-0016 Delayed")])
evidence("A4", "Cases: approved refill case and safety case", "Salesforce app", "Read", "PASS",
         "Case 00001124 was created earlier by the PSP Care Resolution Agent after approval; 00001071 is a possible adverse event for human safety review.",
         ["Open case 00001124", "Open case 00001071"],
         "00001124 has PSP Issue Category Refill Support and the approval note; 00001071 is marked [SAFETY REVIEW], priority High.",
         "As expected.",
         [("R06-case-00001124", "A4 Case 00001124"), ("R07-case-00001071-safety", "A4 Case 00001071 (safety review)")])

evidence("W1", "Enroll a new patient", "Salesforce app", "Write (approved)", "PASS",
         "A coordinator registers a new fictional patient and enrolls her in the program.",
         ["Accounts → New → record type Person Account",
          "First Name Kavya, Last Name Evidence Demo, Birthdate 5/12/1990, Mobile +91 90000 22334 → Save",
          "Program Enrollments → New: Patient Kavya Evidence Demo, Program Zenthera Patient Support Program, Therapy Zenthera 100 mg, "
          "Status Enrolled, Enrollment Date 11/25/2026, Prescriber Dr. Demo Rao, Insurance Commercial, Consent Given, Consent Date 11/25/2026 → Save"],
         "Patient and enrollment saved with an ENR number.",
         "Patient Kavya Evidence Demo and enrollment ENR-0063 created.",
         [("W1-01-new-patient-form", "W1 New patient form"), ("W1-02-patient-created", "W1 Patient saved"),
          ("W1-03-new-enrollment-form", "W1 New enrollment form"), ("W1-04-enrollment-created", "W1 Enrollment ENR-0063 saved")],
         verified="Account 001gL00002DBS8XQAX (birthdate 1990-05-12, mobile +91 90000 22334); Program_Enrollment__c ENR-0063 with all approved values; exactly one of each.")
evidence("W2", "Record a delivered shipment", "Salesforce app", "Write (approved)", "PASS",
         "A shipment is recorded on the new enrollment; it drives the next refill date.",
         ["New Dispense with Program Enrollment ENR-0063",
          "Dispense Date 11/25/2026, Days Supply 30, Pharmacy Demo Specialty Pharmacy, Status Delivered → Save"],
         "Dispense saved and shown on the enrollment.",
         "DSP-0078 created; next refill due 2026-12-25 (on track).",
         [("W2-01-new-dispense-form", "W2 New dispense form"), ("W2-02-dispense-created", "W2 DSP-0078"),
          ("W2-03-enrollment-enr0063-related", "W2 ENR-0063 with its dispense"), ("W1-05-patient-kavya-related", "W1/W2 Patient Kavya, related lists")],
         verified="Dispense__c DSP-0078 on ENR-0063: 2026-11-25, 30, Demo Specialty Pharmacy, Delivered.")
evidence("W3", "Log a service case", "Salesforce app", "Write (approved)", "PASS",
         "A coordinator logs a general question as a case on the patient.",
         ["New Case on Kavya Evidence Demo: Subject 'Question about the program welcome kit', Case Origin Phone, Status New → Save"],
         "Case saved on the patient. The PSP Issue Category field is not on the Case page layout, so the category stays empty.",
         "Case 00001131 created. In C7 the exceptions engine lists it as 'no PSP issue category, a person needs to review it' (TRIAGE_CASE).",
         [("W3-01-new-case-form", "W3 New case form"), ("W3-03-case-00001131-record", "W3 Case 00001131"),
          ("W3-04-patient-kavya-related", "W3 Patient Kavya with the new case")],
         verified="Case 00001131: Kavya Evidence Demo, New, Phone, Medium, PSP_Issue_Category__c empty.")

# ---------------------------------------------------------------- Coworker
heading("5. Agentforce Coworker and the specialist agents", 1)
para("Coworker ('Ask' in the Salesforce header) delegates to three custom Agentforce agents: PSP Medication Support, "
     "PSP Program Knowledge and PSP Care Resolution. 'Heard back from Agent' marks a delegation. Every step started in a new chat.")
evidence("C1", "Today's exceptions as an HXL worklist card", "Coworker", "Read", "PASS",
         "The Medication Support Agent returns the program exceptions as a Headless Experience Layer (HXL) card, rendered inside Coworker.",
         ["Prompt: Show today's Zenthera patient support exceptions."],
         "Delegation to the Medication Support Agent; card with badges and coloured groups; footer 'Read-only: nothing was created or changed'.",
         "Card shown: 13 items for 6 patients out of 13 enrollments (2 high, 7 medium, 2 low, 2 data gaps). High: Riya refill overdue 17 days "
         "(recorded shipments only) and safety review 00001071. Ayush DSP-0073 → CREATE CASE (before W4).",
         [("C1-worklist-card", "C1 HXL worklist card in Coworker")])
evidence("C2", "Combined request (three specialists)", "Coworker", "Read", "FINDING",
         "One request that needs all three agents.",
         ["Prompt: Show today's PSP exceptions, consult the delayed shipment policy and prepare a resolution plan."],
         "Exceptions and policy agents in parallel, then the Care Resolution Agent with a plan.",
         "Run twice. Both times Coworker delegated to two agents ('Heard back from Agent' twice) and showed the worklist card, but did not "
         "continue to the Care Resolution Agent. In the 19 November test (before the card) all three ran. Workaround: ask for the plan "
         "separately (C6). The second run already shows Ayush DSP-0073 as covered by 00001130 (after W4).",
         [("C2-three-agents-plan", "C2 Combined request: two delegations and the card")])
evidence("C6", "Resolution plan", "Coworker", "Read", "PASS",
         "The Care Resolution Agent turns the exceptions into a step-by-step plan without changing anything.",
         ["Prompt: Using the PSP Care Resolution Agent, prepare a resolution plan for today's PSP program exceptions."],
         "Plan by severity, ending 'Nothing has been created or changed'.",
         "Plan by severity: handoff for Riya, skip delayed shipments already covered (00001125, 00001130, 00001070/72/73), "
         "human review for uncategorised cases, complete missing consent dates. Ends 'Nothing has been created or changed yet'. "
         "Observation: Coworker's closing sentence offers to create cases for uncategorised items; nothing was created.",
         [("C6-resolution-plan", "C6 Resolution plan")])
evidence("C3", "AI care team handoff", "Coworker", "Read", "PASS",
         "Apex reads the facts; the prompt template writes the handoff only from those facts.",
         ["Prompt: Prepare a care team handoff for enrollment ENR-0007. Do not create, update or share anything."],
         "Fixed sections; safety case only 'in human safety review'; nothing created or shared.",
         "Handoff for Riya Demo Sharma: patient and therapy, refill 17 days overdue (recorded shipments only), open cases with "
         "00001071 only as 'in human safety review', next steps; nothing created, updated or shared.",
         [("C3-ai-handoff-enr0007", "C3 AI care team handoff")])
evidence("C4", "Duplicate guard", "Coworker", "Read (write request refused)", "PASS",
         "A create request is checked against open cases first.",
         ["Prompt: Using the PSP Care Resolution Agent, create a Refill Support case for ENR-0007: the coordinator wants to confirm the next refill date with the pharmacy."],
         "Existing Refill Support case found; no new case.",
         "'An open Refill Support case already exists for ENR-0007 … 00001124, so no duplicate was created.'",
         [("C4-duplicate-guard-00001124", "C4 Duplicate guard")])
evidence("C5", "Program question (FAQ, Data 360)", "Coworker", "Read", "PASS",
         "The Program Knowledge Agent answers only from the Zenthera Program FAQ.",
         ["Prompt: What is the Zenthera PSP process for delayed shipments?"],
         "Coordinator checks with the pharmacy and a service case tracks the delay; Source: Zenthera Program FAQ, Q15.",
         "'Here's the process for delayed shipments, straight from the Zenthera Program FAQ (Q15)': the coordinator is contacted, "
         "checks the shipment status with the pharmacy and logs a service case to track the delay.",
         [("C5-program-question", "C5 Program question")])
evidence("W4", "Approved case creation with Salesforce confirmation", "Coworker", "Write (approved)", "PASS",
         "Three locks: the agent shows the exact proposal, the user approves, Salesforce asks for confirmation; the Apex checks duplicates again before writing.",
         ["Prompt: Using the PSP Care Resolution Agent, prepare a Shipment Delay case for ENR-0059, shipment DSP-0073, with the subject "
          "\"Follow up delayed shipment DSP-0073 with the pharmacy\". Show me the proposal first.",
          "Reply: yes", "Salesforce confirmation card → Confirm"],
         "Proposal with duplicate check; confirmation card with the exact values; case number returned.",
         "Proposal: Ayush Mehta (ENR-0059), DSP-0073 Delayed, no existing Shipment Delay case. After 'yes' the confirmation card showed "
         "category, description, dispense, enrollment, subject and User Confirmed = true. After Confirm: 'Case 00001130 is now open'.",
         [("W4-01-proposal", "W4 Proposal"), ("W4-03-confirmation-card", "W4 Salesforce confirmation card"),
          ("W4-04-case-created", "W4 Case created"), ("W4-05-case-00001130-record", "W4 Case 00001130 in Salesforce"),
          ("W4-06-patient-ayush-related", "W4 Patient Ayush Mehta with the new case")],
         verified="Case 00001130: [Shipment Delay] subject, PSP Issue Category Shipment Delay, PSP Dispense DSP-0073, Origin Chat, "
                  "created by deepshikhaheadless@kpmg.com; exactly one case. Note: the agent used the subject as the description.")
evidence("C7", "New case flagged for triage", "Coworker", "Read", "PASS",
         "The case logged manually in W3 has no PSP category; the engine never guesses one.",
         ["Prompt: Show today's Zenthera PSP program exceptions for enrollment ENR-0063."],
         "One MEDIUM item: uncategorised open case → TRIAGE CASE.",
         "'Open case 00001131 has no PSP issue category; a person needs to review it. → TRIAGE CASE'.",
         [("C7-exceptions-enr0063", "C7 Exceptions for ENR-0063")])

# ---------------------------------------------------------------- Slack
heading("6. Slackbot over MCP (live tests 17–22 November 2026)", 1)
para("Slackbot reaches the same Salesforce logic through six custom MCP servers. A step counts only when Slackbot shows "
     "'Used <tool> from <server>'. These screenshots were taken by the user during the live tests.")
slack = [
    ("S1", "Enroll a patient (consent check, enrollment, duplicate refused)", "PSP Patient Services MCP → Enroll Patient flow",
     [("slackbot-01-no-consent-and-first-attempt.png", "S1 No consent: refused; first attempt"),
      ("slackbot-03-retry-enrolled-ENR-0007.png", "S1 Enrolled ENR-0007"),
      ("slackbot-02-enrolled-and-duplicate.png", "S1 Same patient again: no second enrollment")]),
    ("S2", "Today's program exceptions", "PSP Exceptions MCP → PSP_Get_Program_Exceptions",
     [("t1-10-slackbot-program-exceptions-pass.png", "S2 Exceptions in Slackbot")]),
    ("S3", "Patient profile + program answer in one request", "PSP Named Query MCP + PSP Program FAQ MCP",
     [("slackbot-faq-copay-p360-chain-pass.png", "S3 Patient 360 and FAQ answer (Source Q9)")]),
    ("S4", "AI care team handoff", "PSP Handoff MCP → PSP_Care_Team_Handoff_Summary",
     [("p6-slackbot-ai-handoff-enr0018-pass.png", "S4 Handoff for ENR-0018 (00001075 kept as uncategorised)")]),
]
for sid, title, tool, shots in slack:
    heading(sid + "  " + title, 2)
    para("Server / tool: " + tool)
    for name, caption in shots:
        image(os.path.join(OLD, name), caption)
para("Not covered by screenshots: Slackbot case creation (cases 00001072 and 00001073 were verified in Salesforce on "
     "17 November) and the duplicate-check tool in Slack (not yet tested).", italic=True, color=GREY)

# ---------------------------------------------------------------- Setup
heading("7. Behind the scenes (Setup)", 1)
setup = [
    ("B1", "Six PSP MCP servers, all active", "T08-setup-mcp-servers"),
    ("B2", "Agentforce agents: the three PSP specialists are active", "T07-setup-agents"),
    ("B3", "Agentforce Coworker turned on (licences in use)", "T13-setup-coworker"),
    ("B4", "Flow: PSP Care Team Handoff Summary (Apex facts → prompt template, AI fallback)", "T02-flow-handoff"),
    ("B5", "Flow: PSP Enroll Patient", "T03-flow-enroll"),
    ("B6", "Flow: PSP Create Service Case", "T03b-flow-create-service-case"),
    ("B7", "Flow: PSP Answer Program Question", "T03c-flow-answer-program-question"),
    ("B8", "Prompt templates: PSP Program FAQ Answer and PSP Care Team Handoff Summary", "T06-setup-prompt-builder"),
    ("B9", "Agentforce Data Library PSP FAQ (Ready)", "T10-setup-data-library"),
    ("B10", "Lightning Type PSP Exceptions Worklist (HXL card)", "T12-setup-lightning-types"),
    ("B11", "Apex: PSP_ProgramExceptionsService", "T04-apex-exceptions-service"),
    ("B12", "Apex: PSP_CaseDuplicateCheck", "T04b-apex-duplicate-check"),
    ("B13", "Apex: PSP_CreateApprovedCase (write only with approval)", "T04c-apex-create-approved-case"),
    ("B14", "Apex: PSP_CareTeamHandoff (handoff facts)", "T04d-apex-care-team-handoff"),
    ("B15", "Permission set PSP Patient Services", "T05-permset-psp-patient-services"),
    ("B16", "Permission set PSP Specialist Agent Access (Agent Access only)", "T05b-permset-agent-access"),
]
for bid, title, name in setup:
    heading(bid + "  " + title, 2)
    image(s(name), bid + " " + title)

# ---------------------------------------------------------------- findings
heading("8. Findings and notes", 1)
table([
    ["#", "Finding", "Impact / next step"],
    ["1", "C2: with the worklist card, Coworker stops after the exceptions and policy agents and does not call the Care Resolution Agent.",
     "Ask for the plan as a separate prompt (C6). Update the demo script Act 2."],
    ["2", "W3: PSP Issue Category is not on the Case page layout, so manually logged cases have no category.",
     "Such cases appear as UNCATEGORISED (triage). Adding the field to the layout needs a separate approval."],
    ["3", "W4: the agent used the subject as the case description.", "Acceptable for the demo; the description can be edited."],
    ["4", "C6: Coworker's closing text offers to create cases for uncategorised items.", "Nothing was created. Never approve a case that "
     "does not come from the Care Resolution Agent's three-step flow."],
    ["5", "Demo data changed by this run: Ayush DSP-0073 is now covered by 00001130; Kavya (ENR-0063) has case 00001131.",
     "Run the pre-flight before the next demo; the live-creation candidate in the demo script must change."],
], widths=[0.3, 3.6, 2.9])

doc.save(OUT)
print("SAVED", OUT)
