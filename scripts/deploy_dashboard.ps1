$token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
$h = @{Authorization="Bearer $token"; 'Content-Type'='application/json'}
$tmpl = Get-Content "c:\KustoHistorianCompatibility\docs\dashboard\WonderwareRealtimeDashboard.template.json" -Raw
$def = $tmpl `
    -replace '__CLUSTER_URI__','https://trd-ssnd5nx50gey5rc8hs.z3.kusto.fabric.microsoft.com' `
    -replace '__KQL_DB_ID__','832b5240-f84b-45ea-b5de-994ad75b8241' `
    -replace '__KQL_DB_NAME__','rtininjakustodb' `
    -replace '__WORKSPACE_ID__','29f18537-b8ef-430a-bfa5-918ebbbfcb64'
$defB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($def))
$platform = '{"$schema":"https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json","metadata":{"type":"KQLDashboard","displayName":"Wonderware Realtime Dashboard"},"config":{"version":"2.0","logicalId":"db3730c3-3801-4197-8149-d5ff1da32305"}}'
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
    Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/29f18537-b8ef-430a-bfa5-918ebbbfcb64/items/db3730c3-3801-4197-8149-d5ff1da32305/updateDefinition" -Method Post -Headers $h -Body $body | Out-Null
    Write-Output "SUCCESS"
} catch {
    $e = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($e) { $e | ConvertTo-Json -Depth 10 } else { $_.Exception.Message }
}
