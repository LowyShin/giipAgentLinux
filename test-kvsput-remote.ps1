# Test kvsput.sh on Remote Server
# Uploads test script and executes it

param(
    [string]$Server = "10.2.0.5",
    [string]$User = "root"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "kvsput.sh Remote Test" -ForegroundColor Cyan
Write-Host "Server: $Server" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$scriptPath = Join-Path $PSScriptRoot "giipscripts\test-kvsput.sh"

if (-not (Test-Path $scriptPath)) {
    Write-Error "Test script not found: $scriptPath"
    exit 1
}

try {
    # Upload test script
    Write-Host "1. Uploading test script..." -ForegroundColor Yellow
    scp $scriptPath "${User}@${Server}:/tmp/test-kvsput.sh"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to upload test script"
    }
    Write-Host "   ✓ Uploaded" -ForegroundColor Green
    Write-Host ""
    
    # Execute test
    Write-Host "2. Executing test on server..." -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Gray
    ssh "${User}@${Server}" "chmod +x /tmp/test-kvsput.sh && bash /tmp/test-kvsput.sh"
    $exitCode = $LASTEXITCODE
    Write-Host "========================================" -ForegroundColor Gray
    Write-Host ""
    
    if ($exitCode -eq 0) {
        Write-Host "✅ Test completed successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Checking database..." -ForegroundColor Cyan
        
        # Check KVS data
        $checkScript = Join-Path $PSScriptRoot "..\giipdb\check_autodiscover_kvs.ps1"
        if (Test-Path $checkScript) {
            Write-Host ""
            & $checkScript -KFactor kvstest -Top 1
        }
        else {
            Write-Host "Run this to check:" -ForegroundColor Yellow
            Write-Host "  cd c:\Users\lowys\Downloads\projects\giipprj\giipdb" -ForegroundColor Gray
            Write-Host "  .\check_autodiscover_kvs.ps1 -KFactor kvstest" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "❌ Test failed with exit code: $exitCode" -ForegroundColor Red
        Write-Host ""
        Write-Host "Common Issues:" -ForegroundColor Yellow
        Write-Host "1. Missing jq: sudo apt-get install jq" -ForegroundColor Gray
        Write-Host "2. Invalid config: Check giipAgent.cnf" -ForegroundColor Gray
        Write-Host "3. Network issue: Check firewall/connectivity" -ForegroundColor Gray
    }
}
catch {
    Write-Error "Test execution failed: $_"
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
