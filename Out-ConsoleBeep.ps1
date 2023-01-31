# A function that creates a beep sound using [console]::Beep()

function Out-ConsoleBeep {
    Param(
        [Parameter(Mandatory=$False, Position=0, ValueFromPipeline=$False)]
            [int]$Frequency=800
        ,[Parameter(Mandatory=$False, Position=1, ValueFromPipeline=$False)]
            [int]$Duration=200
    )
    [console]::Beep($Frequency, $Duration)
}