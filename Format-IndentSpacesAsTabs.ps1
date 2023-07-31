<#
	.SYNOPSIS
		Converts indentation spaces to tabs.
	
	.DESCRIPTION
		Author: @JamesDBartlett3@techhub.social (https://techhub.social/@JamesDBartlett3)
	
	.PARAMETER InputFile
		The file to format.
	
	.PARAMETER Indentation
		The number of spaces to convert to tabs. Default is 2.
	
	.EXAMPLE
		PS C:\> Format-IndentSpacesAsTabs.ps1 -InputFile ".\MyScript.ps1"

	.EXAMPLE
		PS C:\> Format-IndentSpacesAsTabs.ps1 -InputFile ".\*.ps1"
	
	.EXAMPLE
		PS C:\> Get-ChildItem -Path ".\*.ps1" | Format-IndentSpacesAsTabs.ps1 -Indentation 4
	
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

# Process
Begin {
	
	# Set the tab character
	$tab = "`t"
	
	# Set the regex pattern
	$pattern = " " * $Indentation
	
}

Process {
	
	# Check if InputFile is a wildcard
	If ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($InputFile)) {
		
		# Get the files
		$InputFile = Get-ChildItem -Path $InputFile -File
	
	}
	
	# Loop through each file
	ForEach ($file in $InputFile) {

		# Resolve the file path
		$filePath = $file | Resolve-Path -ErrorAction SilentlyContinue
		
		# Read the file
		$content = Get-Content -LiteralPath $filePath
		
		# Replace the spaces with tabs
		$content.Replace($pattern, $tab) | Set-Content -LiteralPath $filePath -Force
		
		# Clear the variables
		Remove-Variable -Name filePath, content -ErrorAction SilentlyContinue
		
	}
	
}

End {
	
	# Clear the variables
	Remove-Variable -Name tab, pattern -ErrorAction SilentlyContinue
	
}
