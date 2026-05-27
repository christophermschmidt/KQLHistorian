$token = az account get-access-token --resource https://kusto.kusto.windows.net --query accessToken -o tsv
$h = @{Authorization="Bearer $token"; 'Content-Type'='application/json; charset=utf-8'; Accept='application/json'}
$cluster = 'https://trd-ssnd5nx50gey5rc8hs.z3.kusto.fabric.microsoft.com'

# Try a minimal repro
$kql = @'
.set-or-replace ww_raw_analog <|
let _now = now();
union
  (print tag_name='WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation', source_timestamp=_now-26m, ingest_time=_now-26m, value=0.0, quality='Good', source='Wonderware', source_iteration=long(1)),
  (print tag_name='WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation', source_timestamp=_now-22m, ingest_time=_now-22m, value=-0.5, quality='Good', source='Wonderware', source_iteration=long(2)),
  (print tag_name='WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation', source_timestamp=_now-8m,  ingest_time=_now-1m,  value=0.0, quality='Good', source='Wonderware', source_iteration=long(25)),
  (print tag_name='WND_106_BATCH_BH_Actual_Weight_Silo2_Deviation', source_timestamp=_now-25m, ingest_time=_now-25m, value=0.1, quality='Good', source='Wonderware', source_iteration=long(1)),
  (print tag_name='WND_106_BATCH_BH_Actual_Weight_Silo2_Deviation', source_timestamp=_now-18m, ingest_time=_now-18m, value=0.0, quality='Good', source='Wonderware', source_iteration=long(8)),
  (print tag_name='WND_106_BATCH_BH_Actual_Weight_Silo2_Deviation', source_timestamp=_now-11m, ingest_time=_now-11m, value=-0.2, quality='Good', source='Wonderware', source_iteration=long(15)),
  (print tag_name='WND_106_BATCH_BH_Actual_Weight_Silo2_Deviation', source_timestamp=_now-4m,  ingest_time=_now-4m,  value=0.1, quality='Good', source='Wonderware', source_iteration=long(22)),
  (print tag_name='WND_106_BATCH_Mixer_Temp', source_timestamp=_now-29m, ingest_time=_now-29m, value=68.5, quality='Good', source='Wonderware', source_iteration=long(1)),
  (print tag_name='WND_106_BATCH_Mixer_Temp', source_timestamp=_now-19m, ingest_time=_now-19m, value=69.2, quality='Good', source='Wonderware', source_iteration=long(11)),
  (print tag_name='WND_106_BATCH_Mixer_Temp', source_timestamp=_now-9m,  ingest_time=_now-9m,  value=70.1, quality='Good', source='Wonderware', source_iteration=long(21)),
  (print tag_name='WND_106_BATCH_LinePressure', source_timestamp=_now-29m, ingest_time=_now-29m, value=11.2, quality='Good', source='Wonderware', source_iteration=long(1)),
  (print tag_name='WND_106_BATCH_LinePressure', source_timestamp=_now-23m, ingest_time=_now-23m, value=11.8, quality='Good', source='Wonderware', source_iteration=long(7)),
  (print tag_name='WND_106_BATCH_LinePressure', source_timestamp=_now-13m, ingest_time=_now-13m, value=11.1, quality='Good', source='Wonderware', source_iteration=long(17)),
  (print tag_name='WND_106_BATCH_LinePressure', source_timestamp=_now-5m,  ingest_time=_now-5m,  value=10.9, quality='Good', source='Wonderware', source_iteration=long(25))
'@

$body = @{ db='rtininjakustodb'; csl=$kql } | ConvertTo-Json -Compress
try {
    $resp = Invoke-WebRequest -Uri "$cluster/v1/rest/mgmt" -Method Post -Headers $h -Body $body
    Write-Output "OK"
} catch {
    $r = $_.Exception.Response
    if ($r) {
        $stream = $r.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        Write-Output $reader.ReadToEnd()
    }
    Write-Output $_.Exception.Message
}

$q = @{ db='rtininjakustodb'; csl='ww_raw_analog | summarize n=count(), oldest=min(source_timestamp), newest=max(source_timestamp)' } | ConvertTo-Json -Compress
$r2 = Invoke-RestMethod -Uri "$cluster/v1/rest/query" -Method Post -Headers $h -Body $q
$r2.Tables[0].Rows | ForEach-Object { "rows=$($_[0]) oldest=$($_[1]) newest=$($_[2])" }
