. "$PSScriptRoot\_env.ps1"
$token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
$h = @{Authorization="Bearer $token"; 'Content-Type'='application/json'}
$r = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$FabricWorkspaceId/kqlDashboards/$FabricDashboardId/getDefinition" -Method Post -Headers $h
$raw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($r.definition.parts | Where-Object { $_.path -eq 'RealTimeDashboard.json' }).payload))
($raw | ConvertFrom-Json).parameters[1] | ConvertTo-Json -Depth 10
