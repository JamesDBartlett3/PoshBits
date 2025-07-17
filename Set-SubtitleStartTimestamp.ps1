# Usage: .\sync-vtt.ps1 -InputFile "input.vtt" -OutputFile "output.vtt" -Offset "00:03:19.000"

param(
    [Parameter()][string]$InputFile,
    [Parameter()][string]$OutputFile,
    [Parameter()][string]$Offset = "00:00:00.000"
)

if (-not (Test-Path $InputFile)) {
    Write-Error "Input file '$InputFile' does not exist."
    exit 1
}

function Split-Time($str) {
    $parts = $str -split ":", 3
    $secParts = $parts[2] -split "\.", 2
    $hours = [int]$parts[0]
    $minutes = [int]$parts[1] 
    $seconds = [int]$secParts[0]
    $milliseconds = [int]$secParts[1]
    
    return New-TimeSpan -Hours $hours -Minutes $minutes -Seconds $seconds -Milliseconds $milliseconds
}

function Format-Time($ts) {
    $h = $ts.Hours.ToString("00")
    $m = $ts.Minutes.ToString("00")
    $s = $ts.Seconds.ToString("00")
    $ms = $ts.Milliseconds.ToString("000")
    "$h`:$m`:$s.$ms"
}

$offset = [TimeSpan]::Parse($Offset)
$lines = Get-Content $InputFile
$out = @()
$i = 0

while ($i -lt $lines.Count) {
    $line = $lines[$i]
    # Match timestamp lines
    if ($line -match "(\d{2}:\d{2}:\d{2}\.\d{3}) --> (\d{2}:\d{2}:\d{2}\.\d{3})") {
        $start = Split-Time $matches[1]
        $end = Split-Time $matches[2]
        if ($start -ge $offset) {
            # Keep block, adjust timestamps
            $newStart = $start - $offset
            $newEnd = $end - $offset
            $out += $lines[$i-1] # block id/comment if present
            $out += "$(Format-Time $newStart) --> $(Format-Time $newEnd)"
            $i++
            # Copy following lines until next timestamp or empty line
            while ($i -lt $lines.Count -and $lines[$i] -notmatch "^\s*$" -and $lines[$i] -notmatch "\d{2}:\d{2}:\d{2}\.\d{3} -->") {
                $out += $lines[$i]
                $i++
            }
            $out += "" # blank line between blocks
        } else {
            # Skip this block
            $i++
            while ($i -lt $lines.Count -and $lines[$i] -notmatch "^\s*$" -and $lines[$i] -notmatch "\d{2}:\d{2}:\d{2}\.\d{3} -->") {
                $i++
            }
        }
    } else {
        # Always keep the header
        if ($i -eq 0 -and $line -match "^WEBVTT") {
            $out += $line
            $out += "" # blank line after header
        }
        $i++
    }
}

$out | Set-Content $OutputFile -Encoding UTF8
