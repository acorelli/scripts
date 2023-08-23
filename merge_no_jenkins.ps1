#
# Author: Corelli
# Date: 27OCT2022
# Version: 0.1
#
# NOTE:   Powershell does not use UTF8 strings by default. Please
#       check encoding using ANSI to make sure special characters
#       display properly

<#
	.SYNOPSIS
	Creates and populates a merge request in the current repo with the given JIRA Issue ID
	
	.DESCRIPTION
	Tool for creating merge requests with all info filled
	
	.PARAMETER Help
	Show the help documentation
	
	.PARAMETER Issue
	The JIRA Ticket ID, e.x. PROJ-2
	
	.PARAMETER TestRun
	Perform a test-run of the update. Doesn't commit/push the new branch
	
	.EXAMPLE
	PS> create_merge_request.ps1 -i PROJ-2
#>
[CmdletBinding(DefaultParametersetName="Issue")]
param(
	[switch][Alias("h")] $Help,                         # include to display the help message and then exit
	[switch][Alias("Test", "t")] $TestRun,              # test-run, don't create merge
	[Parameter(ValueFromPipeline = $true)]
	[string][Alias("i")] $Issue,
	[switch][Alias("Self", "s")] $AssignSelf
)

if($Help){
	# call the Get-Help
	Get-Help $MyInvocation.MyCommand.Path
	exit 0
}

if($TestRun){
	"-------- TEST RUN STARTING: --------" | Write-Host -ForegroundColor "yellow"
}

# URL for managing Jira tokens
$TokenSite = "https://{{jira_url}}/secure/ViewProfile.jspa?selectedTab=com.atlassian.pats.pats-plugin:jira-user-personal-access-tokens"

# Build open Jira Token URL prompt options
$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Open Jira Token management website."
$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Exit script."
$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

# get Jira authentication
if(!$BearerToken){
	$BearerToken = (Get-Content -Path '~/.jiratoken/token')
}
if(!$BearerToken){
	"No BearerToken found." | Write-Host -ForegroundColor "red"
	
	$title = "No Jira BearerToken found."
	$message = "Open Jira Token management website?"
	$result = $host.ui.PromptForChoice($title, $message, $options, 0)
	switch($result){
		0{
			# Yes
			'Opening Jira Token website. Please create a token and save it in "~/.jiratoken/token" then try again.' | Write-Host -ForegroundColor "yellow"
			Start-Process $TokenSite
		}
		1{
			# No
			exit 1
		}
	}
	
	"Exiting." | Write-Host -ForegroundColor "red"
	exit 1
}

# check if inside git repo worktree
$inRepo = (git rev-parse --is-inside-work-tree) 2>&1
if($inRepo -ne "true"){
	"Not in a git repository. Exiting" | Write-Host -ForegroundColor "red"
	exit 1
}

# read branch name if not specified (or if different than ticket)
if(!$Issue){
	$Issue = (git branch --show-current).toUpper()
} else {
	$Issue = ($Issue).toUpper()
}

$Issue | Write-Host -ForegroundColor "yellow"

# Setup API request
$Headers = @{
	Authorization = "Bearer $BearerToken"
}

if($response -ne $null){
	Clear-Variable response
}
if($responseError -ne $null){
	Clear-Variable responseError
}

# Query Jira and construct request fields
try {
	$response = Invoke-RestMethod -Method GET -Headers $Headers -Uri "https://{{jira_url}}/rest/agile/1.0/issue/$Issue"
} catch {
	$responseError = $true
	# Handle common server errors
	$eCode = $_.Exception.Response.StatusCode.value__
	"Error " + $eCode | Write-Host -ForegroundColor "red" -BackgroundColor "black"
	if($eCode -eq 401){	
		# 401: no auth
		$result = $_.Exception.Response.GetResponseStream()
		$reader = New-Object System.IO.StreamReader($result)
		$reader.BaseStream.Position = 0
		$reader.DiscardBufferedData()
		$responseBody = $reader.ReadToEnd();
		$eMsg = (Select-Xml -Content $responseBody -XPath "/status/message" | foreach {$_.node.InnerXML})
		$eMsg | Write-Host -ForegroundColor "red" -BackgroundColor "black"
		"-- Please check user authentication token" | Write-Host -ForegroundColor "red" -BackgroundColor "black"
		
		$title = "Invalid Jira Access Token."
		$message = "Open Jira Token management website?"
		$result = $host.ui.PromptForChoice($title, $message, $options, 0)
		switch($result){
			0{
				# Yes
				'Opening Jira Token website. Please create a token and save it in "~/.jiratoken/token" then try again.' | Write-Host -ForegroundColor "yellow"
				Start-Process $TokenSite
			}
			1{
				# No
				exit 1
			}
		}
	}
	if($eCode -eq 404){
		# 404: not found
		"Jira Issue " + $Issue + " not found" | Write-Host -ForegroundColor "red" -BackgroundColor "black"
		"-- Please check specified branch or use -Issue (-i) flag" | Write-Host -ForegroundColor "red" -BackgroundColor "black"
	}
	
	exit 1
}
if($responseError){
	# handle any add'l errors in the catch by just quitting
	"Other errors occurred. Exiting" | Write-Host -ForegroundColor "red" -BackgroundColor "black"
	exit 1
}


# Parse git username for current user (used to assign to self)
$UnameResp = (ssh -T git@{{git_url}}) 2>&1
$UName = "@" + ($UnameResp | Select-String -Pattern '@(\w+)!' -AllMatches).Matches.Groups[1]

# Random assign assignee/reviewer -- excluding self
$devs = "@{{uname1}}", "@{{uname2}}", "@{{uname3}}", "@{{uname4}}"
$exclude = $devs.IndexOf($UName)

$firstNumber = Get-Random -Minimum 0 -Maximum 4
while($firstNumber -eq $exclude){
	$firstNumber = Get-Random -Minimum 0 -Maximum 4
}

$secondNumber = Get-Random -Minimum 0 -Maximum 4
while($secondNumber -eq $firstNumber -or $secondNumber -eq $exclude){
	$secondNumber = Get-Random -Minimum 0 -Maximum 4
}


if($AssignSelf){
	$assignee = $UName
	$noAtAssignee = $assignee.Substring(1)
	$reviewer = $assignee
} else {
	$assignee = $devs[$firstNumber]
	$noAtAssignee = $assignee.Substring(1)
	$reviewer = $devs[$secondNumber]
}

Write-Host "Assignee: $assignee"
Write-Host "Reviewer: $reviewer"

"" | Write-Host
"" | Write-Host

$IssueCol = $Issue + ':'
$ProjectName = $response.fields.project.name
$RepoNameSplit = $(git rev-parse --show-toplevel).Split('/')
$SplitCount = $RepoNameSplit.count
$RepoGroup = $RepoNameSplit[$SplitCount - 2]
$RepoName = $RepoNameSplit[$SplitCount - 1]

$Title = $Issue + ': ' + $response.fields.summary

$Desc = $response.fields.description
$DescSingleLine = [string]::join("", ($Desc.split("`r")))
$DescSingleLine = [string]::join("\n", ($DescSingleLine.split("`n")))

$Comments = "Ticket Comments:\n" + $($response.fields.comment.comments | %{$_.body})
$CommentsSingleLine = [string]::join("", ($Comments.split("`r")))
$CommentsSingleLine = [string]::join("\n", ($CommentsSingleLine.split("`n")))

# git push options do not allow line breaks in the string
$Description = "[:link: $Title](https://{{jira_url}}/browse/$Issue)  \n  \n-----  \n``````  \n$DescSingleLine\n``````  \n-----  \n``````  \n$CommentsSingleLine\n``````  \n-----  \n-----  \n  \n-----  \n-----  \n**Developer Checklist:**  \n-----  \n- [x] Doxygen comments  \n- [x] Unit tests (if applicable)  \n- [x] Fix merge conflicts w/ target branch  \n- [x] Update ``title`` and ``description`` fields of this merge request  \n- [x] Assign to a reviewer that (_ideally_) did not write code in this request  \n- [x] :warning: Verify that the ``Remove source branch when merge request is accepted.`` and ``Squash commits when merge request is accepted.`` checkboxes on the ``New Merge Request``/``Edit Merge Request`` page are checked.  \n  \n**Reviewer Checklist:**  \n-----  \n- [ ] Review code  \n- [ ] Review merge request ``Title``/``Description``  \n- [ ] :warning: Verify that the merge/squash commit message is of the form: ``XYZ-###: Jira Issue Title``  \n  \n  \n/draft  \n/assign $assignee  \n/reviewer $reviewer  \n/cc @{{tech_lead}}  \n\n:information_source: This merge request content was auto-generated. Assignee/Reviewer were chosen randomly :game_die:. If you notice any errors please let @{{tech_lead}} know. Thanks!"

"" | Write-Host
"" | Write-Host
"" | Write-Host
$Title | Write-Host
"----------" | Write-Host
"" | Write-Host
$Description | Write-Host


if($TestRun){
	"Test Run Exiting" | Write-Host -ForegroundColor "green"
	exit 0
}

# make empty commit so we can push it
git commit --allow-empty -m "Create merge request (via script)"

$remoteOutput = $( $output = git push --porcelain `
			-o merge_request.create `
			-o merge_request.remove_source_branch `
			-o merge_request.title="$Title" `
			-o merge_request.description=$Description `
			-o merge_request.draft `
			-o merge_request.label="Automated" `
			-o merge_request.assign="$noAtAssignee" `
			-u origin HEAD) 2>&1

# Show git response
$remoteOutput | Write-Host -ForegroundColor "yellow"

# open merge request in web
$url = "$remoteOutput" -match "(https:\/\/{{git_url_escaped}}\/[^\s]*)"
$mergeUrl = $matches[0] + "/edit"
if($url){
	"Launching: $mergeUrl" | Write-Host
	Start-Process $mergeUrl
}