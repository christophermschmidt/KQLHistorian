# Wonderware Historian Compatibility in KQL (rtininjakustodb)

## Scope and source
This design is based on the loaded historian analysis document and the existing workspace skills:
- `.github/.skills/07-realtime-dashboard` for deployable KQL Dashboard structure.
- `.github/.skills/09-factory-floor` for real-time event modeling and MV usage pattern.
- `.github/.skills/08-activator` for query/function organization conventions.

## What the existing Wonderware process is doing
From the loaded analysis, the current process repeatedly queries Wonderware over an 8-hour window at ~1-minute cadence and stores snapshots by iteration.

### Core behaviors observed
1. Raw analog history is append-like and may include delayed arrivals.
2. Cyclic mode returns the last known value at each minute boundary.
3. Average mode returns time-weighted averages (TWA) and is sensitive to interpolation type.
4. Linear interpolation can retroactively change older TWA values when a later point arrives.
5. StairStep interpolation is less retroactive for historical boundaries.
6. Cyclic values are stable for historical boundaries unless truly late data has a timestamp before the boundary.

### Why this matters for KQL
If downstream systems ingest only first-seen TWA values, they can become stale. A KQL-native model should support:
- deterministic recomputation from raw data,
- as-of evaluation for auditing,
- parameterized retrieval modes so users pick Cyclic vs TWA and tag subsets.

## Proposed self-contained KQL structure
Implemented scripts are in `docs/kql`.

### Objects
- `ww_tag_config`: tag metadata and parameter defaults.
- `ww_raw_analog`: raw historian-compatible events with both source timestamp and ingest time.
- `ww_query_audit`: optional query invocation logging.
- `ww_mv_latest_by_tag`: materialized view for latest-value acceleration.

### Functions
- `fn_ww_active_tags(area_filter)`
- `fn_ww_raw_effective(start_time, end_time, tag_filter, area_filter)`
- `fn_ww_cyclic(start_time, end_time, interval, tag_filter, area_filter)`
- `fn_ww_twa_stair(start_time, end_time, interval, tag_filter, area_filter)`
- `fn_ww_twa_linear(start_time, end_time, interval, tag_filter, area_filter)`
- `fn_ww_twa_linear_asof(start_time, end_time, interval, asof_time, tag_filter, area_filter)`
- `fn_ww_view(mode, start_time, end_time, interval, tag_filter, area_filter)`

## Parameterization model (Wonderware-like)
Users can select:
- mode: `Cyclic`, `TWA_StairStep`, `TWA_Linear`
- time range: start/end and interval
- tags: explicit list (`dynamic([...])`) or metadata-driven defaults
- area: optional high-level process filter

This maps directly to the user experience in Wonderware where retrieval mode, tag set, and time granularity are user-selected.

## Recommendation: materialized views vs functions
Use both, but for different jobs.

### Functions should be primary for historian compatibility
- They preserve correctness and replayability.
- They support as-of auditing (critical for late-arrival drift analysis).
- They allow true parameterization per user request.

### Materialized views should be selective accelerators
- Best for expensive, repeated, low-variance slices.
- Good fit: latest-value cards and alerting (`ww_mv_latest_by_tag`).
- Avoid replacing parameterized historian retrieval with fixed MVs because that loses flexibility and may hide drift logic.

### Decision
Primary pattern: **functions first**.
Performance pattern: **add targeted MVs only where dashboard/alerts need sub-second repeated reads**.

## Dashboard design (real-time)
Dashboard template and deployment script are under `docs/dashboard`.

Proposed tile set:
1. Active tags count (card)
2. Latest good values by tag (table)
3. Cyclic trend by selected tags (time chart)
4. TWA linear trend by selected tags (time chart)
5. TWA stair-step trend by selected tags (time chart)
6. Drift detector (table, compares as-of vs current linear TWA)
7. Late arrivals in last 30 minutes (table)

## Validation approach
`docs/kql/03_validation_tests.kql` includes four test blocks:
1. Cyclic historical stability test.
2. Linear TWA retroactive drift test.
3. Mode selector parameterization test.
4. Materialized-view coverage test.

Expected result is explicit PASS/FAIL rows.

## Execution sequence
1. Run `docs/kql/01_schema_and_functions.kql`.
2. Run `docs/kql/02_seed_sample_data.kql`.
3. Run `docs/kql/03_validation_tests.kql`.
4. Deploy dashboard using `docs/dashboard/deploy_dashboard.ps1`.
