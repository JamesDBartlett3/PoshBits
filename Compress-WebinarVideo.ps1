
#------------------------------------------------------------------------------------------------------------------
# Author:   James Bartlett @jamesdbartlett3
# Synopsis: Uses ffmpeg to compress a webinar video to a much more manageable size
# Requires: ffmpeg CLI application, accessible in path
#------------------------------------------------------------------------------------------------------------------
# Note: Nvidia GPU acceleration is currently not working as intended, so use CPU only
# TODO: Add AMD GPU support
#------------------------------------------------------------------------------------------------------------------

function Compress-WebinarVideo {

    Param(
        [Parameter(Mandatory=$True, Position=0, ValueFromPipeline=$True)]
            [string]$InputFile,
        [Parameter(Mandatory=$False, Position=1, ValueFromPipeline=$False)]
            [int]$FrameRate=5,
        [Parameter(Mandatory=$False, Position=2, ValueFromPipeline=$False)]
            [switch]$UseNvidiaGPU
    )

    [string]$targetDir = Get-ItemPropertyValue -LiteralPath $InputFile -Name FullName | Split-Path -Path {$_}
    [string]$inputFileBase = Get-ItemPropertyValue -LiteralPath $InputFile -Name BaseName
    [string]$inputFileExtension = Get-ItemPropertyValue -LiteralPath $InputFile -Name Extension
    [string]$outputFile = "$(Join-Path -Path $targetDir -ChildPath $inputFileBase)_[" + $FrameRate + "fps]" + $inputFileExtension

    if ($UseNvidiaGPU) {
        ffmpeg -hwaccel cuda -hwaccel_output_format cuda -i $InputFile -vf fps=$FrameRate -c:v hevc_nvenc -ac 1 -ar 22050 $outputFile
    } else {
        #ffmpeg -i $InputFile -c:v libx265 -filter:v fps=fps=$FrameRate -ac 1 -ar 22050 $outputFile        
        ffmpeg -i $InputFile -vf fps=$FrameRate -c:v libx265 -ac 1 -ar 22050 $outputFile
    }

}
