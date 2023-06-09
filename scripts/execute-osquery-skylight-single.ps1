# QUERY FOR INFORMATION ON THE ENDPOINT USING OSQUERY
# This script queries data from an endpoint using osquery by adding a single 
# query to the command as a base64-encoded (no need to escape any special character)
# parameter and sends the output to Skylight using a direct upload 
#
# AUTHOR  : Andreas Baeumer (andreasb@sentinelone.com)
# VERSION : 1.6 
# USAGE   : 
# execute-osquery-skylight-single.ps1 (optional parameters) 
# 
# Optional and mandatory parameters are defined below
# 
# ERROR CODES
#  0  - no error occured
#  1  - unspecified error occured
# 14  - powershell version not matching the minimum version
# 15  - could not locate the osqueryi.exe binary
# 25  - no valid Skylight token specified

# TODO 
# - select region from input parameter to allow script to run in various regions
# - verify Skylight token length
# - get proxy settings from agent/system and use it for upload
# - idea: offload dataset upload library to deploy-binaries and import it from there


Param(
    [parameter(Mandatory = $True)]      # skylight write token
    [String]$skylight_token="",
    [Parameter(Mandatory=$True)]        # single query as base64 encoded string 
    [String]$q="",
    [Parameter(Mandatory=$False)]       # tag for query name
    [String]$q_name="",
    [parameter(Mandatory = $False)]     # skylight region eu|us 
    [String]$skylight_region="eu",
    [Parameter(Mandatory=$False)]       # path where osqueryi.exe is stored
    [String]$StorageLocation="C:\ProgramData\SentinelOne\osqueryi.exe",
    [Parameter(Mandatory=$False)]       # Enable/Disable debug logging
    [Boolean]$DebugLogging=$True

)


if (Get-Module LogToDataSet) {Remove-Module LogToDataSet}
New-Module -Name 'LogToDataSet' -ScriptBlock {

    $dataset_region = "us";
    
    $logtodataset_source = @"     
    using System.Collections;
    using System.Collections.Generic;
    using System.IO;
    using System.Text;

    public class DataSetEvent {        
        public string ts;     // timestamp in nanoseconds as string
        public int sev; //// 0-6 - "finest, finer, fine, info, warning, error, fatal"
        public Hashtable attrs; // // event attributes

        public DataSetEvent() {                
            this.ts = (System.DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()*1000000).ToString();// // Get nanosecond time
            this.sev = 3;// // set default severity 3
            this.attrs = new Hashtable();
            this.attrs.Add("logfile", "");
            this.attrs.Add("parser", "json");
        }

        public void SetEventAttributes(Hashtable attributes) {
            this.attrs = attributes;
        }

        public void AddEventAttribute(string key, string value) {
            if (this.attrs.ContainsKey(key)) {
                this.attrs.Remove(key);
            }
            this.attrs.Add(key, value);
        }
    }

    public class DataSetLog {
        public string token;
        public string session;
        public Hashtable sessionInfo;
        public System.Collections.Generic.List<DataSetEvent> events;
        
        public DataSetLog()
        {
            this.session = System.Guid.NewGuid().ToString();
            this.sessionInfo = new Hashtable();
            this.sessionInfo.Add("serverHost", "");
            this.events = new System.Collections.Generic.List<DataSetEvent>();        
        }

        public DataSetLog(string token = null) 
        {
            this.token = token;
        }    

        public void SetToken(string token) {
            this.token = token;
        }
    }

    public class LogToDataSet {
        public string datasetus = "https://xdr.us1.sentinelone.net/api/addEvents";    
        public string dataseteu = "https://xdr.eu1.sentinelone.net/api/addEvents";    
        public string dataseturl = "";
        public DataSetLog session;
        public string global_Event_Logfile; // logfile to apply to all events added
        public Hashtable global_Event_Attrs; // event attributes to apply to all events added    
        public System.Collections.Generic.Queue<DataSetEvent> EventQueue;  // event queue 
        public long lastTs ; // store last event timestamp, each event added must have a timestamp > previous
        public int MaxEvents; // max events in session before sending

        public LogToDataSet(string token, string url = "us", int MaxEvents = 1000) {
            this.session = new DataSetLog();
            this.lastTs = 0;        
            this.session.token = token;    
            this.MaxEvents = MaxEvents;    
            this.EventQueue = new System.Collections.Generic.Queue<DataSetEvent>(); 
            switch (url.ToLower()) {
                case "us":
                    this.dataseturl = this.datasetus;
                    break;
                case "eu":
                    this.dataseturl = this.dataseteu;      
                    break;      
                default:
                    this.dataseturl = url;
                    break;
            }        
        }   

        public void SetToken(string token) {
            this.session.SetToken(token);
        }

        public void SetSessionAttributes(Hashtable attributes) {
            this.session.sessionInfo = attributes;
        }
        
        public void AddSessionAttribute(string key, string value) {
            if (this.session.sessionInfo.ContainsKey(key)) {
                this.session.sessionInfo.Remove(key);
            }
            this.session.sessionInfo.Add(key, value);
        }

        public void SetServerHost(string serverHost) {
            this.AddSessionAttribute("serverHost", serverHost) ;       
        }

        public void AddSessionAttributes<T>(T attrs) {} //replace in powershell
        public void AddEventObject(DataSetEvent sevent) {} //replace in powershell
        public void AddEvent(object aevent) {} //replace in powershell
        public void FlushEvents() {} //replace in powershell
    }
"@
        
    Add-Type -TypeDefinition $logtodataset_source
    $log2dataset = New-Object LogToDataSet("", $dataset_region)

    Add-Member -InputObject $log2dataset -MemberType ScriptMethod -Name "AddEventObject" -Force -Value {
        param([DataSetEvent]$addevent)
        
        $eventts = [int64]$addevent.ts
        if ($eventts -le $this.lastTs) {
            $eventts +=1
            $addevent.ts = [string]$eventts            
            $this.lastTs = $eventts
        } else {
            $this.lastTs = $eventts
        }        
        if ($this.global_Event_Attrs.Count -ne 0) {
            foreach ($attr in $this.global_Event_Attrs.Keys) {
                $addevent.AddEventAttribute($attr, $this.global_Event_Attrs[$attr])
            }
        }
        if ($this.global_Event_Logfile -ne "") {
            $addevent.AddEventAttribute("logfile", $this.global_Event_Logfile)            
        }            
        
        $this.EventQueue.Enqueue($addevent)                    
        
        if ($this.EventQueue.Count -ge $this.MaxEvents) {
            $this.FlushEvents()
        }                
    }
    
    Add-Member -InputObject $log2dataset -MemberType ScriptMethod -Name "AddEvent" -Force -Value {
        param($message)
    
        $emessage = ""
        if ($message.GetType().Name -eq "string") {
            $emessage = $message
        }
        else {
            $emessage = ($message | ConvertTo-Json -Compress)
        }
        [DataSetEvent]$newevent = New-Object DataSetEvent
        $newevent.AddEventAttribute("message", $emessage)
        $this.AddEventObject($newevent)       
    }

    Add-Member -InputObject $log2dataset -MemberType ScriptMethod -Name "AddSessionAttributes" -Force -Value {
        param($attrs)

        if ($attrs) {
            if ($attrs.GetType().Name -eq 'String[]') {
                try {
                        $attrs = ConvertFrom-StringData -StringData ($attrs -join "`n") -ErrorVariable ConvErr
                }
                catch {Write-Host "Error Converting Session Attributes"}                      
                }     
                if ($attrs -and $attrs.GetType().Name -eq 'Hashtable') {
                    $attrs.GetEnumerator() | ForEach-Object {
                        $this.AddSessionAttribute($_.Key, $_.Value)
                }       
            }            
        }    
    }

    Add-Member -InputObject $log2dataset -MemberType ScriptMethod -Name "SetGlobal_LogFile" -Force -Value {
        param($logfile)

        $this.global_Event_Logfile = $logfile
    }

    Add-Member -InputObject $log2dataset -MemberType ScriptMethod -Name "SetGlobal_EventAttrs" -Force -Value {
        param($attrs)

        $this.global_Event_Attrs = $attrs
    }

    Add-Member -InputObject $log2dataset -MemberType ScriptMethod -Name "FlushEvents" -Force -Value {   
        while ($this.EventQueue.Count -ne 0) {
            for ($i = 0; $i -lt $this.MaxEvents; $i++) {
                if ($this.EventQueue.Count -ne 0) {
                    $this.session.events.Add($this.EventQueue.Dequeue())
                }                    
            }
            try{
                $body = ($this.session | ConvertTo-Json -Compress -Depth 100) 
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12          
                $response = Invoke-RestMethod -Uri $this.dataseturl -Method 'Post' -Body $body -ContentType 'application/json'
                if ($response.status -eq 'success') {                        
                    $this.session.events.Clear()    
                } else {
                    Write-Error "Error Sending To DataSet: Status: $($response.status) - Message: $($response.message)"            
                }  
            } 
            catch {
                Write-Error "Error Sending To DataSet - $($Error)"
            }
        }        
    } 
    
    function Get-DataSetLogger($token) {        
        $log2dataset.SetToken($token)
        return $log2dataset # Initialize DataSet Logger
    }
    
    Export-ModuleMember -Function Get-DataSetLogger  
} | Import-Module


# LOGGING 
function Logging($msg) {
    if ($DebugLogging -eq $True) {
        $logpath = "C:\Temp"
        If(!(Test-Path -PathType container $logpath)) {
            New-Item -ItemType Directory -Path $logpath
        }       
        $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $LogMessage = "$stamp $msg"
        Add-content  "$logpath\execute-osquery-skylight.txt" -value $LogMessage
    }
}

# FINDING AGENT ID 
function getagentid{
    $installpath = dir -Path "C:\Program Files\SentinelOne" -Filter SentinelCtl.exe -Recurse
    $installfolder = $installpath.Directory.FullName
    $sentinelctl = $installpath.FullName

    try {
        $a = "`"$sentinelctl`" agent_id"
        $agent_uuid = Invoke-Expression "& $a"
        Logging "AgentUUID: '$agent_uuid'"
        return $agent_uuid
    } catch {
        Logging "could not retrieve agent uuid"
        Logging $_.Exception.Message
    } 
    exit(1)
}

# EXECUTE OSQUERY
function ExecuteOsquery($base64_sql) {
    $SQL = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64_sql))
    $q = "`"$StorageLocation`" --json `"$SQL`""
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
    # CHECKING IF POWERSHELL VERSION IS MINIMUM 3
    $psv = $host.Version.Major
    if ($psv -ge 3) {
        Logging "Powershell version is matching the requirements"
        Logging "Version found: $psv"
    } else {
        Logging "Powershell version is too old to run the script"
        exit(14)
    }
    
    # CHECKING IF OSQUERY EXISTS ON THE ENDPOINT
    if(Test-Path $StorageLocation) {
        Logging "osquery binary is found"  
    } else {
        Logging "Could not find osquery binary in '$StorageLocation'"
        exit(15)
    }




    Logging "========================================================================"
    Logging "COLLECTING HOSTINFO"

    ## COLLECTING HOSTNAME AND AGENT ID
    $agent_name = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
    Logging "AgentName: $agent_name"
    $agent_uuid = getagentid
    $guid = [guid]::NewGuid().toString()
    Logging "GUID: $guid"

    # INSTANTIATE SkylightLogger
    $dataset = Get-DatasetLogger($skylight_token) 
    $dataset.SetServerHost("RemoteOps-osquery")
    $dataset.AddSessionAttribute("endpoint.name", $agent_name)
    $dataset.AddSessionAttribute("agent.uuid", $agent_uuid)


    # Ensures that Invoke-WebRequest uses TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # RUNNING SINGLE QUERY 
    $output = ExecuteOsquery ($q)
    if ($output -ne $False) {
        logging "Received data from osquery - start to upload data to Skylight"
        # SPLITTING RESULT BY LINEBREAK AND FILL IN ARRAY
        $x = $output -replace "`n",", " -replace "`r",", " | ConvertFrom-Json
        logging $x.Count" records recieved"
        # LOOPING THROUGH OUTPUT ARRAY AND ADD CONTENT TO DATASET/SKYLIGHT ARRAY
        foreach ($r in $x) {
            logging "adding new event to queue"
            $element = New-Object DatasetEvent
            $element.ts = $([DateTimeOffset]::Now.ToUnixTimeMilliseconds())*1000000 
            $element.attrs.Add("osquery.uuid", $guid)
            $element.attrs.Add("osquery.queryname", $q_name)
            $r.PSObject.Properties | ForEach-Object {
                $element.attrs.Add($_.name,$_.value)
            }
            $dataset.AddEventObject($element)
        }
        $dataset.FlushEvents()  
    }
    Logging "========================================================================"
    Logging "Finished script"
    Logging "========================================================================"
}

runfunc @Args