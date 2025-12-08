<#
.SYNOPSIS
    Sets up Git branch isolation for specific files using .gitignore and .gitattributes.

.DESCRIPTION
    This script automates the process of isolating specific files to one branch (e.g., dev)
    while excluding them from another branch (e.g., main) using Git's ignore and merge strategies.
    
    The script will:
    1. Create/update .gitignore on the excluded branch to ignore specified files
    2. Create/update .gitattributes on both branches with merge=ours strategy
    3. Commit changes on both branches
    4. Configure Git's merge.ours driver

.PARAMETER IsolatedFiles
    Array of file paths to isolate (relative to repository root).
    These files will be tracked in the development branch but ignored in the main branch.

.PARAMETER DevBranch
    Name of the branch where files will be tracked. Default: 'dev'

.PARAMETER MainBranch
    Name of the branch where files will be ignored. Default: 'main'

.PARAMETER CommitChanges
    If specified, automatically commits changes. Otherwise, stages files for manual review.

.EXAMPLE
    .\Setup-GitBranchIsolation.ps1 -IsolatedFiles @('.github/copilot-instructions.md', 'TODO.md')
    
    Sets up isolation for two documentation files using default branch names.

.EXAMPLE
    .\Setup-GitBranchIsolation.ps1 -IsolatedFiles @('config.local.json', 'secrets.env') -DevBranch 'develop' -MainBranch 'production' -CommitChanges
    
    Sets up isolation for config files between custom branch names, then automatically commits the changes.

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$IsolatedFiles,
    
    [Parameter(Mandatory = $false)]
    [string]$DevBranch = 'dev',
    
    [Parameter(Mandatory = $false)]
    [string]$MainBranch = 'main',
    
    [Parameter(Mandatory = $false)]
    [switch]$CommitChanges
)

# Ensure we're in a Git repository
if (-not (Test-Path .git)) {
    Write-Error "Not in a Git repository root. Please run this script from the repository root."
    exit 1
}

# Store original branch
$originalBranch = git branch --show-current
Write-Host "Current branch: $originalBranch" -ForegroundColor Cyan

# Configure merge.ours driver if not already set
$mergeDriver = git config --get merge.ours.driver
if (-not $mergeDriver) {
    Write-Host "Configuring merge.ours driver..." -ForegroundColor Yellow
    git config merge.ours.driver true
}

# Function to update or create .gitignore
function Update-GitIgnore {
    param([string[]]$FilesToIgnore)
    
    $ignoreContent = @"
# Development documentation files (tracked in $DevBranch branch only)
"@
    
    foreach ($file in $FilesToIgnore) {
        $ignoreContent += "`n$file"
    }
    
    Set-Content -Path .gitignore -Value $ignoreContent -Force
    Write-Host "  Updated .gitignore" -ForegroundColor Green
}

# Function to update or create .gitattributes
function Update-GitAttributes {
    param(
        [string[]]$ProtectedFiles,
        [string]$BranchName
    )
    
    $attrContent = @"
# Always keep $BranchName branch version of these files when merging
"@
    
    foreach ($file in $ProtectedFiles) {
        $attrContent += "`n$file merge=ours"
    }
    
    Set-Content -Path .gitattributes -Value $attrContent -Force
    Write-Host "  Updated .gitattributes" -ForegroundColor Green
}

# Switch to main branch and set up exclusions
Write-Host "`nSetting up $MainBranch branch..." -ForegroundColor Cyan
git checkout $MainBranch 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to checkout $MainBranch branch. Does it exist?"
    git checkout $originalBranch
    exit 1
}

# Update .gitignore to exclude isolated files
Update-GitIgnore -FilesToIgnore $IsolatedFiles

# Update .gitattributes to protect isolated files + config files
$mainProtectedFiles = $IsolatedFiles + @('.gitignore', '.gitattributes')
Update-GitAttributes -ProtectedFiles $mainProtectedFiles -BranchName $MainBranch

# Stage or commit changes
git add .gitignore .gitattributes
if ($CommitChanges) {
    git commit -m "Configure branch isolation for $MainBranch branch" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Committed changes to $MainBranch" -ForegroundColor Green
    } else {
        Write-Host "  No changes to commit on $MainBranch" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Staged changes (use 'git commit' to finalize)" -ForegroundColor Yellow
}

# Switch to dev branch and set up tracking
Write-Host "`nSetting up $DevBranch branch..." -ForegroundColor Cyan
git checkout $DevBranch 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to checkout $DevBranch branch. Does it exist?"
    git checkout $originalBranch
    exit 1
}

# Create minimal .gitignore (no exclusions for isolated files)
$devIgnoreContent = @"
# $DevBranch branch - no ignores for documentation files
# These files are tracked here
"@
Set-Content -Path .gitignore -Value $devIgnoreContent -Force
Write-Host "  Updated .gitignore" -ForegroundColor Green

# Update .gitattributes to protect only config files
Update-GitAttributes -ProtectedFiles @('.gitignore', '.gitattributes') -BranchName $DevBranch

# Stage or commit changes
git add .gitignore .gitattributes
if ($CommitChanges) {
    git commit -m "Configure branch isolation for $DevBranch branch" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Committed changes to $DevBranch" -ForegroundColor Green
    } else {
        Write-Host "  No changes to commit on $DevBranch" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Staged changes (use 'git commit' to finalize)" -ForegroundColor Yellow
}

# Return to original branch
Write-Host "`nReturning to $originalBranch branch..." -ForegroundColor Cyan
git checkout $originalBranch

Write-Host "`n✓ Branch isolation setup complete!" -ForegroundColor Green
Write-Host "`nConfiguration summary:" -ForegroundColor Cyan
Write-Host "  - Files isolated to $DevBranch`: $($IsolatedFiles -join ', ')" -ForegroundColor White
Write-Host "  - Files ignored in $MainBranch`: $($IsolatedFiles -join ', ')" -ForegroundColor White
Write-Host "  - Config files protected on both branches: .gitignore, .gitattributes" -ForegroundColor White
Write-Host "`nMerge behavior:" -ForegroundColor Cyan
Write-Host "  - $DevBranch → $MainBranch`: Isolated files stay excluded from $MainBranch" -ForegroundColor White
Write-Host "  - $MainBranch → $DevBranch`: Config files stay as-is on each branch" -ForegroundColor White
