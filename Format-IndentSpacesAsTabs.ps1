<#
	.SYNOPSIS
		Converts indentation spaces to tabs.
	
	.DESCRIPTION
		Author: @JamesDBartlett3@techhub.social (https://techhub.social/@JamesDBartlett3)
	
	.PARAMETER InputFile
		The file to format.
	
	.PARAMETER Indentation
		The number of spaces to convert to tabs.
	
	.EXAMPLE
		PS C:\> Format-IndentSpacesAsTabs -InputFile ".\MyScript.ps1" -Indentation 4
	
	.EXAMPLE
		PS C:\> Get-ChildItem -Path ".\*.ps1" | Format-IndentSpacesAsTabs -Indentation 4
	
#>