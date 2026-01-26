# Simulation of giipAgent3.sh config loading logic in PowerShell

# 1. Create dummy parent config
Set-Content -Path "../giipAgent.cnf" -Value 'sk="PARENT_SECRET_KEY"' -Encoding UTF8

# 2. Create dummy local template (trap)
Set-Content -Path "./giipAgent.cnf" -Value 'sk="TEMPLATE_KEY"' -Encoding UTF8

# 3. Simulate load_config logic
function load_config {
    param([string]$config_file = "../giipAgent.cnf")
    
    if (-not (Test-Path $config_file)) {
        Write-Host "❌ Error: Configuration file not found: $config_file"
        return $false
    }
    
    # Simple parsing for test
    $content = Get-Content $config_file
    if ($content -match 'sk="([^"]+)"') {
        $global:loaded_sk = $matches[1]
    }
    return $true
}

# 4. Simulate giipAgent3.sh call (no arguments)
load_config

# 5. Verify which key was loaded
if ($global:loaded_sk -eq "PARENT_SECRET_KEY") {
    Write-Host "✅ SUCCESS: Loaded PARENT config correctly."
    Write-Host "Loaded SK: $global:loaded_sk"
    exit 0
}
elseif ($global:loaded_sk -eq "TEMPLATE_KEY") {
    Write-Host "❌ FAILURE: Loaded TEMPLATE config (Dangerous!)."
    Write-Host "Loaded SK: $global:loaded_sk"
    exit 1
}
else {
    Write-Host "❌ FAILURE: Failed to load any config."
    exit 1
}
