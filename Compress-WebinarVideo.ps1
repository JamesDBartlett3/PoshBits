
#------------------------------------------------------------------------------------------------------------------
# Author:   James Bartlett @jamesdbartlett3@techhub.social
# Synopsis: Uses ffmpeg to compress a webinar video to a much more manageable size
# Requires: ffmpeg CLI application, accessible in path
#------------------------------------------------------------------------------------------------------------------
# Note: Nvidia GPU acceleration is currently not working as intended, so use CPU only
# TODO: Add AMD GPU support
#------------------------------------------------------------------------------------------------------------------

function Compress-WebinarVideo {

    Param(
        [Parameter(Mandatory=$True, Position=0, ValueFromPipeline=$True)]
            [string]$InputFile
        ,[Parameter(Mandatory=$False, Position=1, ValueFromPipeline=$False)]
            [int]$FrameRate=10
        ,[Parameter(Mandatory=$False, Position=2, ValueFromPipeline=$False)]
            [string]$VideoCodec
        ,[Parameter(Mandatory=$False, ValueFromPipeline=$False)]
            [string]$TrimStart = "00:00:00"
        ,[Parameter(Mandatory=$False, ValueFromPipeline=$False)]
            [string]$TrimEnd
        # ,[Parameter(Mandatory=$False, ValueFromPipeline=$False)]
        #     [switch]$KeepOriginal
        # ,[Parameter(Mandatory=$False, ValueFromPipeline=$False)]
        #     [switch]$UseNvidiaGPU
        # ,[Parameter(Mandatory=$False, ValueFromPipeline=$False)]
        #     [switch]$UseAMDGPU
    )

    [string]$inputFileFullName = Get-ItemPropertyValue -LiteralPath $InputFile -Name FullName
    [string]$targetDir = Get-ItemPropertyValue -LiteralPath $inputFile -Name DirectoryName
    [string]$inputFileBase = Get-ItemPropertyValue -LiteralPath $InputFile -Name BaseName
    [string]$inputFileExtension = Get-ItemPropertyValue -LiteralPath $InputFile -Name Extension
    [string]$tempFile = Join-Path -Path $targetDir -ChildPath "$($inputFileBase)_temp$($inputFileExtension)"
    [string]$inputFileNewName = "$($inputFileBase)_original$($inputFileExtension)"
    [string]$outputFileName = $inputFileBase + $inputFileExtension
    [string]$outputVideoCodec = $VideoCodec ? "libx$($VideoCodec)" : "copy"

    $trimParams = $TrimStart ? "-ss $TrimStart" + $($TrimEnd ? " -to $TrimEnd" : "") : ""
    
    $ffmpegExpression = 
        [string]::Concat(
            "ffmpeg",
            " -hwaccel auto",
            " -i ""$InputFile""",
            " $trimParams",
            " -vf fps=$FrameRate",
            " -c:v $outputVideoCodec",
            " -ac 1 -ar 22050",
            " ""$tempFile"""
        )

    Write-Host -ForegroundColor Green "`nRunning ffmpeg command:"
    Write-Host -ForegroundColor Blue "`n`t$ffmpegExpression`n"

    Invoke-Expression $ffmpegExpression

    Rename-Item -LiteralPath $inputFileFullName -NewName $inputFileNewName
    Rename-Item -LiteralPath $tempFile -NewName $outputFileName
    (Get-ChildItem -LiteralPath $inputFileFullName).LastWriteTime = Get-Date

}
