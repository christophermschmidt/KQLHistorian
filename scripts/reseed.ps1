$token = az account get-access-token --resource https://kusto.kusto.windows.net --query accessToken -o tsv
$h = @{Authorization="Bearer $token"; 'Content-Type'='application/json; charset=utf-8'; Accept='application/json'}
$cluster = 'https://trd-ssnd5nx50gey5rc8hs.z3.kusto.fabric.microsoft.com'
$full = Get-Content "c:\KustoHistorianCompatibility\docs\kql\02_seed_sample_data.kql" -Raw

$cmds = @()
$current = ""
foreach ($line in ($full -split "`n")) {
    if ($line -match '^\.set-or-replace' -and $current.Trim()) {
        $cmds += $current
        $current = $line + "`n"
    } else {
        $current += $line + "`n"
    }
}
if ($current.Trim()) { $cmds += $current }

foreach ($c in $cmds) {
    if (-not ($c -match '\.set-or-replace')) { continue }
    $body = @{ db='rtininjakustodb'; csl=$c } | ConvertTo-Json -Compress
    try {
        Invoke-RestMethod -Uri "$cluster/v1/rest/mgmt" -Method Post -Headers $h -Body $body | Out-Null
        Write-Output ("CMD OK: " + (($c -split "`n")[0]))
    } catch {
        Write-Output ("CMD FAIL: " + (($c -split "`n")[0]))
        Write-Output ($_.ErrorDetails.Message)
        Write-Output ($_.Exception.Message)
    }
}

$q = @{ db='rtininjakustodb'; csl='ww_raw_analog | summarize n=count(), oldest=min(source_timestamp), newest=max(source_timestamp)' } | ConvertTo-Json -Compress
$r2 = Invoke-RestMethod -Uri "$cluster/v1/rest/query" -Method Post -Headers $h -Body $q
$r2.Tables[0].Rows | ForEach-Object { "rows=$($_[0]) oldest=$($_[1]) newest=$($_[2])" }
