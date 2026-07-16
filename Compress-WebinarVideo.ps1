
#------------------------------------------------------------------------------------------------------------------
# Author:	  James Bartlett @jamesdbartlett3@techhub.social
# Synopsis: Uses ffmpeg to compress a webinar video to a much more manageable size
# Requires: ffmpeg CLI application, accessible in path
#------------------------------------------------------------------------------------------------------------------
# TODO: 
# - Add support for using TrimStart and TrimEnd independently 
#	 - currently, TrimStart must be specified, or TrimEnd will be ignored
#	 - temporary workaround: TrimStart defaults to "00:00:00"
# - Add GPU acceleration
# - Add doc block w/ help & examples
# - Add parameter validation
#	 - FrameRate must be an integer
#	 - TrimStart & TrimEnd must be valid timecodes (hh:mm:ss)
#------------------------------------------------------------------------------------------------------------------


Param(
  [Parameter(Mandatory = $True, Position = 0, ValueFromPipeline = $True)][string]$InputFile
  ,[Parameter(Mandatory = $False, Position = 1, ValueFromPipeline = $False)][int]$FrameRate = 10
  ,[Parameter(Mandatory = $False, Position = 2, ValueFromPipeline = $False)][ValidateSet(
      "libx264", "libx265", "h264_nvenc", "hevc", "hevc_nvenc", "h264_amf", 
      "hevc_amf", "h264_qsv", "hevc_qsv", "h264_vaapi", "hevc_vaapi"
    )][string]$VideoCodec
  ,[Parameter(Mandatory = $False, ValueFromPipeline = $False)][string]$TrimStart = "00:00:00"
  ,[Parameter(Mandatory = $False, ValueFromPipeline = $False)][string]$TrimEnd
  ,[Parameter(Mandatory = $False, ValueFromPipeline = $False)][double]$TargetSizeMB
  ,[Parameter(Mandatory = $False, ValueFromPipeline = $False)][switch]$TwoPass
)

$ErrorActionPreference = "Stop"

if ($TwoPass.IsPresent -and $TargetSizeMB -le 0) {
    throw "The -TwoPass switch requires a valid -TargetSizeMB value greater than 0."
}

[string]$inputFile = [WildcardPattern]::Unescape($InputFile)
[string]$inputFileFullName = Get-ItemPropertyValue -LiteralPath $InputFile -Name FullName
[string]$targetDir = Get-ItemPropertyValue -LiteralPath $inputFile -Name DirectoryName
[string]$inputFileBase = Get-ItemPropertyValue -LiteralPath $InputFile -Name BaseName
[string]$inputFileExtension = Get-ItemPropertyValue -LiteralPath $InputFile -Name Extension
[string]$tempFile = Join-Path -Path $targetDir -ChildPath "$($inputFileBase)_temp$($inputFileExtension)"
[string]$inputFileNewName = "$($inputFileBase)_original$($inputFileExtension)"
[string]$outputFileName = $inputFileBase + $inputFileExtension
[string]$outputVideoCodec = $VideoCodec ?? "copy"
[string]$appleCompatibility = $VideoCodec -like "*hevc*" -or $VideoCodec -like "*265*" ? " -tag:v hvc1" : ""

$trimParams = $TrimStart ? " -ss $TrimStart" + $($TrimEnd ? " -to $TrimEnd" : "") : ""

[string]$targetSizeParams = ""
if ($TargetSizeMB -gt 0) {
    [double]$durationSeconds = 0
    if (-not [string]::IsNullOrEmpty($TrimEnd)) {
        $durationSeconds = ([timespan]$TrimEnd).TotalSeconds
    } else {
        [string]$durationStr = (ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$InputFile")
        $durationSeconds = [double]::Parse($durationStr, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    
    if (-not [string]::IsNullOrEmpty($TrimStart) -and $TrimStart -ne "00:00:00") {
        $durationSeconds -= ([timespan]$TrimStart).TotalSeconds
    }
    
    if ($durationSeconds -gt 0) {
        # Subtract estimated audio bitrate (64k bps) to get target video bitrate
        [double]$totalBitrate = ($TargetSizeMB * 8388608) / $durationSeconds
        [int]$videoBitrate = [math]::Max([math]::Floor($totalBitrate - 64000), 10000)
        
        if ($TwoPass.IsPresent) {
            # 2-pass allows Variable Bitrate (VBR) to efficiently allocate bits based on scene complexity
            $targetSizeParams = " -b:v $videoBitrate"
        } else {
            # 1-pass needs Constrained Bitrate (CBR) to guarantee it hits the target size
            [int]$bufSize = $videoBitrate * 2
            $targetSizeParams = " -b:v $videoBitrate -maxrate $videoBitrate -bufsize $bufSize"
        }
    }
}

[string]$baseFfmpeg = [string]::Concat(
  "ffmpeg",
  " -hide_banner -loglevel error -stats",
  " -y",
  " -hwaccel auto",
  " -i ""$InputFile""",
  " -map 0:v:0? -map 0:a:0? -map 0:s:0?",
  "$trimParams",
  " -vf fps=$FrameRate",
  " -c:v $outputVideoCodec$($appleCompatibility)",
  "$targetSizeParams"
)

[string]$audioAndSubParams = " -ac 1 -ar 22050 -c:s mov_text -metadata:s:s:0 language=eng"

if ($TwoPass.IsPresent) {
    [string]$nullDevice = if ($IsWindows -eq $false -or $PSEdition -ne "Desktop") { "/dev/null" } else { "NUL" }
    [string]$passLogPrefix = Join-Path -Path $targetDir -ChildPath "$($inputFileBase)_passlog"
    
    $pass1Expression = "$baseFfmpeg -pass 1 -passlogfile ""$passLogPrefix"" -an -f null $nullDevice"
    Write-Host -ForegroundColor Green "`nRunning ffmpeg Pass 1:"
    Write-Host -ForegroundColor Blue "`n$pass1Expression`n"
    Invoke-Expression $pass1Expression

    $ffmpegExpression = "$baseFfmpeg -pass 2 -passlogfile ""$passLogPrefix"" $audioAndSubParams ""$tempFile"""
    Write-Host -ForegroundColor Green "`nRunning ffmpeg Pass 2:"
    Write-Host -ForegroundColor Blue "`n$ffmpegExpression`n"
    Invoke-Expression $ffmpegExpression

    # Clean up 2-pass log files
    Remove-Item -Path "$passLogPrefix*" -Force -ErrorAction SilentlyContinue
} else {
    $ffmpegExpression = "$baseFfmpeg $audioAndSubParams ""$tempFile"""
    Write-Host -ForegroundColor Green "`nRunning ffmpeg command:"
    Write-Host -ForegroundColor Blue "`n$ffmpegExpression`n"
    Invoke-Expression $ffmpegExpression
}

Rename-Item -LiteralPath $inputFileFullName -NewName $inputFileNewName
Rename-Item -LiteralPath $tempFile -NewName $outputFileName

(Get-ChildItem -LiteralPath $outputFileName).LastWriteTime = (Get-ChildItem -LiteralPath $inputFileFullName).LastWriteTime
