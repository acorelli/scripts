#
# Author: Corelli
# Date: 23AUG2022
# Version: 0.1

<#
	.SYNOPSIS
	Queries the  Jira board for sprint numbers
	
	.DESCRIPTION
	Tool for querying the  Jira Board to feed the number into other scripts
	
	.PARAMETER Help
	Show the help documentation
	
	.PARAMETER LastClosed
	Query the sprint number of the most recently closed sprint
	
	.PARAMETER FirstActive
	Query the sprint number of the oldest active sprint
	
	.PARAMETER LastActive
	Query the sprint number of the newest active sprint
	
	.INPUTS
	BearerToken the Jira Personal Access Token (Bearer Token) used to authenticate to the server. Default will be read from file at: `~/.jiratoken/token`
	
	.OUTPUTS
	The requested sprint number value
	
	.EXAMPLE
	PS> jira_sprint_query.ps1      # Default
	
	.EXAMPLE
	PS> jira_sprint_query.ps1 -lc  # Get the last completed sprint
	
	.EXAMPLE
	PS> jira_sprint_query.ps1 -fa  # Get the first active sprint (oldest active)
	
	.EXAMPLE
	PS> jira_sprint_query.ps1 -la  # Get the last active sprint (newest active)
	
#>
[CmdletBinding(DefaultParametersetName="LastClosed")]
param(
	[switch][Alias("h")] $Help,                         # include to display the help message and then exit
	[Parameter(ParameterSetName="LastClosed")]
	[switch][Alias("lc")] $LastClosed,
	[Parameter(ParameterSetName="FirstActive")]
	[switch][Alias("fa")] $FirstActive,
	[Parameter(ParameterSetName="LastActive")]
	[switch][Alias("la")] $LastActive,
	[Parameter(ValueFromPipeline = $true)]
	[string] $BearerToken
)

if(!$FirstActive -and !$LastActive){
	$LastClosed = $true
}

if($Help){
	# call the Get-Help
	Get-Help $MyInvocation.MyCommand.Path
	exit 0
}

if(!$BearerToken){
	$BearerToken = (Get-Content -Path '~/.jiratoken/token')
}
$Headers = @{
	Authorization = "Bearer $BearerToken"
}

$offset = 0
if(Test-Path variable:\response){
	Clear-Variable response
}
$foundFirstActive = $false
while($response.isLast -ne "True"){
	$response = Invoke-RestMethod -Method GET -Headers $Headers -Uri "https://{{jira_url}}/rest/agile/1.0/board/{{board_id}}/sprint?startAt=$offset"
	$values = $response.values
	$offset = $offset + $values.length
	for($i = 0; $i -lt $values.length; $i++){
		$value = $values[$i]
		$value.name | Write-Debug
		": " | Write-Debug
		$status = $value.state
		if($status -eq "active"){
			[console]::ForegroundColor = "green"
			$latestActiveNum = ($value.name | Select-String -Pattern "\d+" | %{$_.matches.value})
			if(!$foundFirstActive){
				$foundFirstActive = $true
				$firstActiveNum = $latestActiveNum
			}
		}
		if($status -eq "future"){
			[console]::ForegroundColor = "yellow"
		}
		if($status -eq "closed"){
			$latestClosedNum = ($value.name | Select-String -Pattern "\d+" | %{$_.matches.value})
			[console]::ForegroundColor = "red"
		}
		$status | write-Debug
		[console]::ResetColor()
	}
}

if($LastClosed){
	$latestClosedNum | Write-Output
}
if($FirstActive){
	$firstActiveNum | Write-Output
}
if($LastActive){
	$latestActiveNum | Write-Output
}
