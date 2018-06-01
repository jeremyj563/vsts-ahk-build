# Script Name: ahk-build.ps1
# Usage: ahk-build.ps1 [script.ahk]
# Example: .\ahk-build.ps1 ahk-service-test.ahk
# Author: Jeremy Johnson
# Date: 05/25/2018
#
# Purpose: Compile AutoHotKey script using Ahk2Exe.exe.
#          Automatically download the compiler files if necessary.
#
# Dependencies: AutoHotKey Compiler (Ahk2Exe.exe and Unicode 32-bit.bin)
#
# Exit Codes:   0 = success
#               1 = dependency download failed
#               2 = problem extracting dependency archive    
#               3 = problem compiling script

# Parameters
Param (
    [Parameter(Mandatory=$true)]
    [string] $infile,
    [string] $log = ""
)

# Setup log and scriptname variables
$ScriptName = ([io.fileinfo]$MyInvocation.MyCommand.Definition).BaseName
If ($log -eq "") { $log = "$PSScriptRoot/$ScriptName.log" }

# Log Functions
Function WriteLog($content) {
    Write-Host $content
    Add-Content $log -Value $content
}

Function TaskEvent([string] $event) {
    WriteLog("*" * 78)
    WriteLog("$event`: [$ScriptName]")
    WriteLog("*" * 78)
}

Function EventNotification($event) {
    $date = Get-Date -Format s
    $content = ("{0} | {1}" -f $date, $event)
    WriteLog -content $content
}

# Dependency Functions
Function NewDependency {
    Param (
        [string] $Name,
        [string] $Url,
        [string] $Archive,
        [string[]] $Files
    )
    $dependency = New-Object PSObject
    $dependency | Add-Member -type NoteProperty -Name Name -Value $Name
    $dependency | Add-Member -type NoteProperty -Name Url -Value $Url
    $dependency | Add-Member -type NoteProperty -Name Archive -Value $Archive
    $dependency | Add-Member -type NoteProperty -Name Files -Value $Files
    
    return $dependency
}

Function CheckDependency([PSObject] $dependency) {
    ForEach ($file in $dependency.Files) {
        If (!(Test-Path "$PSScriptRoot/$file")) {
            # Missing dependenies so download them
            EventNotification "Missing dependencies"
            DownloadDependency($dependency)
            return
        }
    }
    EventNotification "Dependencies found"
}

Function DownloadDependency([PSObject] $dependency) {
    EventNotification "Attempting to download dependency: $($dependency.Name)"
    Try {
        EventNotification "Downloading $($dependency.Name)`: $($dependency.Url)"
        Invoke-WebRequest "$($dependency.Url)" -OutFile "$PSScriptRoot/$($dependency.Archive)"
        If (!(Test-Path "$PSScriptRoot/$($dependency.Archive)")) {
            ExitScript -exitcode 1 -message ([string]::Format("Error in function ({0}): $PSScriptRoot/$($dependency.Archive) was not created", $MyInvocation.MyCommand))
        }
        EventNotification "Download complete"
    }
    Catch {
        ExitScript -exitcode 1 -message ([string]::Format("Error in function ({0})", $MyInvocation.MyCommand))
    }
    
    EventNotification "Attempting to extract dependency archive: $($dependency.Archive)"
    ForEach ($file in $dependency.Files) {
        ExtractFromZip -in "$PSScriptRoot/$($dependency.Archive)" -query "$file" -out "$PSScriptRoot" -overwrite $true
    }
    Remove-Item "$PSScriptRoot/$($dependency.Archive)"
}

# Other Functions
Function ExtractFromZip {
    Param (
        [string] $in,
        [string] $query,
        [string] $out,
        [boolean] $overwrite
    )
    Try {
        Add-Type -Assembly System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($in)
        $zip.Entries | Where-Object {$_.Name -like "$query"} | ForEach-Object {[System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "$out\$query", $overwrite)}
        $zip.Dispose()
        If (!(Test-Path "$out\$query")) {
            ExitScript -exitcode 2 -message ([string]::Format("Error in function ({0}): $out\$query was not created", $MyInvocation.MyCommand))
        }
        EventNotification "Extracted file: $out\$query"
    }
    Catch {
        ExitScript -exitcode 2 -message ([string]::Format("Error in function ({0})", $MyInvocation.MyCommand))
    }
}

Function Build([string] $in) {
    Try {
        $basename = [System.IO.Path]::GetFileNameWithoutExtension("$in")
        If (Test-Path "$PSScriptRoot\$basename.exe") {
            EventNotification "Previous build artifact found, attempting to cleanup"
            Remove-Item -Path "$PSScriptRoot\$basename.exe" -Force
            If (!(Test-Path "$PSScriptRoot\$basename.exe")) {
                EventNotification "Successfully deleted previous build artifact"
            }
            Else {
                ExitScript -exitcode 3 -message ([string]::Format("Error in function ({0}): Failed to delete previous build artifact: $PSScriptRoot\$basename.exe", $MyInvocation.MyCommand))
            }
        }
        EventNotification "Attempting to build: $in"
        & $PSScriptRoot\Ahk2Exe.exe /in "$PSScriptRoot\$in" | Out-Null
        Start-Sleep -s 3 # Wait for build to complete
        If (!(Test-Path "$PSScriptRoot\$basename.exe")) {
            ExitScript -exitcode 3 -message ([string]::Format("Error in function ({0}): $PSScriptRoot\$basename.exe was not created", $MyInvocation.MyCommand))
        }
        Else {
            EventNotification "Script built successfully: $PSScriptRoot\$basename.exe"
        }
    }
    Catch {
        ExitScript -exitcode 3 -message ([string]::Format("Error in function ({0})", $MyInvocation.MyCommand))
    }
}

Function ExitScript {
    Param (
        [int] $exitcode,
        [string] $message
    )
    
    TaskEvent "Finishing"

    If (!($exitcode -eq '0')) {
        WriteLog "[$ScriptName] $message - exit code: $exitcode"
    }
    
    Exit "$exitcode"
}

# MAIN SCRIPT

TaskEvent "Starting"
$Ahk2Exe = NewDependency "AutoHotKey Compiler" "https://autohotkey.com/download/ahk.zip" "ahk.zip" @('Ahk2Exe.exe','Unicode 32-bit.bin')
CheckDependency($Ahk2Exe)
Build($infile)

# EOF
ExitScript -exitcode 0