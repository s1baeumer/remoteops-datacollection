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
# Output to File
# adding session id, additional identifiers to JSON 
# 
# {
#    "dataSource.category" : "security",
#    "dataSource.vendor" : "RemoteOps",
#    "dataSource.name" : "osquery"
#    "site.id"
# }
#




Param(
    [parameter(Mandatory = $False)]      # name of the query pack as base64-encoded blob
    [String]$pack_name="WindowsData",
    [parameter(Mandatory = $False)]     # URL to download the query pack as base64-encoded blob
    [String]$pack_url="https://raw.githubusercontent.com/s1baeumer/remoteops-datacollection/main/query-packs/base64/",
    [Parameter(Mandatory=$False)]       # path where osqueryi.exe is stored
    [String]$StorageLocation="C:\Temp\osqueryi.exe",
#    [String]$StorageLocation="C:\ProgramData\SentinelOne\osqueryi.exe",
    [Parameter(Mandatory=$False)]       # path where output from osquery is stored
#    [String]$OutputLocation="C:\ProgramData\SentinelOne\output.json",
    [String]$OutputLocation="C:\Temp\output.json",
    [Parameter(Mandatory=$False)]       # Enable/Disable debug logging
    [Boolean]$DebugLogging=$True
)

# LOGGING 
function Logging($msg) {
    if ($DebugLogging -eq $True) {
        $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $LogMessage = "$stamp $msg"
        Add-content  "C:\Temp\execute-osquery-skylight.txt" -value $LogMessage
    }
}

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
    Logging "SQL: $SQL"
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


# CHECKING IF OSQUERY EXISTS ON THE ENDPOINT
try {
    Test-Path $StorageLocation
    Logging "osquery binary is found"  
} catch {
    Logging "Could not find osquery binary in '$StorageLocation'"
    exit(15)
}

#### START CODE ####


Logging "========================================================================"
Logging "Starting Script"
Logging "========================================================================"
Logging ""
Logging "COLLECTING HOSTINFO"

## COLLECTING HOSTNAME AND AGENT ID
$agent_name = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
Logging "AgentName: $agent_name"
#$agent_id = getagentid

$purl = "$pack_url$pack_name.b64"
Logging "Building pack url: $purl"



# QUERY FOR PACK FROM QUERY PACK URL
Logging "START DOWNLOAD QUERYPACK"
Logging "FROM PACK URL: $purl"

# Ensures that Invoke-WebRequest uses TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# SEND REQUEST TO DOWLOAD QUERYPACK
#TODO download blob from remote server
Logging "started download from $purl"
$query_pack_blob = Invoke-WebRequest -Uri $purl -UseBasicParsing
# CONVERT BLOB TO JSON
Logging "downloaded string - try to decode"
$q = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($query_pack_blob)) | ConvertFrom-Json

# START LOOPING THROUGH QUERIES FROM QUERYPACK 
$bj = New-Object System.Collections.ArrayList
foreach($item in $q.queries) {
    # RUNNING SINGLE QUERY 
    $output = ExecuteOsquery ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($item.query)))
    # SPLITTING RESULT BY LINEBREAK AND FILL IN ARRAY
    $x = $output -replace "`n",", " -replace "`r",", " | ConvertFrom-Json
 
    $result = New-Object System.Collections.ArrayList
    # LOOPING THROUGH OUTPUT ARRAY AND ADD CONTENT TO ARRAY
    foreach ($r in $x) {
        # REMOVE FIRST AND LAST BRACKET
        #if ($r -ne "[" -and $r -ne "]") {
            $result.Add($r)
        #}
    }
    $res = @{}
    $res.Add("name",$item.name)
    $res.Add("description",$item.description)
    $res.Add("type",$item.type)
    $res.Add("query",$item.query)
    $res.Add("data",$result)
    $bj.Add($res)
    break
}

Logging "Trying to save the collected data to json file"
$bj | ConvertTo-Json -Depth 4 | Out-File $OutputLocation



Logging "========================================================================"
Logging "Finished script"
Logging "========================================================================"

