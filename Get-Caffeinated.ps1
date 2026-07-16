<#
.SYNOPSIS
    Keeps the system from sleeping/locking, using either SetThreadExecutionState
    (default) or simulated keypresses (if -Key is specified).

.DESCRIPTION
    Default behavior calls SetThreadExecutionState with ES_CONTINUOUS |
    ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED, which tells the OS the machine
    is actively in use. This prevents the display timeout, sleep, and machine
    inactivity lock timer, without touching the console's input buffer.

    If -Key is specified, the script instead uses SendKeys to simulate a
    keypress, and does NOT call SetThreadExecutionState. This exists for
    cases where SetThreadExecutionState alone isn't sufficient (e.g. some
    third-party lock/idle tools watch for real input rather than the power
    API), at the cost of a small race window around the "press any key to
    stop" detection (see below).

    Exits cleanly on any keypress and always resets execution state on exit
    (normal, keypress, or Ctrl+C) if SetThreadExecutionState was used.

.PARAMETER Key
    The key to simulate via SendKeys. If omitted, the script uses
    SetThreadExecutionState instead and never sends synthetic input.
    - Single character: A, B, 1, or " " (space)
    - Named key: Space, UP, DOWN, F16 (auto-wrapped to {SPACE}, {UP}, etc.)
    - Already wrapped: {ENTER}, {UP} (passed as-is)
    - With modifiers: ^A (Ctrl+A), +{UP} (Shift+Up), %{F4} (Alt+F4)

.PARAMETER Delay
    Seconds between refresh cycles. Default 60.

.PARAMETER ResetOnly
    Skip everything else and just clear any previously-set execution state.
    Use this after a crashed or force-closed session to make sure the
    ES_SYSTEM_REQUIRED / ES_DISPLAY_REQUIRED flags aren't still asserted
    by a dead thread handle. Has no effect if you were using -Key, since
    that mode never sets execution state in the first place.

.EXAMPLE
    .\Get-Caffeinated.ps1
    Default: SetThreadExecutionState only, refreshed every 60s.

.EXAMPLE
    .\Get-Caffeinated.ps1 -Key F16
    Uses simulated F16 keypresses instead, every 60s.

.EXAMPLE
    .\Get-Caffeinated.ps1 -ResetOnly
    Clears any leftover execution-state flags without running the loop.
#>

param(
    [string]$Key,
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Delay = 60,
    [switch]$ResetOnly
)

Add-Type -Namespace Win32 -Name PowerUtil -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern uint SetThreadExecutionState(uint esFlags);
'@

$ES_CONTINUOUS       = [uint32]0x80000000L
$ES_SYSTEM_REQUIRED  = [uint32]0x00000001L
$ES_DISPLAY_REQUIRED = [uint32]0x00000002L

if ($ResetOnly) {
    $result = [Win32.PowerUtil]::SetThreadExecutionState($ES_CONTINUOUS)
    if ($result -eq 0) {
        Write-Warning "SetThreadExecutionState failed to reset. GetLastError not surfaced by this P/Invoke signature; re-run elevated if the issue persists."
        exit 1
    }
    Write-Host "Execution state reset. Any leftover system/display-required assertion has been cleared." -ForegroundColor Yellow
    exit 0
}

$usingKeyPress = -not [string]::IsNullOrWhiteSpace($Key)

if ($usingKeyPress) {
    Add-Type -AssemblyName System.Windows.Forms
    if ($Key -notmatch '^\{.*\}$' -and $Key.Length -gt 1 -and $Key -notmatch '^[\^+%]') {
        $Key = "{$Key}"
    }
}

# Flush any buffered keystrokes so a stray leftover keypress doesn't
# immediately end the session the moment it starts.
$Host.UI.RawUI.FlushInputBuffer()

# Poll in ticks so keypress response is bounded, but only fire the
# execution-state / SendKeys refresh once per $Delay seconds. Clamp the
# poll interval to $Delay so a short -Delay isn't bottlenecked by a
# poll interval longer than the cycle itself.
$pollInterval = [math]::Min(5, $Delay)
$ticksPerDelay = [math]::Max(1, [int]($Delay / $pollInterval))

if ($usingKeyPress) {
    Write-Host "Keeping system awake via simulated '$Key' keypress every $Delay s." -ForegroundColor Green
} else {
    Write-Host "Keeping system awake via SetThreadExecutionState (refresh every $Delay s)." -ForegroundColor Green
}
Write-Host "Press any key to stop (may take up to $pollInterval seconds to respond)." -ForegroundColor Green

try {
    $stop = $false
    while (-not $stop) {
        if ($usingKeyPress) {
            [System.Windows.Forms.SendKeys]::SendWait($Key) | Out-Null
            # SendWait delivers into this console's own input buffer since it
            # has focus; flush immediately so the polling loop below doesn't
            # mistake the synthetic press for a real "stop" keypress.
            $Host.UI.RawUI.FlushInputBuffer()
        } else {
            $result = [Win32.PowerUtil]::SetThreadExecutionState($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED -bor $ES_DISPLAY_REQUIRED)
            if ($result -eq 0) {
                Write-Warning "SetThreadExecutionState failed (GetLastError not surfaced by this P/Invoke signature)."
            }
        }

        for ($i = 0; $i -lt $ticksPerDelay; $i++) {
            if ($Host.UI.RawUI.KeyAvailable) {
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                $stop = $true
                Write-Host "Keypress detected, exiting." -ForegroundColor Yellow
                break
            }
            Start-Sleep -Seconds $pollInterval
        }
    }
}
finally {
    if (-not $usingKeyPress) {
        [Win32.PowerUtil]::SetThreadExecutionState($ES_CONTINUOUS) | Out-Null
    }
}