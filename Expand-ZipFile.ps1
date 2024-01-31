<#
.SYNOPSIS
	Extracts a zip file to a specified folder
.DESCRIPTION
	- Extracts a zip file to a specified folder.
	- If the destination folder is specified, but does not exist, it will be created.
	- If the destination folder is not specified, a new folder will be created in the same location as the zip file, 
		with the same name as the zip file (minus the .zip extension), and the files will be extracted to that folder.
	- If the $Overwrite switch is specified, any existing files and folders will be overwritten.
	- If $ZipFile is not a valid zip file, an error will be written to the console.
.PARAMETER ZipFile (Mandatory)
	The path of the zip file to be extracted.
.PARAMETER DestinationFolder (Optional)
	The path of the folder to which the zip file will be extracted. If not specified, a new folder will be created in the same location as the zip file, with the same name as the zip file (minus the .zip extension).
.PARAMETER Overwrite (Optional)
	Specifies that any existing files and folders will be overwritten.
.EXAMPLE
	# Extract the contents of the zip file "C:\Temp\MyZipFile.zip" to the folder "C:\Temp\MyFolder", overwriting any existing files and folders.
	.\Expand-ZipFile.ps1 -ZipFile "C:\Temp\MyZipFile.zip" -DestinationFolder "C:\Temp\MyFolder" -Overwrite
.EXAMPLE
	# Take output from Get-ChildItem and extract the contents of each zip file into a new folder with the same name (minus the .zip extension) and parent directory as that zip file, skipping any existing files and folders.
	Get-ChildItem -Recurse -Path "C:\Temp" -Filter "*.zip" | .\Expand-ZipFile.ps1
.NOTES
	Requires PowerShell 5.1 or later.
.LINK
	[Original source code](https://github.com/jamesdbartlett3/PoshBits/blob/main/Expand-ZipFile.ps1)
.LINK
	[Read the author's blog](https://datavolume.xyz)
.LINK
	[Follow the author on Mastodon](https://techhub.social/@jamesdbartlett3)
.LINK
	[Follow the author on Bluesky](https://bsky.app/profile/jamesdbartlett3.bsky.social)
.LINK 
	[Follow the author on GitHub](https://github.com/jamesdbartlett3)
.LINK
	[Follow the author on LinkedIn](https://www.linkedin.com/in/jamesdbartlett3)
#>

param(
	[Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias("FullName")][string]$ZipFile
	, [Parameter()][string]$DestinationFolder
	, [Parameter()][switch]$Overwrite
)
begin {
	Write-Verbose "Expanding Zip file(s)..."
}
process {
	if (!($DestinationFolder)) {
		$DestinationFolder = [System.IO.Path]::Combine((Get-Item -LiteralPath $ZipFile).DirectoryName, [System.IO.Path]::GetFileNameWithoutExtension($ZipFile))
	}
	# Check if the file exists
	if (!(Test-Path -LiteralPath $ZipFile)) {
		Write-Error "The file $ZipFile does not exist."
		return
	}
	# Check if the destination folder exists. If not, create it
	if (!(Test-Path -LiteralPath $DestinationFolder)) {
		try {
			New-Item -Path $DestinationFolder -ItemType Directory -ErrorAction Stop | Out-Null
		}
		catch {
			Write-Error "Failed to create the folder $DestinationFolder."
			return
		}
	}
	# Check the file header to see if it is a zip file
	$contents = [string](Get-Content -Raw -Encoding Unknown -LiteralPath $ZipFile).ToCharArray()
	# Escape illegal characters in the file paths
	$DestinationFolder = [Management.Automation.WildcardPattern]::Escape($DestinationFolder)
	$ZipFile = [Management.Automation.WildcardPattern]::Escape($ZipFile)
	# If file is a zip file, attempt to expand it
	if ([convert]::tostring([convert]::toint32($contents[0]), 16) -eq "4b50") {
		try {
			# Create expression to expand the zip file. If $Overwrite switch is specified, add the -Force switch to the Expand-Archive cmdlet
			[string]$Expression = "Expand-Archive -Path '$ZipFile' -DestinationPath '$DestinationFolder' $(if ($Overwrite) { '-Force' })"
			# Invoke the expression
			Write-Host "Invoking expression: $Expression"
			Invoke-Expression $Expression
		}
		catch {
			# If the attempt fails, write the error to the console
			Write-Verbose $Error[0]
			Write-Error "Failed to expand the file $ZipFile."
		}
	}
	else {
		# If the file is not a zip file, write a message to the console saying so
		Write-Error "The file $ZipFile is not a zip file."
	}
	# Clear the variables
	$DestinationFolder = $null
	$ZipFile = $null
}