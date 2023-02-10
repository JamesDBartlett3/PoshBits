#------------------------------------------------------------------------------------------------------------------
# Title:      Expand-CompressedFile.ps1
# Synopsis:   A PowerShell script that expands a compressed archive file
# Author:     James Bartlett @jamesdbartlett3@techhub.social
# Source:     https://github.com/jamesdbartlett3/PoshBits/blob/main/Expand-CompressedFile.ps1
# 
# Parameters: 
#   1) $ArchiveFile = full path of the archive file (mandatory)
#   2) $DestinationFolder = the full path of the destination folder (optional)
# Requires:   PowerShell 5.1 or later
#------------------------------------------------------------------------------------------------------------------

param(
  [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
    [string]$ArchiveFile,
  [Parameter(Mandatory=$false, Position=1, ValueFromPipeline=$true)]
    [string]$DestinationFolder = $(Join-Path `
      -LiteralPath $( Split-Path -LiteralPath $ArchiveFile) `
      -ChildPath (Split-Path -LiteralPath $ArchiveFile -LeafBase))
)

# Check if the archive file exists
if (!(Test-Path -LiteralPath $ArchiveFile)) {
  Write-Error "The archive file $ArchiveFile does not exist"
  return
}

try {
  Expand-Archive -LiteralPath $ArchiveFile -DestinationPath $DestinationFolder
} catch {
  Write-Error "Failed to expand the archive file $ArchiveFile"
} finally {
  Write-Host "The archive file $ArchiveFile was expanded to $DestinationFolder"
}
