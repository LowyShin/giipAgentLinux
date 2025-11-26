# Test network collection on remote server

param(
    [string]$Server = "10.2.0.5",
    [string]$User = "root"
)

Write-Host "Uploading debug script to $Server..." -ForegroundColor Cyan
scp giipscripts/debug-network.sh ${User}@${Server}:/tmp/

Write-Host "`nExecuting debug script on server..." -ForegroundColor Cyan
ssh ${User}@${Server} "chmod +x /tmp/debug-network.sh && bash /tmp/debug-network.sh"

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Debug complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
