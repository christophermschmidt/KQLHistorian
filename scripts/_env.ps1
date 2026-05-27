# Dot-source this from other scripts to load .env (if present) and expose
# config as both $env:* and $script:* variables.
#
# Usage:  . "$PSScriptRoot\_env.ps1"

$envFile = Join-Path $PSScriptRoot '..\.env'
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*#') { return }
        if ($_ -match '^\s*$') { return }
        if ($_ -match '^\s*([^=]+?)\s*=\s*(.*?)\s*$') {
            $k = $matches[1]; $v = $matches[2]
            if (-not [Environment]::GetEnvironmentVariable($k)) {
                Set-Item -Path "env:$k" -Value $v
            }
        }
    }
}

$required = @('KUSTO_CLUSTER_URI','KUSTO_DATABASE','FABRIC_WORKSPACE_ID','FABRIC_KQL_DB_ID','FABRIC_DASHBOARD_ID')
$missing = $required | Where-Object { -not [Environment]::GetEnvironmentVariable($_) }
if ($missing) {
    throw "Missing required environment variables: $($missing -join ', '). Copy .env.example to .env or set them in your shell."
}

$script:KustoClusterUri   = $env:KUSTO_CLUSTER_URI
$script:KustoDatabase     = $env:KUSTO_DATABASE
$script:FabricWorkspaceId = $env:FABRIC_WORKSPACE_ID
$script:FabricKqlDbId     = $env:FABRIC_KQL_DB_ID
$script:FabricDashboardId = $env:FABRIC_DASHBOARD_ID
