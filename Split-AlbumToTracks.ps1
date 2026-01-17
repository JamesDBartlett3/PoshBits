
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
  -FastSeek   # optional: faster but may cut at nearest keyframe
#>

param(
    [string]$InputAudio,

    [string]$AlbumCover,

    [string]$TracklistCsv,

    [string]$OutputDir = ".",

    [string]$Album = "",
    [string]$AlbumArtist = "",
    [string]$Genre = "",
    [string]$Year = "",

    [switch]$FastSeek,              # Seek before input (faster but may cut at nearest keyframe)
    [switch]$GenerateTemplateCSV,   # Generate a template CSV file and exit
    [ValidateSet('Track-Title', 'Track-Artist-Title', 'Track-Title-Artist', 'Title', 'Artist-Title', 'Title-Artist')]
    [string]$FilenameSchema = "Track-Title",  # Output filename format
    [string]$AudioCodec = "",       # Re-encode with specified codec (e.g., libmp3lame, aac, flac). If omitted, stream copy is used.
    [string]$Quality = "2"          # For libmp3lame: 0(best)-9; For AAC we'll use a default bitrate instead
)

# --- Generate Template CSV and Exit ---
if ($GenerateTemplateCSV) {
    $templatePath = "tracklist_template.csv"
    $templateContent = @"
Track,Start,End,Artist,Title
1,0:00,1:30,Artist One,Track One
2,1:30,3:15,Artist Two,Track Two
3,3:15,,Artist Three,Track Three
"@
    $templateContent | Out-File -LiteralPath $templatePath -Encoding UTF8
    Write-Host "Template CSV generated: $templatePath"
    Write-Host "Columns: Track (optional), Start, End (optional), Artist, Title"
    Write-Host "Start and End support formats: s, m:ss, h:mm:ss, and with milliseconds (.fff)"
    exit 0
}

# --- Validate Required Parameters ---
if ([string]::IsNullOrWhiteSpace($InputAudio)) { throw "InputAudio is required." }
if ([string]::IsNullOrWhiteSpace($TracklistCsv)) { throw "TracklistCsv is required." }

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

function Build-Filename {
    param(
        [int]$TrackNum,
        [string]$Title,
        [string]$Artist,
        [string]$Schema
    )
    $num = ("{0:D$($digits)}" -f $TrackNum)
    $safeTitle = Sanitize-FileName $Title
    $safeArtist = Sanitize-FileName $Artist
    
    $filename = switch ($Schema) {
        "Track-Title"        { "$num - $safeTitle" }
        "Track-Artist-Title" { "$num - $safeArtist - $safeTitle" }
        "Track-Title-Artist" { "$num - $safeTitle - $safeArtist" }
        "Title"              { $safeTitle }
        "Artist-Title"       { "$safeArtist - $safeTitle" }
        "Title-Artist"       { "$safeTitle - $safeArtist" }
        default              { "$num - $safeTitle" } # fallback
    }
    return $filename
}

function Parse-Timestamp {
    <#
      Accepts formats like:
        ss
        m:ss / mm:ss
        h:mm:ss / hh:mm:ss
        with optional .ff (hundredths) or .fff (milliseconds) fractional seconds
    #>
    param([string]$Text)
    $text = ($Text -replace '\s','').Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { throw "Empty timestamp encountered." }

    $formats = @(
        "h\:mm\:ss\.fff","h\:mm\:ss\.ff","h\:mm\:ss",
        "hh\:mm\:ss\.fff","hh\:mm\:ss\.ff","hh\:mm\:ss",
        "m\:ss\.fff","m\:ss\.ff","m\:ss",
        "mm\:ss\.fff","mm\:ss\.ff","mm\:ss",
        "s\.fff","s\.ff","s"
    )
    
    # Try each format
    foreach ($format in $formats) {
        $ts = New-Object TimeSpan
        if ([TimeSpan]::TryParseExact($text, $format, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$ts)) {
            return $ts
        }
    }
    
    throw "Invalid timestamp '$Text'. Use formats like 0:00, 12:34, 1:02:03.250"
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
if (-not [string]::IsNullOrWhiteSpace($AlbumCover)) { Throw-IfNotFound $AlbumCover }
Throw-IfNotFound $TracklistCsv

if (-not (Test-Tool "ffmpeg")) { throw "ffmpeg not found in PATH. Please install ffmpeg and ensure it's in PATH." }
if (-not (Test-Tool "ffprobe")) { throw "ffprobe not found in PATH. Please install ffmpeg (includes ffprobe) and ensure it's in PATH." }

# --- Prepare Output ---
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# --- Inspect audio & derive defaults ---
$inputExt = [IO.Path]::GetExtension($InputAudio).TrimStart('.').ToLowerInvariant()
$totalDuration = Get-AudioDuration -AudioPath $InputAudio

# Check if re-encoding is requested via -AudioCodec
$Reencode = -not [string]::IsNullOrWhiteSpace($AudioCodec)
if ($Reencode) {
    # Warn about potential quality loss for lossy codecs
    $lossyCodecs = @("libmp3lame", "aac", "libvorbis", "libopus")
    if ($AudioCodec.ToLowerInvariant() -in $lossyCodecs) {
        Write-Warning "Re-encoding to '$AudioCodec' may result in audio quality loss."
        $choice = Read-Host "Continue with re-encoding? [Y] Yes  [N] No, use stream copy instead  (default: N)"
        if ($choice -notmatch '^[Yy]') {
            Write-Host "Switching to stream copy (lossless)."
            $Reencode = $false
            $AudioCodec = ""
        }
    }
}

# Determine output extension based on codec (or use input extension for stream copy)
$outputExt = $inputExt
if ($Reencode) {
    $outputExt = switch ($AudioCodec.ToLowerInvariant()) {
        "libmp3lame" { "mp3" }
        "aac"        { "m4a" }
        "flac"       { "flac" }
        "libvorbis"  { "ogg" }
        "libopus"    { "opus" }
        default      { $inputExt }
    }
}

# --- Read and normalize CSV ---
$rowsRaw = Import-Csv -LiteralPath $TracklistCsv
if (-not $rowsRaw -or $rowsRaw.Count -eq 0) { throw "CSV appears empty: $TracklistCsv" }

# Map flexible column headers
$headerMap = @{
    Track   = @("track","tracknumber","track_number","number","num")
    Start   = @("start","timestamp","time","begin","start_time","starttime")
    End     = @("end","stop","end_time","endtime")
    Artist  = @("artist","trackartist","track_artist","artist_name","performer")
    Title   = @("title","name","track_name","song")
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
$colTrack  = Resolve-Column $first "Track"
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
    $trackNum = if ($colTrack -and $row.$colTrack -and $row.$colTrack.ToString().Trim() -ne "") { [int]$row.$colTrack } else { 0 }
    $startTS = Parse-Timestamp $row.$colStart
    $endTS = $null
    if ($colEnd -and $row.$colEnd -and $row.$colEnd.ToString().Trim() -ne "") {
        $endTS = Parse-Timestamp $row.$colEnd
    }
    $artist = if ($colArtist) { [string]$row.$colArtist } else { "" }
    $title  = [string]$row.$colTitle

    $tracks += [PSCustomObject]@{
        RowIndex = $index
        Track    = $trackNum
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

$digits = [Math]::Max(2, ($tracks.Count.ToString()).Length)
$total  = $tracks.Count
$trackNo = 0

foreach ($t in $tracks) {
    # Use track number from CSV if provided, otherwise use sequential numbering
    $trackNo = if ($t.Track -gt 0) { $t.Track } else { $trackNo + 1 }
    $outName = "$(Build-Filename -TrackNum $trackNo -Title $t.Title -Artist $t.Artist -Schema $FilenameSchema).$outputExt"
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

    # Input seeking: -ss before -i seeks in the input (fast, keyframe-aligned)
    if ($FastSeek) {
        $args += @("-ss", $seek, "-i", $InputAudio)
    } else {
        $args += @("-accurate_seek", "-ss", $seek, "-i", $InputAudio)
    }
    
    # Add cover image if provided (separate input)
    if (-not [string]::IsNullOrWhiteSpace($AlbumCover)) {
        $args += @("-i", $AlbumCover)
    }

    # Strip original file metadata so duration isn't inherited from source
    $args += @("-map_metadata", "-1")

    # Map streams: take first audio from input 0, and cover image (if present) as attached picture
    $args += @("-map", "0:a:0")
    if (-not [string]::IsNullOrWhiteSpace($AlbumCover)) { $args += @("-map", "1") }

    # Audio coding strategy
    if ($Reencode) {
        $args += @("-c:a", $AudioCodec)

        switch ($AudioCodec.ToLowerInvariant()) {
            "libmp3lame" { $args += @("-q:a", $Quality); $args += @("-id3v2_version","3") }
            "aac"        { $args += @("-b:a", "256k") }
            "libvorbis"  { $args += @("-q:a", $Quality) }  # Quality 0-10, default 2
            "libopus"    { $args += @("-b:a", "128k") }    # Opus is efficient; 128k is good quality
            default      { # flac/others: defaults okay
            }
        }
    } else {
        # Stream copy for most formats, but re-encode FLAC to fix duration metadata
        # (FLAC→FLAC is lossless, so no quality loss)
        if ($inputExt -eq "flac") {
            $args += @("-c:a", "flac")
        } else {
            $args += @("-c:a", "copy")
            # Reset timestamps to start from zero when using stream copy
            $args += @("-avoid_negative_ts", "make_zero")
        }
        if ($inputExt -eq "mp3") { $args += @("-id3v2_version","3") }
    }

    # Embed cover image as attached picture (if provided)
    if (-not [string]::IsNullOrWhiteSpace($AlbumCover)) {
        $args += @("-c:v", "copy", "-disposition:v", "attached_pic")
        # Nice-to-have cover metadata
        $args += @("-metadata:s:v", "title=Album cover", "-metadata:s:v", "comment=Cover (front)")
    }

    # Add metadata
    $args += $metaArgs

    # Output duration limit (must be output option, right before output file)
    $args += @("-t", $dur)

    # Output path
    $args += $outPath

    Write-Host ("[{0}/{1}] Creating: {2}" -f $trackNo, $total, $outName)
    # Invoke ffmpeg
    & ffmpeg @args

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outPath)) {
        Write-Warning "ffmpeg reported an issue on track $($trackNo): '$($t.Title)'."
    }
}

Write-Host "Done. Files saved to: $((Resolve-Path $OutputDir).Path)"
