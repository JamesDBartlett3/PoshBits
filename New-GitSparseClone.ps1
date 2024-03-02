<#
.SYNOPSIS
Clones a git repository with a sparse checkout.
.DESCRIPTION
Clones a git repository with a sparse checkout. This means that only the files and directories specified in the $SparseCheckoutPaths parameter will be downloaded. This can be useful for large repositories where only a small subset of the files are needed.
.PARAMETER RepoUrl
The URL of the repository to clone.
.PARAMETER LocalDir
The local directory to clone the repository into. If not specified, the repository will be cloned into a directory with the same name as the repository.
.PARAMETER SparseCheckoutPaths
The files and directories to download. If not specified, the entire repository will be downloaded.
.INPUTS
None - You cannot pipe objects to New-GitSparseClone.
.OUTPUTS
None - This function does not generate any pipeline outputs.
.EXAMPLE
New-GitSparseClone -RepoUrl "https://github.com/example/repo.git" -SparseCheckoutPaths "path/to/file.txt", "path/to/directory"
.NOTES
This function requires git to be installed and available in the PATH. It also requires that the user has the necessary permissions to clone the repository.
.LINK
Based on and inspired by this bash script on Stack Overflow: https://stackoverflow.com/a/13738951
.LINK
Follow the author on:
	- [GitHub](https://github.com/JamesDBartlett3)
	- [Mastodon](https://techhub.social/@jamesdbartlett3)
	- [LinkedIn](https://www.linkedin.com/in/jamesdbartlett3)
	- [Blog](https://datavolume.xyz)
#>

Function New-GitSparseClone {
	param(
		[Parameter(Mandatory)][string]$RepoUrl,
		[Parameter()][string]$LocalDir = (Join-Path -Path $PWD -ChildPath (Split-Path -Path $RepoUrl -Leaf)),
		[Parameter(ValueFromRemainingArguments)][string[]]$SparseCheckoutPaths
	)
	New-Item -ItemType Directory -Force -Path $LocalDir
	Set-Location -Path $LocalDir
	git init
	git remote add -f origin $RepoUrl
	$defaultBranch = (git remote show origin | ForEach-Object { if ($_ -match 'HEAD branch') { $_.Split()[-1] } })
	git config core.sparsecheckout true
	foreach ($path in $SparseCheckoutPaths) {
		Add-Content -Path ./.git/info/sparse-checkout -Value $path
	}
	git fetch origin $defaultBranch
	foreach ($path in $SparseCheckoutPaths) {
		git -C $path pull origin $defaultBranch
	}
}