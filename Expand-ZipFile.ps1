#------------------------------------------------------------------------------------------------------------------
# Title:      Expand-ZipFile.ps1
# Synopsis:   A PowerShell script that extracts a zip file to a specified folder
# Author:     James Bartlett @jamesdbartlett3@techhub.social
# Source:     https://github.com/jamesdbartlett3/PoshBits/blob/main/Expand-ZipFile.ps1
# 
# Parameters: 
#   1) $ZipFile = full path of the zip file (mandatory)
#   2) $DestinationFolder = the full path of the destination folder (optional)
#   3) $Overwrite = switch to overwrite any existing files (optional)
# Requires:   PowerShell 5.1 or later
#------------------------------------------------------------------------------------------------------------------

param(
  [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
    [string]$ZipFile,
  [Parameter(Mandatory=$false, Position=1, ValueFromPipeline=$true)]
    [string]$DestinationFolder = $(Split-Path -LiteralPath $ZipFile),
  [Parameter(Mandatory=$false, Position=2, ValueFromPipeline=$true)]
    [switch]$Overwrite
)

$DestinationFolder = Join-Path -Path $DestinationFolder -ChildPath $(Split-Path -Path $ZipFile -LeafBase)

# Check if the file exists
if (!(Test-Path -LiteralPath $ZipFile)) {
  Write-Error "The file $ZipFile does not exist"
  return
}

# Check the file header to see if it is a zip file
$contents = [string](Get-Content -Raw -Encoding Unknown -LiteralPath $ZipFile).ToCharArray()

# If file is a zip file, attempt to expand it
if ([convert]::tostring([convert]::toint32($contents[0]),16) -eq "4b50") {
  try {
    # Expand the zip file. If $Overwrite is specified, overwrite any existing files
    if ($Overwrite) {
      Expand-Archive -LiteralPath $ZipFile -DestinationPath $DestinationFolder -Force
    } else {
      Expand-Archive -LiteralPath $ZipFile -DestinationPath $DestinationFolder
    }
  } catch {
    # If the attempt fails, write the error to the console
    Write-Verbose $Error[0]
    Write-Error "Failed to expand the file $ZipFile"
  }
} else {
  # If the file is not a zip file, write a message to the console saying so
  Write-Error "The file $ZipFile is not a zip file"
}