
<#
.SYNOPSIS
Splits a single audio file into individual tracks based on a CSV cue sheet,
names files by track title, and embeds the album cover into each output.

.REQUIREMENTS
- ffmpeg and ffprobe must be installed and available in PATH.
- Cover image should be JPG or PNG (preferably square).

.EXAMPLE
.\Split-Album.ps1 `
  -InputAudio ".\full_album.mp3" `
  -AlbumCover ".\cover.jpg" `
  -TracklistCsv ".\tracks.csv" `
  -OutputDir ".\Output" `
  -Album "My Album" `
  -AlbumArtist "Various Artists" `
  -Genre "Electronic" `
  -Year "2025" `
  -Reencode   # optional: use for frame-accurate cuts
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$InputAudio,

    [Parameter(Mandatory = $true)]
    [string]$AlbumCover,

    [Parameter(Mandatory = $true)]
    [string]$TracklistCsv,

    [string]$OutputDir = ".",

    [string]$Album = "",
    [string]$AlbumArtist = "",
    [string]$Genre = "",
    [string]$Year = "",

    [switch]$Reencode,              # Accurate cuts; re-encodes audio
    [string]$AudioCodec = "",       # Override codec when re-encoding (e.g., libmp3lame, aac, flac)
    [string]$Quality = "2"          # For libmp3lame: 0(best)-9; For AAC we'll use a default bitrate instead
)

# --- Helpers ---

function Throw-IfNotFound {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Path not found: $Path"
    }
}

function Test-Tool {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

function Get-AudioDuration {
    param([string]$AudioPath)
    $ffprobeArgs = @(
        "-v","error",
        "-show_entries","format=duration",
        "-of","default=noprint_wrappers=1:nokey=1",
        $AudioPath
    )
    $durationStr = & ffprobe @ffprobeArgs 2>$null
    if (-not $durationStr) { throw "Unable to get duration from ffprobe for '$AudioPath'." }
    $seconds = [double]::Parse($durationStr.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
    # Return as TimeSpan
    return [TimeSpan]::FromSeconds($seconds)
}

function Parse-Timestamp {
    <#
      Accepts formats like:
        ss
        m:ss / mm:ss
        h:mm:ss / hh:mm:ss
        with optional .fff fractional seconds
    #>
    param([string]$Text)
    $text = ($Text -replace '\s','').Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { throw "Empty timestamp encountered." }

    $formats = @(
        "h\:mm\:ss\.fff","h\:mm\:ss",
        "hh\:mm\:ss\.fff","hh\:mm\:ss",
        "m\:ss\.fff","m\:ss",
        "mm\:ss\.fff","mm\:ss",
        "s\.fff","s"
    )
    $ts = $null
    if ([TimeSpan]::TryParseExact($text, $formats, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$ts)) {
        return $ts
    } else {
        throw "Invalid timestamp '$Text'. Use formats like 0:00, 12:34, 1:02:03.250"
    }
}

function Sanitize-FileName {
    param([string]$Name)
    $sanitized = $Name -replace '[\\\/\:\*\?\"<>\|]', ''            # remove invalid
    $sanitized = $sanitized.Trim().TrimEnd('.')                    # Windows doesn't like trailing periods
    if ([string]::IsNullOrWhiteSpace($sanitized)) { $sanitized = "Track" }
    return $sanitized
}

function Pad2($n) { return "{0:D2}" -f [int]$n }

function Format-TS($ts) {
    # Always output HH:MM:SS.mmm (ffmpeg-friendly)
    $sign = ""
    if ($ts -lt [TimeSpan]::Zero) { $sign = "-"; $ts = -$ts }
    $hours = [int][math]::Floor($ts.TotalHours)
    $str = "{0}{1:00}:{2:00}:{3:00}.{4:000}" -f $sign, $hours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds
    return $str
}

# --- Validations ---
Throw-IfNotFound $InputAudio
Throw-IfNotFound $AlbumCover
Throw-IfNotFound $TracklistCsv

if (-not (Test-Tool "ffmpeg")) { throw "ffmpeg not found in PATH. Please install ffmpeg and ensure it's in PATH." }
if (-not (Test-Tool "ffprobe")) { throw "ffprobe not found in PATH. Please install ffmpeg (includes ffprobe) and ensure it's in PATH." }

# --- Prepare Output ---
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# --- Inspect audio & derive defaults ---
$inputExt = [IO.Path]::GetExtension($InputAudio).TrimStart('.').ToLowerInvariant()
$totalDuration = Get-AudioDuration -AudioPath $InputAudio

# Decide default codec when re-encoding (if none provided)
if ($Reencode -and [string]::IsNullOrWhiteSpace($AudioCodec)) {
    switch ($inputExt) {
        "mp3"   { $AudioCodec = "libmp3lame" }
        "m4a"   { $AudioCodec = "aac" }
        "mp4"   { $AudioCodec = "aac" }
        "aac"   { $AudioCodec = "aac" }
        "flac"  { $AudioCodec = "flac" }
        default { $AudioCodec = "libmp3lame" } # sensible default
    }
}

# --- Read and normalize CSV ---
$rowsRaw = Import-Csv -LiteralPath $TracklistCsv
if (-not $rowsRaw -or $rowsRaw.Count -eq 0) { throw "CSV appears empty: $TracklistCsv" }

# Map flexible column headers
$headerMap = @{
    Start   = @("start","timestamp","time","begin","start_time","starttime")
    End     = @("end","stop","end_time","endtime")
    Artist  = @("artist","trackartist","track_artist","artist_name","performer")
    Title   = @("title","track","name","track_name","song")
}

function Resolve-Column {
    param($object, [string]$logicalName)
    $aliases = $headerMap[$logicalName]
    foreach ($k in $object.PSObject.Properties.Name) {
        if ($aliases -contains ($k.ToLowerInvariant())) { return $k }
    }
    return $null
}

# Detect columns
$first = $rowsRaw | Select-Object -First 1
$colStart  = Resolve-Column $first "Start"
$colEnd    = Resolve-Column $first "End"
$colArtist = Resolve-Column $first "Artist"
$colTitle  = Resolve-Column $first "Title"

if (-not $colStart)  { throw "CSV missing a Start/Time/Timestamp column." }
if (-not $colTitle)  { throw "CSV missing a Title/Track/Name column." }
if (-not $colArtist) { Write-Warning "CSV missing an Artist column; will leave per-track artist blank." }

# Normalize and sort by start time
$tracks = @()
$index = 0
foreach ($row in $rowsRaw) {
    $index++
    $startTS = Parse-Timestamp $row.$colStart
    $endTS = $null
    if ($colEnd -and $row.$colEnd -and $row.$colEnd.ToString().Trim() -ne "") {
        $endTS = Parse-Timestamp $row.$colEnd
    }
    $artist = if ($colArtist) { [string]$row.$colArtist } else { "" }
    $title  = [string]$row.$colTitle

    $tracks += [PSCustomObject]@{
        RowIndex = $index
        Start    = $startTS
        End      = $endTS
        Artist   = $artist
        Title    = $title
    }
}
$tracks = $tracks | Sort-Object Start

# Compute implicit ends/durations
for ($i = 0; $i -lt $tracks.Count; $i++) {
    $cur = $tracks[$i]
    $next = if ($i -lt $tracks.Count-1) { $tracks[$i+1] } else { $null }

    if (-not $cur.End) {
        $cur | Add-Member -NotePropertyName "ComputedEnd" -NotePropertyValue ($(if ($next) { $next.Start } else { $totalDuration })) -Force
    } else {
        $cur | Add-Member -NotePropertyName "ComputedEnd" -NotePropertyValue $cur.End -Force
    }

    $duration = $cur.ComputedEnd - $cur.Start
    if ($duration.TotalMilliseconds -le 50) {
        throw "Non-positive or too-short duration for track '$($cur.Title)' (row $($cur.RowIndex)). Check timestamps."
    }
    $cur | Add-Member -NotePropertyName "Duration" -NotePropertyValue $duration -Force
}

# --- Process each track with ffmpeg ---
$coverExt = [IO.Path]::GetExtension($AlbumCover).ToLowerInvariant()
if ($coverExt -notin @(".jpg",".jpeg",".png")) {
    Write-Warning "Cover image is not JPG/PNG. ffmpeg may still work, but JPG/PNG is recommended."
}

$digits = ($tracks.Count.ToString()).Length
$total  = $tracks.Count
$trackNo = 0

foreach ($t in $tracks) {
    $trackNo++
    $num = ("{0:D$digits}" -f $trackNo)
    $safeTitle = Sanitize-FileName $t.Title
    $outName = "$num - $safeTitle.$inputExt"
    $outPath = Join-Path -Path $OutputDir -ChildPath $outName

    # Metadata
    $metaArgs = @()
    if ($t.Artist)       { $metaArgs += @("-metadata", "artist=$($t.Artist)") }
    if ($Album)          { $metaArgs += @("-metadata", "album=$Album") }
    if ($AlbumArtist)    { $metaArgs += @("-metadata", "album_artist=$AlbumArtist") }
    if ($Genre)          { $metaArgs += @("-metadata", "genre=$Genre") }
    if ($Year)           { $metaArgs += @("-metadata", "date=$Year") }
    $metaArgs += @("-metadata", "title=$($t.Title)")
    $metaArgs += @("-metadata", "track=$trackNo/$total")

    # Base args: input, seek, duration, cover
    $seek = Format-TS $t.Start
    $dur  = Format-TS $t.Duration

    # Build ffmpeg args
    $args = @("-hide_banner", "-loglevel", "error", "-y")

    # For better accuracy with stream copy, seek after input; for speed, seek before input.
    # We'll use: -ss start -t duration -i audio -i cover
    $args += @("-ss", $seek, "-t", $dur, "-i", $InputAudio, "-i", $AlbumCover)

    # Map streams: take first audio from input 0, and the cover image as attached picture
    $args += @("-map", "0:a:0", "-map", "1")

    # Audio coding strategy
    if ($Reencode) {
        $args += @("-c:v", "mjpeg", "-disposition:v", "attached_pic")
        $args += @("-c:a", $AudioCodec)

        switch ($AudioCodec.ToLowerInvariant()) {
            "libmp3lame" { $args += @("-q:a", $Quality); $args += @("-id3v2_version","3") }
            "aac"        { $args += @("-b:a", "256k") }
            default      { # flac/others: defaults okay
            }
        }
    } else {
        # Stream copy audio (no re-encode). Cuts are at keyframes; may be slightly imprecise.
        $args += @("-c:a", "copy")
        $args += @("-c:v", "mjpeg", "-disposition:v", "attached_pic")
        if ($inputExt -eq "mp3") { $args += @("-id3v2_version","3") }
    }

    # Add metadata
    $args += $metaArgs
    # Nice-to-have cover metadata
    $args += @("-metadata:s:v", "title=Album cover", "-metadata:s:v", "comment=Cover (front)")

    # Output path
    $args += $outPath

    Write-Host ("[{0}/{1}] Creating: {2}" -f $trackNo, $total, $outName)
    # Invoke ffmpeg
    & ffmpeg @args

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outPath)) {
        Write-Warning "ffmpeg reported an issue on track $trackNo: '$($t.Title)'."
    }
}

Write-Host "Done. Files saved to: $((Resolve-Path $OutputDir).Path)"
