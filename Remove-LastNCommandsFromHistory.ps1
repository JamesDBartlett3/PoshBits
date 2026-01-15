param (
    [int]$NumberOfCommands
)

$historyFile = $(Get-PSReadlineOption).HistorySavePath

if (-not (Test-Path -Path $historyFile)) {
    Write-Error "History file not found at '$historyFile'"
    exit 1
}

try {
    $historyContent = Get-Content $historyFile
	$newHistoryContent = ($historyContent | Select-Object -SkipLast ($NumberOfCommands + 1))
	$newHistoryContent | Set-Content $historyFile
    Write-Host "Removed the last $NumberOfCommands commands from history."
} catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    exit 1
}