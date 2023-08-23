# test get new token

#[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS -bor [Net.SecurityProtocolType]::TLS11 -bor [Net.SecurityProtocolType]::TLS12
[Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

if(!$BearerToken){
	$BearerToken = (Get-Content -Path '~/.jiratoken/token')
}
#$BearerToken | write-debug

$Headers = @{
	"Authorization" = "Bearer $BearerToken"
	"Content-Type" = "application/json"
	"Accept" = "application/json"
}
#$headers | write-debug

$postParams = '{ "name": "tokenName", "expirationDuration": 90 }'
#$postParams | write-debug

$tokenInfo = Invoke-RestMethod -Method GET -Uri https://{{jira_url}}/rest/pat/latest/tokens -Headers $Headers
#$tokenInfo.expiringAt | write-host

#$token = Invoke-WebRequest -Uri https://{{jira_url}}/rest/pat/latest/tokens -Method POST -Headers $Headers -Body $postParams
$token = Invoke-RestMethod -Method POST -Uri https://{{jira_url}}/rest/pat/latest/tokens -Headers $Headers -Body $postParams
#$token | write-host
$token.rawToken | write-host