# Fabric notebook source
# METADATA ********************

# META {
# META   "kernel_info": { "name": "synapse_pyspark" },
# META   "language_info": { "name": "python" }
# META }

# CELL ********************
# Factory Floor Machine Event Simulator — Zava Shoes
# Simulates PLC / SCADA / MES signals from 3 manufacturing plants
# Set EVENT_HUB_CONN_STR to stream live, or DRY_RUN=True to preview

# CELL ********************
EVENT_HUB_CONN_STR = ""
EVENT_HUB_NAME     = "factory-floor-events"
EVENTS_PER_SECOND  = 3
TOTAL_EVENTS       = 300          # 0 = run forever
DRY_RUN            = (EVENT_HUB_CONN_STR == "")
OTD_SCENARIO       = True         # Inject critical fault scenario for demo

# CELL ********************
import json, random, time, uuid
from datetime import datetime, timedelta, timezone

# ── Machine Fleet ─────────────────────────────────────────────────────────────
MACHINES = {
    "PDX_MFG": [
        {"id": "M-PDX-CUT-01",    "type": "CUTTING",    "line": "LINE_A", "products": ["ZV-CAS-001","ZV-BSK-001"]},
        {"id": "M-PDX-CUT-02",    "type": "CUTTING",    "line": "LINE_B", "products": ["ZV-RUN-001","ZV-TRL-001"]},
        {"id": "M-PDX-STITCH-01", "type": "STITCHING",  "line": "LINE_A", "products": ["ZV-CAS-001"]},
        {"id": "M-PDX-STITCH-02", "type": "STITCHING",  "line": "LINE_B", "products": ["ZV-BSK-001"]},
        {"id": "M-PDX-MOLD-01",   "type": "MOLDING",    "line": "LINE_C", "products": ["ZV-RUN-001","ZV-TRL-001","ZV-HIKE-001"]},
        {"id": "M-PDX-ASSY-01",   "type": "ASSEMBLY",   "line": "LINE_D", "products": ["ZV-RUN-001","ZV-CAS-001"]},
    ],
    "HCM_MFG": [
        {"id": "M-HCM-KNIT-01",   "type": "STITCHING",  "line": "LINE_A", "products": ["ZV-RUN-001","ZV-TRL-001"]},
        {"id": "M-HCM-KNIT-02",   "type": "STITCHING",  "line": "LINE_B", "products": ["ZV-RUN-001"]},
        {"id": "M-HCM-STITCH-01", "type": "STITCHING",  "line": "LINE_C", "products": ["ZV-CAS-001"]},
        {"id": "M-HCM-STITCH-02", "type": "STITCHING",  "line": "LINE_D", "products": ["ZV-CAS-001","ZV-BSK-001"]},
        {"id": "M-HCM-STITCH-03", "type": "STITCHING",  "line": "LINE_E", "products": ["ZV-HIKE-001"]},
        {"id": "M-HCM-STITCH-04", "type": "STITCHING",  "line": "LINE_F", "products": ["ZV-TRL-001"]},
        {"id": "M-HCM-MOLD-01",   "type": "MOLDING",    "line": "LINE_G", "products": ["ZV-RUN-001","ZV-TRL-001"]},
        {"id": "M-HCM-MOLD-02",   "type": "MOLDING",    "line": "LINE_H", "products": ["ZV-CAS-001","ZV-HIKE-001"]},
        {"id": "M-HCM-ASSY-01",   "type": "ASSEMBLY",   "line": "LINE_A", "products": ["ZV-RUN-001","ZV-CAS-001"]},
        {"id": "M-HCM-ASSY-02",   "type": "ASSEMBLY",   "line": "LINE_B", "products": ["ZV-TRL-001","ZV-BSK-001"]},
    ],
    "JKT_MFG": [
        {"id": "M-JKT-CUT-01",    "type": "CUTTING",    "line": "LINE_A", "products": ["ZV-RUN-001","ZV-HIKE-001"]},
        {"id": "M-JKT-CUT-02",    "type": "CUTTING",    "line": "LINE_B", "products": ["ZV-BSK-001"]},
        {"id": "M-JKT-STITCH-01", "type": "STITCHING",  "line": "LINE_C", "products": ["ZV-RUN-001","ZV-HIKE-001"]},
        {"id": "M-JKT-STITCH-02", "type": "STITCHING",  "line": "LINE_D", "products": ["ZV-BSK-001"]},
        {"id": "M-JKT-ASSY-01",   "type": "ASSEMBLY",   "line": "LINE_E", "products": ["ZV-RUN-001","ZV-HIKE-001"]},
        {"id": "M-JKT-ASSY-02",   "type": "ASSEMBLY",   "line": "LINE_F", "products": ["ZV-BSK-001"]},
    ],
}
ALL_MACHINES = [(plant, m) for plant, machines in MACHINES.items() for m in machines]

# ── Fault library ─────────────────────────────────────────────────────────────
FAULTS = {
    "STITCHING": [
        ("F_NEEDLE_BREAK",    "WARNING",  0.5),
        ("F_THREAD_TENSION",  "WARNING",  0.75),
        ("F_FEED_JAM",        "CRITICAL", 2.0),
        ("F_MOTOR_OVERLOAD",  "CRITICAL", 3.5),
        ("F_HEAD_MISALIGN",   "SHUTDOWN", 6.0),
    ],
    "CUTTING": [
        ("F_BLADE_DULL",      "WARNING",  0.25),
        ("F_MATERIAL_SLIP",   "WARNING",  0.5),
        ("F_PNEUMATIC_FAIL",  "CRITICAL", 2.0),
        ("F_VISION_SENSOR",   "CRITICAL", 1.5),
    ],
    "MOLDING": [
        ("F_PRESS_PRESSURE",  "WARNING",  1.0),
        ("F_TEMP_DEVIATION",  "CRITICAL", 4.0),
        ("F_MOLD_WEAR",       "WARNING",  0.5),
        ("F_HYDRAULIC_LEAK",  "SHUTDOWN", 8.0),
    ],
    "ASSEMBLY": [
        ("F_ADHESIVE_FLOW",   "WARNING",  0.5),
        ("F_CONVEYOR_JAM",    "CRITICAL", 1.5),
        ("F_ROBOT_ARM_FAULT", "SHUTDOWN", 4.0),
    ],
}

def now_iso():
    return datetime.now(timezone.utc).isoformat()

def rand_oee(base=82, std=8):
    return round(max(0.0, min(100.0, random.gauss(base, std))), 1)

# CELL ********************
# ── Event generators ─────────────────────────────────────────────────────────

def gen_oee_update(plant, machine):
    oee = rand_oee()
    avail = rand_oee(90, 5)
    perf  = rand_oee(88, 6)
    qual  = rand_oee(97, 2)
    units_planned = random.randint(80, 200)
    units_actual  = int(units_planned * (oee / 100.0))
    return {
        "event_id": str(uuid.uuid4()),
        "event_type": "OEE_UPDATE",
        "machine_id": machine["id"],
        "machine_type": machine["type"],
        "plant": plant,
        "plant_code": plant,
        "production_line": machine["line"],
        "product_code": random.choice(machine["products"]),
        "oee_overall": oee,
        "oee_availability": avail,
        "oee_performance": perf,
        "oee_quality": qual,
        "oee_pct": oee,
        "availability_pct": avail,
        "performance_pct": perf,
        "quality_pct": qual,
        "output_count": units_actual,
        "reject_count": max(0, units_planned - units_actual),
        "temperature_c": round(random.uniform(31.0, 46.0), 1),
        "vibration_hz": round(random.uniform(8.0, 18.0), 2),
        "status": "RUNNING",
        "units_planned_hr": units_planned,
        "units_actual_hr": units_actual,
        "fault_code": None,
        "fault_severity": "INFO",
        "estimated_downtime_hrs": 0.0,
        "impacted_orders": [],
        "timestamp": now_iso(),
    }

def gen_fault(plant, machine, forced_fault=None):
    fault_list = FAULTS.get(machine["type"], FAULTS["ASSEMBLY"])
    if forced_fault:
        fault_code, severity, downtime = forced_fault
    else:
        fault_code, severity, downtime = random.choice(fault_list)
    oee_during_fault = 0.0 if severity == "SHUTDOWN" else rand_oee(35, 10)
    return {
        "event_id": str(uuid.uuid4()),
        "event_type": "FAULT_DETECTED",
        "machine_id": machine["id"],
        "machine_type": machine["type"],
        "plant": plant,
        "plant_code": plant,
        "production_line": machine["line"],
        "product_code": random.choice(machine["products"]),
        "oee_overall": oee_during_fault,
        "oee_availability": 0.0 if severity == "SHUTDOWN" else rand_oee(20, 10),
        "oee_performance": 0.0 if severity == "SHUTDOWN" else rand_oee(40, 15),
        "oee_quality": rand_oee(60, 15),
        "oee_pct": oee_during_fault,
        "availability_pct": 0.0 if severity == "SHUTDOWN" else rand_oee(20, 10),
        "performance_pct": 0.0 if severity == "SHUTDOWN" else rand_oee(40, 15),
        "quality_pct": rand_oee(60, 15),
        "output_count": 0 if severity == "SHUTDOWN" else random.randint(10, 40),
        "reject_count": random.randint(0, 8),
        "temperature_c": round(random.uniform(46.0, 68.0), 1),
        "vibration_hz": round(random.uniform(18.0, 42.0), 2),
        "status": "SHUTDOWN" if severity == "SHUTDOWN" else "FAULT",
        "units_planned_hr": random.randint(80, 200),
        "units_actual_hr": 0 if severity == "SHUTDOWN" else random.randint(10, 40),
        "fault_code": fault_code,
        "fault_severity": severity,
        "estimated_downtime_hrs": round(downtime * random.uniform(0.8, 1.4), 1),
        "impacted_orders": [f"PROD-{random.randint(1000000, 9999999)}" for _ in range(random.randint(1, 4))],
        "timestamp": now_iso(),
    }

def gen_fault_cleared(plant, machine):
    return {
        "event_id": str(uuid.uuid4()),
        "event_type": "FAULT_CLEARED",
        "machine_id": machine["id"],
        "machine_type": machine["type"],
        "plant": plant,
        "plant_code": plant,
        "production_line": machine["line"],
        "product_code": random.choice(machine["products"]),
        "oee_overall": rand_oee(70, 8),
        "oee_availability": rand_oee(80, 8),
        "oee_performance": rand_oee(82, 8),
        "oee_quality": rand_oee(95, 3),
        "oee_pct": rand_oee(70, 8),  # recovering
        "availability_pct": rand_oee(80, 8),
        "performance_pct": rand_oee(82, 8),
        "quality_pct": rand_oee(95, 3),
        "output_count": random.randint(50, 160),
        "reject_count": random.randint(0, 4),
        "temperature_c": round(random.uniform(32.0, 48.0), 1),
        "vibration_hz": round(random.uniform(8.0, 20.0), 2),
        "status": "RUNNING",
        "units_planned_hr": random.randint(80, 200),
        "units_actual_hr": random.randint(50, 160),
        "fault_code": None,
        "fault_severity": "INFO",
        "estimated_downtime_hrs": 0.0,
        "impacted_orders": [],
        "timestamp": now_iso(),
    }

def gen_quality_alert(plant, machine):
    quality = round(random.uniform(78, 88), 1)
    return {
        "event_id": str(uuid.uuid4()),
        "event_type": "QUALITY_ALERT",
        "machine_id": machine["id"],
        "machine_type": machine["type"],
        "plant": plant,
        "plant_code": plant,
        "production_line": machine["line"],
        "product_code": random.choice(machine["products"]),
        "oee_overall": rand_oee(75, 10),
        "oee_availability": rand_oee(92, 4),
        "oee_performance": rand_oee(88, 5),
        "oee_quality": quality,
        "oee_pct": rand_oee(75, 10),
        "availability_pct": rand_oee(92, 4),
        "performance_pct": rand_oee(88, 5),
        "quality_pct": quality,  # below 90% = quality issue
        "output_count": random.randint(50, 160),
        "reject_count": random.randint(5, 18),
        "temperature_c": round(random.uniform(34.0, 52.0), 1),
        "vibration_hz": round(random.uniform(10.0, 24.0), 2),
        "status": "QUALITY_HOLD",
        "units_planned_hr": random.randint(80, 200),
        "units_actual_hr": random.randint(50, 160),
        "fault_code": random.choice(["Q_STITCH_SKIP", "Q_ALIGNMENT", "Q_ADHESION", "Q_COLOR_DEV"]),
        "fault_severity": "WARNING",
        "estimated_downtime_hrs": 0.0,
        "impacted_orders": [f"PROD-{random.randint(1000000, 9999999)}" for _ in range(random.randint(1, 3))],
        "timestamp": now_iso(),
    }

# CELL ********************
# ── Demo Scenario: OTD Impact Sequence ────────────────────────────────────────
# This sequence tells the story: machine fault → OTD risk → agent re-routes

def inject_otd_scenario():
    """
    Critical demo sequence:
    1. Motor overload fault on M-HCM-STITCH-04 (HCM_MFG) — SHUTDOWN
    2. Cascading quality alert on adjacent line
    3. Second fault on backup machine
    This forces the Operations Agent to consider shifting to Portland.
    """
    hcm_stitch_04 = {"id": "M-HCM-STITCH-04", "type": "STITCHING", "line": "LINE_F", "products": ["ZV-TRL-001"]}
    hcm_knit_01   = {"id": "M-HCM-KNIT-01",   "type": "STITCHING", "line": "LINE_A", "products": ["ZV-RUN-001","ZV-TRL-001"]}
    
    events = []
    # Event 1: Primary shutdown
    fault_evt = gen_fault("HCM_MFG", hcm_stitch_04, forced_fault=("F_MOTOR_OVERLOAD", "SHUTDOWN", 6.5))
    fault_evt["estimated_downtime_hrs"] = 6.5
    fault_evt["impacted_orders"] = ["PROD-4521038", "PROD-4521039", "PROD-4521040"]
    events.append(fault_evt)
    # Event 2: Adjacent quality degradation
    qa_evt = gen_quality_alert("HCM_MFG", hcm_knit_01)
    qa_evt["quality_pct"] = 79.2
    qa_evt["fault_code"] = "Q_TENSION_DRIFT"
    events.append(qa_evt)
    # Event 3: Secondary fault on backup  
    hcm_stitch_03 = {"id": "M-HCM-STITCH-03", "type": "STITCHING", "line": "LINE_E", "products": ["ZV-HIKE-001"]}
    fault2 = gen_fault("HCM_MFG", hcm_stitch_03, forced_fault=("F_FEED_JAM", "CRITICAL", 2.0))
    events.append(fault2)
    return events

# CELL ********************
# ── Preview ───────────────────────────────────────────────────────────────────
if DRY_RUN:
    print("=== DRY RUN — sample events ===\n")
    
    plant, machine = random.choice(ALL_MACHINES)
    print("-- OEE Update --")
    print(json.dumps(gen_oee_update(plant, machine), indent=2))
    print()
    
    print("-- Fault Detection --")
    print(json.dumps(gen_fault(plant, machine), indent=2))
    print()
    
    if OTD_SCENARIO:
        print("=== OTD CRITICAL SCENARIO ===")
        for e in inject_otd_scenario():
            print(json.dumps(e, indent=2))
            print()

# CELL ********************
# ── Live Streaming ────────────────────────────────────────────────────────────
if not DRY_RUN:
    try:
        from azure.eventhub import EventHubProducerClient, EventData
    except ImportError:
        raise RuntimeError("pip install azure-eventhub")

    producer = EventHubProducerClient.from_connection_string(
        conn_str=EVENT_HUB_CONN_STR, eventhub_name=EVENT_HUB_NAME)

    delay = 1.0 / EVENTS_PER_SECOND
    sent = 0

    # If OTD_SCENARIO, inject the critical sequence first
    if OTD_SCENARIO:
        print("Injecting OTD Critical Scenario events...")
        scenario_events = inject_otd_scenario()
        with producer:
            for evt in scenario_events:
                evt["payload"] = {k: v for k, v in evt.items() if k != "payload"}
                batch = producer.create_batch()
                batch.add(EventData(json.dumps(evt)))
                producer.send_batch(batch)
                print(f"  [SCENARIO] {evt['event_type']} | {evt['machine_id']} | {evt['fault_severity']}")
                time.sleep(1.0)
        print(f"Scenario injected. Starting normal stream...\n")
        producer = EventHubProducerClient.from_connection_string(
            conn_str=EVENT_HUB_CONN_STR, eventhub_name=EVENT_HUB_NAME)

    print(f"Streaming factory floor events at ~{EVENTS_PER_SECOND} eps...")
    try:
        with producer:
            while TOTAL_EVENTS == 0 or sent < TOTAL_EVENTS:
                plant, machine = random.choice(ALL_MACHINES)
                # Weight: 70% OEE updates, 15% faults, 10% quality alerts, 5% cleared
                r = random.random()
                if r < 0.70:
                    evt = gen_oee_update(plant, machine)
                elif r < 0.85:
                    evt = gen_fault(plant, machine)
                elif r < 0.95:
                    evt = gen_quality_alert(plant, machine)
                else:
                    evt = gen_fault_cleared(plant, machine)

                evt["payload"] = {k: v for k, v in evt.items() if k != "payload"}
                batch = producer.create_batch()
                batch.add(EventData(json.dumps(evt)))
                producer.send_batch(batch)
                sent += 1
                if sent % 50 == 0:
                    print(f"  Sent {sent} | last: {evt['event_type']} @ {evt['machine_id']}")
                time.sleep(delay)
    except KeyboardInterrupt:
        print(f"\nStopped. Total: {sent}")

    print(f"Done. Total events: {sent}")
