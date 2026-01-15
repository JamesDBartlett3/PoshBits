<#
.SYNOPSIS
    Rewrites Git commit author/committer information across repository history.

.DESCRIPTION
    This script uses git filter-branch to rewrite commit metadata. It can either:
    - Replace ALL commits with new author info (default)
    - Replace only commits matching a specific old author name/email

    WARNING: This rewrites Git history! Only use on repos where you can force push,
    and coordinate with any collaborators before running.

.PARAMETER NewName
    The new author/committer name to use.

.PARAMETER NewEmail
    The new author/committer email to use.

.PARAMETER OldEmail
    (Optional) Only rewrite commits that match this email address.
    If not specified, ALL commits will be rewritten.

.PARAMETER OldName
    (Optional) Only rewrite commits that match this author name.
    If not specified, ALL commits will be rewritten.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    .\Repair-GitCommitAuthor.ps1 -NewName "JamesDBartlett3" -NewEmail "37491308+jamesdbartlett3@users.noreply.github.com"

    Rewrites ALL commits to use the specified name and email.

.EXAMPLE
    .\Repair-GitCommitAuthor.ps1 -NewName "JamesDBartlett3" -NewEmail "37491308+jamesdbartlett3@users.noreply.github.com" -OldEmail "wrong@email.com"

    Only rewrites commits where the author email was "wrong@email.com".

.EXAMPLE
    .\Repair-GitCommitAuthor.ps1 -NewName "JamesDBartlett3" -NewEmail "37491308+jamesdbartlett3@users.noreply.github.com" -Force

    Rewrites all commits without prompting for confirmation.

.NOTES
    After running this script, you'll need to force push:
    git push origin <branch> --force
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NewName,

    [Parameter(Mandatory = $true)]
    [string]$NewEmail,

    [Parameter(Mandatory = $false)]
    [string]$OldEmail,

    [Parameter(Mandatory = $false)]
    [string]$OldName,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Verify we're in a git repository
$gitRoot = git rev-parse --show-toplevel 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not a git repository. Please run this script from within a git repo."
    exit 1
}

Write-Host "Git Repository: $gitRoot" -ForegroundColor Cyan

# Get current branch
$currentBranch = git rev-parse --abbrev-ref HEAD
Write-Host "Current Branch: $currentBranch" -ForegroundColor Cyan

# Count commits that will be affected
$commitCount = git rev-list --count HEAD
Write-Host "Total Commits: $commitCount" -ForegroundColor Cyan

# Show current commit authors
Write-Host "`nCurrent commit authors in this repo:" -ForegroundColor Yellow
git log --format="%an <%ae>" | Sort-Object -Unique | ForEach-Object {
    Write-Host "  $_" -ForegroundColor Gray
}

Write-Host "`n--- Planned Changes ---" -ForegroundColor Yellow
Write-Host "New Author Name:  $NewName" -ForegroundColor Green
Write-Host "New Author Email: $NewEmail" -ForegroundColor Green

if ($OldEmail -or $OldName) {
    Write-Host "`nFilter (only matching commits will be changed):" -ForegroundColor Yellow
    if ($OldEmail) { Write-Host "  Old Email: $OldEmail" -ForegroundColor Gray }
    if ($OldName) { Write-Host "  Old Name:  $OldName" -ForegroundColor Gray }
} else {
    Write-Host "`nScope: ALL commits will be rewritten" -ForegroundColor Red
}

# Confirmation prompt
if (-not $Force) {
    Write-Host "`n" -NoNewline
    Write-Warning "This will rewrite Git history! This action cannot be undone."
    Write-Host "After completion, you'll need to run: " -NoNewline
    Write-Host "git push origin $currentBranch --force" -ForegroundColor Cyan

    $confirm = Read-Host "`nType 'yes' to proceed"
    if ($confirm -ne 'yes') {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
}

# Check for uncommitted changes
$status = git status --porcelain
if ($status) {
    Write-Host "`nYou have uncommitted changes. Stashing them temporarily..." -ForegroundColor Yellow
    git stash push -m "Temporary stash for author rewrite"
    $stashed = $true
} else {
    $stashed = $false
}

# Build the filter-branch command
if ($OldEmail -or $OldName) {
    # Conditional rewrite - only matching commits
    $conditions = @()
    if ($OldEmail) { $conditions += "`$GIT_AUTHOR_EMAIL = '$OldEmail'" }
    if ($OldName) { $conditions += "`$GIT_AUTHOR_NAME = '$OldName'" }
    $conditionString = $conditions -join ' -and '

    $envFilter = @"
if [ "`$GIT_AUTHOR_EMAIL" = "$OldEmail" ] || [ "`$GIT_AUTHOR_NAME" = "$OldName" ]; then
    export GIT_AUTHOR_NAME="$NewName"
    export GIT_AUTHOR_EMAIL="$NewEmail"
    export GIT_COMMITTER_NAME="$NewName"
    export GIT_COMMITTER_EMAIL="$NewEmail"
fi
"@
} else {
    # Unconditional rewrite - all commits
    $envFilter = @"
export GIT_AUTHOR_NAME="$NewName"
export GIT_AUTHOR_EMAIL="$NewEmail"
export GIT_COMMITTER_NAME="$NewName"
export GIT_COMMITTER_EMAIL="$NewEmail"
"@
}

Write-Host "`nRewriting commit history..." -ForegroundColor Yellow

# Set environment variable to suppress warning
$env:FILTER_BRANCH_SQUELCH_WARNING = "1"

# Run git filter-branch
$result = git filter-branch -f --env-filter $envFilter HEAD 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "git filter-branch failed: $result"
    if ($stashed) {
        Write-Host "Restoring stashed changes..." -ForegroundColor Yellow
        git stash pop
    }
    exit 1
}

Write-Host $result -ForegroundColor Gray

# Restore stashed changes if any
if ($stashed) {
    Write-Host "`nRestoring stashed changes..." -ForegroundColor Yellow
    git stash pop
}

# Show results
Write-Host "`n--- Results ---" -ForegroundColor Green
Write-Host "Commit authors after rewrite:" -ForegroundColor Yellow
git log --format="%an <%ae>" | Sort-Object -Unique | ForEach-Object {
    Write-Host "  $_" -ForegroundColor Gray
}

Write-Host "`n" -NoNewline
Write-Host "SUCCESS!" -ForegroundColor Green -BackgroundColor Black
Write-Host "`nNext step - force push to remote:" -ForegroundColor Yellow
Write-Host "  git push origin $currentBranch --force" -ForegroundColor Cyan

# Clean up backup refs created by filter-branch
Write-Host "`nCleaning up backup refs..." -ForegroundColor Gray
git for-each-ref --format="%(refname)" refs/original/ | ForEach-Object {
    git update-ref -d $_
}

Write-Host "`nDone!" -ForegroundColor Green
