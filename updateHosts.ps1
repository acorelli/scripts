[CmdletBinding(DefaultParametersetName="gitDir")]
param(
	[Parameter(ValueFromPipeline = $true)]
	[string][Alias("i")] $gitDir
)

$oldHost = "{{old_host_url}}"
$newHost = "{{new_host_url}}"

$replaceMap = @{
	"$oldHost" = "$newHost"
	"/wip" = "/draft"
}


if(!$gitDir){
	$gitDir = "{{default path to top level git projects dir}}"
}
$prefix = (Convert-Path $PWD)
$prefixSplit = $prefix.Split("\").Length

# Grab the merge_no_jenkins.ps1 from this directory
$mergeTool = Join-Path $PSScriptRoot "merge_no_jenkins.ps1"

$excludedDirs = @(
	"{{any excluded dirs}}"
	"{{2nd excluded dir}}"
)

# "" for files without extension like Jenkinsfile, Dockerfile, etc.
$textExts = @("", ".bash", ".bat", ".bat.in", ".cmd", ".sh", ".sh.in", ".cmake", ".txt", ".md", ".ps1")

function UpdateRepo {
	param([string]$repoDir)
	
	# don't traverse these paths
	if($repoDir -like "*_deps*"){
		return
	}
	
	$repoDir = $_.FullName.Replace(".git", "")
	Write-Host Updating $_
	
	$choice = Read-Host "Update $_`? y/n"
	if($choice -ne "Y" -or $choice -ne "y"){
		# Skip
		return
	}
	
	
	# check if $target update-remote branch already exists on remote e.g. fixes have already been pushed up
	$target = "{{updating hosts JIRA ticket ID, e.g. PROJ-123}}"
	if((git ls-remote origin $target | Measure-Object | select -ExpandProperty Count) -gt 0){
		Write-Host "$target already exists on origin/remotes, skipping"
		return
	}
	
	Write-Host "This script will 'git reset --hard;' and 'git switch develop' (if develop exists). You will lose any uncommitted work you might have in this repo" -ForegroundColor Yellow
	$choice = Read-Host "Continue? y/n"
	if($choice -ne "Y" -or $choice -ne "y"){
		# Skip
		return
	}
	
	# set current dir, hard reset and checkout develop
	Set-Location $repoDir
	git reset --hard
	git fetch --all
	# check for develop branch and switch if it exists
	if((git ls-remote origin develop | Measure-Object | select -ExpandProperty Count) -gt 0){
		Write-Host "Switching to develop and pulling any new changes"
		git switch develop
		git pull
	}
	git pull
	
	# check if $target update-remote branch already exists
	if( (git rev-parse --verify refs/heads/$target).Length -ne 0){
		Write-Error "Target branch '$target' already exists -- deleting it"
		git branch -D $target
	}
	
	# make new branch
	git checkout -b $target
	
	# regex replace hostnames
	Get-ChildItem -Path $repoDir -Recurse -File | ForEach-Object {
		if($_.Extension -in $textExts){
			Write-Host "Checking $_"
			$t = Get-Content $_.FullName
			foreach ($pair in $replaceMap.GetEnumerator()){
				$oldValue = $pair.Key
				$newValue = $pair.Value
				$t = $t -replace "$oldValue", "$newValue"
			}
			Set-Content $_.FullName $t
		}
	}
	git status
	
	# update local remotes as part of the process -- will push to new host
	git remote set-url origin ((git remote get-url origin) -replace "$oldHost", "$newHost")
	git remote get-url origin
	
	# check for changes
	$status = git status --porcelain
	Write-Host $status
	if($status -match "^ [MADCRU]"){
		
		git diff | ForEach-Object {
			$triple = ''
			if($_.Length -gt 3){
				$triple = $_.substring(0,3)
			}
			$symbol = $_.Substring(0,1)
			
			if($triple -eq "+++" -or $triple -eq "---"){
				Write-Host $_ -ForegroundColor Yellow
			} else {
				if($symbol -eq "+"){
					Write-Host $_ -ForegroundColor DarkGreen
				} elseif($_ -match "^-"){
					Write-Host $_ -ForegroundColor DarkRed
				} else {
					Write-Host $_
				}
			}
		}
		
		Write-Host "You are about to commit and push these changes to the origin, proceed?" -ForegroundColor Yellow
		$choice = Read-Host "Continue? y/n"
		if($choice -ne "Y" -or $choice -ne "y"){
			# Skip
			return
		}
		
		# make a commit and push it up to the new remote
		git commit -am "update refs to: $newHost"
		git push -u origin HEAD --force
		
		& $mergeTool -i $target
	} else {
		Write-Host "No changes detected"
	}
}

function RecurseDirs {
	param([string]$dirPath)
	
	# don't traverse these paths
	if($dirPath -like "*_deps*"){
		return;
	}
	
	# recurse through the directory structure
	Get-ChildItem -Path $dirPath -Directory -Recurse -Exclude $excludedDirs | ForEach-Object {
		# update current location
		$subDir = $_.FullName
		Set-Location $subDir
		
		# don't traverse these paths
		if($subDir -like "*_deps*"){
			return
		}
		
		# check if inside a git repo
		if(Test-Path -Path "$subDir\.git" -PathType Container){
			UpdateRepo -repoDir $subDir
			return
		}
	}
}

$scriptDir = $PWD

Set-Location $gitDir
RecurseDirs -dirPath $gitDir
Set-Location $scriptDir