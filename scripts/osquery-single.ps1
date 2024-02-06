# QUERY FOR INFORMATION ON THE ENDPOINT USING OSQUERY
# This script queries data from an endpoint using osquery by using a parameter for issuing a 
# single query and sends the output to Skylight 
#
# AUTHOR  : Andreas Baeumer (andreasb@sentinelone.com)
# VERSION : 1.0 
# USAGE   : osquery-single.ps1 (optional parameters) 
# 
# Optional and mandatory parameters are defined below
# 
# ERROR CODES
# 0   - no error occured
# 1   - unspecified error occured
# 15  - could not locate the osqueryi.exe binary


Param(
    [parameter(Mandatory = $True)]      # query
    [String]$Query="",
    [Parameter(Mandatory=$False)]       # Enable/Disable debug logging
    [Boolean]$DebugLogging=$False
)

# BUILDING PATH FOR BINARY AND QUERY PACK
$BinaryPath = Join-Path -Path $Env:S1_PACKAGE_DIR_PATH -ChildPath "osqueryi.exe"

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

    $json_array = @()

    # RUNNING SINGLE QUERY 
    $output = ExecuteOsquery ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($query)))
    if ($output -ne $False) {
        $t = $query -match ".*from ([A-Za-z0-9_]{3,}).*"
        # SPLITTING RESULT BY LINEBREAK AND FILL IN ARRAY
        $x = $output -replace "`n",", " -replace "`r",", " | ConvertFrom-Json
        # LOOPING THROUGH OUTPUT ARRAY AND ADD CONTENT TO ARRAY
        foreach ($r in $x) {
            $element = New-Object -TypeName PSObject
            $element | Add-Member -Name 'endpoint.name' -MemberType Noteproperty -Value $agent_name
            $element | Add-Member -Name "agent.uuid" -MemberType NoteProperty -Value $agent_uuid
            $element | Add-Member -Name "osquery.task.uuid" -MemberType NoteProperty -Value $guid
            $element | Add-Member -Name "osquery.packname" -MemberType NoteProperty -Value "single"
            $element | Add-Member -Name "osquery.name" -MemberType NoteProperty -Value $q
            $element | Add-Member -Name "osquery.table" -MemberType NoteProperty -Value $t[1]
            $r.PSObject.Properties | ForEach-Object {
                try {
                    $element | Add-Member -Name "osquery.result."$_.name -MemberType NoteProperty -Value $_.value
                } catch {
                    Logging "Kölsch gefunden? $($Error)"
                    exit(1)
                }
            }
            $json_array += $element
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


runfunc @Args