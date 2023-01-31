
# A function which takes a string as input and converts it to speech
# Requires the System.Speech assembly

function Out-TextToSpeech {
    Param(
        [Parameter(Mandatory=$True, Position=0, ValueFromPipeline=$True)]
            [string]$Text
        ,[Parameter(Mandatory=$False, Position=1, ValueFromPipeline=$False)]
            [string]$Voice="Microsoft Zira Desktop"
        ,[Parameter(Mandatory=$False, Position=2, ValueFromPipeline=$False)]
            [int]$Rate=2
        ,[Parameter(Mandatory=$False, Position=3, ValueFromPipeline=$False)]
            [int]$Volume=100
    )
    Add-Type -AssemblyName System.Speech
    $speechSynthesizer = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $speechSynthesizer.SelectVoice($Voice)
    $speechSynthesizer.Rate = $Rate
    $speechSynthesizer.Volume = $Volume
    $speechSynthesizer.Speak($Text)
}

