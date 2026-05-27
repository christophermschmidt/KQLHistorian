$token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
$h = @{Authorization="Bearer $token"; 'Content-Type'='application/json'}
$r = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/29f18537-b8ef-430a-bfa5-918ebbbfcb64/kqlDashboards/db3730c3-3801-4197-8149-d5ff1da32305/getDefinition" -Method Post -Headers $h
$raw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($r.definition.parts | Where-Object { $_.path -eq 'RealTimeDashboard.json' }).payload))
($raw | ConvertFrom-Json).parameters[1] | ConvertTo-Json -Depth 10
