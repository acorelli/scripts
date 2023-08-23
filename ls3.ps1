#
# Author: Corelli
# Date: 07AUG2023
# Version: 0.1
#
# NOTE:   Powershell does not use UTF8 strings by default. Please
#       check encoding using ANSI to make sure special characters
#       display properly

<#
	.SYNOPSIS
	ls + s3. Quick script to make using s3mock easier
	
	.DESCRIPTION
	ls + s3. Script for listing local s3mock files
	
	.PARAMETER Help
	Show the help documentation
	
	.PARAMETER s3Path
	The s3 bucket path with or without the leading s3://, e.g. myBucket, s3://test
	
	.EXAMPLE
	PS> ls3.ps1 my-bucket
#>
[CmdletBinding(DefaultParametersetName="default")]
param(
	[switch][Alias("h")] $Help,             # include to display the help message and then exit
	[Parameter(ValueFromPipeline = $true)]
	[string][Alias("s3")] $s3Path           # The desired s3 bucket path to list
)

if($Help){
	# call the Get-Help
	Get-Help $MyInvocation.MyCommand.Path
	exit 0
}

if(-not $s3path.StartsWith("s3://")){
  $s3path = "s3://" + $s3Path	
}

if(-not $s3Path.EndsWith("/")){
	$s3Path += "/"
}

# Note these endpoint details are configured to work with the current s3mock configuration
# Change/update them as necessary to point to your local s3 endpoint
"aws s3 ls $s3Path --endpoint-url http://localhost:9090" | Write-Host -ForegroundColor Yellow
aws s3 ls $s3Path --endpoint-url http://localhost:9090