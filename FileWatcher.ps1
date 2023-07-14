<#
    .Name
     FileWatcher

    .Version 
    0.1.0

    .SYNOPSIS
    Starts a new filewatcher session to monitor files within a given folder path

    .DESCRIPTION
       
    .Configurable Variables

    .Requirements
    - Powershell v3.0 or higher
    - Module designed for Samson Media Player

    .OUTPUTS
    System.Management.Automation.PSObject

    .Author
    EZTechhelp - https://www.eztechhelp.com

    .NOTES

    .RequiredModules
    /Modules/Write-EZLogs/Write-EZLogs.psm1
    /Modules/Start-RunSpace/Start-Runspace.psm1

#>
Add-Type -AssemblyName WindowsBase
Import-Module "$PSScriptRoot\Modules\Write-EZLogs\Write-EZLogs.psm1"
Import-Module "$PSScriptRoot\Modules\EZT-FileWatcher\EZT-FileWatcher.psm1"
#---------------------------------------------- 
#region Start-FileWatcher Function
#----------------------------------------------
Start-EZLogs -logfile_directory 'c:\logs' -ScriptPath $PSCommandPath -Global_Log_Level 3 -StartLogWriter -wait -UseGlobalLogFile
Start-FileWatcher -FolderPath 'C:\Users\DopaDodge\OneDrive - EZTechhelp Company\Development\Repositories\EZT-MediaPlayer-Samson' -MonitorSubFolders
#---------------------------------------------- 
#endregion Start-FileWatcher Function
#----------------------------------------------
