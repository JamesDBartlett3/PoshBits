# Install PowerShell Modules Useful for BI, DA, and DS Development

if ($PSVersionTable.PSVersion.Major -lt 7) {
	Write-Output "Please run this script with PowerShell Core version 7.0 or later."
	Write-Output "Press any key to exit..."
	$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
	exit
} else {

	Function Draw-Separator {
	    [CmdletBinding()]
	    Param(
		[Parameter(Mandatory=$false)]
		[int]$Length = $Host.UI.RawUI.WindowSize.Width
	    )
	    Write-Host ('-' * $Length)
	}

	# $isAdmin = (
	# 	[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
	# 	).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

	# if (!$isAdmin){
	# 	$a = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PSCommandPath`""
	# 	Start-Process pwsh.exe $a -Verb RunAs; exit}

	# Declare list of PowerShell modules to install
	[PSCustomObject]$modules = @(
		"Az.Accounts"
		, "Az.AnalysisServices"
		, "Az.ApiManagement"
		, "Az.AppConfiguration"
		, "Az.DataFactory"
		, "Az.DataLakeAnalytics"
		, "Az.DataLakeStore"
		, "Az.Functions"
		, "Az.LogAnalytics"
		, "Az.PowerBIEmbedded"
		, "Az.Resources"
		, "Az.Sql"
		, "Az.Storage"
		, "Az.Synapse"
		, "AzureAD"
		, "AzureADPreview"
		, "Configuration"
		, "DataGateway"
		, "DataGateway.Profile"
		, "DataMashup"
		, "dbatools"
		, "dbops"
		, "ExchangePowerShell"
		, "ImportExcel"
		, "InvokeBuild"
		, "Metadata"
		, "MicrosoftPowerBIMgmt"
		, "MicrosoftTeams"
		, "Microsoft.Online.SharePoint.PowerShell"
		, "Microsoft.Graph"
		, "ModuleBuilder"
		, "MSOnline"
		, "oh-my-posh"
		, "OnPremisesDataGatewayHAMgmt"
		, "Pester"
		, "posh-git"
		, "PowerHTML"
		, "PowerShell-Beautifier"
		, "PowerShellForGitHub"
		, "PowerShellGet"
		, "PowerShellNotebook"
		, "PowerShellProTools"
		, "ps2exe"
		, "PSFramework"
		, "PSKoans"
		, "PSReadLine"
		, "PSRequiredModules"
		, "PSScriptAnalyzer"
		, "PSScriptTools"
		, "ReportingServicesTools"
		, "SqlServer"
	)

	# Loop through $modules object and install each module
	foreach ($module in $modules) {
		Draw-Separator
		Write-Output "Installing module: '$module'..."
		Install-Module -Name $module -Scope CurrentUser -Repository PSGallery -AllowPrerelease
	}

	Draw-Separator

	# Update local help cache
	Update-Help

}
