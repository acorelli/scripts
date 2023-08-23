$oldHost = "{{old_host_url}}"
$newHost = "{{new_host_url}}"

$gitDir = $PWD
$prefix = (Convert-Path $PWD)
$prefixSplit = $prefix.Split("\").Length


function UpdateRemote {
	param([string]$repoDir)
	
	# don't traverse these paths
	if($repoDir -like "*_deps*"){
		return
	}
	if($repoDir -like "*build*"){
		return
	}
	
	# regex replace hostnames
	$o = git remote get-url origin
	$n = $o -replace "$oldHost", "$newHost"
	
		
	if($o -ne $n){
		
		$splitRepo = (Convert-Path $repoDir).Split("\")
		$postPath = ($splitRepo | Select-Object -Skip $prefixSplit | Join-Path -ChildPath "")
		$postPath = $postPath -replace "\\", "/"
		
		git remote set-url origin $n
		Write-Host "Updating /$postPath remote to $n"
	}
}

function RecurseDirs {
	param([string]$dirPath)
	
	# don't traverse these paths
	if($dirPath -like "*_deps*"){
		return;
	}
	if($repoDir -like "*build*"){
		return
	}
	
	# recurse through the directory structure
	Get-ChildItem -Path $dirPath -Directory -Recurse -Exclude $excludedDirs | ForEach-Object {
		$subDir = $_.FullName
		
		# update current location
		Set-Location $subDir
		
		# don't traverse these paths
		if($subDir -like "*_deps*"){
			return
		}
		if($subDir -like "*build*"){
			return
		}
		
		$spinnerChar = $spinner[$spinCounter/5 % $spinner.Length]
		
		Write-Host -NoNewLine "`b"
		Write-Host -NoNewLine $spinnerChar
		$spinCounter++
		
		# check if inside a git repo
		if(Test-Path -Path "$subDir\.git" -PathType Container){
			UpdateRemote -repoDir $subDir
			return
		}
	}
}

$spinner = "-\|/"
$spinCounter = 0

$scriptDir = $PWD

Set-Location $gitDir
RecurseDirs -dirPath $gitDir
Set-Location $scriptDir