param(
	[switch][Alias("h")] $Help,                         # include to display the help message and then exit
	[switch][Alias("Test", "t")] $TestRun              # test-run, don't create merge
)

if($Help){
	# call the Get-Help
	Get-Help $MyInvocation.MyCommand.Path
	exit 0
}

if($TestRun){
	"-------- TEST RUN STARTING: --------" | Write-Host -ForegroundColor "yellow"
}

$branchOutput = git branch -a -vv

$branchesToDelete = $branchOutput | Select-String -Pattern '\s*(\S+)\s+\S+\s+\[.*: gone\]' | ForEach-Object { $_.Matches.Groups[1].Value }


if($TestRun){
	$branchesToDelete | Write-Host
	"Test Run Exiting" | Write-Host -ForegroundColor "green"
	exit 0
}

$branchesToDelete | ForEach-Object {
	$branchName = $_
	Write-Host "Deleting branch : $branchName"
	git branch -D $branchName
}