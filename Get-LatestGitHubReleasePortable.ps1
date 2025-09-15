#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads the latest GitHub release portable Windows app for a specified repository.

.DESCRIPTION
    This script queries the GitHub Releases API for a specified repository, finds the latest release,
    downloads the Windows portable application (filtering out other OS versions), extracts the contents,
    moves them to a specified location, and unblocks any executable files.

.PARAMETER Repository
    The GitHub repository. Can be specified as:
    - 'owner/repository' format (e.g., 'notepad-plus-plus/notepad-plus-plus')
    - Full GitHub URL (e.g., 'https://github.com/notepad-plus-plus/notepad-plus-plus')

.PARAMETER DestinationPath
    Optional local filesystem path where the portable app should be installed. 
    If not specified, files will be extracted in-place to the current directory.

.PARAMETER GitHubToken
    Optional GitHub personal access token for authenticated requests (increases rate limits).

.PARAMETER Force
    Overwrites existing files in the destination path without prompting.

.EXAMPLE
    Get-LatestGitHubReleasePortable -Repository "notepad-plus-plus/notepad-plus-plus" -DestinationPath "C:\Tools\Notepad++"

.EXAMPLE
    Get-LatestGitHubReleasePortable -Repository "https://github.com/git-for-windows/git" -DestinationPath "C:\Tools\Git" -Force

.EXAMPLE
    Get-LatestGitHubReleasePortable -Repository "microsoft/powertoys"
    # Extracts to current directory

.NOTES
    Author: James Bartlett
    Requires: PowerShell 5.1 or later
    The script filters for Windows portable apps by excluding files with "linux", "mac", "darwin", "arm" in their names.
#>

[CmdletBinding()]
param(
	[Parameter(Mandatory = $true, HelpMessage = "GitHub repository in 'owner/repo' format or full GitHub URL")]
	[ValidateNotNullOrEmpty()]
	[string]$Repository,

	[Parameter(Mandatory = $false, HelpMessage = "Local destination path for the portable app (defaults to current directory)")]
	[string]$DestinationPath,

	[Parameter(Mandatory = $false, HelpMessage = "GitHub personal access token")]
	[string]$GitHubToken,

	[Parameter(Mandatory = $false, HelpMessage = "Overwrite existing files without prompting")]
	[switch]$Force
)

# Set error action preference
$ErrorActionPreference = 'Stop'

# Function to write colored output
function Write-ColoredOutput {
	param(
		[string]$Message,
		[string]$Color = 'White'
	)
	Write-Host $Message -ForegroundColor $Color
}

# Function to parse repository string and extract owner/repo
function Get-RepositoryInfo {
	param(
		[string]$RepositoryString
	)
	
	# Remove trailing slash if present
	$RepositoryString = $RepositoryString.TrimEnd('/')
	
	# Check if it's a full GitHub URL
	if ($RepositoryString -match '^https://github\.com/([^/]+)/([^/]+)/?$') {
		$owner = $Matches[1]
		$repo = $Matches[2]
	}
	# Check if it's in owner/repo format
	elseif ($RepositoryString -match '^([^/]+)/([^/]+)$') {
		$owner = $Matches[1]
		$repo = $Matches[2]
	}
	else {
		throw "Invalid repository format. Use 'owner/repository' or 'https://github.com/owner/repository'"
	}
	
	return @{
		Owner      = $owner
		Repository = $repo
	}
}

# Function to get latest release from GitHub API
function Get-GitHubLatestRelease {
	param(
		[string]$Owner,
		[string]$Repository,
		[string]$Token
	)
    
	$apiUrl = "https://api.github.com/repos/$Owner/$Repository/releases/latest"
	$headers = @{
		'User-Agent' = 'PowerShell-GitHubReleaseDownloader'
	}
    
	if ($Token) {
		$headers['Authorization'] = "token $Token"
	}
    
	try {
		Write-ColoredOutput "Querying GitHub API for latest release..." "Cyan"
		$response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get
		return $response
	}
	catch {
		if ($_.Exception.Response.StatusCode -eq 404) {
			throw "Repository '$Owner/$Repository' not found or no releases available."
		}
		elseif ($_.Exception.Response.StatusCode -eq 403) {
			throw "API rate limit exceeded. Consider using a GitHub token with the -GitHubToken parameter."
		}
		else {
			throw "Failed to query GitHub API: $($_.Exception.Message)"
		}
	}
}

# Function to filter Windows portable assets
function Get-WindowsPortableAsset {
	param(
		[array]$Assets
	)
    
	# Patterns to exclude (non-Windows or non-portable)
	$excludePatterns = @(
		'linux', 'mac', 'darwin', 'osx', 'arm64', 'aarch64',
		'android', 'ios', 'source', 'src', 'debug', 'symbols'
	)
    
	# Patterns to prefer (Windows portable indicators)
	$preferPatterns = @('portable', 'win', 'windows', 'x64', 'x86', 'exe', 'zip')
    
	Write-ColoredOutput "Filtering assets for Windows portable versions..." "Cyan"
    
	# Filter out non-Windows assets
	$windowsAssets = $Assets | Where-Object {
		$assetName = $_.name.ToLower()
		$exclude = $false
        
		foreach ($pattern in $excludePatterns) {
			if ($assetName -match $pattern) {
				$exclude = $true
				break
			}
		}
        
		return -not $exclude
	}
    
	if (-not $windowsAssets) {
		throw "No Windows-compatible assets found in the latest release."
	}
    
	# Prefer portable versions
	$portableAssets = $windowsAssets | Where-Object {
		$assetName = $_.name.ToLower()
		foreach ($pattern in $preferPatterns) {
			if ($assetName -match $pattern) {
				return $true
			}
		}
		return $false
	}
    
	# Return the most suitable asset
	$selectedAsset = if ($portableAssets) { $portableAssets[0] } else { $windowsAssets[0] }
    
	Write-ColoredOutput "Selected asset: $($selectedAsset.name)" "Green"
	return $selectedAsset
}

# Function to download and extract asset
function Invoke-AssetDownloadAndExtraction {
	param(
		[object]$Asset,
		[string]$DestinationPath,
		[bool]$Force,
		[bool]$InPlace = $false
	)
    
	# Adjust destination path for in-place extraction
	$finalDestinationPath = $DestinationPath
	if ($InPlace -and ($Asset.name -match '\.(zip|7z)$')) {
		# Create a subfolder based on the zip file name (without extension)
		$zipBaseName = [System.IO.Path]::GetFileNameWithoutExtension($Asset.name)
		$finalDestinationPath = Join-Path $DestinationPath $zipBaseName
		Write-ColoredOutput "In-place extraction: Creating subfolder '$zipBaseName'" "Cyan"
	}
    
	# Create destination directory if it doesn't exist
	if (-not (Test-Path $finalDestinationPath)) {
		Write-ColoredOutput "Creating destination directory: $finalDestinationPath" "Cyan"
		New-Item -Path $finalDestinationPath -ItemType Directory -Force | Out-Null
	}
	elseif ((Get-ChildItem $finalDestinationPath -ErrorAction SilentlyContinue) -and -not $Force) {
		$response = Read-Host "Destination path '$finalDestinationPath' is not empty. Continue? (y/N)"
		if ($response -notmatch '^[Yy]') {
			throw "Operation cancelled by user."
		}
	}
    
	# Create temp directory for download
	$tempDir = Join-Path $env:TEMP "GitHubRelease_$(Get-Random)"
	New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    
	try {
		# Download the asset
		$downloadPath = Join-Path $tempDir $Asset.name
		Write-ColoredOutput "Downloading $($Asset.name) ($([math]::Round($Asset.size / 1MB, 2)) MB)..." "Cyan"
        
		$progressParams = @{
			Activity = "Downloading $($Asset.name)"
			Status   = "Please wait..."
		}
		Write-Progress @progressParams
        
		Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $downloadPath -UseBasicParsing
        
		Write-Progress @progressParams -Completed
		Write-ColoredOutput "Download completed successfully." "Green"
        
		# Extract if it's a zip file
		if ($Asset.name -match '\.(zip|7z)$') {
			Write-ColoredOutput "Extracting archive..." "Cyan"
            
			if ($Asset.name -match '\.zip$') {
				# Use built-in Expand-Archive for zip files
				Expand-Archive -Path $downloadPath -DestinationPath $tempDir -Force
			}
			else {
				throw "Archive format not supported. Only ZIP files are currently supported."
			}
            
			# Find extracted content (exclude the original zip)
			$extractedItems = Get-ChildItem $tempDir | Where-Object { $_.Name -ne $Asset.name }
            
			if ($extractedItems) {
				Write-ColoredOutput "Moving extracted files to destination..." "Cyan"
				foreach ($item in $extractedItems) {
					$targetPath = Join-Path $finalDestinationPath $item.Name
					if ($Force -and (Test-Path $targetPath)) {
						Remove-Item $targetPath -Recurse -Force
					}
					Move-Item $item.FullName $finalDestinationPath -Force
				}
			}
			else {
				Write-ColoredOutput "No files were extracted. Moving the downloaded file..." "Yellow"
				Move-Item $downloadPath $finalDestinationPath -Force
			}
		}
		else {
			# Not an archive, just move the file
			Write-ColoredOutput "Moving downloaded file to destination..." "Cyan"
			$targetPath = Join-Path $finalDestinationPath $Asset.name
			if ($Force -and (Test-Path $targetPath)) {
				Remove-Item $targetPath -Force
			}
			Move-Item $downloadPath $finalDestinationPath -Force
		}
        
		Write-ColoredOutput "Files successfully moved to: $finalDestinationPath" "Green"
        
	}
	finally {
		# Clean up temp directory
		if (Test-Path $tempDir) {
			Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
		}
	}
}

# Function to unblock executable files
function Invoke-UnblockExecutables {
	param(
		[string]$Path
	)
    
	Write-ColoredOutput "Unblocking executable files..." "Cyan"
    
	$executables = Get-ChildItem $Path -Recurse -Include "*.exe", "*.dll", "*.msi" -ErrorAction SilentlyContinue
    
	foreach ($exe in $executables) {
		try {
			Unblock-File $exe.FullName
			Write-ColoredOutput "Unblocked: $($exe.Name)" "Green"
		}
		catch {
			Write-ColoredOutput "Warning: Could not unblock $($exe.Name): $($_.Exception.Message)" "Yellow"
		}
	}
    
	if ($executables.Count -eq 0) {
		Write-ColoredOutput "No executable files found to unblock." "Yellow"
	}
	else {
		Write-ColoredOutput "Unblocked $($executables.Count) executable file(s)." "Green"
	}
}

# Main script execution
try {
	Write-ColoredOutput "Starting GitHub Release Portable App Download" "Magenta"
	
	# Parse repository string to extract owner and repository name
	$repoInfo = Get-RepositoryInfo -RepositoryString $Repository
	$owner = $repoInfo.Owner
	$repoName = $repoInfo.Repository
	
	# Set default destination path if not provided
	$inPlaceExtraction = $false
	if (-not $DestinationPath) {
		$DestinationPath = Get-Location | Select-Object -ExpandProperty Path
		$inPlaceExtraction = $true
		Write-ColoredOutput "No destination specified, using current directory: $DestinationPath" "Yellow"
	}
	
	Write-ColoredOutput "Repository: $owner/$repoName" "White"
	Write-ColoredOutput "Destination: $DestinationPath" "White"
	Write-ColoredOutput "" "White"
    
	# Get latest release information
	$release = Get-GitHubLatestRelease -Owner $owner -Repository $repoName -Token $GitHubToken
    
	Write-ColoredOutput "Latest release: $($release.tag_name) - $($release.name)" "Green"
	Write-ColoredOutput "Published: $($release.published_at)" "White"
	Write-ColoredOutput "Assets available: $($release.assets.Count)" "White"
	Write-ColoredOutput "" "White"
    
	if ($release.assets.Count -eq 0) {
		throw "No assets found in the latest release."
	}
    
	# Filter and select Windows portable asset
	$selectedAsset = Get-WindowsPortableAsset -Assets $release.assets
    
	# Download and extract
	Invoke-AssetDownloadAndExtraction -Asset $selectedAsset -DestinationPath $DestinationPath -Force $Force -InPlace $inPlaceExtraction
    
	# Determine the actual path where files were extracted
	$actualPath = $DestinationPath
	if ($inPlaceExtraction -and ($selectedAsset.name -match '\.(zip|7z)$')) {
		$zipBaseName = [System.IO.Path]::GetFileNameWithoutExtension($selectedAsset.name)
		$actualPath = Join-Path $DestinationPath $zipBaseName
	}
    
	# Unblock executables
	Invoke-UnblockExecutables -Path $actualPath
    
	Write-ColoredOutput "" "White"
	Write-ColoredOutput "Successfully installed $($release.name) to $actualPath" "Green"
	Write-ColoredOutput "Release notes: $($release.html_url)" "Cyan"
}
catch {
	Write-ColoredOutput "" "White"
	Write-ColoredOutput "Error: $($_.Exception.Message)" "Red"
	exit 1
}
