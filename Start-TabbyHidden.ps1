function Set-WindowState {
# Source of this function: https://gist.github.com/prasannavl/effd901e2460a651ad2c
    param(
    [Parameter()]
    [ValidateSet('FORCEMINIMIZE', 'HIDE', 'MAXIMIZE', 'MINIMIZE', 'RESTORE',
    'SHOW', 'SHOWDEFAULT', 'SHOWMAXIMIZED', 'SHOWMINIMIZED',
    'SHOWMINNOACTIVE', 'SHOWNA', 'SHOWNOACTIVATE', 'SHOWNORMAL')]
    $State = 'SHOW',
    [Parameter()]
    $MainWindowHandle = (Get-Process -id $pid).MainWindowHandle
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
    $Win32ShowWindowAsync = Add-Type -name "Win32ShowWindowAsync" -namespace Win32Functions -passThru -memberDefinition '
    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    '
    $Win32ShowWindowAsync::ShowWindowAsync($MainWindowHandle, $WindowStates[($State)]) | Out-Null
    Write-Verbose ("Set Window Style on $MainWindowHandle to $State") 
}

Start-Process Tabby
Start-Sleep -Seconds 5
Set-WindowState -State HIDE -MainWindowHandle ((Get-Process Tabby).MainWindowHandle | Sort-Object -Descending | Select-Object -First 1)
