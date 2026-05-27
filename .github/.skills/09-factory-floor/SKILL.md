---
name: factory-floor
description: "Use when adding factory floor IoT/OT machine data to the supply chain demo. Creates a second Eventstream for machine sensor events (OEE, faults, downtime) from manufacturing plants. Data feeds real-time KQL tables that power OTD risk scoring. Covers: machine event schema, OEE calculation, fault classification, and the simulator notebook. Source: MQTT/AMQP from PLCs and SCADA systems, simulated via Azure Event Hubs."
---

# Skill: Factory Floor — OT/IoT Machine Intelligence

## Purpose as Head of Supply Chain

Factory floor data is the **earliest warning signal** for On-Time Delivery failures. A critical machine fault in Ho Chi Minh City at 06:00 can be translated to a customer OTD risk score by 06:05 — giving the Operations Agent 72 hours to re-route before a miss becomes unavoidable. Without this data, supply chain managers react *after* the miss. With it, they act *before*.

**Key Insight**: 68% of OTD failures trace back to unplanned machine downtime that was visible in OEE data 4+ hours before it hit production schedules.

## Architecture

```
[PLC / SCADA / MES]
        │ MQTT / AMQP
        ▼
[Azure IoT Hub]
        │
        ▼
[ZavaShoes_FactoryFloor_ES: Eventstream]
        │ Custom App source (simulation)
        ├── → KQL Database: MachineTelemetry (streaming table)
        ├── → KQL Database: MachineStatus (MV - current state per machine)
        └── → Lakehouse: bronze.machine_telemetry_raw (Delta archive)

[KQL: Risk_MachineOTD] computes OTD risk per order every 5 min
[Activator] monitors MachineStatus.fault_severity = 'CRITICAL' or OEE < 65%
```

## Data Model: MachineTelemetry

| Column | Type | Description |
|---|---|---|
| `event_id` | string | UUID |
| `event_type` | string | MACHINE_START, MACHINE_STOP, OEE_UPDATE, FAULT_DETECTED, FAULT_CLEARED, MAINTENANCE_START, MAINTENANCE_END, QUALITY_ALERT, PRODUCTION_RATE_CHANGE |
| `machine_id` | string | e.g. M-HCM-STITCH-04 |
| `machine_type` | string | STITCHING, CUTTING, MOLDING, ASSEMBLY, INSPECTION, PACKAGING |
| `plant_code` | string | PDX_MFG, HCM_MFG, JKT_MFG |
| `production_line` | string | LINE_A through LINE_F |
| `product_code` | string | Active SKU being produced |
| `oee_pct` | real | Overall Equipment Effectiveness 0-100 |
| `availability_pct` | real | Availability component of OEE |
| `performance_pct` | real | Performance component |
| `quality_pct` | real | Quality component |
| `units_planned_hr` | int | Target units per hour |
| `units_actual_hr` | int | Actual units per hour |
| `fault_code` | string | e.g. F_NEEDLE_BREAK, F_MOTOR_OVERLOAD |
| `fault_severity` | string | INFO, WARNING, CRITICAL, SHUTDOWN |
| `estimated_downtime_hrs` | real | ML-estimated downtime duration |
| `impacted_orders` | dynamic | List of production order IDs affected |
| `timestamp` | datetime | UTC event time |

## Machine Fleet (Zava Shoes Manufacturing)

### Portland (PDX_MFG) — 6 production lines
| Machine | ID | Type | Critical for |
|---|---|---|---|
| Cutting Table A | M-PDX-CUT-01 | CUTTING | All products |
| Cutting Table B | M-PDX-CUT-02 | CUTTING | All products |
| Stitching Unit 1 | M-PDX-STITCH-01 | STITCHING | Leather products |
| Stitching Unit 2 | M-PDX-STITCH-02 | STITCHING | Leather products |
| Sole Press 1 | M-PDX-MOLD-01 | MOLDING | Rubber soles |
| Assembly Line 1 | M-PDX-ASSY-01 | ASSEMBLY | Final assembly |

### Ho Chi Minh City (HCM_MFG) — 8 production lines (highest volume)
| Machine | ID | Type | Critical for |
|---|---|---|---|
| Knit Machine A | M-HCM-KNIT-01 | STITCHING | Mesh uppers |
| Knit Machine B | M-HCM-KNIT-02 | STITCHING | Mesh uppers |
| Stitching Unit 1-4 | M-HCM-STITCH-01..04 | STITCHING | All products |
| Sole Press 1-2 | M-HCM-MOLD-01..02 | MOLDING | Rubber soles |
| Assembly Line 1-2 | M-HCM-ASSY-01..02 | ASSEMBLY | Final assembly |

### Jakarta (JKT_MFG) — 6 production lines
| Machine | ID | Type | Critical for |
|---|---|---|---|
| Cutting Table A-B | M-JKT-CUT-01..02 | CUTTING | Synthetics |
| Stitching Unit 1-2 | M-JKT-STITCH-01..02 | STITCHING | Synthetic uppers |
| Assembly Line 1-2 | M-JKT-ASSY-01..02 | ASSEMBLY | Final assembly |

## OEE Thresholds (Zava Shoes Standard)

| Status | OEE % | Action |
|---|---|---|
| World Class | ≥ 85% | No action |
| Acceptable | 65–84% | Monitor |
| Warning | 50–64% | Investigate — triggers Activator WARNING |
| Critical | < 50% | Escalate — triggers Activator CRITICAL + OTD risk re-score |
| Shutdown | 0% | Emergency — triggers OTD agent workflow |

## OTD Impact Calculation

```kql
// For each active production order, compute OTD risk contribution from machine health
let MachineHealth = MachineStatus
    | summarize avg_oee = avg(oee_pct), shutdowns = countif(fault_severity == 'SHUTDOWN')
      by plant_code, tostring(machine_type)
    | extend capacity_factor = avg_oee / 100.0;
// JOIN to production orders...
// OTD risk score = f(remaining_production_hours, capacity_factor, buffer_days)
```

## Deployment Steps

> **Tooling:** Use the **Fabric RTI MCP server** (`microsoft/fabric-rti-mcp`) eventstream builder tools — same pattern as the SAP eventstream (skill 02).

### 1. Build the Factory-Floor Eventstream (RTI MCP)

```
eventstream_start_definition
eventstream_add_custom_endpoint_source
  source-name: "FactoryFloor_Sim"
  → capture Event Hub connection string for 09_FactoryFloorSimulator.py

eventstream_add_eventhouse_destination
  destination-name: "ToKQL_MachineTelemetry"
  workspace-id:    {WS_ID}
  eventhouse-id:   {prefix}_RealTime_EH
  database-name:   {prefix}_RealTime_EH
  table-name:      MachineTelemetry
  data-format:     JSON

eventstream_add_custom_endpoint_destination
  destination-name: "ToLakehouseBronze"
  → wire to bronze.machine_telemetry_raw on {prefix}_SupplyChain_LH

eventstream_validate_definition
eventstream_create_from_definition
  workspace-id:  {WS_ID}
  display-name:  {prefix}_FactoryFloor_ES
  folder-id:     {FOLDER_ID}
```

In production this Eventstream would source from Azure IoT Hub (MQTT/AMQP from PLCs and SCADA). For the demo, the simulator notebook posts directly to the Custom App endpoint.

### 2. Run Schema Script
Run the MachineTelemetry schema via the RTI MCP `kusto_command` tool — see skill `03-kql-realtime` step "Apply schema" — pointed at `09-factory-floor/kql/09_schema.kql`.

### 3. Upload and Run Simulator
Upload `09_FactoryFloorSimulator.py` as notebook `{prefix}_09_FactoryFloorSim`. Configure `EVENT_HUB_CONN_STR` from step 1 before running.

## Activator Rules (for OTD protection)

### Rule: MACHINE_SHUTDOWN
```
Source: MachineStatus (KQL)
Condition: fault_severity == 'SHUTDOWN' AND plant_code IN ('HCM_MFG','JKT_MFG','PDX_MFG')
Action: Trigger ZavaShoes_OpsAgent.OTD_ReRoute_Workflow
Urgency: CRITICAL
Message: "Machine {{machine_id}} at {{plant_code}} has shut down. Estimated downtime: {{estimated_downtime_hrs}}h. Calculating OTD impact..."
```

### Rule: OEE_BELOW_THRESHOLD
```
Source: MachineStatus (KQL)
Condition: oee_pct < 65 for 15+ consecutive minutes
Action: Notify supply chain operations team via Teams
Urgency: WARNING
```

## KQL Schema (09_schema.kql additions)

```kql
.create-merge table MachineTelemetry (
    event_id: string, event_type: string, machine_id: string,
    machine_type: string, plant_code: string, production_line: string,
    product_code: string, oee_pct: real, availability_pct: real,
    performance_pct: real, quality_pct: real, units_planned_hr: int,
    units_actual_hr: int, fault_code: string, fault_severity: string,
    estimated_downtime_hrs: real, impacted_orders: dynamic, timestamp: datetime
)

.create materialized-view with (backfill=true) MachineStatus on table MachineTelemetry
{
    MachineTelemetry
    | summarize arg_max(timestamp, *) by machine_id
}
```

## Connector to Operations Agent

When a SHUTDOWN event fires, the Operations Agent should:
1. `query_supply_chain_data("What production orders are running at {plant_code} right now?")`
2. `traverse_supply_graph(entity=machine_id, direction=downstream)` → affected orders → affected customers
3. `calculate_otd_impact(orders=affected_orders, delay_hours=estimated_downtime_hrs)`
4. Propose re-routing options (see `06-operations-agent/SKILL.md`)
