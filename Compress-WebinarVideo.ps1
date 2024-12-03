
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
			"libx264", "libx265", "h264_nvenc", "hevc_nvenc", "h264_amf", 
			"hevc_amf", "h264_qsv", "hevc_qsv", "h264_vaapi", "hevc_vaapi"
		)][string]$VideoCodec
	,[Parameter(Mandatory = $False, ValueFromPipeline = $False)][string]$TrimStart = "00:00:00"
	,[Parameter(Mandatory = $False, ValueFromPipeline = $False)][string]$TrimEnd
)

$ErrorActionPreference = "Stop"

[string]$inputFile = [WildcardPattern]::Unescape($InputFile)
[string]$inputFileFullName = Get-ItemPropertyValue -LiteralPath $InputFile -Name FullName
[string]$targetDir = Get-ItemPropertyValue -LiteralPath $inputFile -Name DirectoryName
[string]$inputFileBase = Get-ItemPropertyValue -LiteralPath $InputFile -Name BaseName
[string]$inputFileExtension = Get-ItemPropertyValue -LiteralPath $InputFile -Name Extension
[string]$tempFile = Join-Path -Path $targetDir -ChildPath "$($inputFileBase)_temp$($inputFileExtension)"
[string]$inputFileNewName = "$($inputFileBase)_original$($inputFileExtension)"
[string]$outputFileName = $inputFileBase + $inputFileExtension
[string]$outputVideoCodec = $VideoCodec ?? "copy"

$trimParams = $TrimStart ? " -ss $TrimStart" + $($TrimEnd ? " -to $TrimEnd" : "") : ""
	
$ffmpegExpression = [string]::Concat(
	"ffmpeg",
	" -hwaccel auto",
	" -i ""$InputFile""",
	" -map 0:v:0? -map 0:a:0? -map 0:s:0?",
	"$trimParams",
	" -vf fps=$FrameRate",
	" -c:v $outputVideoCodec",
	" -ac 1 -ar 22050",
	" -c:s mov_text -metadata:s:s:0 language=eng",
	" ""$tempFile"""
)

Write-Host -ForegroundColor Green "`nRunning ffmpeg command:"
Write-Host -ForegroundColor Blue "`n$ffmpegExpression`n"

Invoke-Expression $ffmpegExpression

Rename-Item -LiteralPath $inputFileFullName -NewName $inputFileNewName
Rename-Item -LiteralPath $tempFile -NewName $outputFileName

(Get-ChildItem -LiteralPath $outputFileName).LastWriteTime = (Get-ChildItem -LiteralPath $inputFileFullName).LastWriteTime
