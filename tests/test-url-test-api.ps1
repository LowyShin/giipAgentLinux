param(
    [string]$Server = "http://localhost:3000",
    [string]$Token = "",
    [string]$Csn = "47"
)

Write-Host "🧪 GIIP AI URL Test API Verification" -ForegroundColor Cyan

# 1. Token Extraction (Manual placeholder for now)
if ([string]::IsNullOrEmpty($Token)) {
    Write-Host "🔑 Please provide a session token to run this test." -ForegroundColor Yellow
    Write-Host "   Example: pwsh test-url-test-api.ps1 -Token 'YOUR_TOKEN'"
    exit
}

# 2. Test: URLTestPut (Create Request)
Write-Host "`n[TEST 1] Creating new URL Test Request..." -ForegroundColor Yellow
$text = "URLTestPut csn url depth context"
$jsondata = @{
    csn     = [int]$Csn
    url     = "https://www.google.com"
    depth   = "SHALLOW"
    context = "API Test Attempt"
} | ConvertTo-Json

$params = @{
    text      = $text
    jsondata  = $jsondata
    token     = $Token
    usertoken = $Token
}

$body = $params.GetEnumerator() | ForEach-Object { 
    "$($_.Key)=$(([System.Net.WebUtility]::UrlEncode($_.Value)))" 
} | Join-String -Separator "&"

try {
    $response = Invoke-WebRequest -Uri "$Server/api/giip-proxy" `
        -Method POST -Body $body `
        -ContentType "application/x-www-form-urlencoded" `
        -UseBasicParsing

    Write-Host "✅ PUT Response Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Content: $($response.Content)"
}
catch {
    Write-Host "❌ PUT Failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        Write-Host "Error Body: $($reader.ReadToEnd())" -ForegroundColor Red
    }
}

# 3. Test: URLTestGet (List Requests)
Write-Host "`n[TEST 2] Fetching URL Test Requests..." -ForegroundColor Yellow
$getText = "URLTestGet csn"
$getJson = @{ csn = [int]$Csn } | ConvertTo-Json

$getParams = @{
    text      = $getText
    jsondata  = $getJson
    token     = $Token
    usertoken = $Token
}

$getBody = $getParams.GetEnumerator() | ForEach-Object { 
    "$($_.Key)=$(([System.Net.WebUtility]::UrlEncode($_.Value)))" 
} | Join-String -Separator "&"

try {
    $getResponse = Invoke-WebRequest -Uri "$Server/api/giip-proxy" `
        -Method POST -Body $getBody `
        -ContentType "application/x-www-form-urlencoded" `
        -UseBasicParsing

    Write-Host "✅ GET Response Status: $($getResponse.StatusCode)" -ForegroundColor Green
    $parsed = $getResponse.Content | ConvertFrom-Json
    Write-Host ($parsed | ConvertTo-Json -Depth 5)
}
catch {
    Write-Host "❌ GET Failed: $($_.Exception.Message)" -ForegroundColor Red
}
