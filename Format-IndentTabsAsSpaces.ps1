<#
  .SYNOPSIS
    Converts tabs to indentation spaces.
  
  .DESCRIPTION
    Author: @JamesDBartlett3@techhub.social (https://techhub.social/@JamesDBartlett3)
  
  .PARAMETER InputFile
    The file to format.
  
  .PARAMETER Indentation
    The number of spaces to replace each tab with. Default is 2.
  
  .EXAMPLE
    Format-IndentTabsAsSpaces.ps1 -InputFile ".\MyScript.ps1"
  
  .EXAMPLE
    # This example will convert all PowerShell scripts in the current directory from tabs to 2 spaces.
    Format-IndentTabsAsSpaces.ps1 -InputFile ".\*.ps1"
  
  .EXAMPLE
    # This example will convert all PowerShell scripts in the parent directory from tabs to 4 spaces.
    Get-ChildItem -Path "..\*.ps1" | Format-IndentTabsAsSpaces.ps1 -Indentation 4
  
#>

# Parameters
Param(
  [Parameter(
    Mandatory = $true,
    ValueFromPipeline = $true
  )]
  [ValidateNotNullOrEmpty()]
  [string[]]$InputFile,
  
  [Parameter(
    Mandatory = $false
  )]
  [ValidateNotNullOrEmpty()]
  [int]$Indentation = 2
)

Begin {
  # Set the regex pattern
  $pattern = "`t"
  $replaceWith = " " * $Indentation
}

# Process
Process {
  ForEach ($File in $InputFile) {
    (Get-Content $File) | ForEach-Object {
      $_ -replace $pattern, $replaceWith
    } | Set-Content $File
  }
}