# DEPLOY (FORENSIC BINARIES) FROM GITHUB REPO
# This script allows to download the binaries from a Github Repo
#
# AUTHOR: Andreas Baeumer (andreasb@sentinelone.com)
# VERSION : 1.5 
# USAGE
# deploy-binaries.ps1 (optional parameters) 
# 
# Optional parameters are defined below
# 
# ERROR CODES
# 0   - no error occured
# 1   - unspecified error occured
# 5   - directory to store the packages could not be created
# 6   - directory to store the packages could not be deleted
#
# TODO 
# - Logfile Pfad check and create if not exists
# LOGGING TO XDR
# CONNECTIVITY CHECK / PROXY
# SET FOLDER ACL DomainIRUser


param (
    # SETTING OPTIONAL PARAMETERS TO CONTROL THE SCRIPT
    [Parameter(Mandatory=$false)]               # skipping the version check of binaries to remove and download fresh versions 
    [Boolean]$skipVersionCheck=$False,
    [Parameter(Mandatory=$false)]               # Path to where the binaries should be stored
    [String]$StorageLocation="C:\ProgramData\SentinelOne",
    [Parameter(Mandatory=$false)]               # URL of repo where the binaries are stored
    [String]$REPO_URL="https://github.com/s1baeumer/remoteops-datacollection/blob/main/binaries/",
    [Parameter(Mandatory=$false)]               # URL of file where the versions are stored
    [String]$VERSION_URL="https://raw.githubusercontent.com/s1baeumer/remoteops-datacollection/main/binaries/versions",
    [Parameter(Mandatory=$false)]               # remove all files in directory
    [Boolean]$Remove=$False,
    [Parameter(Mandatory=$false)]               # Enable/Disable debug logging
    [Boolean]$DebugLogging=$False
)


# LOGGING 
function Logging($msg) {
    if ($DebugLogging -eq $True) {
        $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $LogMessage = "$stamp $msg"
        Add-content  "C:\Temp\deploy-binaries.txt" -value $LogMessage
    }
}

# Set ACL for folder 
function SetFolderACL () {
    Logging "Trying to set ACL for folder $StorageLocation"
    try {
        $Acl = Get-Acl $StorageLocation
        # Disable Permission Inheritance
        $Acl.SetAccessRuleProtection($true,$false)
        
        # Set permissions to RemoteOps user (owner) 
        $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($un, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.SetAccessRule($Ar)
        Set-Acl $StorageLocation $Acl
        Logging "successfully set folder permissions"
        return $True
    } catch {
        Logging "could not set folder permissions"
        Logging $_.Exception.Message
        return $False
    }
}


# MAIN SCRIPT START
Logging "########## STARTING SCRIPT ##########"
$un = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Logging "Trying to download versions file from repo"
Logging "Running script as user: $un"
Logging "Current Directory: $StorageLocation"


# Check if custom path is set through script parameters
#if ((Test-Path $StorageLocation) -eq "") {
#    $StorageLocation = (Get-Location).Path        
#    Logging "No custom path is set - will set to default: $StorageLocation"
#}



if ($Remove -eq $True) {
    Logging "Remove all files and folders from $StorageLocation"
    try {
        Remove-Item -LiteralPath $StorageLocation -Force -Recurse
    } catch {
        Logging $_.Exception.Message
        exit(6)
    }
} else {
    # Verify that directory Structure exists before downloading the binaries
    try {
        if ((Test-Path "$StorageLocation") -ne $True) {
            Logging "Path $StorageLocation not existing"  
            Logging "trying to create directory $StorageLocation"  
            $c = New-Item -Path $StorageLocation -ItemType Directory
            SetFolderACL
        } else {
            Logging "Path exists - no action taken"
        }
    }
    catch {
        Logging "Could not create the directory structure to store the binaries"
        Logging $_.Exception.Message
        exit(5)
    }

    # DOWNLOAD VERSION FILE
    try{
        if ((Test-Path "$StorageLocation\versions.txt") -eq $True) {
            Remove-Item "$StorageLocation\versions.txt"
        }
        Invoke-WebRequest -Uri $VERSION_URL -OutFile "$StorageLocation\versions.txt"
        $arrayFromFile = Get-Content -Path "$StorageLocation\versions.txt"

        foreach ($data in $arrayFromFile) {
            $d = $data -split '='
            $bin = $d[0]
            $hash = $d[1]
            $ver = $d[2]
            $path = $StorageLocation+'\'+$bin
            $repo = $REPO_URL+$bin+"?raw=true"
            if ($skipVersionCheck -ne $True) {
                if ((Test-Path $path) -eq $True) {
                    $chash = (Get-FileHash $path -Algorithm SHA1).hash
                } else {
                    $chash = ""
                } 
                if ($hash -ne $chash) {
                    Logging $hash" vs. "$chash
                    Logging "Version mismatch or file not existing - trying to download the correct binary from repo"
                    try {
                        Logging "Removing binary $bin before new download"
                        if ((Test-Path $path) -eq $True) {
                            Logging "Remove file $path"
                            Remove-Item $path
                        }
                        Logging "Download new binary $bin"
                        Invoke-WebRequest -Uri $repo  -OutFile $path
                    } 
                    catch {
                        Logging "couldn't download $bin from repo" 
                        Logging $_.Exception.Message

                    }
                    finally {
                        Logging "finished download of $bin from $REPO_URL "
                    }
                } else {
                    Logging $path" - hash matches - no download necessary "
                }
            } else {
                Logging "Removing binary $bin before new download"
                if ((Test-Path $path) -eq $True) {
                    Logging "Remove file $path"
                    Remove-Item $path
                }
                Logging "Download new binary from $REPO_URL$bin?raw=true"
                Invoke-WebRequest -Uri $repo -OutFile $path
            }
        }
    }
    catch {
        Logging "something went terribly wrong"
        Logging $_.Exception.Message
        exit(1)
    }
    finally{
        Logging "########## FINISHED SCRIPT ##########"
        exit(0)
    }
}
