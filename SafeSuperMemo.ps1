﻿<#
.SYNOPSIS

SuperMemo Backup and Run Script


.DESCRIPTION

This script is designed to wrap execution of SuperMemo so that it can be started and terminated cleanly,
allowing it to be hosted in either Dropbox or OneDrive.

It has two main features:

  - Dropbox and OneDrive compatibility. (see important warnings in NOTES)
  - Backups automatically generated at runtime.

OneNote compatibility is currently only briefly tested. Feedback from actual users is appreciated.

The script is configured using an external file named SafeSuperMemo.properties.ps1. It is fully documented.
All configuration settings must be formatted as Powershell variables, with leading $ symbols.

To configure it to run automatically when an icon is double-clicked (or single-clicked if docked to the Windows
taskbar, etc) create a shortcut from THIS .ps1 file and use the following:

For the Target:  
  
  C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -command "& '<YOUR_PATH>\SafeSuperMemo.ps1'"
  
  - Replace <YOUR_PATH> with the full path to the folder containing the script
  - Ensure the double-quotes and single-quotes are kept exactly as shown

For the Start In box:

  "<YOUR_PATH>"

  - This is exactly the same path as above
  - Double-quotes are needed if there are spaces in the path

If you pin the shortcut to the Windows taskbar you can right-click and edit the pinned icon's properties
and add a global keyboard shortcut (ex: CTRL+ALT+S) that will execute the script when pressed.

.NOTES

The script will manage termination and restart of the sync service (Dropbox, OneNote) automatically. This 
means the collection "SHOULD BE" safely hostable in either service. Be aware however that there are grave 
warnings on the SuperMemo support site[1] that sync services can and likely WILL cause massive corruption of 
the collection if the service is actively running in the background while SuperMemo is running. This is
because SuperMemo expects the collection to be untouched by any process other than SuperMemo while it is
in use, and it updates the collection's data files as you proceed through the element queue. If the sync 
service is running at the same time it will detect these changes and attempt to sync the files individually 
with its cloud storage, causing brief file locks and resulting in files becoming out of sync within the
SuperMemo collection. When this occurs there can be significant data loss and data corruption that can
be difficult or impossible to recover completely. As such the SuperMemo site warns explicitly against
using services like Dropbox and OneNote to host the collection files.

That said, the solution is simple and has been in use for several years. Another user created an
AutoHotKey script[2] that will disable the Dropbox service, run SuperMemo, then when SuperMemo exits it
restarts the Dropbox service. This allows the user to host the SuperMemo collection in Dropbox for syncing
between multiple computers (and a lightweight backup capability) while ensuring the collection can be
used in SuperMemo safely.

This script does exactly the same thing as the AutoHotKey script, except it also now supports OneNote: 
it disables the sync service completely when executed, then runs SuperMemo and waits for it to finish. 
Once SuperMemo is closed the script will re-enable the sync service. (so Dropbox/OneNote will sync again)

What this script does differently is it generates a backup every time it is run. Backups are generated as
follows:

  - A backup name is generated in this format:  YYYYMMDDTHHMMSS - Collection Name
  - A new folder with that name is created in the backup folder designated in the properties file
  - The entire current collection is copied from the source location to this new folder
  - The script then verifies the backup integrity by comparing file counts and folder counts
  - If either of the counts are off the script throws an error and terminates

This behavior is designed to ensure you have a clean backup that can be reverted to at any time. Because
the script will refuse to run if the counts are different you can see immediately that there is a problem
and investigate.

WARNING:
This script is NOT a replacement for your own due diligence in managing your collection's integrity!
While the author of this script has used it very successfully without incident that does not mean it
will work exactly the same on every computer. Because of the importance of your SuperMemo collection 
in your life you should continue to perform periodic manual backups and consider redundant backups.
For example, storing the active collection in a sync service and storing the backups on the local computer 
which is in turn backed up regularly via another cloud backup service and/or hard disk backups and/or images.
You are responsible for the integrity of your collection. 

Do not taunt Happy Fun Ball. Colon Blow may cause abdominal distention. Consult a physician.

Refs:

[1] http://supermemopedia.com/wiki/Conflicted_copy_of_files_on_DropBox

[2] http://wiki.supermemo.org/index.php?title=SuperMemo-Dropbox_Conflict_Resolver
#>

Import-Module $($PsScriptRoot + "\SafeSuperMemo.properties.ps1")

#
# These variables are automatically generated, do not mess with them
#
$backupName        = (Get-Date).ToString("yyyyMMddTHHmmss") + " - " + $collectionName
$fromDir           = $collectionRootDir + $collectionName
$toDir             = $backupRootDir + $backupName

function KillDropbox 
{
    echo "Killing dropbox"
    Kill -ProcessName Dropbox
    echo "-Done!"
    echo ""
}

function StartDropbox
{
    echo "Starting dropbox"
    Start $dropboxPath
    echo "-Done!"
    echo ""
}

function KillOneDrive
{
    echo "Killing OneDrive"
    & $onedrivePath '/shutdown'
    echo "-Done!"
    echo ""
}

function StartOneDrive
{
    echo "Starting OneDrive"
    & $onedrivePath
    echo "-Done!"
    echo ""
}

function KillSyncService
{
    If ($useService -eq [SyncService]::Dropbox) { KillDropbox }
    ElseIf ($useService -eq [SyncService]::OneDrive) { KillOneDrive }
    Else { throw "*** ERROR:  No valid sync service specified in properties file! ***" }
}

function StartSyncService
{
    If ($useService -eq [SyncService]::Dropbox) { StartDropbox }
    ElseIf ($useService -eq [SyncService]::OneDrive) { StartOneDrive }
}

function BackupCollection
{
    echo "Backing up collection directory"
    echo "-from  <$fromDir>"
    echo "-to    <$toDir>"

    Copy-Item -Recurse $fromDir $toDir 

    $fromFile           = $collectionRootDir + $collectionName + ".Kno"
    $toFile             = $backupRootDir + $backupName + ".Kno"

    echo "Backing up collection file"
    echo "-from  <$fromFile>"
    echo "-to    <$toFile>"

    Copy-Item $fromFile $toFile

    echo "-Done!"
    echo ""
}

function VerifyBackupIntegrity
{
    echo "Verifying counts"
 
    $originalFolderCount = Get-ChildItem -Recurse -Directory $fromDir | Measure-Object | %{$_.Count}
    $backupFolderCount   = Get-ChildItem -Recurse -Directory $toDir   | Measure-Object | %{$_.Count}
    
    if ($originalFolderCount -ne $backupFolderCount)
    {
        throw "*** INTEGRITY FAIL: Original folder count of $originalFolderCount does not match backup folder count of $backupFolderCount ***"
    }
    echo "-folder count   OK   $originalFolderCount   $backupFolderCount"

    $originalFileCount   = Get-ChildItem -Recurse -File      $fromDir | Measure-Object | %{$_.Count}   
    $backupFileCount     = Get-ChildItem -Recurse -File      $toDir   | Measure-Object | %{$_.Count}

    if ($originalFileCount -ne $backupFileCount)
    {
        throw "*** INTEGRITY FAIL: Original file count of $originalFileCount does not match backup file count of $backupFileCount ***"
    }  
    echo "-file count     OK   $originalFileCount   $backupFileCount"

    $originalFilesTotalSize = Get-ChildItem $fromDir -Recurse | Measure-Object -property length -sum | %{$_.Sum}
    $backupFilesTotalSize   = Get-ChildItem $toDir   -Recurse | Measure-Object -property length -sum | %{$_.Sum}

    if ($originalFilesTotalSize -ne $backupFilesTotalSize)
    {
        throw "*** INTEGRITY FAIL: Original file size sum of $originalFilesTotalSize does not match backup sum of $backupFilesTotalSize ***"
    }
    echo "-file size sum  OK   $originalFilesTotalSize   $backupFilesTotalSize"

    echo "-Done!"
    echo ""
}

function RunSuperMemo
{
    echo "running SuperMemo"
    $knoFilePath = $fromDir + ".Kno"
    echo "-path $knoFilePath"
    (Start-Process $knoFilePath -WorkingDirectory $fromDir -PassThru).WaitForExit()
    echo "-Done!"
    echo ""
}

function Report
{
    $numBackups      = Get-ChildItem $backupRootDir | Measure-Object | %{$_.Count}
    
    # calculating size takes a lot of time as collection size increases
    # and number of backups increases
    #$totalBackupSize = Get-ChildItem $backupRootDir -Recurse | Measure-Object -property length -sum | %{$_.Sum}
    #$roundedSize     = [math]::Round($totalBackupSize / 1MB)
    
    echo "# Backups:    $numBackups"
    #echo "Space used:  ~$roundedSize MB"
    echo ""
}

function PauseForAnyKey
{
    # IO subsystem is not available in Powershell ISE.
    # If we are in ISE then we are developing the script and the console
    # won't go away after each run, so no need for an IO wait.
    # The $psISE object only exists if running inside ISE.
    if (-not $psISE)
    {
        Write-Host "Press any key to continue ..."
        $HOST.UI.RawUI.ReadKey(“NoEcho,IncludeKeyDown”) | Out-Null
        $HOST.UI.RawUI.Flushinputbuffer()
    }
}

function Main
{
    try { KillSyncService }
    catch
    {
        Write-Error $_.Exception.Message
        PauseForAnyKey
        exit
    }

    BackupCollection
    VerifyBackupIntegrity
    RunSuperMemo
    StartSyncService
    Report
    # PauseForAnyKey
}

Main
