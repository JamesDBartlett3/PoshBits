
<#
.SYNOPSIS
Shrinks album tracks proportionally to fit within an 80-minute CD limit.

.DESCRIPTION
Takes a folder of audio tracks and shortens each one by the same ratio so
the total playtime fits on a standard 80-minute CD. Supports two modes:
  - Speed mode: Increases playback speed (also raises pitch)
  - TimeStretch mode: Increases playback speed without changing pitch

Output is lossless FLAC by default, or WAV if preferred.

.REQUIREMENTS
- ffmpeg and ffprobe must be installed and available in PATH.

.PARAMETER InputFolder
Path to folder containing the audio tracks to shrink.

.PARAMETER OutputFolder
Path to folder where shrunk tracks will be saved. Defaults to ".\Output".

.PARAMETER TargetMinutes
Target total playtime in minutes. Defaults to 80 (standard CD limit).

.PARAMETER Mode
Processing mode:
  - Speed: Increases playback speed (pitch also increases)
  - TimeStretch: Increases speed without changing pitch (uses rubberband filter)

.PARAMETER OutputFormat
Output format: FLAC (default, lossless) or WAV (also lossless).

.PARAMETER FilePattern
Glob pattern to match input files. Defaults to common audio extensions.

.EXAMPLE
.\Compress-AlbumToFitCD.ps1 -InputFolder ".\MyAlbum" -Mode Speed
# Speeds up all tracks proportionally to fit in 80 minutes

.EXAMPLE
.\Compress-AlbumToFitCD.ps1 -InputFolder ".\MyAlbum" -Mode TimeStretch -OutputFormat WAV
# Time-stretches tracks without pitch change, outputs as WAV

.EXAMPLE
.\Compress-AlbumToFitCD.ps1 -InputFolder ".\MyAlbum" -TargetMinutes 74 -Mode TimeStretch
# Fit onto a 74-minute CD using time-stretch
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$InputFolder,

    [string]$OutputFolder = ".\Output",

    [double]$TargetMinutes = 80,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Speed', 'TimeStretch')]
    [string]$Mode,

    [ValidateSet('FLAC', 'WAV')]
    [string]$OutputFormat = "FLAC",

    [string]$FilePattern = ""
)

# --- Helper Functions ---

function Test-Tool {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

function Get-AudioDuration {
    param([string]$AudioPath)
    $ffprobeArgs = @(
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        $AudioPath
    )
    $durationStr = & ffprobe @ffprobeArgs 2>$null
    if (-not $durationStr) { throw "Unable to get duration from ffprobe for '$AudioPath'." }
    $seconds = [double]::Parse($durationStr.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
    return [TimeSpan]::FromSeconds($seconds)
}

function Format-Duration {
    param([TimeSpan]$Duration)
    if ($Duration.TotalHours -ge 1) {
        return "{0}:{1:00}:{2:00}.{3:000}" -f [int]$Duration.TotalHours, $Duration.Minutes, $Duration.Seconds, $Duration.Milliseconds
    }
    else {
        return "{0}:{1:00}.{2:000}" -f [int]$Duration.TotalMinutes, $Duration.Seconds, $Duration.Milliseconds
    }
}

function Format-DurationShort {
    param([TimeSpan]$Duration)
    if ($Duration.TotalHours -ge 1) {
        return "{0}:{1:00}:{2:00}" -f [int]$Duration.TotalHours, $Duration.Minutes, $Duration.Seconds
    }
    else {
        return "{0}:{1:00}" -f [int]$Duration.TotalMinutes, $Duration.Seconds
    }
}

# --- Validations ---

if (-not (Test-Path -LiteralPath $InputFolder -PathType Container)) {
    throw "Input folder not found: $InputFolder"
}

if (-not (Test-Tool "ffmpeg")) { throw "ffmpeg not found in PATH. Please install ffmpeg and ensure it's in PATH." }
if (-not (Test-Tool "ffprobe")) { throw "ffprobe not found in PATH. Please install ffmpeg (includes ffprobe) and ensure it's in PATH." }

# --- Find Audio Files ---

$audioExtensions = @("*.mp3", "*.flac", "*.wav", "*.m4a", "*.ogg", "*.opus", "*.wma", "*.aac", "*.aiff")

if ([string]::IsNullOrWhiteSpace($FilePattern)) {
    $audioFiles = @()
    foreach ($ext in $audioExtensions) {
        $audioFiles += Get-ChildItem -LiteralPath $InputFolder -Filter $ext -File
    }
}
else {
    $audioFiles = Get-ChildItem -LiteralPath $InputFolder -Filter $FilePattern -File
}

# Sort files naturally (by name)
$audioFiles = $audioFiles | Sort-Object Name

if ($audioFiles.Count -eq 0) {
    throw "No audio files found in '$InputFolder'. Supported extensions: $($audioExtensions -join ', ')"
}

Write-Host "Found $($audioFiles.Count) audio file(s) in '$InputFolder'"
Write-Host ""

# --- Calculate Total Duration ---

$trackInfo = @()
$totalSeconds = 0

Write-Host "Analyzing track durations..."
foreach ($file in $audioFiles) {
    $duration = Get-AudioDuration -AudioPath $file.FullName
    $totalSeconds += $duration.TotalSeconds
    $trackInfo += [PSCustomObject]@{
        File     = $file
        Duration = $duration
    }
    Write-Host "  $($file.Name): $(Format-DurationShort $duration)"
}

$totalDuration = [TimeSpan]::FromSeconds($totalSeconds)
$targetSeconds = $TargetMinutes * 60
$targetDuration = [TimeSpan]::FromSeconds($targetSeconds)

Write-Host ""
Write-Host "Total album duration: $(Format-DurationShort $totalDuration) ($([math]::Round($totalDuration.TotalMinutes, 2)) minutes)"
Write-Host "Target duration:      $(Format-DurationShort $targetDuration) ($TargetMinutes minutes)"

# --- Check if Shrinking is Needed ---

if ($totalSeconds -le $targetSeconds) {
    Write-Host ""
    Write-Host "Album already fits within $TargetMinutes minutes. No shrinking needed!" -ForegroundColor Green
    exit 0
}

# --- Calculate Speed Factor ---

# speedFactor > 1 means faster playback (shorter duration)
$speedFactor = $totalSeconds / $targetSeconds
$percentIncrease = ($speedFactor - 1) * 100
$newTotalSeconds = $totalSeconds / $speedFactor

Write-Host ""
Write-Host ("Speed factor required: {0:F4}x ({1:F2}% faster)" -f $speedFactor, $percentIncrease)
Write-Host "New total duration:    $(Format-DurationShort ([TimeSpan]::FromSeconds($newTotalSeconds)))"
Write-Host ""

# --- Confirm with User ---

$modeDescription = switch ($Mode) {
    "Speed"       { "Speed up (pitch will increase)" }
    "TimeStretch" { "Time-stretch (pitch preserved)" }
}

Write-Host "Processing mode: $modeDescription"
Write-Host "Output format:   $OutputFormat"
Write-Host ""

$confirm = Read-Host "Proceed with shrinking? [Y/N] (default: Y)"
if ($confirm -match '^[Nn]') {
    Write-Host "Aborted."
    exit 0
}

# --- Prepare Output Folder ---

New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

# --- Determine Output Extension ---

$outputExt = switch ($OutputFormat.ToUpperInvariant()) {
    "FLAC" { "flac" }
    "WAV"  { "wav" }
}

# --- Process Each Track ---

$digits = [Math]::Max(2, ($trackInfo.Count.ToString()).Length)
$trackNo = 0
$processedTracks = @()

foreach ($track in $trackInfo) {
    $trackNo++
    $inputFile = $track.File
    $originalDuration = $track.Duration
    $newDuration = [TimeSpan]::FromSeconds($originalDuration.TotalSeconds / $speedFactor)

    # Build output filename (preserve original name, change extension)
    $baseName = [IO.Path]::GetFileNameWithoutExtension($inputFile.Name)
    $outName = "$baseName.$outputExt"
    $outPath = Join-Path -Path $OutputFolder -ChildPath $outName

    Write-Host ("[{0}/{1}] Processing: {2}" -f $trackNo, $trackInfo.Count, $inputFile.Name)
    Write-Host ("         Original: {0} -> New: {1}" -f (Format-DurationShort $originalDuration), (Format-DurationShort $newDuration))

    # Build ffmpeg arguments
    $args = @("-hide_banner", "-loglevel", "error", "-y")
    $args += @("-i", $inputFile.FullName)

    # Apply speed/time-stretch filter
    switch ($Mode) {
        "Speed" {
            # atempo filter: changes speed AND pitch
            # atempo only supports 0.5 to 2.0, so chain if needed
            $tempo = $speedFactor
            $atempoChain = @()
            
            while ($tempo -gt 2.0) {
                $atempoChain += "atempo=2.0"
                $tempo = $tempo / 2.0
            }
            while ($tempo -lt 0.5) {
                $atempoChain += "atempo=0.5"
                $tempo = $tempo / 0.5
            }
            $atempoChain += "atempo=$([math]::Round($tempo, 6))"
            
            $filterComplex = $atempoChain -join ","
            $args += @("-af", $filterComplex)
        }
        "TimeStretch" {
            # rubberband filter: changes speed WITHOUT changing pitch
            # This requires ffmpeg built with librubberband support
            $args += @("-af", "rubberband=tempo=$([math]::Round($speedFactor, 6))")
        }
    }

    # Output codec
    switch ($OutputFormat.ToUpperInvariant()) {
        "FLAC" {
            $args += @("-c:a", "flac")
            $args += @("-compression_level", "8")  # Maximum compression (still lossless)
        }
        "WAV" {
            $args += @("-c:a", "pcm_s16le")  # 16-bit PCM WAV
        }
    }

    # Copy metadata from source
    $args += @("-map_metadata", "0")

    # Output path
    $args += $outPath

    # Run ffmpeg
    & ffmpeg @args

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "ffmpeg reported an issue processing '$($inputFile.Name)'."
        if ($Mode -eq "TimeStretch") {
            Write-Warning "Note: TimeStretch mode requires ffmpeg built with librubberband support."
            Write-Warning "If not available, try using -Mode Speed instead."
        }
    }
    elseif (Test-Path -LiteralPath $outPath) {
        $actualDuration = Get-AudioDuration -AudioPath $outPath
        $processedTracks += [PSCustomObject]@{
            Name            = $outName
            OriginalDuration = $originalDuration
            NewDuration     = $actualDuration
        }
    }
}

# --- Summary ---

Write-Host ""
Write-Host "Processing complete!" -ForegroundColor Green
Write-Host "Output folder: $((Resolve-Path $OutputFolder).Path)"
Write-Host ""

if ($processedTracks.Count -gt 0) {
    $actualTotalSeconds = ($processedTracks | Measure-Object -Property { $_.NewDuration.TotalSeconds } -Sum).Sum
    $actualTotal = [TimeSpan]::FromSeconds($actualTotalSeconds)
    
    Write-Host "Summary:"
    Write-Host "  Original total: $(Format-DurationShort $totalDuration)"
    Write-Host "  New total:      $(Format-DurationShort $actualTotal)"
    Write-Host "  Target was:     $(Format-DurationShort $targetDuration)"
    
    # Use small tolerance (0.1 second) to account for floating-point precision only
    $tolerance = 0.1
    if ($actualTotalSeconds -le ($targetSeconds + $tolerance)) {
        Write-Host ""
        Write-Host "Success! Album now fits on an $TargetMinutes-minute CD." -ForegroundColor Green
    }
    else {
        $overBy = [TimeSpan]::FromSeconds($actualTotalSeconds - $targetSeconds)
        Write-Host ""
        Write-Host "Warning: Still over by $(Format-DurationShort $overBy). May need manual adjustment." -ForegroundColor Yellow
    }
}

