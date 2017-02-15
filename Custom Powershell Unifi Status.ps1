# Monitor the Status of AP's on Unfi Controller in PRTG v0.6 15/02/2017
# Published Here: https://kb.paessler.com/en/topic/71263
#
# Parameters in PRTG are: Controller's URI, Port, Site, Username and Password. Example without placeholders:
# -server 'unifi.domain.tld' -port '8443' -site 'default' -username 'admin' -password 'somepassword'
#
# -server '%host' -port '8443' -site 'default' -username '%windowsuser' -password '%windowspassword'
# This second option requires the device's address in PRTG to be the controller's address, the credentials for windows devices
# must also match the log-in/password from the controller. This way you don't leave the password exposed in the sensor's settings.
#
# It's recommended to use larger scanning intervals for exe/xml scripts. Please also mind the 50 exe/script sensor's recommendation per probe.
# The sensor will not generate alerts by default, after creating your sensor, define limits accordingly.
# This sensor is to be considered experimental. The Ubnt's API documentation isn't completely disclosed.
#
#   Source(s):
#   http://community.ubnt.com/t5/UniFi-Wireless/little-php-class-for-unifi-api/m-p/603051
#   https://github.com/fbagnol/class.unifi.php
#   https://www.ubnt.com/downloads/unifi/5.3.8/unifi_sh_api
#   https://github.com/malle-pietje/UniFi-API-browser/blob/master/phpapi/class.unifi.php

param(
	[string]$server = 'unifi.domain.com',
	[string]$port = '8443',
	[string]$site = 'default',
	[string]$username = 'admin',
	[string]$password = '123456',
	[switch]$debug = $false
)

#Ignore SSL Errors
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}  

# Confirm Powershell Version.
if ($PSVersionTable.PSVersion.Major -lt 3) {
	Write-Output "<prtg>"
	Write-Output "<error>1</error>"
	Write-Output "<text>Powershell Version is $($PSVersionTable.PSVersion.Major) Requires at least 3. </text>"
	Write-Output "</prtg>"
	Exit
}

# Create $controller and $credential using multiple variables/parameters.
[string]$controller = "https://$($server):$($port)"
[string]$credential = "`{`"username`":`"$username`",`"password`":`"$password`"`}"

# Start debug timer
$queryMeasurement = [System.Diagnostics.Stopwatch]::StartNew()

# Perform the authentication and store the token to myWebSession
try {
$null = Invoke-Restmethod -Uri "$controller/api/login" -method post -body $credential -ContentType "application/json; charset=utf-8"  -SessionVariable myWebSession
}catch{
	Write-Output "<prtg>"
	Write-Output "<error>1</error>"
	Write-Output "<text>Authentication Failed: $($_.Exception.Message)</text>"
	Write-Output "</prtg>"
	Exit
}

#Query API providing token from first query.
try {
$jsonresultat = Invoke-Restmethod -Uri "$controller/api/s/$site/stat/device/" -WebSession $myWebSession
}catch{
	Write-Output "<prtg>"
	Write-Output "<error>1</error>"
	Write-Output "<text>API Query Failed: $($_.Exception.Message)</text>"
	Write-Output "</prtg>"
	Exit
}

# To Review the output manually
# $jsonresultat | ConvertTo-Json

# Stop debug timer
$queryMeasurement.Stop()


# Iterate jsonresultat and count the number of AP's. 
#   $_.state -eq "1" = Connected 
#   $_.type -like "uap" = Access Point ?

$apCount = 0
Foreach ($entry in ($jsonresultat.data | where-object { $_.state -eq "1" -and $_.type -like "uap"})){
	$apCount ++
}

$apUpgradeable = 0
Foreach ($entry in ($jsonresultat.data | where-object { $_.state -eq "1" -and $_.type -like "uap" -and $_.upgradable -eq "true"})){
	$apUpgradeable ++
}

$userCount = 0
Foreach ($entry in ($jsonresultat.data | where-object { $_.type -like "uap"})){
	$userCount += $entry.'num_sta'
}

$guestCount = 0
Foreach ($entry in $jsonresultat.data){
	$guestCount += $entry.'guest-num_sta'
}

#Write Results

write-host "<prtg>"

Write-Host "<result>"
Write-Host "<channel>Access Points Connected</channel>"
Write-Host "<value>$($apCount)</value>"
Write-Host "</result>"

Write-Host "<result>"
Write-Host "<channel>Access Points Upgradeable</channel>"
Write-Host "<value>$($apUpgradeable)</value>"
Write-Host "</result>"

Write-Host "<result>"
Write-Host "<channel>Clients (Total)</channel>"
Write-Host "<value>$($userCount)</value>"
Write-Host "</result>"

Write-Host "<result>"
Write-Host "<channel>Guests</channel>"
Write-Host "<value>$($guestCount)</value>"
Write-Host "</result>"

Write-Host "<result>"
Write-Host "<channel>Response Time</channel>"
Write-Host "<value>$($queryMeasurement.ElapsedMilliseconds)</value>"
Write-Host "<CustomUnit>msecs</CustomUnit>"
Write-Host "</result>"

write-host "</prtg>"

# Write JSON file to disk when -debug is set. For troubleshooting only.
if ($debug){
	[string]$logPath = ((Get-ItemProperty -Path "hklm:SOFTWARE\Wow6432Node\Paessler\PRTG Network Monitor\Server\Core" -Name "Datapath").DataPath) + "Logs (Sensors)\"
	$timeStamp = (Get-Date -format yyyy-dd-MM-hh-mm-ss)

	$json = $jsonresultat | ConvertTo-Json
	$json | Out-File $logPath"unifi_sensor$($timeStamp)_log.json"
}
