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
		PS C:\> Format-IndentSpacesAsTabs -InputFile ".\MyScript.ps1"
	
	.EXAMPLE
		PS C:\> Get-ChildItem -Path ".\*.ps1" | Format-IndentSpacesAsTabs -Indentation 4
	
#>

# Parameters
Param(
	
	[Parameter(
		Mandatory = $true,
		ValueFromPipeline = $true
	)]
	[Alias("FullName")]
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
	
	# Loop through each file
	ForEach ($file in $InputFile) {
		
		# Read the file
		$content = Get-Content -LiteralPath $file
		
		# Replace the spaces with tabs
		$content.Replace($pattern, $tab) | Set-Content -LiteralPath $file -Force
		
	}
	
}

End {
	
	# Clear the variables
	Remove-Variable -Name tabWidth, tab, pattern -ErrorAction SilentlyContinue
	
}