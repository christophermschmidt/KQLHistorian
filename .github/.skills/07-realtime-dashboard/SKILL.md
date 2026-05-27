---
name: realtime-dashboard
description: "Use when creating a Fabric KQL Dashboard or Power BI real-time report for supply chain monitoring. Defines all dashboard tiles, KQL queries, refresh settings, and visual layout for the Zava Shoes supply chain control tower. Connects to the KQL Database for streaming data."
---

# Skill: Real-Time Dashboard — Supply Chain Control Tower

## Purpose
Creates a Fabric KQL Dashboard that serves as the supply chain control tower. All tiles query the KQL Database in real-time, with 30-second auto-refresh. Shows live event stream, KPIs, inventory heatmap, shipment map, and quality alerts.

## Deployment Steps

> **Tooling note:** The Fabric RTI MCP **does not** create Real-Time Dashboard items (it is currently listed under "Coming soon" in the RTI MCP README). The supported programmatic path is the **Fabric Items REST API** with a **base64-encoded definition payload**. This is the same pattern the activator skill uses for KQL Querysets.
>
> This skill therefore deploys the dashboard via direct REST calls. The agent should treat the dashboard JSON as a parameterized template — author the definition once in the UI, export via Git integration, then re-deploy programmatically with workspace/cluster/database GUIDs substituted.

### 1. Author the dashboard definition (one-time, per template)

Build the dashboard once in the Fabric UI (`{prefix}_RealTime_Dashboard`) with all tiles defined below. Then enable Git integration on the workspace and pull the resulting folder to disk:
```
{prefix}_RealTime_Dashboard.Dashboard/
  ├── RTDashboard.json     ← the dashboard definition (data sources, pages, tiles, layout)
  └── .platform            ← item metadata (type, displayName, logicalId)
```
Treat `RTDashboard.json` as the **template**. The two values that must be substituted on every deploy are:
- `dataSources[].clusterUri`     → `https://{prefix}_RealTime_EH.kusto.fabric.microsoft.com`
- `dataSources[].databaseId`     → KQL Database item id (NOT Eventhouse id)
- `dataSources[].databaseName`   → KQL DB display name
- `dataSources[].workspaceId`    → workspace GUID

### 2. Deploy via Items REST API (base64 definition)

```powershell
$ws       = "<workspace guid>"
$prefix   = "ZavaShoes"
$kqlDbId  = "<KQL Database item id>"
$kqlDbName= "{prefix}_RealTime_EH"
$cluster  = "https://{prefix}_RealTime_EH.kusto.fabric.microsoft.com"

# 1. Load + parameterize the template
$def = Get-Content ".github/skills/07-realtime-dashboard/RTDashboard.template.json" -Raw |
       ConvertFrom-Json
foreach ($d in $def.dataSources) {
  $d.clusterUri   = $cluster
  $d.databaseId   = $kqlDbId
  $d.databaseName = $kqlDbName
  $d.workspaceId  = $ws
}
$rtJson = ($def | ConvertTo-Json -Depth 50 -Compress)

# 2. Build .platform with a fresh GUID logicalId
$platform = @"
{
  "`$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
  "metadata": { "type": "Dashboard", "displayName": "${prefix}_RealTime_Dashboard",
                "description": "Supply chain real-time control tower" },
  "config":   { "version": "2.0", "logicalId": "$([guid]::NewGuid())" }
}
"@

# 3. Base64-encode both parts
$rtB64       = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($rtJson))
$platformB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($platform))

# 4. POST to Fabric Items REST API
$body = @{
  displayName = "${prefix}_RealTime_Dashboard"
  type        = "Dashboard"
  definition  = @{
    parts = @(
      @{ path = "RTDashboard.json"; payload = $rtB64;       payloadType = "InlineBase64" },
      @{ path = ".platform";        payload = $platformB64; payloadType = "InlineBase64" }
    )
  }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod `
  -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ws/items" `
  -Method POST `
  -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
  -Body $body
```

### 3. Verify and debug

The API returns **HTTP 200** even when the inner `RTDashboard.json` is malformed. Always read it back:
```powershell
$d = Invoke-RestMethod `
  -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ws/items/$itemId/getDefinition" `
  -Method POST -Headers $h
foreach ($p in $d.definition.parts) {
  Write-Host "=== $($p.path) ==="
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p.payload))
}
```
If the dashboard renders blank or "Something went wrong":
- Check `dataSources[].clusterUri` and `workspaceId` are populated (Git integration injects these on deploy; REST does not).
- Check `dataSources[].type == "Fabric"` (not `"AzureDataExplorer"`).
- `databaseId` must be the KQL Database **item id**, not the Eventhouse id.
- Use a fresh GUID for `.platform` `logicalId` (not all-zeros).
- Hard-refresh the browser (Ctrl+Shift+R) — Fabric caches dashboard definitions per session.

### 4. Configure auto-refresh

Set in the dashboard JSON under `pages[].autoRefresh.intervalSeconds = 30` before deploy, or toggle in the UI after.

### 5. Add tiles
Tile definitions below — they go into the `pages[].tiles[]` array of `RTDashboard.json`.

---

## Dashboard Tiles

### Row 1: Executive KPI Cards (5 stat tiles)

#### Tile 1: On-Time Delivery Rate
- **Type**: Stat tile
- **Icon**: truck, green/red indicator
```kql
KPI_SupplierOTD(30)
| summarize OTD = round(avg(OTD_Pct), 1)
```
- **Threshold**: Green ≥95%, Yellow 90-94%, Red <90%

#### Tile 2: First-Pass Quality Rate
- **Type**: Stat tile
```kql
KPI_FirstPassQuality(7)
| summarize FPQ = round(avg(FPQ_Pct), 1)
```
- **Threshold**: Green ≥98%, Yellow 95-97%, Red <95%

#### Tile 3: Events in Last Hour
- **Type**: Stat tile with sparkline
```kql
SAPEvents
| where timestamp >= ago(1h)
| count
```

#### Tile 4: Critical Inventory Alerts
- **Type**: Stat tile (count)
```kql
InventorySnapshot
| where qty_on_hand <= reorder_point
| count
```
- **Threshold**: Green =0, Yellow 1-5, Red >5

#### Tile 5: Active Shipment Delays
- **Type**: Stat tile
```kql
KPI_ShipmentDelayRisk()
| count
```

---

### Row 2: Event Stream & Production (2 tiles)

#### Tile 6: Live SAP Event Stream (Time Chart)
- **Type**: TimeSeries / Line chart
- **Width**: 8 columns
```kql
SAPEvents
| where timestamp >= ago(30m)
| summarize EventCount = count() by bin(timestamp, 1m), sap_module
| order by timestamp asc
```
- **Series**: One line per SAP module (MM, PP, WM, SD, QM)
- **Title**: "SAP Events per Minute (Last 30 min)"

#### Tile 7: Production Yield by Factory
- **Type**: BarChart
```kql
KPI_ProductionYield()
| project factory_id, AvgYield, OrderCount
| order by AvgYield asc
```

---

### Row 3: Inventory Heatmap (1 full-width tile)

#### Tile 8: Inventory Health Matrix
- **Type**: Table with conditional formatting
- **Width**: 12 columns
```kql
InventorySnapshot
| extend stock_status = case(
    qty_on_hand == 0,                    'OUT_OF_STOCK',
    qty_on_hand <= reorder_point,        'CRITICAL',
    qty_on_hand <= reorder_point * 1.5,  'LOW',
    'HEALTHY')
| project warehouse_id, material_id, qty_on_hand, reorder_point,
          qty_on_hand - qty_reserved as qty_available, stock_status
| order by stock_status asc, qty_on_hand asc
```
- **Conditional format**: stock_status column colored RED/ORANGE/YELLOW/GREEN

---

### Row 4: Supplier & Quality (2 tiles)

#### Tile 9: Supplier OTD Leaderboard
- **Type**: BarChart (horizontal)
```kql
KPI_SupplierOTD(30)
| top 12 by OTD_Pct asc
| project vendor_id, OTD_Pct
```

#### Tile 10: Quality Inspection Results (Last 24h)
- **Type**: Donut / PieChart
```kql
SAPEvents
| where event_type == 'QUALITY_INSPECTION' and timestamp >= ago(24h)
| extend result = tostring(payload.result)
| summarize count() by result
```

---

### Row 5: Shipments & Alerts (2 tiles)

#### Tile 11: At-Risk Shipments
- **Type**: Table
```kql
KPI_ShipmentDelayRisk()
| project shipment_id, carrier, origin_wh, eta, days_to_eta, delay_status
| take 20
```
- **Conditional format**: OVERDUE = Red, AT_RISK = Orange

#### Tile 12: Recent Critical Alerts
- **Type**: Table
```kql
SAPAlerts
| where timestamp >= ago(24h)
| order by timestamp desc
| project timestamp, event_type, sap_module, severity, alert_message
| take 15
```
- **Conditional format**: CRITICAL = Red, WARNING = Orange

---

## Dashboard Parameters — Verified JSON Schemas

### IMPORTANT: Parameter kind vs UI type mapping

| UI Type | JSON `kind` | `selectionType` | Notes |
|---------|------------|----------------|-------|
| Time range | `duration` | (n/a) | Uses `beginVariableName` / `endVariableName` |
| Single selection | `string` (or other data type) | `scalar` | Dropdown, one value |
| Multiple selection | `string` (or other data type) | `array` | Dropdown, multi-select |
| Free text | `string` (or other data type) | `freetext` | User types value, no `dataSource` |

> **Critical**: The discriminator is `selectionType`, NOT `kind`. `kind` is the **data type** (`string`, `int`, `decimal`, `bool`, `datetime`). `selectionType` is the **input mode** with enum `scalar` | `array` | `freetext`.
>
> Common mistakes that cause `must NOT have unevaluated properties` errors:
> - `selectionType: "single"` (use `"scalar"`)
> - `selectionType: "multi"` (use `"array"`)
> - `defaultValue.kind: "static"` (use `"value"`)
> - Missing `selectionType` on a non-`duration` parameter — invalidates the whole `then` branch of the discriminated schema, making every other property report as unevaluated.

### `duration` parameter (time range picker)

```json
{
  "id": "cc100001-0001-4001-8001-000000000001",
  "kind": "duration",
  "displayName": "Time range",
  "description": "",
  "beginVariableName": "_startTime",
  "endVariableName": "_endTime",
  "defaultValue": {
    "kind": "dynamic",
    "count": 30,
    "unit": "minutes"
  },
  "showOnPages": { "kind": "all" }
}
```

Allowed `defaultValue.kind` for duration: `dynamic` (relative), `absolute` (fixed range), `no-selection`.
Allowed `unit`: `"minutes"`, `"hours"`, `"days"`.

### `string` parameter — single-selection fixed-values dropdown (VERIFIED LIVE)

```json
{
  "id": "cc100001-0002-4001-8001-000000000002",
  "kind": "string",
  "displayName": "Retrieval Mode",
  "description": "Switch between historian retrieval modes",
  "variableName": "_retrieval_mode",
  "selectionType": "scalar",
  "includeAllOption": false,
  "defaultValue": {
    "kind": "value",
    "value": "Cyclic"
  },
  "dataSource": {
    "kind": "static",
    "values": [
      { "value": "Cyclic" },
      { "value": "TWA_Linear" },
      { "value": "TWA_StairStep" }
    ]
  },
  "showOnPages": { "kind": "all" }
}
```

Allowed `defaultValue.kind` for `scalar`: `"value"`, `"all"`, `"no-selection"`, `"query-result"`.
Do NOT use `"static"` — that is invalid and causes schema errors.

For `selectionType: "array"` (multi-select), use `defaultValue.kind: "values"` with a `values` array, or `"all"` / `"no-selection"`.
When `includeAllOption: true`, handle in KQL with `isempty(_param) or _param == '*'` pattern.

For `selectionType: "freetext"`, omit `dataSource` and `includeAllOption`; use `defaultValue.kind: "value"` with a default string.

For query-based values (dynamic dropdown from KQL), use:
```json
"dataSource": {
  "kind": "query",
  "queryRef": { "kind": "inline", "query": "<KQL>", "dataSourceId": "<id>" }
}
```

Third `dataSource.kind` is `"dataSource"` — used for cross-dashboard data source parameters (rare).

### `dataSource.kind` enum (VERIFIED from API error)
`static` | `query` | `dataSource` — NOT `"fixed"`.

### `dataSource.values` items (for `kind: "static"`)
Each item is `{ "value": "..." }` only. **Do NOT add `label`** — it causes `unevaluated properties` errors. The displayed label equals the value.

### Debugging parameter schema errors

When the dashboard reports `must NOT have unevaluated properties` on multiple fields of one parameter, it means the conditional schema branch for that parameter's `selectionType` did not match. The `if/then/else` JSON Schema validator falls through and flags every property in the parameter as "unevaluated". **Fix `selectionType` first** — the rest of the errors usually disappear once the correct branch is selected.

The `selectionType` enum was confirmed live via API error: `freetext | scalar | array`.

## Demo Script for Real-Time Dashboard
1. Open the dashboard — show the 5 KPI cards as the "health score"
2. Point to Tile 6 (live event stream) — "This is SAP data flowing in right now"
3. Scroll to Tile 8 (inventory matrix) — highlight any RED rows
4. Show Tile 11 (at-risk shipments) — "These shipments need attention today"
5. Show Tile 12 (alerts) — "The Activator already detected these and notified the team"
