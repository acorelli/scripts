# Parse git username for current user (used to assign to self)
$UnameResp = (ssh -T git@{{git_url}}) 2>&1
Write-Host $UnameResp

$UName = "@" + ($UnameResp | Select-String -Pattern '@(\w+)!' -AllMatches).Matches.Groups[1]
Write-Host "I am $UName"

$names = "@{{uname1}}", "@{{uname2}}", "@{{uname3}}", {{...}}

$exclude = $names.IndexOf($UName)
Write-Host "Excluding: $exclude"

$firstNumber = Get-Random -Minimum 0 -Maximum 4
while($firstNumber -eq $exclude){
	$firstNumber = Get-Random -Minimum 0 -Maximum 4
}

$secondNumber = Get-Random -Minimum 0 -Maximum 4
while($secondNumber -eq $firstNumber -or $secondNumber -eq $exclude){
	$secondNumber = Get-Random -Minimum 0 -Maximum 4
}

$assignee = $names[$firstNumber]
$noAtAssignee = $assignee.Substring(1)
Write-Host "Assignee: $assignee"
Write-Host "A: $noAtAssignee"
$reviewer = $names[$secondNumber]
$noAtReviewer = $names[$secondNumber].Substring(1)
Write-Host "Reviewer: $reviewer"
Write-Host "R: $noAtReviewer"