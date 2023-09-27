# TODO: Merge or replace with: https://github.com/itpro-tips/PowerShell-Toolbox/blob/master/Get-MSIFileInformation.ps1

Param (
	[Parameter(Mandatory)][string]$FileName,
	[Parameter()][ValidateSet("ProductVersion", "ProductCode")]
	[string]$Property = "ProductVersion"
)

try {
	$FullPath = (Resolve-Path $FileName).Path
	$windowsInstaller = New-Object -com WindowsInstaller.Installer

	$database = $windowsInstaller.GetType().InvokeMember(
		"OpenDatabase", "InvokeMethod", $Null, 
		$windowsInstaller, @($FullPath, 0)
	)

	$q = "SELECT Value FROM Property WHERE Property = '$Property'"
	$View = $database.GetType().InvokeMember(
		"OpenView", "InvokeMethod", $Null, $database, ($q)
	)

	$View.GetType().InvokeMember("Execute", "InvokeMethod", $Null, $View, $Null)

	$record = $View.GetType().InvokeMember(
		"Fetch", "InvokeMethod", $Null, $View, $Null
	)

	$msiFileInfo = $record.GetType().InvokeMember(
		"StringData", "GetProperty", $Null, $record, 1
	)

	$View.GetType().InvokeMember("Close", "InvokeMethod", $Null, $View, $Null)

	return $msiFileInfo

}
catch {
	throw "Failed to get MSI file info. The error was: {0}." -f $_
}
