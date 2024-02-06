# QUERY FOR INFORMATION ON THE ENDPOINT USING OSQUERY
# This script queries data from an endpoint using osquery by using querypacks zipped  
# together with the osquery binary and sends the output to Skylight 
#
# AUTHOR  : Andreas Baeumer (andreasb@sentinelone.com)
# VERSION : 1.4 
# USAGE   : osquery-packed.ps1 (optional parameters) 
# 
# Optional and mandatory parameters are defined below
# 
# ERROR CODES
# 0   - no error occured
# 1   - unspecified error occured
# 15  - could not locate the osqueryi.exe binary
# 16  - could not locate the base64-encoded query pack defined in $PackName
# 20  - could not decode b64 encoded query pack

Param(
    [parameter(Mandatory = $True)]      # name of the query pack as base64-encoded blob
    [String]$PackName="",
    [Parameter(Mandatory=$False)]       # Enable/Disable debug logging
    [Boolean]$DebugLogging=$False
)

# BUILDING PATH FOR BINARY AND QUERY PACK
$BinaryPath = Join-Path -Path $Env:S1_PACKAGE_DIR_PATH -ChildPath "osqueryi.exe"
$QueryPackPath = Join-Path -Path $Env:S1_PACKAGE_DIR_PATH -ChildPath $PackName".b64"


# LOGGING 
function Logging($msg) {
    if ($DebugLogging -eq $True) {
        $logpath = $Env:TEMP
        If(!(Test-Path -PathType container $logpath)) {
            New-Item -ItemType Directory -Path $logpath
        }       
        $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $LogMessage = "$stamp $msg"
        Add-content  "$logpath\execute-osquery.txt" -value $LogMessage
    }
}

## help functions 

# EXECUTE OSQUERY
function ExecuteOsquery($base64_sql) {
    $SQL = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64_sql))
    $q = $BinaryPath+" --json `"$SQL`""
    try {
        $output = Invoke-Expression "& $q"
        Logging $q
        return $output
    }
    catch {
        Logging "could not execute the query '$SQL' exiting"
        Logging $_.Exception.Message
        return $False
    }
}

#### START CODE ####
function runfunc() {
    Logging "========================================================================"
    Logging "Starting Script"
    Logging "========================================================================"
    Logging ""
    Logging "COLLECTING HOSTINFO"

    ## COLLECTING HOSTNAME AND AGENT ID
    $agent_name = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
    Logging "AgentName: $agent_name"
    
    $agent = (New-Object -ComObject 'SentinelHelper.1').GetAgentStatusJSON() | ConvertFrom-Json
    $agent_uuid = $agent.'agent-id'
    Logging "AgentUUID : $agent_uuid" 

    $guid = [guid]::NewGuid().toString()
    Logging "GUID: $guid"

    #READ BLOB FROM PACK
    $query_pack_blob = Get-Content -Path $QueryPackPath
    # CONVERT BLOB TO JSON
    Logging "try to decode blob from query pack"
    Logging $query_pack_blob
    try {
        $q = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($query_pack_blob)) | ConvertFrom-Json
    } catch {
        Logging "could not decode string and convert it to json"
        exit(20)
    }

    $json_array = @()
    foreach($item in $q.queries) {
        # RUNNING SINGLE QUERY 
        $output = ExecuteOsquery ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($item.query)))
        if ($output -ne $False) {
            $t = $item.query -match ".*from ([A-Za-z0-9_]{3,}).*"
            # SPLITTING RESULT BY LINEBREAK AND FILL IN ARRAY
            $x = $output -replace "`n",", " -replace "`r",", " | ConvertFrom-Json
            # LOOPING THROUGH OUTPUT ARRAY AND ADD CONTENT TO ARRAY
            foreach ($r in $x) {
                $element = New-Object -TypeName PSObject
                $element | Add-Member -Name 'endpoint.name' -MemberType Noteproperty -Value $agent_name
                $element | Add-Member -Name "agent.uuid" -MemberType NoteProperty -Value $agent_uuid
                $element | Add-Member -Name "osquery.task.uuid" -MemberType NoteProperty -Value $guid
                $element | Add-Member -Name "osquery.packname" -MemberType NoteProperty -Value $PackName
                $element | Add-Member -Name "osquery.name" -MemberType NoteProperty -Value $item.name
                $element | Add-Member -Name "osquery.description" -MemberType NoteProperty -Value $item.description
                $element | Add-Member -Name "osquery.type" -MemberType NoteProperty -Value $item.type
                $element | Add-Member -Name "osquery.table" -MemberType NoteProperty -Value $t[1]
                $r.PSObject.Properties | ForEach-Object {
                    try {
                        $key_name = "osquery.result."+$_.name
                        $element | Add-Member -Name $key_name -MemberType NoteProperty -Value $_.value
                    } catch {
                        Logging "Kölsch gefunden? $($Error)"
                        exit(1)
                    }
                }
                $json_array += $element
            }
        }
    }
    $output = $json_array  | ConvertTo-Json
    Write-Output $output -NoEnumerate | Set-Content -Path $Env:S1_XDR_OUTPUT_FILE_PATH -Force

    Logging "========================================================================"
    Logging "Finished script"
    Logging "========================================================================"
    Exit(0)
}

# BEGIN OF SCRIPT
logging "#####################"
logging "## BEGIN OF SCRIPT ##"
logging "#####################"

logging "START PRE CHECKS"
logging "Env:S1_PACKAGE_DIR_PATH : $Env:S1_PACKAGE_DIR_PATH"
logging "Env:S1_XDR_OUTPUT_FILE_PATH: $Env:S1_XDR_OUTPUT_FILE_PATH"

# RUNNING PRE-CHECKS
# CHECKING IF OSQUERY EXISTS ON THE ENDPOINT
if(Test-Path $BinaryPath) {
    Logging "osquery binary is found"  
} else {
    Logging "Could not find osquery binary in '$BinaryPath'"
    exit(15)
}

# CHECKING IF QUERY PACK WITH NAME OF $PackName EXISTS ON THE ENDPOINT
if(Test-Path $QueryPackPath) {
    Logging "query pack with name $PackName is found"  
} else {
    Logging "Could not find  '$QueryPackPath'"
    exit(16)
}


runfunc @Args