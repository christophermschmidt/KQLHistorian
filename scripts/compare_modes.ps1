. "$PSScriptRoot\_env.ps1"
$tok = az account get-access-token --resource https://kusto.kusto.windows.net --query accessToken -o tsv
$cluster = $KustoClusterUri
$db = $KustoDatabase
$headers = @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json' }
$kql = @'
let tag = 'WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation';
let s = ago(30m); let e = now(); let i = 1m; let tf = dynamic([]);
fn_ww_view('Cyclic',        s, e, i, dynamic(['WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation']), '*') | extend m='Cyclic'
| union (fn_ww_view('TWA_StairStep', s, e, i, dynamic(['WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation']), '*') | extend m='Stair')
| union (fn_ww_view('TWA_Linear',    s, e, i, dynamic(['WND_106_BATCH_BH_Actual_Weight_Silo1_Deviation']), '*') | extend m='Linear')
| summarize Cyclic=anyif(value,m=='Cyclic'), Stair=anyif(value,m=='Stair'), Linear=anyif(value,m=='Linear') by timestamp
| order by timestamp asc
'@
$body = @{ db = $db; csl = $kql } | ConvertTo-Json
$r = Invoke-RestMethod -Uri "$cluster/v2/rest/query" -Method Post -Headers $headers -Body $body -UseBasicParsing
$tbl = $r | Where-Object { $_.TableKind -eq 'PrimaryResult' }
$cols = $tbl.Columns.ColumnName
"{0,-22} {1,8} {2,8} {3,8}" -f 'timestamp','Cyclic','Stair','Linear'
foreach ($row in $tbl.Rows) {
  "{0,-22} {1,8} {2,8} {3,8}" -f ([datetime]$row[0]).ToString('HH:mm:ss'), $row[1], $row[2], [math]::Round([double]$row[3],4)
}
