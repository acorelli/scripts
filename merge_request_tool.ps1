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
	[string][Alias("u")] $JenkinsUrl,
	[switch][Alias("BranchName", "b")] $UseBranch,
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

# get JIRA authentication
if(!$BearerToken){
	$BearerToken = (Get-Content -Path '~/.jiratoken/token')
}
if(!$BearerToken){
	"No BearerToken found. Exiting." | Write-Host -ForegroundColor "red"
	exit 1
}

$Branch = (git branch --show-current).toUpper()

# read branch name if not specified (or if different than ticket)
if(!$Issue){
	$Issue = $Branch
} else {
	$Issue = ($Issue).toUpper()
}

$Issue | Write-Host -ForegroundColor "yellow"

$IssueLC = $Issue.toLower()
$IssueLC | Write-Host -ForegroundColor "yellow"


# Setup API request
$Headers = @{
	Authorization = "Bearer $BearerToken"
}
if($response -ne $null){
	Clear-Variable response
}

# Query JIRA and construct request fields
$response = Invoke-RestMethod -Method GET -Headers $Headers -Uri "https://{{jira_url}}/rest/agile/1.0/issue/$Issue"

# Parse git username for current user (used to assign to self)
$UnameResp = (ssh -T git@{{git_url}}) 2>&1
$UName = "@" + ($UnameResp | Select-String -Pattern '@(\w+)!' -AllMatches).Matches.Groups[1]

# Random assign assignee/reviewer -- excluding self
$devs = "@{{tech_lead}}", "@{{uname1}}", "@{{uname2}}", {{...}}
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

if($UseBranch){
	$Title = $Branch + ': ' + $response.fields.summary
} else {
	$Title = $Issue + ': ' + $response.fields.summary
}

$Desc = $response.fields.description
$DescSingleLine = [string]::join("", ($Desc.split("`r")))
$DescSingleLine = [string]::join("\n", ($DescSingleLine.split("`n")))

$Comments = "Ticket Comments:\n" + $($response.fields.comment.comments | %{$_.body})
$CommentsSingleLine = [string]::join("", ($Comments.split("`r")))
$CommentsSingleLine = [string]::join("\n", ($CommentsSingleLine.split("`n")))

if(!$JenkinsUrl){
	$JenkinsUrl = "http://{{jenkins_url}}/job/$RepoGroup/job/$RepoName/"
} else {
	$JenkinsUrl = "http://{{jenkins_url}}/job/$JenkinsUrl"
}

# git push options do not allow line breaks in the string
$Description = "[:link: $Title](https://{{jira_url}}/browse/$Issue)  \n  \n-----  \n``````  \n$DescSingleLine\n``````  \n-----  \n``````  \n$CommentsSingleLine\n``````  \n-----  \n-----  \n\nBuilds must pass the [Jenkins]($JenkinsUrl) build pipeline.  \n  \nto build with [Jenkins]($JenkinsUrl)  \npost ``jenkins please try a build``  \ndown in the comments  \n  \n-----  \n-----  \n**Developer Checklist:**  \n-----  \n- [ ] Doxygen comments  \n- [ ] Unit tests (if applicable)  \n- [ ] Fix merge conflicts w/ target branch  \n- [x] Update ``title`` and ``description`` fields of this merge request  \n- [ ] Assign to a reviewer that (_ideally_) did not write code in this request  \n- [ ] :warning: Verify that the ``Remove source branch when merge request is accepted.`` and ``Squash commits when merge request is accepted.`` checkboxes on the ``New Merge Request``/``Edit Merge Request`` page are checked.  \n  \n**Reviewer Checklist:**  \n-----  \n- [ ] Review code  \n- [ ] Review [:link: Jenkins build/test results]($JenkinsUrl)  \n- [ ] Review [:link: cppcheck findings]($JenkinsUrl)  \n- [ ] Review merge request ``Title``/``Description``  \n- [ ] :warning: Verify that the merge/squash commit message is of the form: ``XYZ-###: JIRA Issue Title``  \n  \n  \n/draft  \n/assign $assignee  \n/reviewer $reviewer  \n/cc @{{tech_lead}}  \n\n:information_source: This merge request content was auto-generated. Assignee/Reviewer were chosen randomly :game_die:. If you notice any errors please let @{{tech_lead}} know. Thanks!"

"" | Write-Host
"" | Write-Host
"" | Write-Host
$Title | Write-Host
"----------" | Write-Host
"" | Write-Host
$Description | Write-Host

# Parse git username for current user (used to assign to self)
$UnameResp = (ssh -T git@{{git_url}}) 2>&1
$UName = ($UnameResp | Select-String -Pattern '@(\w+)!' -AllMatches).Matches.Groups[1]

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