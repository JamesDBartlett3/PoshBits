#------------------------------------------------------------------------------------------------------------------
# Author:   James Bartlett @jamesdbartlett3
# Synopsis: Uses ffmpeg to embed contents of a subtitle file into an MP4 video file, with no transcoding.
# Requires: ffmpeg CLI application, accessible in path
# Assumes:  inputVid is an MP4 or M4V file; inputVid and subtitle file have same BaseName (filename w/o extension)
#------------------------------------------------------------------------------------------------------------------
Param(
    [Parameter(Mandatory=$True, Position=0, ValueFromPipeline=$False)]
        $inputVid,
    [Parameter(Mandatory=$False, Position=1, ValueFromPipeline=$False)]
        [System.String] $subtitleFileExtension='vtt'
)
[string]$targetDir = Get-ItemPropertyValue -Path $inputVid -Name FullName | Split-Path -Path {$_}
[string]$inputFileBase = Get-ItemPropertyValue -Path $inputVid -Name BaseName
[string]$inputFileExtension = Get-ItemPropertyValue -Path $inputVid -Name Extension
[string]$inputSub = Join-Path -Path $targetDir -ChildPath "$inputFileBase.$subtitleFileExtension"
[string]$outputFile = $inputVid
[string]$tempFile = "$inputFileBase.temp.$inputFileExtension"

$ffmpegExpression = 
	[string]::Concat(
		"ffmpeg",
		" -hwaccel auto",
		" -i ""$inputVid""",
        " -i ""$inputSub""",
        " -c:v copy -c:a copy -c:s mov_text",
        " -metadata:s:s:0 language=eng",
		" ""$tempFile"""
	)

Write-Host -ForegroundColor Green "`nRunning ffmpeg command:"
Write-Host -ForegroundColor Blue "`n`t$ffmpegExpression`n"

Invoke-Expression $ffmpegExpression

Rename-Item -LiteralPath $inputVid -NewName "$($inputFileBase)_original.$($inputFileExtension)"
Rename-Item -LiteralPath $tempFile -NewName $outputFile
(Get-ChildItem -LiteralPath $inputVid).LastWriteTime = Get-Date