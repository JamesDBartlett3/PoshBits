<#
.SYNOPSIS
    Launch multiple applications and ensure they start hidden/in the system tray (best-effort).

.DESCRIPTION
    This script takes a list of application definitions (inline PSCustomObject or JSON/PSScript config file),
    launches each app, and attempts to unify their behavior so they appear in the system tray without
    showing a visible window.

    Because each app implements tray behavior differently, the script uses several strategies (Hide,
    Minimize, Close) and falls back if the first approach doesn't cause the app to hide. Use the
    `StartAction` field in the app config to prefer how the app should be triggered.

.PARAMETER Apps
    Array of app configuration objects. Each object should have properties defined in CONFIGURATION PROPERTIES below.

.PARAMETER ConfigFile
    Path to a JSON file containing app configurations.

.PARAMETER LogFile
    Optional path to log file for diagnostic output.

.EXAMPLE
    # Run with config file
    .\Start-AppsToTray.ps1 -ConfigFile .\my-apps.json

.EXAMPLE
    # Run with inline apps
    $apps = @(
        [pscustomobject]@{ Name = 'Tabby'; Path = 'C:\Program Files\Tabby\Tabby.exe'; StartAction = 'Hide'; WaitMs = 4000 }
    )
    .\Start-AppsToTray.ps1 -Apps $apps

.EXAMPLE
    # Use as library (dot-source to load functions)
    . .\Start-AppsToTray.ps1
    Start-AppsToTray -Apps $apps -LogFile $logPath

.CONFIGURATION PROPERTIES (per app)
    Name           - Friendly name (optional)
    Path           - Path to executable (required). Environment variables are expanded.
    Args           - Command-line args (optional)
    StartAction    - Preferred action: Auto (default) | Hide | Minimize | Close | ShowThenMinimize | None
    StartStyle     - Optional start style: Normal (default) | MinimizedProcess | HiddenProcess (controls Start-Process WindowStyle)
    RunAsAdmin     - Optional boolean: $true to request running the app elevated (will prompt UAC if current session is not elevated)
    RedirectOutput - Optional boolean: $true (default) to redirect stdout/stderr to null; will be disabled when launching elevated via UAC prompt
    WaitMs         - How long to wait for the tray behavior after applying action (ms). Default 5000
    TimeoutMs      - How long to wait for the app window to appear after launch (ms). Default 8000
    WindowTitleRegex - Optional regex pattern to match window title for complex process scenarios
    ProcessNameRegex - Optional regex pattern to match process name for child process detection

.NOTES
    - Behavior is "best-effort": some apps may not expose tray icons unless launched with their own
      --minimized/--tray command line or if they are installed with specific options.
    - Running apps that require elevation from a non-elevated session may fail to start.

#>
[CmdletBinding(DefaultParameterSetName='CustomApps')]
param(
    [Parameter(ParameterSetName='CustomApps', Mandatory=$true, Position=0)]
    [object[]]$Apps,
    
    [Parameter(ParameterSetName='ConfigFile', Mandatory=$true)]
    [string]$ConfigFile,
    
    [Parameter(ParameterSetName='CustomApps')]
    [Parameter(ParameterSetName='ConfigFile')]
    [string]$LogFile
)

# Add Win32 functions for window manipulation
try {
    # If the type already exists, referencing it will succeed; if not, the reference will throw and we'll create it.
    [Win32.NativeMethods] | Out-Null
} catch {
    Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

namespace Win32 {
    public class NativeMethods {
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr GetShellWindow();

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    }
}
"@ -PassThru
}

# Constants
$WS_SHOW = 5
$WS_HIDE = 0
$WS_MINIMIZE = 6
$WM_CLOSE = 0x0010
$WM_SYSCOMMAND = 0x0112
$SC_MINIMIZE = 0xF020
$SC_CLOSE = 0xF060

function Test-IsElevated {
    try {
        $wi = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $wp = New-Object System.Security.Principal.WindowsPrincipal($wi)
        return $wp.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Start-ProcessWithRedirect {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [string]$Arguments,
        [ValidateSet('Normal','Minimized','Hidden')] [string]$WindowStyle = 'Hidden'
    )
    # Use .NET Process class with CreateNoWindow for true console suppression
    # Default to Hidden to prevent window flash before minimize/hide actions
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    
    switch ($WindowStyle) {
        'Normal' { $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal }
        'Minimized' { $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized }
        'Hidden' { $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden }
    }
    
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    
    # Get the process ID before disposing
    $processId = $proc.Id
    
    # Dispose immediately to release all handles
    $proc.Dispose()
    
    # Return a fresh process object that just has the ID (no handles)
    return Get-Process -Id $processId -ErrorAction SilentlyContinue
}

function Start-ElevatedHelper {
    param(
        [Parameter(Mandatory)] [string]$ExePath,
        [Parameter(Mandatory=$false)] [string]$Arguments = '',
        [Parameter(Mandatory)][ValidateSet('Normal','Minimized','Hidden')] [string]$StartStyle = 'Normal'
    )

    # Record existing processes for this exe name so we can detect newly spawned child
    $exeName = [System.IO.Path]::GetFileNameWithoutExtension($ExePath)
    $existing = @(Get-Process -Name $exeName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)

    # Build inline PowerShell helper code that starts the target exe with redirected stdout/stderr to temp files
    $psHelper = @"
`$logFile = [System.IO.Path]::Combine(`$env:TEMP, "poshbits_elevated_helper_`$(Get-Date -Format 'yyyyMMdd_HHmmss').log")
function Write-HelperLog { param([string]`$msg) "`$(Get-Date -Format 'HH:mm:ss.fff') - `$msg" | Out-File -FilePath `$logFile -Append -Encoding UTF8 }

try {
    Write-HelperLog "Helper started. EXE=`$EXE, STARTSTYLE=`$STARTSTYLE"
    
    `$ARGS = ''
    if (`$ARGS64) {
        try {
            `$ARGS = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(`$ARGS64))
            Write-HelperLog "Arguments decoded: `$ARGS"
        } catch {
            Write-HelperLog "Failed to decode arguments: `$_"
        }
    }
    
    # Use .NET Process class with CreateNoWindow to suppress console windows
    # This works better than Start-Process -WindowStyle Hidden for console applications
    Write-HelperLog "Creating process with CreateNoWindow flag..."
    
    `$psi = New-Object System.Diagnostics.ProcessStartInfo
    `$psi.FileName = `$EXE
    if (`$ARGS) { `$psi.Arguments = `$ARGS }
    `$psi.UseShellExecute = `$false
    `$psi.CreateNoWindow = `$true
    
    switch (`$STARTSTYLE) {
        'Minimized' { `$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized }
        'Hidden' { `$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden }
        'Normal' { `$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal }
        default { `$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden }
    }
    
    `$process = New-Object System.Diagnostics.Process
    `$process.StartInfo = `$psi
    `$null = `$process.Start()
    
    Write-HelperLog "Process started successfully with CreateNoWindow (PID: `$(`$process.Id))"
    # Sleep to allow child processes to fully spawn and detach before this helper exits
    Start-Sleep -Seconds 5
    
    Write-HelperLog "Helper exiting"
    exit 0
} catch {
    Write-HelperLog "EXCEPTION: `$(`$_.Exception.Message)"
    Write-HelperLog "StackTrace: `$(`$_.Exception.StackTrace)"
    exit 1
}
"@

    # Encode the helper command so we don't create a script file
    $args64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Arguments))
    
    # Create a wrapper that captures ALL errors to a file
    $errorLogFile = Join-Path $env:TEMP "poshbits_elevated_error_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $fullScript = @"
`$ErrorActionPreference = 'Stop'
`$errorLog = '$($errorLogFile -replace "'","''")'
`$EXE='$($ExePath -replace "'","''")'
`$ARGS64='$args64'
`$STARTSTYLE='$StartStyle'

try {
    # Log start
    "Elevated script started at `$(Get-Date)" | Out-File -FilePath `$errorLog -Encoding UTF8
    "EXE: `$EXE" | Out-File -FilePath `$errorLog -Append
    "STARTSTYLE: `$STARTSTYLE" | Out-File -FilePath `$errorLog -Append
    
$psHelper
    
    "Elevated script completed successfully" | Out-File -FilePath `$errorLog -Append
} catch {
    "ERROR: `$(`$_.Exception.Message)" | Out-File -FilePath `$errorLog -Append
    "ERROR TYPE: `$(`$_.Exception.GetType().FullName)" | Out-File -FilePath `$errorLog -Append
    "STACK: `$(`$_.ScriptStackTrace)" | Out-File -FilePath `$errorLog -Append
    exit 1
}
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($fullScript))
    $pwsh = Join-Path $PSHOME 'pwsh.exe'

    # Write the helper script to a temporary file instead of using encoded command
    # This avoids issues with command length limits and encoding problems
    $helperScriptFile = Join-Path $env:TEMP "poshbits_elevated_helper_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
    $fullScript | Out-File -FilePath $helperScriptFile -Encoding UTF8 -Force
    
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log "Starting elevated helper from script file: $helperScriptFile"
    } else {
        Write-Verbose "Starting elevated helper from script file: $helperScriptFile"
    }
    
    try {
        $helperProc = Start-Process -FilePath $pwsh -ArgumentList ('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$helperScriptFile) -Verb RunAs -PassThru -ErrorAction Stop
        $helperPid = $null
        if ($helperProc) {
            $helperPid = $helperProc.Id
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Elevated helper process started: PID=$helperPid" } else { Write-Verbose "Elevated helper process started: PID=$helperPid" }
            # Dispose immediately to release handles
            $helperProc.Dispose()
            $helperProc = $null
        } else {
            Write-Warning "Start-Process returned null for elevated helper"
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Start-Process returned null for elevated helper" }
        }
        
        # Don't use background jobs - they prevent the script from exiting cleanly
        # The helper script file will be cleaned up manually or by temp folder cleanup
        
    } catch {
        Write-Warning "Failed to start elevated helper: $_"
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Failed to start elevated helper: $_" } else { Write-Verbose "Failed to start elevated helper: $_" }
        throw
    }

    # Wait for a new process with the exe name to appear. First try to find children of the helper via WMI (ParentProcessId), then fallback to scanning new same-named processes.
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $childPid = $null
    $timeoutMs = 30000
    $argProbe = $null
    try { if ($Arguments) { $argProbe = ($Arguments -replace '"','') } } catch { $argProbe = $null }

    $iterationCount = 0
    while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
        $iterationCount++
        
        # Fallback 1: detect any new process with the same name that wasn't present before (fastest)
        try {
            $candidates = @(Get-Process -Name $exeName -ErrorAction SilentlyContinue | Where-Object { $existing -notcontains $_.Id })
            if ($candidates.Count -gt 0) {
                $childPid = $candidates[0].Id
                if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                    Write-Log "Found elevated child PID=$childPid via process name match (iteration $iterationCount)"
                }
                break
            }
        } catch { }

        # Every 5th iteration, try WMI/CIM queries (slower but more reliable for parent-child relationships)
        if ($iterationCount % 5 -eq 0) {
            try {
                # Use WMI/CIM to query processes where ParentProcessId equals helper PID
                $wmiCandidates = Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $($helperProc.Id)" -ErrorAction SilentlyContinue -Verbose:$false
                if ($wmiCandidates) {
                    $match = $wmiCandidates | Where-Object { $_.Name -ieq "$exeName.exe" } | Select-Object -First 1
                    if ($match) {
                        $childPid = [int]$match.ProcessId
                        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                            Write-Log "Found elevated child PID=$childPid via parent-child relationship (iteration $iterationCount)"
                        }
                        break
                    }
                }
            } catch { }

            # Fallback 2: search Win32_Process commandline for a new process that contains a piece of the arguments
            if ($argProbe) {
                try {
                    $probe = $argProbe.Substring(0, [Math]::Min(40, $argProbe.Length))
                    $cmdMatches = Get-CimInstance -ClassName Win32_Process -Filter "Name = '$exeName.exe'" -ErrorAction SilentlyContinue -Verbose:$false | Where-Object { $existing -notcontains $_.ProcessId -and $_.CommandLine -and ($_.CommandLine -match [regex]::Escape($probe)) }
                    if ($cmdMatches.Count -gt 0) {
                        $childPid = [int]$cmdMatches[0].ProcessId
                        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                            Write-Log "Found elevated child PID=$childPid via command line match (iteration $iterationCount)"
                        }
                        break
                    }
                } catch { }
            }
        }

        Start-Sleep -Milliseconds 500
    }
    
    if (-not $childPid -and (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
        Write-Log "Child process detection completed after $iterationCount iterations ($($sw.ElapsedMilliseconds)ms) without finding child"
    }

    return [PSCustomObject]@{
        HelperProcess = $null  # Disposed to prevent hanging
        TempData = $null
        StdOutFile = $null
        StdErrFile = $null
        PidFile = $null
        ChildPid = $childPid
    }
}
function Get-MainWindowHandleFromProcessId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int]$ProcessId
    )
    $shell = [Win32.NativeMethods]::GetShellWindow()

    # Initialize in script scope so callback can modify it
    $script:foundHandle = [IntPtr]::Zero

    $callback = [Win32.NativeMethods+EnumWindowsProc]{
        param($hWnd, $lParam)

        $sb = New-Object -TypeName System.Text.StringBuilder -ArgumentList 256
        [Win32.NativeMethods]::GetWindowText($hWnd, $sb, $sb.Capacity) | Out-Null
        $title = $sb.ToString()

        [uint32]$winpid = 0
        [Win32.NativeMethods]::GetWindowThreadProcessId($hWnd, [ref]$winpid) | Out-Null

        if ($winpid -eq $ProcessId -and $hWnd -ne $shell) {
            # prefer visible top-level windows with titles
            if ([Win32.NativeMethods]::IsWindowVisible($hWnd) -and $title.Length -gt 0) {
                $script:foundHandle = $hWnd
                return $false # stop enumeration
            }
            # keep a candidate if no better choice otherwise
            if ($script:foundHandle -eq [IntPtr]::Zero) { $script:foundHandle = $hWnd }
        }
        return $true
    }

    [Win32.NativeMethods]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null

    $result = $script:foundHandle
    # Clean up script-scoped variable
    $script:foundHandle = $null
    
    # Ensure we always return an IntPtr, never null
    if ($null -eq $result) { return [IntPtr]::Zero }
    return $result
}

function Set-WindowState {
    param(
        [Parameter(Mandatory)] [ValidateSet('FORCEMINIMIZE','HIDE','MAXIMIZE','MINIMIZE','RESTORE','SHOW','SHOWDEFAULT','SHOWMAXIMIZED','SHOWMINIMIZED','SHOWMINNOACTIVE','SHOWNA','SHOWNOACTIVATE','SHOWNORMAL')]$State = 'HIDE',
        [Parameter(Mandatory)] [System.IntPtr]$MainWindowHandle
    )

    $WindowStates = @{
        'FORCEMINIMIZE' = 11
        'HIDE' = 0
        'MAXIMIZE' = 3
        'MINIMIZE' = 6
        'RESTORE' = 9
        'SHOW' = 5
        'SHOWDEFAULT' = 10
        'SHOWMAXIMIZED' = 3
        'SHOWMINIMIZED' = 2
        'SHOWMINNOACTIVE' = 7
        'SHOWNA' = 8
        'SHOWNOACTIVATE' = 4
        'SHOWNORMAL' = 1
    }

    [Win32.NativeMethods]::ShowWindowAsync($MainWindowHandle, [int]$WindowStates[$State]) | Out-Null
}

function Wait-ForWindow {
    param(
        [Parameter(Mandatory)] [int]$ProcessId,
        [int]$TimeoutMs = 8000,
        [int]$PollMs = 200
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        $h = Get-MainWindowHandleFromProcessId -ProcessId $ProcessId
        if ($h -ne [IntPtr]::Zero) { return $h }
        Start-Sleep -Milliseconds $PollMs
    }
    return [IntPtr]::Zero
}

function Apply-ActionToWindow {
    param(
        [Parameter(Mandatory)] [System.IntPtr]$Handle,
        [Parameter(Mandatory)] [ValidateSet('Hide','Minimize','Close','ShowThenMinimize')] [string]$Action
    )

    switch ($Action) {
        'Hide' { Set-WindowState -State 'HIDE' -MainWindowHandle $Handle }
        'Minimize' {
            # Try multiple minimize methods (best-effort): ShowWindowAsync, PostMessage SC_MINIMIZE, then force minimize
            try { Set-WindowState -State 'MINIMIZE' -MainWindowHandle $Handle } catch {}
            try { [Win32.NativeMethods]::PostMessage($Handle, $WM_SYSCOMMAND, [IntPtr]$SC_MINIMIZE, [IntPtr]0) | Out-Null } catch {}
            Start-Sleep -Milliseconds 150
            try { Set-WindowState -State 'FORCEMINIMIZE' -MainWindowHandle $Handle } catch {}
        }
        'Close' { [Win32.NativeMethods]::PostMessage($Handle, $WM_CLOSE, [IntPtr]0, [IntPtr]0) | Out-Null }
        'ShowThenMinimize' { Set-WindowState -State 'SHOW' -MainWindowHandle $Handle; Start-Sleep -Milliseconds 300; Set-WindowState -State 'MINIMIZE' -MainWindowHandle $Handle; Start-Sleep -Milliseconds 150; [Win32.NativeMethods]::PostMessage($Handle, $WM_SYSCOMMAND, [IntPtr]$SC_MINIMIZE, [IntPtr]0) | Out-Null }
    }
}

function Wait-ForHiddenOrExit {
    param(
        [Parameter(Mandatory)] [int]$ProcessId,
        [int]$TimeoutMs = 5000,
        [int]$PollMs = 300
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        try {
            $proc = Get-Process -Id $ProcessId -ErrorAction Stop
        } catch { return $true } # process exited

        $h = Get-MainWindowHandleFromProcessId -ProcessId $ProcessId
        if ($h -eq [IntPtr]::Zero) { return $true }
        # if window exists but is not visible
        if (-not [Win32.NativeMethods]::IsWindowVisible($h)) { return $true }

        Start-Sleep -Milliseconds $PollMs
    }
    return $false
}

function Start-AppsToTray {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)] [System.Object[]]$Apps,
        [Parameter(Mandatory = $false)] [string]$ConfigFile,
        [Parameter(Mandatory = $false)] [string]$LogFile,
        [switch]$WhatIf
    )

    function Write-Log {
        param([string]$Message)
        if ($LogFile) {
            "$((Get-Date).ToString('o')) - $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
        }
    }

    if ($ConfigFile) {
        if (-not (Test-Path $ConfigFile)) { throw "Config file not found: $ConfigFile" }
        $ext = [System.IO.Path]::GetExtension($ConfigFile).ToLowerInvariant()
        if ($ext -in '.json') { $Apps = Get-Content $ConfigFile -Raw | ConvertFrom-Json }
        elseif ($ext -in '.ps1') { . $ConfigFile; if (-not $apps) { throw "Script did not define `$apps` variable." } }
        else { throw "Unsupported config file type: $ext. Use .json or .ps1." }
    }

    if (-not $Apps -or $Apps.Count -eq 0) { Write-Verbose 'No apps provided'; return }

    # Phase 1: Launch all apps immediately
    $launchedApps = @()
    
    foreach ($app in $Apps) {
        Write-Log "Processing app object: $([System.Uri]::EscapeDataString(($app | ConvertTo-Json -Compress)))"

        # Evaluate fields (avoid complex inline expressions inside hashtable for compatibility)
        $name = if ($app -and $app.PSObject.Properties.Match('Name') -and $app.Name) { $app.Name } else { [System.IO.Path]::GetFileNameWithoutExtension($app.Path) }
        $path = if ($app -and $app.PSObject.Properties.Match('Path') -and $app.Path) { [Environment]::ExpandEnvironmentVariables($app.Path) } else { $null }
        $args = if ($app -and $app.PSObject.Properties.Match('Args')) { $app.Args } else { $null }
        $startAction = if ($app -and $app.PSObject.Properties.Match('StartAction') -and $app.StartAction) { $app.StartAction } else { 'Auto' }
        $waitMs = if ($app -and $app.PSObject.Properties.Match('WaitMs') -and $app.WaitMs) { $app.WaitMs } else { 5000 }
        $timeoutMs = if ($app -and $app.PSObject.Properties.Match('TimeoutMs') -and $app.TimeoutMs) { $app.TimeoutMs } else { 8000 }
        $spawnDelayMs = if ($app -and $app.PSObject.Properties.Match('SpawnDelayMs') -and $app.SpawnDelayMs) { $app.SpawnDelayMs } else { 250 }
        $startStyle = if ($app -and $app.PSObject.Properties.Match('StartStyle') -and $app.StartStyle) { $app.StartStyle } else { 'Normal' }

        # Precompute optional booleans to avoid inline if expressions in hashtable
        $runAsAdmin = if ($app -and $app.PSObject.Properties.Match('RunAsAdmin')) { [bool]$app.RunAsAdmin } else { $false }
        $redirectOutput = if ($app -and $app.PSObject.Properties.Match('RedirectOutput')) { [bool]$app.RedirectOutput } else { $true }
        
        # Extract optional regex patterns for process matching
        $windowTitleRegex = if ($app -and $app.PSObject.Properties.Match('WindowTitleRegex') -and $app.WindowTitleRegex) { $app.WindowTitleRegex } else { $null }
        $processNameRegex = if ($app -and $app.PSObject.Properties.Match('ProcessNameRegex') -and $app.ProcessNameRegex) { $app.ProcessNameRegex } else { $null }

        $appObj = [PSCustomObject]@{
            Name = $name
            Path = $path
            Args = $args
            StartAction = $startAction
            WaitMs = $waitMs
            TimeoutMs = $timeoutMs
            SpawnDelayMs = $spawnDelayMs
            StartStyle = $startStyle
            RunAsAdmin = $runAsAdmin
            RedirectOutput = $redirectOutput
            WindowTitleRegex = $windowTitleRegex
            ProcessNameRegex = $processNameRegex
        }

        Write-Verbose "Starting '$($appObj.Name)' -> $($appObj.Path) $($appObj.Args)"
        Write-Log "Starting '$($appObj.Name)' -> $($appObj.Path) $($appObj.Args)"

        if ($WhatIf) { Write-Output "WhatIf: Start $($appObj.Path) $($appObj.Args) with action $($appObj.StartAction)"; continue }

        try {
            $startParams = @{ FilePath = $appObj.Path; ArgumentList = $appObj.Args; PassThru = $true }
            # Allow per-app StartStyle to request starting the process minimized/hidden
            switch ($appObj.StartStyle) {
                'MinimizedProcess' { $startParams.WindowStyle = 'Minimized' }
                'HiddenProcess' { $startParams.WindowStyle = 'Hidden' }
                default { }
            }

            # Use the precomputed values from $appObj
            if ($appObj.RunAsAdmin -and -not (Test-IsElevated)) {
                # Need to prompt UAC; if RedirectOutput is requested, start an elevated helper that performs the redirection
                if ($appObj.RedirectOutput) {
                                    if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Starting elevated helper for $($appObj.Name) to capture stdout/stderr to files." } else { Write-Verbose "Starting elevated helper for $($appObj.Name) to capture stdout/stderr to files." }
                    try {
                        $helperInfo = Start-ElevatedHelper -ExePath $appObj.Path -Arguments $appObj.Args -StartStyle ($appObj.StartStyle -eq 'MinimizedProcess' ? 'Minimized' : ($appObj.StartStyle -eq 'HiddenProcess' ? 'Hidden' : 'Normal'))
                        if ($helperInfo.ChildPid) {
                            if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Elevated child process started PID=$($helperInfo.ChildPid); stdout=$($helperInfo.StdOutFile); stderr=$($helperInfo.StdErrFile)" } else { Write-Verbose "Elevated child process started PID=$($helperInfo.ChildPid)" }
                            # Set $proc to a Process object so the rest of the flow can use it where possible
                            try { $proc = Get-Process -Id $helperInfo.ChildPid -ErrorAction SilentlyContinue } catch { $proc = $null }
                        } else {
                            Write-Warning "Elevated helper started but child PID not observed within timeout for $($appObj.Name)."
                            
                            # Check for error log files from the elevated session
                            $errorLogs = Get-ChildItem -Path $env:TEMP -Filter "poshbits_elevated_error_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                            if ($errorLogs) {
                                Write-Warning "Found elevated session error log:"
                                $errorContent = Get-Content $errorLogs.FullName -Raw -ErrorAction SilentlyContinue
                                if ($errorContent) {
                                    Write-Warning $errorContent
                                    if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Elevated error log: $errorContent" }
                                }
                            }
                            
                            # Check for helper log files to diagnose the issue
                            $helperLogs = Get-ChildItem -Path $env:TEMP -Filter "poshbits_elevated_helper_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                            if ($helperLogs) {
                                $logContent = Get-Content $helperLogs.FullName -Raw -ErrorAction SilentlyContinue
                                if ($logContent) {
                                    Write-Warning "Elevated helper log content:"
                                    Write-Warning $logContent
                                    if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Elevated helper log: $logContent" }
                                }
                            }
                            
                            if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Elevated helper started but child PID not observed within timeout for $($appObj.Name). TempDir: $($helperInfo.TempDir)" } else { Write-Verbose "Elevated helper started but child PID not observed within timeout for $($appObj.Name)." }
                            $proc = $null
                        }
                    } catch {
                        Write-Warning "Failed to start elevated helper for $($appObj.Name): $_"
                        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Failed to start elevated helper for $($appObj.Name): $_" } else { Write-Verbose "Failed to start elevated helper for $($appObj.Name): $_" }
                        continue
                    }
                } else {
                    Write-Log "Starting $($appObj.Name) elevated via Shell (UAC will prompt). RedirectOutput disabled for this launch."
                    try {
                        # When running elevated without redirect, we can't suppress output but we try to minimize console visibility
                        $p = Start-Process -FilePath $appObj.Path -ArgumentList $appObj.Args -Verb RunAs -PassThru -WindowStyle Hidden -ErrorAction Stop
                        if ($p) {
                            $processId = $p.Id
                            Write-Log "Elevated process started PID=$processId"
                            # Dispose the process handle immediately to prevent hanging
                            $p.Dispose()
                            # Get a fresh process object without holding handles
                            $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
                        } else {
                            # Some versions may not return a process - attempt to find the process by name
                            $exeName = [System.IO.Path]::GetFileNameWithoutExtension($appObj.Path)
                            $found = $false
                            $sw = [Diagnostics.Stopwatch]::StartNew()
                            while ($sw.ElapsedMilliseconds -lt 10000) {
                                $candidates = Get-Process -Name $exeName -ErrorAction SilentlyContinue
                                if ($candidates) { $proc = $candidates | Select-Object -First 1; $found = $true; Write-Log "Found elevated process PID=$($proc.Id) for $exeName"; break }
                                Start-Sleep -Milliseconds 200
                            }
                            if (-not $found) { Write-Warning "Could not find elevated process for $exeName after UAC launch"; Write-Log "Could not find elevated process for $exeName after UAC launch" }
                        }
                    } catch {
                        Write-Warning "Failed to start elevated $($appObj.Name): $_"
                        Write-Log "Failed to start elevated $($appObj.Name): $_"
                        continue
                    }
                }
            } else {
                if ($redirectOutput) {
                    try {
                        $proc = Start-ProcessWithRedirect -FilePath $appObj.Path -Arguments $appObj.Args -WindowStyle ($appObj.StartStyle -eq 'MinimizedProcess' ? 'Minimized' : 'Normal')
                        Write-Log "Started process PID=$($proc.Id) (with redirected output)"
                    } catch {
                        Write-Warning "Failed to start with redirected output: $_. Falling back to Start-Process."
                        Write-Log "Failed to start with redirected output: $_. Falling back to Start-Process."
                        $proc = Start-Process @startParams -ErrorAction Stop
                        Write-Log "Started process PID=$($proc.Id)"
                    }
                } else {
                    $proc = Start-Process @startParams -ErrorAction Stop
                    Write-Log "Started process PID=$($proc.Id)"
                }
            }
        } catch {
            Write-Warning "Failed to start $($appObj.Name): $_"
            Write-Log "Failed to start $($appObj.Name): $_"
            continue
        }

        # Verify we have a valid process object
        if (-not $proc -or -not $proc.Id) {
            Write-Warning "No valid process object returned for $($appObj.Name)"
            Write-Log "No valid process object returned for $($appObj.Name)"
            continue
        }

        Write-Verbose "Process started with PID=$($proc.Id)"
        Write-Log "Process started with PID=$($proc.Id)"

        # Store app info for phase 2 (window management)
        $launchedApps += [PSCustomObject]@{
            AppObj = $appObj
            Process = $proc
        }
    }
    
    # Phase 2: Wait for windows and apply actions in parallel using background jobs
    Write-Verbose "All apps launched. Starting parallel window detection..."
    Write-Log "All apps launched. Starting parallel window detection..."
    
    # Prepare the NativeMethods type definition to pass to jobs
    $nativeMethodsTypeDef = @"
using System;
using System.Text;
using System.Runtime.InteropServices;

namespace Win32 {
    public class NativeMethods {
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr GetShellWindow();

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
        
        [DllImport("user32.dll", SetLastError = true)]
        public static extern int GetWindowTextLength(IntPtr hWnd);
    }
}
"@
    
    $jobs = @()
    foreach ($launchedApp in $launchedApps) {
        $appObj = $launchedApp.AppObj
        $proc = $launchedApp.Process
        
        # Skip window management if StartAction is 'None'
        if ($appObj.StartAction -eq 'None') {
            Write-Verbose "StartAction is 'None' - skipping window management for $($appObj.Name)"
            Write-Log "StartAction is 'None' - skipping window management for $($appObj.Name)"
            # Dispose process object
            if ($proc) { try { $proc.Dispose() } catch { } }
            continue
        }
        
        # Create background job to wait for window and apply action
        $job = Start-Job -ScriptBlock {
            param($procId, $appObj, $LogFile, $NativeMethodsType)
            
            function Write-JobLog {
                param([string]$Message)
                if ($LogFile) {
                    "$((Get-Date).ToString('o')) - [Job] $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
                }
            }
            
            # Re-import the NativeMethods type in this job
            if ($NativeMethodsType) {
                try {
                    Add-Type -TypeDefinition $NativeMethodsType -ErrorAction SilentlyContinue
                } catch { }
            }
            
            # Import the helper functions (simplified versions for the job)
            . {
                function Get-MainWindowHandleFromProcessId {
                    param([Parameter(Mandatory)] [int]$ProcessId)
                    $script:foundHandle = [IntPtr]::Zero
                    $callback = {
                        param([IntPtr]$hwnd, [IntPtr]$lParam)
                        $pid = 0
                        [Win32.NativeMethods]::GetWindowThreadProcessId($hwnd, [ref]$pid) | Out-Null
                        if ($pid -eq $ProcessId -and [Win32.NativeMethods]::IsWindowVisible($hwnd)) {
                            $length = [Win32.NativeMethods]::GetWindowTextLength($hwnd)
                            if ($length -gt 0) {
                                $script:foundHandle = $hwnd
                                return $false
                            }
                        }
                        return $true
                    }
                    [Win32.NativeMethods]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
                    return $script:foundHandle
                }
                
                function Wait-ForWindow {
                    param([Parameter(Mandatory)] [int]$ProcessId, [int]$TimeoutMs = 5000)
                    $sw = [Diagnostics.Stopwatch]::StartNew()
                    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
                        $handle = Get-MainWindowHandleFromProcessId -ProcessId $ProcessId
                        if ($handle -ne [IntPtr]::Zero) { return $handle }
                        Start-Sleep -Milliseconds 200
                    }
                    return [IntPtr]::Zero
                }
                
                function Apply-ActionToWindow {
                    param([Parameter(Mandatory)] [IntPtr]$Handle, [Parameter(Mandatory)] [string]$Action)
                    switch ($Action) {
                        'Hide' { [Win32.NativeMethods]::ShowWindowAsync($Handle, 0) | Out-Null }
                        'Minimize' { [Win32.NativeMethods]::ShowWindowAsync($Handle, 6) | Out-Null }
                        'Close' { [Win32.NativeMethods]::PostMessage($Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null }
                        'ShowThenMinimize' { [Win32.NativeMethods]::ShowWindowAsync($Handle, 1) | Out-Null; Start-Sleep -Milliseconds 100; [Win32.NativeMethods]::ShowWindowAsync($Handle, 6) | Out-Null }
                    }
                }
                
                function Wait-ForHiddenOrExit {
                    param([Parameter(Mandatory)] [int]$ProcessId, [int]$TimeoutMs = 5000)
                    $sw = [Diagnostics.Stopwatch]::StartNew()
                    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
                        try { $proc = Get-Process -Id $ProcessId -ErrorAction Stop } catch { return $true }
                        $h = Get-MainWindowHandleFromProcessId -ProcessId $ProcessId
                        if ($h -eq [IntPtr]::Zero) { return $true }
                        if (-not [Win32.NativeMethods]::IsWindowVisible($h)) { return $true }
                        Start-Sleep -Milliseconds 300
                    }
                    return $false
                }
            }
            
            Write-JobLog "Waiting for window (PID=$procId, Timeout=$($appObj.TimeoutMs)ms)..."
            $handle = Wait-ForWindow -ProcessId $procId -TimeoutMs $appObj.TimeoutMs
            
            Write-JobLog "After Wait-ForWindow: handle=$handle, IsZero=$($handle -eq [IntPtr]::Zero)"
            
            # If no handle yet, search for child/related processes
            if ($handle -eq [IntPtr]::Zero) {
                Write-JobLog "Searching for child/related processes..."
                $exeName = [System.IO.Path]::GetFileNameWithoutExtension($appObj.Path)
                
                $sw = [Diagnostics.Stopwatch]::StartNew()
                while ($sw.ElapsedMilliseconds -lt 3000) {
                    # Search by process name
                    $candidates = Get-Process -Name $exeName -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $procId }
                    if ($candidates) {
                        foreach ($candidate in $candidates) {
                            $candidateHandle = Get-MainWindowHandleFromProcessId -ProcessId $candidate.Id
                            if ($candidateHandle -ne [IntPtr]::Zero) {
                                $handle = $candidateHandle
                                $procId = $candidate.Id
                                Write-JobLog "Found window in related process PID=$procId"
                                break
                            }
                        }
                        if ($handle -ne [IntPtr]::Zero) { break }
                    }
                    
                    # Search by window title/process name regex
                    if ($appObj.WindowTitleRegex -or $appObj.ProcessNameRegex) {
                        $candidates = Get-Process -ErrorAction SilentlyContinue | Where-Object {
                            $_.MainWindowHandle -ne 0 -and (
                                ($appObj.WindowTitleRegex -and $_.MainWindowTitle -imatch $appObj.WindowTitleRegex) -or
                                ($appObj.ProcessNameRegex -and $_.ProcessName -imatch $appObj.ProcessNameRegex)
                            )
                        }
                        if ($candidates) {
                            $actualProc = $candidates | Select-Object -First 1
                            $handle = [IntPtr]::new([int64]$actualProc.MainWindowHandle)
                            $procId = $actualProc.Id
                            Write-JobLog "Found process by regex: PID=$procId, Title='$($actualProc.MainWindowTitle)'"
                            break
                        }
                    }
                    
                    Start-Sleep -Milliseconds 200
                }
            }
            
            if ($handle -eq [IntPtr]::Zero) {
                Write-JobLog "No window found for $($appObj.Name) after $($appObj.TimeoutMs)ms"
                return @{ Success = $false; AppName = $appObj.Name }
            }
            
            Write-JobLog "Initial handle: $handle"
            
            # Apply window actions
            $actionsToTry = switch ($appObj.StartAction) {
                'Hide' { @('Hide') }
                'Minimize' { @('Minimize','Hide') }
                'Close' { @('Close','Hide') }
                'ShowThenMinimize' { @('ShowThenMinimize','Minimize','Hide') }
                default { @('Hide','Minimize','Close') }
            }
            
            $succeeded = $false
            foreach ($action in $actionsToTry) {
                Write-JobLog "Applying action '$action' to $($appObj.Name)"
                Apply-ActionToWindow -Handle $handle -Action $action
                Start-Sleep -Milliseconds 200
                
                $ok = Wait-ForHiddenOrExit -ProcessId $procId -TimeoutMs $appObj.WaitMs
                if ($ok) { $succeeded = $true; break }
                
                $handle = Get-MainWindowHandleFromProcessId -ProcessId $procId
                if ($handle -eq [IntPtr]::Zero) { $succeeded = $true; break }
            }
            
            if ($succeeded) {
                Write-JobLog "$($appObj.Name) now hidden/handled"
            } else {
                Write-JobLog "Could not hide $($appObj.Name) within configured time"
            }
            
            return @{ Success = $succeeded; AppName = $appObj.Name }
        } -ArgumentList $proc.Id, $appObj, $LogFile, $nativeMethodsTypeDef
        
        $jobs += [PSCustomObject]@{
            Job = $job
            AppName = $appObj.Name
        }
        
        # Dispose process object immediately after starting job
        if ($proc) { try { $proc.Dispose() } catch { } }
    }
    
    # Wait for all jobs to complete
    if ($jobs.Count -gt 0) {
        Write-Verbose "Waiting for $($jobs.Count) window management job(s) to complete..."
        Write-Log "Waiting for $($jobs.Count) window management job(s) to complete..."
        
        $null = Wait-Job -Job $jobs.Job -Timeout 120
        
        foreach ($jobInfo in $jobs) {
            $result = Receive-Job -Job $jobInfo.Job -ErrorAction SilentlyContinue
            if ($result -and $result.Success) {
                Write-Verbose "$($jobInfo.AppName) completed successfully"
            } else {
                Write-Verbose "$($jobInfo.AppName) completed with issues"
            }
            Remove-Job -Job $jobInfo.Job -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Force garbage collection to release any remaining handles
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}


#region Script Execution
# This block runs when the script is executed directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    # Determine which apps to launch
    $appsToLaunch = $null
    
    switch ($PSCmdlet.ParameterSetName) {
        'CustomApps' {
            $appsToLaunch = $Apps
            Write-Verbose "Using apps provided via -Apps parameter"
        }
        'ConfigFile' {
            if (Test-Path $ConfigFile) {
                $appsToLaunch = Get-Content $ConfigFile -Raw | ConvertFrom-Json
                Write-Verbose "Loaded apps from config file: $ConfigFile"
            } else {
                Write-Error "Config file not found: $ConfigFile"
                exit 1
            }
        }
        'DefaultApps' {
            # Validate that default apps paths exist
            $missingApps = @()
            foreach ($app in $DefaultApps) {
                $expandedPath = [System.Environment]::ExpandEnvironmentVariables($app.Path)
                if (-not (Test-Path $expandedPath)) {
                    $missingApps += "$($app.Name): $expandedPath"
                }
            }
            
            if ($missingApps.Count -gt 0) {
                Write-Warning "Some default apps were not found:"
                $missingApps | ForEach-Object { Write-Warning "  - $_" }
                Write-Warning "`nEdit the `$DefaultApps section in this script to configure your apps,"
                Write-Warning "or use -Apps or -ConfigFile parameters to specify apps."
                
                # Filter to only existing apps
                $appsToLaunch = $DefaultApps | Where-Object {
                    $expandedPath = [System.Environment]::ExpandEnvironmentVariables($_.Path)
                    Test-Path $expandedPath
                }
                
                if ($appsToLaunch.Count -eq 0) {
                    Write-Error "No valid apps to launch. Please configure apps in the script or use -Apps/-ConfigFile parameters."
                    exit 1
                }
                
                Write-Host "`nLaunching $($appsToLaunch.Count) available app(s)..." -ForegroundColor Cyan
            } else {
                $appsToLaunch = $DefaultApps
                Write-Verbose "Using default apps configuration"
            }
        }
    }
    
    # Set default log file if not provided
    if (-not $LogFile) {
        $LogFile = Join-Path $env:TEMP "Start-AppsToTray_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    "Name": "MyApp",
    "Path": "C:\\Program Files\\MyApp\\MyApp.exe",
    "StartAction": "Minimize",
    "RunAsAdmin": false,
    "RedirectOutput": true,
    "WaitMs": 3000,
    "TimeoutMs": 8000
  }
]

Then run: .\Start-AppsToTray.ps1 -ConfigFile .\apps.json

## Using as Library:
Dot-source to load functions without execution:
. .\Start-AppsToTray.ps1
$apps = @([pscustomobject]@{ Name='Test'; Path='calc.exe'; StartAction='Minimize' })
Start-AppsToTray -Apps $apps

#>Using Config File (Recommended):
Create a JSON file (e.g., my-apps.json):
[
  {
    "Name": "MyApp",
    "Path": "C:\\Program Files\\MyApp\\MyApp.exe",
    "StartAction": "Minimize",
    "RunAsAdmin": false,
    "RedirectOutput": true,
    "WaitMs": 3000,
    "TimeoutMs": 8000
  }
]

Then run: .\Start-AppsToTray.ps1 -ConfigFile .\my-apps.json

## Using Inline Apps:
$apps = @(
    [pscustomobject]@{ 
        Name = 'Calculator'
        Path = 'C:\Windows\System32\calc.exe'
        StartAction = 'Minimize'
        WaitMs = 2000
    }
)
.\Start-AppsToTray.ps1 -Apps $apps

## Using as Library:
Dot-source to load functions without execution:
. .\Start-AppsToTray.ps1
$apps = @([pscustomobject]@{ Name='Test'; Path='calc.exe'; StartAction='Minimize' })
Start-AppsToTray -Apps $apps -LogFile $logPath