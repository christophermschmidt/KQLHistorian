. "$PSScriptRoot\_env.ps1"
$token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
$h = @{Authorization="Bearer $token"; 'Content-Type'='application/json'}
$tmpl = Get-Content (Join-Path $PSScriptRoot '..\docs\dashboard\WonderwareRealtimeDashboard.template.json') -Raw
$def = $tmpl `
    -replace '__CLUSTER_URI__',$KustoClusterUri `
    -replace '__KQL_DB_ID__',$FabricKqlDbId `
    -replace '__KQL_DB_NAME__',$KustoDatabase `
    -replace '__WORKSPACE_ID__',$FabricWorkspaceId
$defB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($def))
$platform = (@{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json'
    metadata  = @{ type = 'KQLDashboard'; displayName = 'Wonderware Realtime Dashboard' }
    config    = @{ version = '2.0'; logicalId = $FabricDashboardId }
} | ConvertTo-Json -Depth 10 -Compress)
$platB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($platform))
$body = @{
    definition = @{
        parts = @(
            @{ path="RealTimeDashboard.json"; payload=$defB64; payloadType="InlineBase64" },
            @{ path=".platform"; payload=$platB64; payloadType="InlineBase64" }
        )
    }
} | ConvertTo-Json -Depth 10 -Compress
try {
    Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$FabricWorkspaceId/items/$FabricDashboardId/updateDefinition" -Method Post -Headers $h -Body $body | Out-Null
    Write-Output "SUCCESS"
} catch {
    $e = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($e) { $e | ConvertTo-Json -Depth 10 } else { $_.Exception.Message }
}
