---
name: activator-trigger
description: "Use when creating a Fabric Activator (Reflex) for supply chain alert automation. Defines all alert rules, data sources, trigger conditions, and action targets for the Zava Shoes supply chain. Covers inventory alerts, quality failures, shipment delays, supplier SLA breaches, and production issues."
---

# Skill: Activator (Reflex) — Supply Chain Alert Automation

## Purpose
Creates a Fabric Activator (Reflex) that continuously monitors the KQL Database for supply chain anomalies and automatically triggers actions: Teams notifications, Operations Agent activation, and email escalations.

## Deployment Steps

> **Tooling split:**
> - **Activator item creation** → core Fabric MCP (`mcp_fabric_mcp_core_create-item` type=`reflex`).
> - **Activator triggers (rules)** → **Fabric RTI MCP** `activator_create_trigger`. This finally makes rule provisioning programmatic — what used to require manual UI clicks is now one tool call per rule, with the KQL query, schedule, condition, and action targets (Teams / email / webhook) defined inline.
> - **Companion KQL Queryset** for human review and editing → still deployed via the Items REST API + base64 (recipe below). Useful as a reference and as a "rules-as-code" git artifact.

### 1. Create Activator (core Fabric MCP)
```
mcp_fabric_mcp_core_create-item
  type:         reflex
  display-name: {prefix}_Activator
  workspace-id: {WS_ID}
  folder-object-id: {FOLDER_ID}
```
Capture `activator_id`.

### 2. Provision triggers (RTI MCP — `activator_create_trigger`)
For each of the 7 rules in [Alert Rules](#alert-rules) below, issue one call:
```
activator_create_trigger
  activator-id:  {activator_id}
  workspace-id:  {WS_ID}
  trigger-name:  "Rule_N_NAME"
  source:
    type:          KQL
    cluster-uri:   https://{prefix}_RealTime_EH.kusto.fabric.microsoft.com
    database:      {prefix}_RealTime_EH
    query:         <KQL trigger query from rule definition>
    schedule:      <Real-time | "every 5m" | ...>
  condition:
    rowcount-greater-than: 0
  dedupe:
    window:        <per-rule window>
    keys:          [<dimension columns>]
  actions:
    - type:        teams
      webhook:     {teams_webhook_url}
      message:     <templated message from rule>
    - type:        webhook
      url:         {operations_agent_activation_url}
      payload:     { context: "{rule_name}", entities: { ... } }
```
Map each Rule 1–7 below into one `activator_create_trigger` call.

### 3. (Optional but recommended) Companion KQL Queryset
Deploy a `KQLQueryset` containing all 7 trigger queries with metadata comments — for ops, audit, and rule-as-code review. Recipe below in §4.

### 4. Companion `{prefix}ActivatorQueries` KQL Queryset (Items REST API + base64)

**Item type**: `KQLQueryset`
**Display name**: `{prefix}ActivatorQueries`
**Connected to**: `{prefix}Eventhouse` (same KQL DB the Activator monitors)
**Tab**: single tab with all 7 rule queries, separated by `// ===== RULE N: NAME =====` markers.

#### Definition format (REST API)

Two parts in the `definition.parts` array, both `InlineBase64`:

1. **`RealTimeQueryset.json`** — wrapped in `{ "queryset": { ... } }`:
   ```json
   {
     "queryset": {
       "version": "1.0.0",
       "dataSources": [{
         "id": "<new guid>",
         "clusterUri": "<KQL query URI, e.g. https://trd-xxx.z8.kusto.fabric.microsoft.com>",
         "type": "Fabric",
         "databaseItemId": "<KQLDatabase item id (NOT Eventhouse id)>",
         "databaseItemName": "<KQL DB display name>",
         "workspaceId": "<workspace guid>"
       }],
       "tabs": [{
         "id": "<new guid>",
         "title": "Activator Trigger Queries",
         "content": "<KQL text — multi-line comments + queries>",
         "dataSourceId": "<same guid as dataSources[0].id>"
       }]
     }
   }
   ```

   ⚠️ **Common mistakes** (cause the queryset to render empty / show "Something went wrong" in the UI):
   - Missing the outer `"queryset": { ... }` wrapper.
   - Using `type: "AzureDataExplorer"` instead of `type: "Fabric"`.
   - Using `databaseId` / `databaseName` instead of `databaseItemId` / `databaseItemName`.
   - **Empty `clusterUri`** — the in-repo source-control samples can leave this empty, but a queryset created via REST and opened in the UI needs the cluster URI populated.
   - Missing `workspaceId` on the dataSource — required when creating via REST (samples on disk omit it because git-integration injects it).
   - Forgetting to set `tab.dataSourceId` to the same GUID as `dataSources[0].id`.
   - Using all-zeros `logicalId` in `.platform` — set a fresh GUID so the UI treats it as a real item.

2. **`.platform`** — standard, but **use a fresh GUID** for `logicalId` (not all-zeros):
   ```json
   {
     "$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
     "metadata": { "type": "KQLQueryset", "displayName": "{prefix}ActivatorQueries", "description": "..." },
     "config": { "version": "2.0", "logicalId": "<fresh new guid>" }
   }
   ```

#### Recipe (verified working — produced `scdgActivatorQueries`)

```powershell
# 1. Build the KQL tab content as a single multiline string ($kql)
#    with rule blocks separated by `// ===== RULE N: NAME =====` markers.

# 2. Build RealTimeQueryset.json:
$dsId   = [guid]::NewGuid().ToString()
$tabId  = [guid]::NewGuid().ToString()
$queryset = @{
  queryset = @{
    version     = "1.0.0"
    dataSources = @(@{
      id               = $dsId
      clusterUri       = "<KQL query URI>"            # MUST be populated
      type             = "Fabric"                       # NOT "AzureDataExplorer"
      databaseItemId   = "<KQLDatabase item id>"        # NOT Eventhouse id
      databaseItemName = "<KQL DB display name>"
      workspaceId      = "<workspace guid>"             # MUST be populated
    })
    tabs = @(@{
      id           = $tabId
      title        = "Activator Trigger Queries"
      content      = $kql
      dataSourceId = $dsId                              # MUST match dataSources[0].id
    })
  }
} | ConvertTo-Json -Depth 10

# 3. Build .platform with a fresh GUID logicalId.
$platform = @"
{
  "`$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
  "metadata": { "type": "KQLQueryset", "displayName": "{prefix}ActivatorQueries", "description": "Trigger queries for {prefix}Activator rules" },
  "config":   { "version": "2.0", "logicalId": "$([guid]::NewGuid().ToString())" }
}
"@

# 4. Base64-encode both parts and POST to /v1/workspaces/{ws}/kqlQuerysets
#    with body { displayName, description, definition.parts: [{path, payload, payloadType:"InlineBase64"}, ...] }
```

#### Debugging if the queryset still shows empty / "Something went wrong"

The Fabric REST API returns **HTTP 200** even when the inner `RealTimeQueryset.json` is malformed enough that the UI can't render it. Inspect the persisted blob to see exactly what was stored:

```powershell
$r = Invoke-RestMethod -Uri ".../kqlQuerysets/$id/getDefinition" -Headers $h -Method Post
foreach ($p in $r.definition.parts) {
  Write-Host "=== $($p.path) ==="
  [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p.payload))
}
```

If the blob looks correct but the UI still errors, **hard-refresh the browser** (Ctrl+Shift+R) — Fabric caches the queryset's first-load definition in the browser session and won't pick up `updateDefinition` changes until you reload the workspace tab.

#### Reference samples (good source of truth)

- `microsoft/fabric-cicd` → `sample/workspace/SampleKQLQueryset.KQLQueryset/` (minimal queryset)
- `microsoft/fabric-toolbox` → `monitoring/fabric-spark-monitoring/src/Spark Monitoring.KQLQueryset/` (multi-tab queryset)

These samples show the in-repo source-control format. When deploying via REST, you must additionally populate `clusterUri` and `workspaceId` (git integration injects these on deploy; REST does not).

#### Tab content conventions

Header (top of tab) explains how to use it for manual rule setup. Each rule block follows this pattern:

```kql
// =====================================================================================
// ===== RULE N: RULE_NAME =====
// Source    : <table or function>
// Frequency : <real-time / cadence>   |  De-dup: <window per dimension>
// Actions   : <Teams / Run notebook / Activate Operations Agent>
// NOTE      : <optional caveats — e.g. mutual exclusion with another rule>
// =====================================================================================
<KQL query>
```

Add a final **BONUS validation block** that queries any audit table the rules write into (e.g. `SOPAlerts`) so the demo presenter can confirm end-to-end firing.

### 4. Configure Alert Rules (see below)

> Each rule below is mapped to one `activator_create_trigger` call (see Step 2). The KQL trigger query in each rule is the `source.query` argument; `Frequency` is `source.schedule`; `De-duplicate` becomes `dedupe.window`+`dedupe.keys`; `Actions` becomes the `actions` array.

---

## Alert Rules

> **Naming convention.** Each rule's `trigger-name` follows `Trigger_<Domain>_<Verb>` (per [`docs/NAMING.md`](../../../docs/NAMING.md)). All rule queries reference the unified table/function names: streaming tables `SAPEvents`, `MachineTelemetry`, `ShipmentTracking`, `Disruptions`; functions `KPI_*` / `Risk_*` / `Action_*`.

### Rule 1: `Trigger_Quality_Failure`
**Description**: Fires when a SAP `QUALITY_INSPECTION` event lands with a FAIL result or defect rate above the material's quality threshold.
**Data Source**: `SAPEvents` filtered to quality inspections.
**Trigger Query**:
```kql
SAPEvents
| where timestamp > ago(15m)
| where event_type == 'QUALITY_INSPECTION'
| extend result      = tostring(payload.result)
       , defect_rate = todouble(payload.defect_rate_pct)
       , material_id = tostring(payload.material_id)
       , batch_id    = tostring(payload.batch_id)
       , factory_id  = tostring(payload.factory_id)
       , line_id     = tostring(payload.line_id)
| where result == 'FAIL' or defect_rate >= 2.0
| project timestamp, event_id, factory_id, line_id, material_id, batch_id,
          defect_rate, result
```
**Condition**: Row count > 0
**Frequency**: Real-time (streaming trigger)
**De-duplicate**: 2 hours per `factory_id`+`line_id`+`material_id`
**Actions**:
- Send Teams message (HIGH): "🚨 QUALITY FAILURE: {material_id} batch {batch_id} on {factory_id}/{line_id} — defect rate {defect_rate}%."
- Activate Operations Agent with context: `QUALITY_FAILURE`

> Mutually exclusive with **Rule 7** (`Trigger_Quality_SOPGuided`) — disable one when the other is on.

---

### Rule 2: `Trigger_Shipment_SLABreach`
**Description**: Fires when a tracked shipment's ETA slips past its SLA target, computed via `KPI_ShipmentDelayRisk`.
**Data Source**: `KPI_ShipmentDelayRisk()` (joins `ShipmentTracking` to `dim_carrier` SLA targets).
**Trigger Query**:
```kql
KPI_ShipmentDelayRisk()
| where delay_minutes >= 240 or sla_breach == true
| project shipment_id, carrier_id, supplier_id, delay_minutes,
          planned_eta, projected_eta, current_lat, current_lon
```
**Condition**: Row count > 0
**Frequency**: Every 15 minutes
**De-duplicate**: 24 hours per `shipment_id`
**Actions**:
- Send Teams message: "📦 SLA BREACH: shipment {shipment_id} via {carrier_id} is {delay_minutes} min late. Planned ETA {planned_eta}, projected {projected_eta}."
- Activate Operations Agent with context: `SHIPMENT_SLA_BREACH`

---

### Rule 3: `Trigger_Supplier_OTIFBreach`
**Description**: Fires when a supplier's rolling 24h OTD drops below 85% with at least 3 shipments.
**Data Source**: KQL function `KPI_SupplierOTD(1)` (24h window).
**Trigger Query**:
```kql
KPI_SupplierOTD(1)
| where otd_pct < 85.0
| where shipments >= 3
| project supplier_id, shipments, on_time, otd_pct
```
**Condition**: Row count > 0
**Frequency**: Every 2 hours
**De-duplicate**: 48 hours per `supplier_id`
**Actions**:
- Send Teams message (MEDIUM): "⚠️ SUPPLIER OTD: {supplier_id} dropped to {otd_pct}% over last 24h ({on_time}/{shipments} on-time). Review sourcing."
- Activate Operations Agent with context: `SUPPLIER_OTIF_BREACH`

---

### Rule 4: `Trigger_Network_DelaySpike`
**Description**: Fires when the rolling 15-minute composite OTD risk score for the network exceeds 70 (out of 100).
**Data Source**: KQL function `Risk_CompositeOTD()`.
**Trigger Query**:
```kql
Risk_CompositeOTD()
| where window_end > ago(15m)
| summarize avg_score = avg(composite_score), at_risk_shipments = countif(composite_score >= 70)
| where avg_score >= 70.0 or at_risk_shipments >= 10
```
**Condition**: Row count > 0
**Frequency**: Every 5 minutes
**De-duplicate**: 30 minutes
**Actions**:
- Send Teams message: "📈 NETWORK RISK SPIKE: composite OTD risk {avg_score}/100 with {at_risk_shipments} shipments at risk. Network-wide disruption likely."
- Activate Operations Agent with context: `DELIVERY_DELAY_SPIKE`

---

### Rule 5: `Trigger_SKU_AtRisk`
**Description**: Surfaces materials with one or more risk signals (quality fail, SLA breach, supplier OTD drop) in the last 7 days.
**Data Source**: `OTDRiskScores` joined to `dim_material`.
**Trigger Query**:
```kql
OTDRiskScores
| where scored_at > ago(7d)
| where composite_score >= 60
| summarize last_seen = max(scored_at), risk_events = count(),
            top_score = max(composite_score)
        by material_id, supplier_id
| join kind=leftouter dim_material on material_id
| project material_id, material_name, supplier_id, last_seen, risk_events, top_score
```
**Condition**: Row count > 0
**Frequency**: Every 6 hours
**De-duplicate**: 12 hours per `material_id`
**Actions**:
- Send Teams message: "🟡 AT-RISK SKU: {material_name} ({material_id}) from {supplier_id} — {risk_events} risk events in last 7d, peak score {top_score}. Consider safety stock."
- Activate Operations Agent with context: `AT_RISK_SKU`

---

### Rule 6: `Trigger_Shipment_GeofenceBreach`
**Description**: An in-transit shipment is currently outside its planned corridor (latest position vs route polyline).
**Data Source**: `ShipmentPositions` MV (latest GPS per shipment).
**Trigger Query**:
```kql
ShipmentPositions
| where last_seen > ago(30m)
| where geofence_status == 'OUTSIDE'
| project shipment_id, last_seen, current_lat, current_lon, carrier_id, material_id
```
**Condition**: Row count > 0
**Frequency**: Every 5 minutes
**De-duplicate**: 1 hour per `shipment_id`
**Actions**:
- Send Teams message (HIGH): "🛰️ GEOFENCE BREACH: shipment {shipment_id} ({material_id} via {carrier_id}) at ({current_lat}, {current_lon}) outside corridor as of {last_seen}."
- Activate Operations Agent with context: `GEOFENCE_BREACH`

---

### Rule 7: `Trigger_Quality_SOPGuided`  ⭐ Foundry IQ showcase
**Description**: Same trigger as Rule 1, but enriches the Teams notification with the relevant SOP section retrieved via Foundry IQ — turning the alert from "noise" into "actionable with context".
**Data Source**: `SAPEvents` filtered to quality inspections (same as Rule 1).
**Trigger Query**: same as Rule 1 (`Trigger_Quality_Failure`).
**Condition**: Row count > 0
**Frequency**: Real-time (streaming trigger)
**De-duplicate**: 2 hours per `supplier_id`+`sku` (mutually exclusive with Rule 1 — disable Rule 1 when Rule 7 is enabled, or scope each to a different `bizLocation` set for the demo)

**Action chain** (this is the demo "wow"):
1. **Run notebook `scdg_15_SOPRetrieval_Mock`** with parameters from the alert payload.
   - In **mock mode** (current deployment), the notebook IS the Foundry IQ stand-in: it runs in-Fabric, retrieves the SOP from `sop_documents` Delta table in `scdgLakehouse`, contextualizes the steps with alert entities, and ingests the structured result into `SOPAlerts` KQL table in `scdgEventhouse`.
   - The notebook's `handle_alert(alert)` accepts **either** the legacy SAP shape (`factory_id` / `line_id` / `material_id` / `batch_id` / `defect_rate`) **or** the EPCIS shape (`supplier_id` / `sku` / `lot_id` / `bizLocation` / `shipment_id` / `disposition` / `delay_minutes` / `otif_pct`). It auto-detects via `adapt_epcis_alert()` and produces the right summary line.
   - Activator parameter list to pass for an EPCIS-source rule: `alert_type='QUALITY_FAILURE', supplier_id, sku, lot_id, bizLocation, disposition, shipment_id, po_id, eventID`.
   - In **production mode**, replace this step with a webhook call to the real Foundry IQ pipeline:
     - Endpoint: `https://{foundry-iq-endpoint}/pipelines/sop-retrieval/invoke`
     - Method: POST, Body: serialized alert payload, Auth: managed identity, Timeout: 8s.
2. **Parse the JSON response** — extract `sop_id`, `sop_title`, `steps[]`, `doc_url`, `contextualized_summary`, `escalation_required` (the notebook's `handle_alert(alert)` function returns this dict).
3. **(Mock mode: already done by the notebook)** Insert one row into `SOPAlerts` (KQL) for audit + dashboarding.
4. **Send a Teams Adaptive Card** (template below) to channel `#quality-alerts`. In mock mode, the notebook prints the card JSON; for production, set `TEAMS_WEBHOOK_URL` in the notebook config cell.
5. **If `escalation_required = true`** → also activate Operations Agent with context `QUALITY_FAILURE_ESCALATED`.

**Adaptive Card template** (rendered with substituted Foundry IQ output):
```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.5",
  "body": [
    {
      "type": "Container",
      "style": "attention",
      "items": [
        { "type": "TextBlock", "size": "Large", "weight": "Bolder",
          "text": "🚨 Quality Failure — {factory_id} / {line_id}" },
        { "type": "TextBlock", "spacing": "None", "isSubtle": true,
          "text": "Severity {severity} • {timestamp} • Rule SOP_GUIDED_QUALITY_FAILURE" }
      ]
    },
    {
      "type": "Container",
      "items": [
        { "type": "TextBlock", "weight": "Bolder", "text": "What happened" },
        { "type": "FactSet", "facts": [
            { "title": "Material",    "value": "{material_id}" },
            { "title": "Batch",       "value": "{batch_id}" },
            { "title": "Defect rate", "value": "{defect_rate}%" },
            { "title": "Result",      "value": "{result}" }
        ]},
        { "type": "TextBlock", "wrap": true, "text": "{contextualized_summary}" }
      ]
    },
    {
      "type": "Container",
      "style": "emphasis",
      "items": [
        { "type": "TextBlock", "weight": "Bolder",
          "text": "📘 SOP Steps — {sop_id}: {sop_title} → {section}" },
        { "type": "TextBlock", "wrap": true,
          "text": "1. {steps[0].text}\n\n2. {steps[1].text}\n\n3. {steps[2].text}\n\n4. {steps[3].text}" }
      ]
    },
    {
      "type": "TextBlock", "isSubtle": true, "wrap": true,
      "text": "Confidence {confidence} • Retrieved by Foundry IQ from corpus `zavashoes-sop-index`"
    }
  ],
  "actions": [
    { "type": "Action.OpenUrl", "title": "📄 Open SOP in SharePoint", "url": "{doc_url}" },
    { "type": "Action.Submit",  "title": "✅ Acknowledge",
      "data": { "verb": "ack",        "alert_id": "{event_id}" } },
    { "type": "Action.Submit",  "title": "✔️ Mark Step 1 Complete",
      "data": { "verb": "step_done",  "alert_id": "{event_id}", "step": 1 } },
    { "type": "Action.Submit",  "title": "🆘 Escalate to Ops Agent",
      "data": { "verb": "escalate",   "alert_id": "{event_id}" } }
  ]
}
```

**New supporting KQL table** (added to `03-kql-realtime/kql/01_schema.kql`):
```kql
.create-merge table SOPAlerts (
    alert_id:           string,
    fired_at:           datetime,
    rule_name:          string,
    alert_type:         string,
    severity:           string,
    factory_id:         string,
    line_id:            string,
    material_id:        string,
    batch_id:           string,
    sop_id:             string,
    sop_title:          string,
    section:            string,
    doc_url:            string,
    steps:              dynamic,
    contextualized_summary: string,
    confidence:         real,
    escalation_required: bool,
    teams_message_id:   string,
    acknowledged_by:    string,
    acknowledged_at:    datetime,
    closed_at:          datetime
)
.alter table SOPAlerts policy retention softdelete = 365d recoverability = enabled
```

**Demo script for Rule 7** (run live in front of audience):
1. Trigger a synthetic quality failure (defect_rate = 3.1%, batch B-7821, Jakarta Line 3) via the SAP simulator notebook.
2. Within ~5 seconds Activator fires, calls Foundry IQ SOP Retrieval, posts the Adaptive Card to Teams.
3. **Show the audience the Teams card side-by-side with the raw alert text** — the contrast is the punchline.
4. Click "Open SOP in SharePoint" — lands on the exact section that was quoted, proving grounding.
5. Show the `SOPAlerts` KQL dashboard tile: every alert + its retrieved SOP, mean time-to-action.

---


## Activator Throttling Limits (Default Best Practice)

**Fabric Activator enforces strict limits on the number of actions per rule, recipient, and item.**

| Action Type   | Scope                        | Limit                  |
|--------------|------------------------------|------------------------|
| Email        | Messages/activator item/hour | 500                    |
| Email        | Messages/rule/recipient/hour | 30                     |
| Teams        | Messages/activator item/hour | 500                    |
| Teams        | Messages/rule/recipient/hour | 30                     |
| Teams        | Messages/recipient/hour      | 100                    |
| Teams        | Messages/Teams tenant/second | 50                     |
| Custom       | Power Automate/rule/hour     | 10,000                 |
| Fabric item  | Activations/user/minute      | 50                     |

**Default rule design:**
- Set each rule's KQL query to return at most one row per evaluation (e.g., `| order by ... | take 1`).
- Set the trigger interval (`executionIntervalInSeconds`) so that, even in worst-case conditions, no rule can exceed 30 Teams messages per recipient per hour.
- For high-frequency rules (5-minute interval), this means a max of 12 messages/rule/recipient/hour.
- For 15-minute rules, max 4 messages/rule/recipient/hour.
- Never assign more than 3-4 rules to the same recipient if all are high-frequency.
- Always use deduplication windows and keys to prevent duplicate alerts.
- If a rule could fire for many entities at once, aggregate and alert only on the top risk (e.g., `| top 1 by risk desc`).

**If these limits are exceeded, Activator will throttle or cancel actions.**

**Sample safe KQL pattern:**
```kql
// Only alert on the highest-risk entity in the window
... | order by risk desc | take 1
```

**Sample safe Teams recipient config:**
```json
"recipients": [
  {"type": "string", "value": "chschmidt@microsoft.com"},
  {"type": "string", "value": "devsha@microsoft.com"}
]
```

## Teams Action Configuration

For all Teams alerts, configure an **Adaptive Card** with:
- **Header**: Alert type and severity badge
- **Body**: Key metrics and affected entities
- **Buttons**:
  - "Investigate" → Opens Operations Agent with pre-loaded context
  - "Acknowledge" → Marks alert as acknowledged (via Activator API)
  - "View Dashboard" → Deep-link to the KQL Dashboard filtered to affected entity

## Demo Talking Points
- "The Activator is watching 6 different data streams simultaneously — InventorySnapshot (Lakehouse shortcut), the live SAPEvents stream, MachineTelemetry from the factory floor, ShipmentTracking from carriers."
- "When defect rate hits 2.1% at the Jakarta factory, within 30 seconds the Operations Agent is activated AND the quality team already has a Teams message."
- "The de-duplication logic means teams get one actionable alert — not 50 duplicate notifications."
