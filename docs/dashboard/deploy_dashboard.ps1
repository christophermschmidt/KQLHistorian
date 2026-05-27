param(
  [string]$WorkspaceId = '29f18537-b8ef-430a-bfa5-918ebbbfcb64',
  [string]$KqlDbId = '832b5240-f84b-45ea-b5de-994ad75b8241',
  [string]$KqlDbName = 'rtininjakustodb',
  [string]$ClusterUri = 'https://trd-ssnd5nx50gey5rc8hs.z3.kusto.fabric.microsoft.com',
  [string]$DisplayName = 'Wonderware Historian Real-Time Dashboard',
  [string]$TemplatePath = '.\docs\dashboard\WonderwareRealtimeDashboard.template.json'
)

$ErrorActionPreference = 'Stop'

$token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
if (-not $token) {
  throw 'Could not acquire Fabric token from az CLI.'
}

$tmpl = Get-Content $TemplatePath -Raw
$tmpl = $tmpl.Replace('__WORKSPACE_ID__', $WorkspaceId)
$tmpl = $tmpl.Replace('__KQL_DB_ID__', $KqlDbId)
$tmpl = $tmpl.Replace('__KQL_DB_NAME__', $KqlDbName)
$tmpl = $tmpl.Replace('__CLUSTER_URI__', $ClusterUri)

$platform = @"
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
  "metadata": {
    "type": "KQLDashboard",
    "displayName": "$DisplayName",
    "description": "Wonderware historian compatibility dashboard with cyclic and TWA drift monitoring"
  },
  "config": {
    "version": "2.0",
    "logicalId": "$([guid]::NewGuid().ToString())"
  }
}
"@

$dashboardB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($tmpl))
$platformB64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($platform))

$body = @{
  displayName = $DisplayName
  type = 'KQLDashboard'
  definition = @{
    parts = @(
      @{ path = 'RealTimeDashboard.json'; payload = $dashboardB64; payloadType = 'InlineBase64' },
      @{ path = '.platform'; payload = $platformB64; payloadType = 'InlineBase64' }
    )
  }
} | ConvertTo-Json -Depth 20

$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

$result = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items" -Method Post -Headers $headers -Body $body
$result | ConvertTo-Json -Depth 20
