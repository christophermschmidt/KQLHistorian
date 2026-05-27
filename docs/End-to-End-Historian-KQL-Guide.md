# End-to-End Guide: Recreating Wonderware Historian Retrieval in KQL

This guide walks through the complete scenario — from understanding what Wonderware does, to building
equivalent query functions in KQL, seeding representative sample data, and running each retrieval mode
by hand before layering on a parameterized real-time dashboard.

---

## 1. What Wonderware Historian Actually Does

Wonderware InTouch Historian stores process tag values as raw events and then offers three retrieval modes
when a client (InSQL report, ActiveFactory trend, REST export) asks for data over a time range.

### Cyclic retrieval

The historian snaps to equal-spaced time boundaries (e.g., every minute) and returns the **last known value**
at each boundary — whatever the most recent raw point was at or before that timestamp. This is deterministic
once the boundary passes: the answer never changes, even if a late point later arrives before the boundary.

### Time-weighted average — StairStep

For tags flagged `StairStep`, the historian computes a true TWA by treating each raw point as a flat
(stair-step) level from its timestamp until the next raw point. It calculates the area under the step
function within each interval bucket and divides by bucket width. Results are **retroactive** because
late-arriving points can fill gaps and change previously reported averages.

### Time-weighted average — Linear

For tags flagged `Linear`, the historian interpolates a straight line between consecutive raw points and
computes the average of that ramp within each bucket. Late-arriving points materially change the shape of
the interpolated signal and therefore **retroactively rewrite previously reported bucket values** — sometimes
by a large margin if the late point lands between two existing points that currently look flat.

### The retroactive drift problem

Wonderware returns different numbers for the same historical time range depending on *when you ask*.
A report pulled at 09:00 may differ from the same query run at 09:07 simply because a late-arriving field
device pushed a point with a source timestamp inside that window. This is by design, but it makes
reproducible reporting impossible without an as-of-time snapshot.

---

## 2. KQL Schema Design

All objects live in a single KQL database (`rtininjakustodb`). The full DDL is in
[`docs/kql/01_schema_and_functions.kql`](kql/01_schema_and_functions.kql).

### Tables

| Table | Purpose |
|---|---|
| `ww_tag_config` | Tag metadata: name, interpolation type (Linear/StairStep), area, unit, enabled flag |
| `ww_raw_analog` | All raw inbound events. `source_timestamp` = when the value occurred. `ingest_time` = when it arrived. |
| `ww_query_audit` | Optional: records every `fn_ww_view` call for audit/replay. |

### Materialized view

`ww_mv_latest_by_tag` — `arg_max(source_timestamp, *) by tag_name`

This MV is maintained incrementally and accelerates the "Latest Values" card. It should **not** be used as
a substitute for retrieval functions because it loses the temporal history needed for TWA calculations.

### Query functions

| Function | Equivalent historian mode |
|---|---|
| `fn_ww_active_tags(area_filter)` | Tag metadata filter |
| `fn_ww_raw_effective(start, end, tags, area)` | Deduplicated raw events (last ingest wins per tag+timestamp) |
| `fn_ww_cyclic(start, end, interval, tags, area)` | Cyclic — last-known-value at each boundary |
| `fn_ww_twa_stair(start, end, interval, tags, area)` | TWA StairStep — segment overlap calculation |
| `fn_ww_twa_linear(start, end, interval, tags, area)` | TWA Linear — `make-series` + `series_fill_linear` |
| `fn_ww_twa_linear_asof(start, end, interval, asof, tags, area)` | Linear TWA as of a specific ingest cutoff (snapshot replay) |
| `fn_ww_view(mode, start, end, interval, tags, area)` | Single unified entrypoint routing to the above |

---

## 3. Seeding Sample Data

The seed script ([`docs/kql/02_seed_sample_data.kql`](kql/02_seed_sample_data.kql)) uses `now()` relative
timestamps so the data always lands in a "last 30 minutes" time window regardless of when you run it.
Re-run this script any time you want to refresh a demo environment.

**Critical row — the late arrival:**

```kql
(print tag_name='WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation',
       source_timestamp = now() - 8m,   // value occurred 8 minutes ago
       ingest_time      = now() - 1m,   // but only arrived 1 minute ago
       value = 0.0, ...)
```

This single point, arriving 7 minutes after its source timestamp, causes the linear TWA for the
`ago(15m)` bucket to change retroactively once it lands. The Retroactive Drift Detector tile
surfaces this automatically.

### Run seed data manually

```kql
// In KQL Queryset or any KQL editor connected to rtininjakustodb:
.set-or-replace ww_tag_config <| ...  // (paste from 02_seed_sample_data.kql)
.set-or-replace ww_raw_analog <| ...
```

The script uses `.set-or-replace` so running it multiple times is safe — it replaces rather than appends.

---

## 4. Running Each Retrieval Mode Manually

### Step 1 — Verify tags are loaded

```kql
fn_ww_active_tags('*')
```

Expected: 4 rows — Silo1, Silo2 (Linear), Mixer_Temp, LinePressure (StairStep).

### Step 2 — Cyclic retrieval

Returns the last-known value at each 1-minute boundary over the last 30 minutes:

```kql
fn_ww_cyclic(ago(30m), now(), 1m, dynamic([]), '*')
| project tag_name, timestamp, value
| order by tag_name, timestamp
```

You will see all four tags with one row per minute boundary. Values are stable — they will not change
if you re-run this query later, because cyclic uses point-in-time snapshots.

### Step 3 — TWA StairStep

```kql
fn_ww_twa_stair(ago(30m), now(), 1m,
    dynamic(['WND_106_BATCH_Mixer_Temp','WND_106_BATCH_LinePressure']), '*')
| project tag_name, timestamp, value
| order by tag_name, timestamp
```

Each bucket value is the weighted average of the flat step segments that overlap that minute. For the
seeded data the pressure steps clearly between 11.2 → 11.8 → 11.1 → 10.9 bar.

### Step 4 — TWA Linear

```kql
fn_ww_twa_linear(ago(30m), now(), 1m,
    dynamic(['WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation',
             'WND_106_BATCH_BH_Actual_Weight_Silo2_Deviation']), '*')
| project tag_name, timestamp, value
| order by tag_name, timestamp
```

Silo1 will show a ramp from 0.0 → -0.5 → back toward 0.0, with the bucket around `ago(15m)` showing
the influence of the late-arriving point once it lands. Re-run this query a few seconds later and the
bucket value will have changed if the data has just refreshed.

### Step 5 — Retroactive drift: before vs. after the late point

This is the core of the historian drift story. Compare what TWA looked like before the late point arrived
(simulated by filtering `ingest_time <= asof_mid`) against what it looks like now:

```kql
let tags = dynamic(['WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation']);
let data_start = toscalar(ww_raw_analog | summarize min(source_timestamp));
let data_end   = toscalar(ww_raw_analog | summarize max(source_timestamp));
let asof_mid   = toscalar(ww_raw_analog | summarize min(ingest_time) + (max(ingest_time) - min(ingest_time)) / 2);
let before = fn_ww_twa_linear_asof(data_start, data_end, 1m, asof_mid, tags)
             | project tag_name, timestamp, before_val=value;
let nowv   = fn_ww_twa_linear(data_start, data_end, 1m, tags)
             | project tag_name, timestamp, now_val=value;
before
| join kind=inner nowv on tag_name, timestamp
| extend drift = now_val - before_val
| where abs(drift) > 0.001
| project timestamp, tag_name, before_val, now_val, drift
| order by timestamp desc
```

If the late-arriving Silo1 point (source `ago(8m)`, ingested `ago(1m)`) is in the table, you should see
a non-zero `drift` value for the bucket that spans `ago(15m)` to `ago(14m)`. This is exactly the
behaviour Wonderware exhibted in the original analysis: 705 values changed retroactively, some by up to 79%.

### Step 6 — Unified mode selector

The `fn_ww_view` function is the equivalent of the historian's retrieval mode drop-down:

```kql
// Change 'Cyclic' to 'TWA_Linear' or 'TWA_StairStep' as needed.
fn_ww_view('Cyclic', ago(30m), now(), 1m,
    dynamic(['WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation',
             'WND_106_BATCH_BH_Actual_Weight_Silo2_Deviation',
             'WND_106_BATCH_Mixer_Temp',
             'WND_106_BATCH_LinePressure']), '*')
| project timestamp, tag_name, value
```

---

## 5. Real-Time Dashboard

The dashboard ([`docs/dashboard/WonderwareRealtimeDashboard.template.json`](dashboard/WonderwareRealtimeDashboard.template.json))
has 5 tiles arranged on one page.

### Tile layout

| Tile | Type | What it shows |
|---|---|---|
| Active Historian Tags | Card | Count of enabled tags from `ww_tag_config` |
| Latest Values | Table | Current last-known value per tag from the MV |
| Tag Trend View | Line chart | Calls `fn_ww_view` — switches mode with the **Retrieval Mode** parameter |
| Retroactive Drift Detector | Table | Before/after comparison for linear TWA drift |
| Late Arrivals (30m) | Table | Any raw point where `source_timestamp < ingest_time - 3m` |

### Dashboard parameters

| Parameter | Default | Options |
|---|---|---|
| Time range | Last 30 minutes | Any time window |
| Retrieval Mode | `Cyclic` | `Cyclic` · `TWA_Linear` · `TWA_StairStep` |

To switch retrieval mode, edit the **Retrieval Mode** text parameter and press Enter. The Tag Trend View
tile re-queries immediately and renders the correct signal shape for the selected mode.

### Deploying the dashboard

The template uses placeholder tokens. Substitute them and POST via the Fabric Items REST API:

```powershell
$tmpl = (Get-Content '.\docs\dashboard\WonderwareRealtimeDashboard.template.json' -Raw) `
    -replace '__WORKSPACE_ID__',  '<your-workspace-id>' `
    -replace '__KQL_DB_ID__',     '<your-kqldb-id>' `
    -replace '__KQL_DB_NAME__',   '<your-kqldb-name>' `
    -replace '__CLUSTER_URI__',   '<your-cluster-uri>'

# Then base64-encode $tmpl and POST to:
# POST https://api.fabric.microsoft.com/v1/workspaces/{ws}/items/{id}/updateDefinition
```

See [`docs/dashboard/deploy_dashboard.ps1`](dashboard/deploy_dashboard.ps1) for the full script.

### Refreshing demo data

Re-run [`docs/kql/02_seed_sample_data.kql`](kql/02_seed_sample_data.kql) to reset timestamps to
"right now". The dashboard's default time window (last 30 minutes) will pick up fresh data immediately.

---

## 6. MV vs. Function Recommendation

**Use functions as the primary retrieval layer.** `fn_ww_cyclic`, `fn_ww_twa_linear`, and `fn_ww_twa_stair`
accept arbitrary time windows and tag lists, matching the on-demand, parameterized behaviour of the historian.

**Use the MV selectively as an acceleration structure** — not as a data model. `ww_mv_latest_by_tag` is
maintained incrementally and answers "what is the current value?" in microseconds, which is ideal for
the Latest Values card and alert conditions. It should never replace the temporal retrieval functions
because it collapses history into a single row per tag.

Avoid creating MVs that pre-aggregate TWA buckets at a fixed interval. That pattern locks you into
one granularity, prevents retroactive drift analysis, and silently breaks the as-of query pattern.

---

## 7. File Reference

| File | Purpose |
|---|---|
| `docs/kql/01_schema_and_functions.kql` | All DDL: tables, MV, and all 7 KQL functions |
| `docs/kql/02_seed_sample_data.kql` | Demo data using relative timestamps (re-runnable) |
| `docs/kql/03_validation_tests.kql` | 6 PASS/FAIL test blocks covering all retrieval modes |
| `docs/dashboard/WonderwareRealtimeDashboard.template.json` | Dashboard definition with `__PLACEHOLDER__` tokens |
| `docs/dashboard/deploy_dashboard.ps1` | PowerShell deployment script (first-time create) |
| `docs/Wonderware-Historian-to-KQL-Design.md` | Design document with architecture decisions |
| `docs/End-to-End-Historian-KQL-Guide.md` | This file |
