[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$UserA,

    [Parameter(Mandatory)]
    [string]$UserB,

    [switch]$SkipGroups,
    [switch]$SkipRoles,
    [switch]$SkipAppRoles,
    [switch]$SkipLicenses,

    [ValidateSet('All', 'Common', 'Different', 'UniqueToA', 'UniqueToB')]
    [string]$FilterType = 'All'
)

function Compare-UserSets {
    param(
        [string]$Section,
        [hashtable[]]$SetA,
        [hashtable[]]$SetB,
        [string]$FilterType = 'All'
    )
    Write-Host "`n=== $Section ===" -ForegroundColor Cyan
    $keysA   = @($SetA | ForEach-Object { $_.Key })
    $keysB   = @($SetB | ForEach-Object { $_.Key })
    $allKeys = ($keysA + $keysB) | Sort-Object -Unique
    $results = $allKeys | ForEach-Object {
        $key   = $_
        $inA   = $keysA -contains $key
        $inB   = $keysB -contains $key
        $label = ($SetA + $SetB | Where-Object { $_.Key -eq $key } | Select-Object -First 1).Label
        $status = if ($inA -and $inB) { 'Both' }
                  elseif ($inA)        { 'Only UserA' }
                  else                 { 'Only UserB' }
        [PSCustomObject]@{
            Name   = $label
            Id     = $key
            Status = $status
        }
    }

    $filtered = $results | Where-Object {
        if ($FilterType -eq 'All') { $true }
        elseif ($FilterType -eq 'Common') { $_.Status -eq 'Both' }
        elseif ($FilterType -eq 'Different') { $_.Status -ne 'Both' }
        elseif ($FilterType -eq 'UniqueToA') { $_.Status -eq 'Only UserA' }
        elseif ($FilterType -eq 'UniqueToB') { $_.Status -eq 'Only UserB' }
    }

    if ($filtered) {
        $filtered | Format-Table -AutoSize
    } else {
        Write-Host "  (no items match filter)" -ForegroundColor Gray
    }
}

function Get-UserAccessProfile {
    param(
        [string]$UserId,
        [switch]$SkipGroups,
        [switch]$SkipRoles,
        [switch]$SkipAppRoles,
        [switch]$SkipLicenses
    )

    $groups   = @()
    $roles    = @()
    $appRoles = @()
    $licenses = @()

    if (-not $SkipGroups -or -not $SkipRoles) {
        $memberships = Get-MgUserMemberOf -UserId $UserId -All

        if (-not $SkipGroups) {
            $groups = $memberships |
                Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.group' } |
                ForEach-Object { @{ Key = $_.Id; Label = $_.AdditionalProperties['displayName'] } }
        }

        if (-not $SkipRoles) {
            $roles = $memberships |
                Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.directoryRole' } |
                ForEach-Object { @{ Key = $_.Id; Label = $_.AdditionalProperties['displayName'] } }
        }
    }

    if (-not $SkipAppRoles) {
        $appRoles = Get-MgUserAppRoleAssignment -UserId $UserId -All |
            ForEach-Object {
                $label = if ($_.AdditionalProperties['resourceDisplayName']) {
                    $_.AdditionalProperties['resourceDisplayName']
                } else { $_.ResourceDisplayName }
                @{ Key = $_.AppRoleId; Label = $label }
            }
    }

    if (-not $SkipLicenses) {
        $licenses = Get-MgUserLicenseDetail -UserId $UserId -All |
            ForEach-Object { @{ Key = $_.SkuId; Label = $_.SkuPartNumber } }
    }

    return @{
        Groups   = $groups
        Roles    = $roles
        AppRoles = $appRoles
        Licenses = $licenses
    }
}

# --- Main ---
$userObjA = Get-MgUser -UserId $UserA
$userObjB = Get-MgUser -UserId $UserB

Write-Host "`nComparing:" -ForegroundColor Yellow
Write-Host "  A: $($userObjA.DisplayName) ($($userObjA.UserPrincipalName))"
Write-Host "  B: $($userObjB.DisplayName) ($($userObjB.UserPrincipalName))"

$splatA = @{
    UserId       = $userObjA.Id
    SkipGroups   = $SkipGroups
    SkipRoles    = $SkipRoles
    SkipAppRoles = $SkipAppRoles
    SkipLicenses = $SkipLicenses
}
$splatB = @{
    UserId       = $userObjB.Id
    SkipGroups   = $SkipGroups
    SkipRoles    = $SkipRoles
    SkipAppRoles = $SkipAppRoles
    SkipLicenses = $SkipLicenses
}

$profileA = Get-UserAccessProfile @splatA
$profileB = Get-UserAccessProfile @splatB

$nameA = $userObjA.DisplayName.Split(' ')[0]
$nameB = $userObjB.DisplayName.Split(' ')[0]

$compareSplat = @{ NameA = $nameA; NameB = $nameB }

if (-not $SkipGroups)   { Compare-UserSets -Section 'Group Memberships'    -SetA $profileA.Groups   -SetB $profileB.Groups   -FilterType $FilterType }
if (-not $SkipRoles)    { Compare-UserSets -Section 'Directory Roles'      -SetA $profileA.Roles    -SetB $profileB.Roles    -FilterType $FilterType }
if (-not $SkipAppRoles) { Compare-UserSets -Section 'App Role Assignments' -SetA $profileA.AppRoles -SetB $profileB.AppRoles -FilterType $FilterType }
if (-not $SkipLicenses) { Compare-UserSets -Section 'Assigned Licenses'    -SetA $profileA.Licenses -SetB $profileB.Licenses -FilterType $FilterType }