# DEPLOY (FORENSIC BINARIES) FROM GITHUB REPO
# This script allows to download the binaries from a Github Repo
#
# AUTHOR: Andreas Baeumer (andreasb@sentinelone.com)
# USAGE
# deploy-latest-version.ps1 (optional parameters) 

param (
    # SETTING OPTIONAL PARAMETERS TO CONTROL THE SCRIPT
    [Parameter(Mandatory=$false)]               # skipping the version check of binaries to remove and download fresh versions 
    [Boolean]$skipVersionCheck=$True,
    [Parameter(Mandatory=$false)]               # Path to where the binaries should be stored
    [String]$PWD="C:\Users\demo\Desktop",
    [Parameter(Mandatory=$false)]               # URL of repo where the binaries are stored
    [String]$REPO_URL="https://github.com/s1baeumer/remoteops-datacollection/blob/main/binaries/",
    [Parameter(Mandatory=$false)]               # Enable/Disable debug logging
    [Boolean]$DebugLogging=$False
)

# TODO LOGGING TO XDR
# LOGGING 
function Logging( $msg) {
    if ($DebugLogging -eq $True) {
        Write-Host $msg
    } 
}

# MAIN SCRIPT START
Logging "########## STARTING SCRIPT ##########"
Logging "Trying to download versions file from repo"
# DOWNLOAD VERSION FILE
try {
    Remove-Item $PWD"\versions.txt"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/s1baeumer/remoteops-datacollection/main/binaries/versions" -OutFile $PWD"\versions.txt"
    $arrayFromFile = Get-Content -Path $PWD'\versions.txt'

    foreach ($data in $arrayFromFile) {
        $d = $data -split '='
        $bin = $d[0]
        $ver = $d[1]
        $path = $PWD+'\'+$bin
        
        if ($skipVersionCheck -ne $True) {
            $cver = (Get-Item $path).VersionInfo.FileVersion
            if ($ver -ne $cver) {
                Logging "Version mismatch or file not existing - trying to download the correct binary from repo"
                try {
                    Logging "Removing binary $bin before new download"
                    Remove-Item $path
                    Logging "Download new binary "$bin
                    Invoke-WebRequest -Uri $REPO_URL$bin"?raw=true" -OutFile $PWD"\"$bin
                } 
                catch {
                    Logging "couldn't download $bin from repo" 
                }
            } else {
                Logging $path" - perfect match "
            }
        } else {
            Logging "Removing binary $bin before new download"
            Remove-Item $path
            Logging "Download new binary"
            Invoke-WebRequest -Uri $REPO_URL$bin"?raw=true" -OutFile $PWD"\"$bin
        }
    }
}
catch {
    Logging "Couldn't download version file from repo"
}
Logging "########## FINISHED SCRIPT ##########"



