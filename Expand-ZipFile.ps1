#------------------------------------------------------------------------------------------------------------------
# Title:      Expand-ZipFile.ps1
# Synopsis:   A PowerShell script that extracts a zip file to a specified folder
# Author:     James Bartlett @jamesdbartlett3@techhub.social
# Source:     https://github.com/jamesdbartlett3/PoshBits/blob/main/Expand-ZipFile.ps1
# 
# Parameters: 
#   1) $ZipFile = full path of the zip file (mandatory)
#   2) $DestinationFolder = the full path of the destination folder (optional)
# Requires:   PowerShell 5.1 or later
#------------------------------------------------------------------------------------------------------------------

param(
  [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
    [string]$ZipFile,
  [Parameter(Mandatory=$false, Position=1, ValueFromPipeline=$true)]
    [string]$DestinationFolder = $(Join-Path `
      -LiteralPath $( Split-Path -LiteralPath $ZipFile) `
      -ChildPath (Split-Path -LiteralPath $ZipFile -LeafBase))
)

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
    Expand-Archive -LiteralPath $ZipFile -DestinationPath $DestinationFolder
  } catch {
    # If the attempt fails, write the error to the console
    Write-Verbose $Error[0]
    Write-Error "Failed to expand the file $ZipFile"
  } finally {
    if(!$Error) {
      # If it succeeds, write a success message to the console
      Write-Host "The file $ZipFile was expanded to $DestinationFolder"
    }
  }
} else {
  # If the file is not a zip file, write a message to the console saying so
  Write-Error "The file $ZipFile is not a zip file"
}