. "$PSScriptRoot\_env.ps1"
$token = az account get-access-token --resource https://kusto.kusto.windows.net --query accessToken -o tsv
$h = @{Authorization="Bearer $token"; 'Content-Type'='application/json; charset=utf-8'; Accept='application/json'}
$cluster = $KustoClusterUri

$q = @{
    db  = $KustoDatabase
    csl = "fn_ww_view('Cyclic', ago(30m), now(), 1m, dynamic(['WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation','WND_106_BATCH_BH_Actual_Weight_Silo2_Deviation','WND_106_BATCH_Mixer_Temp','WND_106_BATCH_LinePressure']), '*') | summarize n=count(), oldest=min(timestamp), newest=max(timestamp)"
} | ConvertTo-Json -Compress

$r = Invoke-RestMethod -Uri "$cluster/v1/rest/query" -Method Post -Headers $h -Body $q -UseBasicParsing
$r.Tables[0].Rows | ForEach-Object { "Cyclic: rows=$($_[0]) oldest=$($_[1]) newest=$($_[2])" }

$q2 = @{
    db  = $KustoDatabase
    csl = "fn_ww_view('TWA_Linear', ago(30m), now(), 1m, dynamic(['WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation','WND_106_BATCH_BH_Actual_Weight_Silo2_Deviation','WND_106_BATCH_Mixer_Temp','WND_106_BATCH_LinePressure']), '*') | summarize n=count()"
} | ConvertTo-Json -Compress
$r2 = Invoke-RestMethod -Uri "$cluster/v1/rest/query" -Method Post -Headers $h -Body $q2 -UseBasicParsing
"TWA_Linear: rows=$($r2.Tables[0].Rows[0][0])"

$q3 = @{
    db  = $KustoDatabase
    csl = "fn_ww_view('TWA_StairStep', ago(30m), now(), 1m, dynamic(['WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation','WND_106_BATCH_BH_Actual_Weight_Silo2_Deviation','WND_106_BATCH_Mixer_Temp','WND_106_BATCH_LinePressure']), '*') | summarize n=count()"
} | ConvertTo-Json -Compress
$r3 = Invoke-RestMethod -Uri "$cluster/v1/rest/query" -Method Post -Headers $h -Body $q3 -UseBasicParsing
"TWA_StairStep: rows=$($r3.Tables[0].Rows[0][0])"
