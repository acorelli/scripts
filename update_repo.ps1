[CmdletBinding(DefaultParametersetName="default")]
param(
	[switch][Alias("Auto", "a", "y")] $AutoConfirm,
	[Parameter(ParameterSetName="LastClosed")]
	[switch][Alias("lc")] $LastClosed,
	[Parameter(ParameterSetName="FirstActive")]
	[switch][Alias("fa")] $FirstActive,
	[Parameter(ParameterSetName="LastActive")]
	[switch][Alias("la")] $LastActive,
	[Parameter(Position=0, ValueFromPipeline = $true, ParameterSetName="patch")]
	[string]
	[ValidateScript({
		# validate patch value:
		if(Test-Path $_){
			$true
		} else { throw 'Please provide a Valid Project Name (example: ./Products/Example_Project/Application)' }
	})][Alias("p")] $PRODUCT
)
$originalDir = Get-Location

Set-Location "$originalDir/$PRODUCT"
if ((Test-Path ".git") -eq $False){
	"Invalid Project Folder. Please make sure you're using the project-level folder, e.g. ./Products/Example_Project/Application" | Write-Error
	Set-Location $originalDir
	exit 1
}
git reset --hard; git switch develop; git fetch --all --prune; git pull
if($LastClosed){
	$query = "-lc"
}
if($FirstActive){
	$query = "-fa"
}
if($LastActive){
	$query = "-la"
}
$patch = (./{{path_to}}/jira_sprint_query.ps1 $query)
$patch | Write-Host
$confirm = ""
if($AutoConfirm){
	$confirm = "-y"
}
(./{{path_to}}/version_update_tool.ps1 $patch $confirm -o)

Set-Location $originalDir