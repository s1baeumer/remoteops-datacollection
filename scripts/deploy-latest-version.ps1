# DEPLOY (FORENSIC BINARIES) FROM GITHUB REPO
# This script allows to download the binaries from a Github Repo 
# AUTHOR: Andreas Baeumer (andreasb@sentinelone.com)


param (
    [Parameter(Mandatory=$false)][Boolean]$skipVersionCheck=$True,
    [Parameter(Mandatory=$false)][String]$PWD="C:\Users\demo\Desktop",
    [Parameter(Mandatory=$false)][String]$REPO_URL="https://github.com/s1baeumer/remoteops-datacollection/blob/main/binaries/",
    [Parameter(Mandatory=$false)][Boolean]$DebugLogging=$False
)

# TODO LOGGING TO XDR


# DOWNLOAD VERSION FILE
Invoke-WebRequest -Uri "https://github.com/s1baeumer/remoteops-datacollection/blob/main/binaries/versions" -OutFile $PWD"\versions.txt"
$arrayFromFile = Get-Content -Path $PWD'\versions.txt'

foreach ($data in $arrayFromFile) {
    $d = $data -split '='
    $bin = $d[0]
    $ver = $d[1]
    $path = $PWD+'\'+$bin
  
    $cver = (Get-Item $path).VersionInfo.FileVersion
    if ($skipVersionCheck -ne $True) {
        if ($ver -ne $cver) {
            Write-Host "Version mismatch or file not existing - trying to download the correct binary from repo"
            try {
                Remove-Item $path
                Invoke-WebRequest -Uri $REPO_URL$bin"?raw=true" -OutFile $PWD"\"$bin
            } 
            catch {
                Write-Host "couldn't download $bin from repo" 
            }
        } else {
            Write-Host $path "- perfect match "
        }
    } else {
        Remove-Item $path
        Invoke-WebRequest -Uri $REPO_URL$bin"?raw=true" -OutFile $PWD"\"$bin
    }
}
Write-Host "FINISHED SCRIPT"






