# DEPLOY (FORENSIC BINARIES) FROM GITHUB REPO
# This script allows to download the binaries from a Github Repo 
# AUTHOR: Andreas Baeumer (andreasb@sentinelone.com)


param (
    [Parameter(Mandatory=$false)][Boolean]$skipVersionCheck=$False,
    [Parameter(Mandatory=$false)][String]$PWD="C:\Users\demo\Desktop",
    [Parameter(Mandatory=$false)][String]$REPO_URL="https://github.com/s1baeumer/remoteops-datacollection/blob/main/binaries/",
    [Parameter(Mandatory=$false)][Boolean]$DebugLogging=$True
)

function Logging( $msg) {
    if ($DebugLogging -eq $True) {
        Write-Host $msg
    } 
}



Logging "START SCRIPT"
# TODO LOGGING TO XDR


# DOWNLOAD VERSION FILE
Logging "Trying to download versions file from repo"

try {
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
                    Logging "Download new binary"
                    Invoke-WebRequest -Uri $REPO_URL$bin"?raw=true" -OutFile $PWD"\"$bin
                } 
                catch {
                    Logging "couldn't download $bin from repo" 
                }
            } else {
                Logging $path "- perfect match "
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
Logging "FINISHED SCRIPT"



