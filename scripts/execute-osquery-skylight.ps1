# QUERY FOR INFORMATION ON THE ENDPOINT USING OSQUERY
# This script queries data from an endpoint using osquery by using querypacks downloaded 
# from a Github repo and sends the output to Skylight 
#
# AUTHOR  : Andreas Baeumer (andreasb@sentinelone.com)
# VERSION : 1.2 
# USAGE   : 
# deploy-osquery-skylight.ps1 (optional parameters) 
# 
# Optional parameters are defined below
# 
# ERROR CODES
# 0   - no error occured
# 1   - unspecified error occured
# 15  - could not locate the osqueryi.exe binary
#
# TODO 
#

Param(
    [parameter(Mandatory = $True)]      # name of the query pack as base64-encoded blob
    [String]$pack_name="",
    [parameter(Mandatory = $False)]     # URL to download the query pack as base64-encoded blob
    [String]$pack_url="",
    [Parameter(Mandatory=$False)]       # path where osqueryi.exe is stored
    [String]$StorageLocation="C:\ProgramData\SentinelOne\osqueryi.exe",
    [Parameter(Mandatory=$False)]       # path where output from osquery is stored
    [String]$OutputLocation="C:\ProgramData\SentinelOne\output.json",
    [Parameter(Mandatory=$False)]       # Enable/Disable debug logging
    [Boolean]$DebugLogging=$True)
)

# LOGGING 
function Logging($msg) {
if ($DebugLogging -eq $True) {
    $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $LogMessage = "$stamp $msg"
    Add-content  "C:\Temp\execute-osquery-skylight.txt" -value $LogMessage
}
}

# CHECKING IF OSQUERY EXISTS ON THE ENDPOINT
try {
    Test-Path $StorageLocation
    Logging "osquery binary is found"  
} catch {
    Logging "Could not find osquery binary in '$StorageLocation'"
    exit(15)
}

#### START CODE ####
## help functions 

# FINDING AGENT ID 
function getagentid{
    $baseInstalledPath = "C:\Program Files\SentinelOne"
    $agent_install_dir = Get-ChildItem $baseInstalledPath -ErrorAction SilentlyContinue | ?{ $_.PSIsContainer } | Select FullName,Name
    if (!$agent_install_dir) { exit 1 }
    $sentinelctl = "$($agent_install_dir.FullName)\SentinelCtl.exe"
    # Get the agent uuid
    $agent_uuid = & $sentinelctl agent_id
    Logging "Found agent id '$agent_uuid'"
    return $agent_uuid
}

# EXECUTE OSQUERY
function ExecuteOsquery($base64_sql) {
    $SQL = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64_sql))
    Logging "BASE64_SQL: $base64_sql"
    Logging "SQL: $SQL"
    Logging "$path $output_format $SQL"
    try {
        $output = &$StorageLocation --json $SQL 
        Logging "OSQUERY EXECUTET"
        return $output
    }
    catch {
        Logging "could not execute the query '$SQL' exiting"
        return "ERROR IN QUERY"
    }
}


Logging "========================================================================"
Logging "Starting Script"
Logging "========================================================================"
Logging ""
Logging "COLLECTING HOSTINFO"

## COLLECTING HOSTNAME AND AGENT ID
$agent_name = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
Logging "AgentName: $agent_name"
$agent_id = getagentid


# QUERY FOR PACK FROM QUERY PACK URL
Logging "START DOWNLOAD QUERYPACK"
Logging "FROM PACK URL: $pack_url"

# Ensures that Invoke-WebRequest uses TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# SEND REQUEST TO DOWLOAD QUERYPACK
#TODO download blob from remote server
Logging "started download from $pack_url"
$query_pack_blob = Invoke-WebRequest -Uri $pack_url -UseBasicParsing
# CONVERT BLOB TO JSON
Logging "downloaded string - try to decode"
$q = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($query_pack_blob)) | ConvertFrom-Json


# SWITCH ACCORDING TO DESTINATION TYPE
foreach($item in $q.queries) {
    $base64_query =[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($item.query))
    $output = ExecuteOsquery $base64_query
    Add-content $OutputLocation -value $output
}


Logging "========================================================================"
Logging "Finished script"
Logging "========================================================================"

