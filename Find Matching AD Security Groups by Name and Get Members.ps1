[string]$searchTerm = "YOUR_SEARCH_TERM_HERE"
$groups = Get-ADGroup -Filter "GroupCategory -eq 'Security' -and Name -like '*$searchTerm*'"
ForEach($g in $groups) {
	$gName = $g.Name
	$d = "-" * $gName.Length
	$groupMembers = Get-ADGroupMember $g | Select-Object -Property Name
	Write-Output "`n$d `n$gName `n$d"
	ForEach($m in $groupMembers) {
		Write-Output "- $($m.Name)"
	}
}
