Param(
	[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
	[string]$String,

	[Parameter()]
	[ValidateSet("MD5","SHA1","SHA256","SHA384","SHA512")]
	[string]$HashingAlgorithm = "SHA256"
)
process {
	$stream = [IO.MemoryStream]::new([byte[]][char[]]$String)
	return (Get-FileHash -InputStream $stream -Algorithm $HashingAlgorithm).Hash
}