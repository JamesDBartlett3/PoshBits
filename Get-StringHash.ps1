param(
	[Parameter(Mandatory)]
	[string]$String,

	[Parameter()]
	[ValidateSet("MD5","SHA1","SHA256","SHA384","SHA512")]
	[string]$HashingAlgorithm = "SHA256"
)

$stream = [IO.MemoryStream]::new([byte[]][char[]]$String)

return (Get-FileHash -InputStream $stream -Algorithm $HashingAlgorithm).Hash