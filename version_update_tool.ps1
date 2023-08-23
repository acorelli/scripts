#
# Author: Corelli
# Date: 15AUG2022
# Version: 0.1

<#
	.SYNOPSIS
	Updates the version of the CMakeLists in the project repo
	
	.DESCRIPTION
	Tool for updating repo CMakeLists version numbers in a standardized/semi-automated way
	
	.PARAMETER Help
	Show the help documentation
	
	.PARAMETER AutoConfirm
	Auto-accept the changes when specifying the version number as a parameter
	
	.PARAMETER OpenURL
	Open the GitLab merge request after completion
	
	.PARAMETER TestRun
	Perform a test-run of the update. Doesn't commit/push the new branch
	
	.PARAMETER PATCH
	Specifies the new PATCH version number to use.
	
	.PARAMETER Version
	Specifies the new version number to use. Must be in the CMake Version form of d.d.d.d (example: 1.23.456.7890)
	
	.INPUTS
	PATCH value can be piped in
	
	.OUTPUTS
	None
	
	.EXAMPLE
	PS> version_update_tool.ps1                     # run without params
	.EXAMPLE
	PS> version_update_tool.ps1 12                  # run and specify new PATCH value as 12
	.EXAMPLE
	PS> version_update_tool.ps1 -t                  # test run
	.EXAMPLE
	PS> version_update_tool.ps1 -o                  # open merge request url after creation
	.EXAMPLE
	PS> version_update_tool.ps1 -v 1.2.3.4          # specify full version number
	.EXAMPLE
	PS> version_update_tool.ps1 -v 1.2.3.4 -y       # auto-confirm diff changes
	.EXAMPLE
	PS> version_update_tool.ps1 -v 1.2.3.4 -y -o    # combination of above
	
#>
[CmdletBinding(DefaultParametersetName="default")]
param(
	[switch][Alias("h")] $Help,                         # include to display the help message and then exit
	[switch][Alias("Auto", "a", "y")] $AutoConfirm,     # include to skip confirmation prompts (requries -version)
	[switch][Alias("Open", "URL", "o", "u")] $OpenURL,  # include to open the merge request url after creation
	[switch][Alias("Test", "t")] $TestRun,              # test-run, don't create merge
	[Parameter(Position=0, ValueFromPipeline = $true, ParameterSetName="patch")]
	[string]
	[ValidateScript({
		# validate patch value:
		if( $_ -match '^\d+$' ){ $true }
		else { throw 'Please provide a Valid PATCH Number (example: 12)' }
	})][Alias("p")] $PATCH,                             # include to update just the PATCH value
	[Parameter(ParameterSetName="version")]
	[string]
	[ValidateScript({
		# validate version w/ start/end anchors
        if( $_ -match '^(\d+)\.(\d+)\.(\d+)\.(\d+)$'){ $true }
        else { throw 'Please provide a valid Version Number (example: 1.2.3.4)' }
    })][Alias("v", "ver")] $version                     # include to skip the version select dialog and use a specific version
)

if($Help){
	# call the Get-Help
	Get-Help $MyInvocation.MyCommand.Path
	exit 0
}

if($TestRun){
	$AutoConfirm = $false # turn off AutoConfirm if test-run
}

# match cmake style version numbers w/o start/end
$versionRegexAnchors = '^(\d+)\.(\d+)\.(\d+)\.(\d+)$'
$versionRegex = '(\d+)\.(\d+)\.(\d+)\.(\d+)'

# Get current branch name
$currBranch = (git branch --show-current)
Write-Debug "$currBranch"

# Check if on develop
if($currBranch -ne "develop"){
	Write-Error "You must be on the develop branch to use this tool"
	exit 1
}

# Parse current git repo version string from cmakelists
$cmroot = (git rev-parse --show-toplevel)
$repoName = ("$cmroot" | Select-String -Pattern '(\/[^\/]*)?\/([^\/]*)$' -AllMatches).Matches.Groups[0].value
Write-Debug "$repoName"
$cmlist = "/src/CMakeLists.txt"
$cmfile = ($cmroot+$cmlist)
Write-Debug "$cmFile"

$versionRegex = '(\d+)\.(\d+)\.(\d+)\.(\d+)'
$matches = Select-String -Path $cmfile $versionRegex -AllMatches
if(!$matches){
	Write-Error "Could not auto-detect CMAKE_PROJECT_VERSION. Please update the CMakeLists.txt to have a version in the form of MAJOR.MINOR.PATCH.TWEAK"
	exit 1
}
$currVersion = $matches.Matches.Groups[0].value
Write-Debug "Version: $currVersion"
$currMAJOR = $matches.Matches.Groups[1].value
$currMINOR = $matches.Matches.Groups[2].value
$currPATCH = $matches.Matches.Groups[3].value
$currTWEAK = $matches.Matches.Groups[4].value
Write-Debug "MAJOR: $currMAJOR"
Write-Debug "MINOR: $currMINOR"
Write-Debug "PATCH: $currPATCH"
Write-Debug "TWEAK: $currTWEAK"


if($PATCH){
	$version = "$currMAJOR.$currMINOR.$PATCH.$currTWEAK"
}

if(!$version){
	Write-Debug "No version specified"
	if($AutoConfirm){ Write-Debug "Disabling auto-confirm" }
	$AutoConfirm = $false
	
	Write-Host "Current Version is: " -NoNewLine
	Write-Host "$currVersion" -ForegroundColor "yellow"
	do {
		$newVersion = Read-Host "Enter new Version number (d.d.d.d)"
	} while( $newVersion -notmatch $versionRegexAnchors ) # regex match user input
	$version = $newVersion
}

# check if update branch already exists
$target = "update-version-$version"
if( (git rev-parse --verify refs/heads/$target).Length -ne 0){
	Write-Error "Target branch already exists"
	Write-Debug "Resetting to develop"
	git reset --hard
	Exit 1
}

# reset; fetch; pull updates to develop
git reset --hard; git fetch; git pull

######
# regex replace the version in the cmake
(Get-Content $cmfile) -replace $versionRegex, $version | Out-File $cmfile -Encoding ascii 

$changes = (git diff)

Write-Host "Diff: "
for($idx = 0; $idx -lt $changes.Length; $idx++){
	$char = $changes[$idx][0]
	# color diff
	[console]::ResetColor()
	if($char -eq '+'){
		[console]::ForegroundColor = "green"
	}
	if( $char -eq '-'){
		[console]::ForegroundColor = "red"
	}
	Write-Host $changes[$idx]
}
[console]::ResetColor()

if(!$AutoConfirm -and !$TestRun){
	# prompt user to confirm diff
	$title    = 'Review Diff'
	$question = 'Proceed?'
	$choices  = '&Yes', '&No'
	$result = $Host.UI.PromptForChoice($title, $question, $choices, 1)
	if($result -ne 0){
		Write-Host "User canceled update tool. Exiting" -ForegroundColor "yellow" 
		Write-Debug "Resetting to develop"
		git reset --hard
		exit 0
	}
}

if(!$TestRun){
	git switch -c $target

	git commit -am "Update Version to $version"	
	$remoteOutput = $( $output = git push --porcelain `
			-o merge_request.create `
			-o merge_request.remove_source_branch `
			-o merge_request.title="Non-JIRA Issue: Update Version to $version" `
			-o merge_request.description="Update version to $version" `
			-o merge_request.draft `
			-o merge_request.label="Automated" `
			-o merge_request.label="Version Update" `
			-o merge_request.assign="{{tech_lead or your username}}" `
			-u origin HEAD) 2>&1
	$remoteOutput | Write-Host -ForegroundColor "yellow"
	$output | Write-Host
	if($OpenURL){
		$url = "$remoteOutput" -match "(https:\/\/[^\s]*)"
		if($url){
			Start-Process $matches[0]
		}
	}
} else {
	Write-Host "test run finished. resetting to develop" -ForegroundColor "yellow"
	git reset --hard
}

[console]::ForegroundColor = "green"
Write-Host "Finished. Exiting"
[console]::ResetColor()
exit 0