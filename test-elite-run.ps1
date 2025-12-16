$log = Join-Path $env:TEMP 'poshbits_test.log'
if (Test-Path $log) { Remove-Item $log -Force }

Write-Host "`n=== Testing Elite Dangerous Apps ===" -ForegroundColor Cyan
Write-Host "NOTE: You must accept the UAC prompt if it appears!" -ForegroundColor Yellow

$apps = @(
    [pscustomobject]@{
        Name = 'EDHM'
        Path = "C:\Users\James\AppData\Local\EDHM-UI-V3\EDHM-UI-V3.exe"
        RunAsAdmin = $true
        RedirectOutput = $true
        StartAction = 'None'
        WaitMs = 8000
        TimeoutMs = 10000
    }
    [pscustomobject]@{
        Name = 'EDMarketConnector'
        Path = "C:\Program Files (x86)\EDMarketConnector\EDMarketConnector.exe"
        RunAsAdmin = $false
        RedirectOutput = $true
        StartAction = 'Minimize'
        WaitMs = 500
        TimeoutMs = 3000
        WindowTitleRegex = 'E:D Market Connector|EDMarketConnector'
    }
    [pscustomobject]@{
        Name = 'EDOdysseyMaterialsHelper'
        Path = "C:\Users\James\AppData\Local\Elite Dangerous Odyssey Materials Helper Launcher\Elite Dangerous Odyssey Materials Helper Launcher.exe"
        RunAsAdmin = $false
        RedirectOutput = $true
        StartAction = 'Close'
        WaitMs = 3000
        TimeoutMs = 15000
        WindowTitleRegex = 'ED Odyssey Materials Helper'
        ProcessNameRegex = 'Elite Dangerous Odyssey Materials Helper'
    }
)

# Launch apps in a completely detached PowerShell process
$scriptPath = Join-Path $PSScriptRoot "Start-AppsToTray.ps1"
$appsJsonFile = Join-Path $env:TEMP "poshbits_apps_$(Get-Date -Format 'yyyyMMddHHmmss').json"
$apps | ConvertTo-Json -Depth 10 -AsArray | Out-File -FilePath $appsJsonFile -Encoding UTF8

$scriptBlock = @"
. '$($scriptPath.Replace("'","''"))'
`$apps = Get-Content '$($appsJsonFile.Replace("'","''"))' -Raw | ConvertFrom-Json
Start-AppsToTray -Apps `$apps -LogFile '$($log.Replace("'","''"))' -Verbose
Remove-Item '$($appsJsonFile.Replace("'","''"))' -Force -ErrorAction SilentlyContinue
"@

# Start completely detached - no waiting
$null = Start-Process -FilePath 'pwsh' -ArgumentList '-NoProfile', '-Command', $scriptBlock -WindowStyle Hidden

# Give the launcher a moment to start, then we can check results
Write-Host "Launcher process started in background..." -ForegroundColor Cyan
Write-Host "Apps are launching and will minimize to tray automatically..." -ForegroundColor Cyan
Start-Sleep -Seconds 5  # Brief wait just to let initial launches happen

Write-Host "`nWaiting for processes to stabilize..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

Write-Host "`n=== Checking for App Processes ===" -ForegroundColor Cyan
$edmProcesses = Get-Process | Where-Object { $_.ProcessName -match 'EDHM' }
$edmc = Get-Process -Name 'EDMarketConnector' -ErrorAction SilentlyContinue
if ($edmProcesses) {
    Write-Host "✓ Found $($edmProcesses.Count) EDHM process(es):" -ForegroundColor Green
    $edmProcesses | Select-Object Id, ProcessName, MainWindowHandle | Format-Table -AutoSize
} else {
    Write-Host "✗ No EDHM processes found" -ForegroundColor Red
}
if ($edmc) {
    Write-Host "✓ Found EDMarketConnector:" -ForegroundColor Green
    $edmc | Select-Object Id, ProcessName, MainWindowHandle | Format-Table -AutoSize
} else {
    Write-Host "✗ EDMarketConnector not found" -ForegroundColor Red
}

Write-Host "`n=== Log Contents ===" -ForegroundColor Cyan
if (Test-Path $log) {
    Get-Content $log -Raw
} else {
    Write-Host "✗ Log file not created" -ForegroundColor Red
}

Write-Host "`n=== Cleanup ===" -ForegroundColor Yellow
# Commented out - let apps stay running in tray
# Get-Process | Where-Object { $_.ProcessName -match 'EDHM' } | Stop-Process -Force -ErrorAction SilentlyContinue
# Get-Process -Name 'EDMarketConnector' -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item $log -Force -ErrorAction SilentlyContinue

# Clean up any background jobs that might be keeping the script open
Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue

Write-Host "Done - Apps should be running in system tray" -ForegroundColor Green
exit 0
