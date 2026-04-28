<#
.SYNOPSIS
    Collects git commit messages by the current user since a given date across multiple repos.

.DESCRIPTION
    Walks each supplied repo path, runs git log filtered to the current user and date,
    then groups results by date and repo. Outputs to stdout and optionally to a markdown file.

.PARAMETER Since
    Start date (inclusive). Accepts anything [datetime]::Parse understands, e.g. 2025-01-01.

.PARAMETER Repos
    One or more paths to local git repositories.

.PARAMETER OutFile
    Optional path for a markdown report. If omitted, results go to stdout only.

.PARAMETER Author
    Override the git author filter. Defaults to `git config user.name` / `git config user.email`.

.EXAMPLE
    .\Get-GitCommits.ps1 -Since 2025-03-01 -Repos C:\src\api, C:\src\ui
    .\Get-GitCommits.ps1 -Since 2025-03-01 -Repos C:\src\api -OutFile .\commits.md
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [datetime]$Since,

    [Parameter(Mandatory)]
    [string[]]$Repos,

    [string]$OutFile,

    [string]$Author
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Resolve author identity
# ---------------------------------------------------------------------------
if (-not $Author) {
    $Author = (git config user.name 2>$null)
    if (-not $Author) { $Author = (git config user.email 2>$null) }
    if (-not $Author) {
        Write-Error "Could not determine git user. Pass -Author explicitly."
        return
    }
}

$sinceStr = $Since.ToString('yyyy-MM-dd')

Write-Host "Collecting commits by '$Author' since $sinceStr ...`n" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Collect commits
# ---------------------------------------------------------------------------
$allCommits = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($repoPath in $Repos) {
    $resolved = Resolve-Path $repoPath -ErrorAction SilentlyContinue
    if (-not $resolved -or -not (Test-Path (Join-Path $resolved '.git'))) {
        Write-Warning "Skipping '$repoPath' — not a git repository."
        continue
    }

    $repoName = Split-Path $resolved -Leaf

    # --format: ISO date | subject | full hash (pipe-delimited)
    $logArgs = @(
        '-C', $resolved,
        'log',
        "--since=$sinceStr",
        "--author=$Author",
        '--format=%aI|%s|%H',
        '--all'
    )

    $lines = & git @logArgs 2>$null

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\|', 3
        if ($parts.Count -lt 3) { continue }

        $commitDate = ([datetimeoffset]::Parse($parts[0])).LocalDateTime.Date
        $allCommits.Add([PSCustomObject]@{
            Date    = $commitDate
            Repo    = $repoName
            Subject = $parts[1]
            Hash    = $parts[2].Substring(0, 8)
        })
    }
}

if ($allCommits.Count -eq 0) {
    Write-Host "No commits found." -ForegroundColor Yellow
    return
}

# ---------------------------------------------------------------------------
# Group by Date → Repo and build output
# ---------------------------------------------------------------------------
$grouped = $allCommits |
    Sort-Object Date, Repo |
    Group-Object { $_.Date.ToString('yyyy-MM-dd') }

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("# Git Commits — $Author (since $sinceStr)")
[void]$sb.AppendLine()

foreach ($dateGroup in $grouped) {
    [void]$sb.AppendLine("## $($dateGroup.Name)")
    [void]$sb.AppendLine()

    $repoGroups = $dateGroup.Group | Group-Object Repo
    foreach ($rg in $repoGroups) {
        [void]$sb.AppendLine("### $($rg.Name)")
        [void]$sb.AppendLine()
        foreach ($c in $rg.Group) {
            [void]$sb.AppendLine("- ``$($c.Hash)`` $($c.Subject)")
        }
        [void]$sb.AppendLine()
    }
}

$output = $sb.ToString().TrimEnd()

# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------
Write-Host $output

if ($OutFile) {
    $output | Set-Content -Path $OutFile -Encoding UTF8
    Write-Host "`nReport written to $OutFile" -ForegroundColor Green
}
