<#
    .Name
    EZT-FileWatcher

    .Version 
    0.1.0

    .SYNOPSIS
    Creates events to monitor changes using FileSystemWatcher and trigger actions for provided file/folder paths 

    .DESCRIPTION
       
    .Configurable Variables

    .Requirements
    - Powershell v3.0 or higher

    .OUTPUTS
    System.Management.Automation.PSObject

    .Author
    EZTechhelp - https://www.eztechhelp.com

    .NOTES
    Adapted from: https://stackoverflow.com/questions/47273578/a-robust-solution-for-filesystemwatcher-firing-events-multiple-times

    .RequiredModules
    /Modules/Write-EZLogs/Write-EZLogs.psm1
    /Modules/Start-RunSpace/Start-Runspace.psm1
#>

#---------------------------------------------- 
#region Start-FileWatcher Function
#----------------------------------------------

function Start-FileWatcher{
  param (
    [string]$FolderPath,
    [switch]$MonitorSubFolders,
    [string]$SyncDestination,
    [string]$Filter = '*.*',
    [switch]$use_Runspace,
    $thisApp = $thisApp
  )
  $filewatcher_ScriptBlock = {  
    param (
      [string]$FolderPath = $FolderPath,
      [switch]$MonitorSubFolders = $MonitorSubFolders,
      [string]$SyncDestination = $SyncDestination,
      [string]$Filter = $Filter,
      [switch]$use_Runspace = $use_Runspace,
      $thisApp = $thisApp
    )
    try{
      if(!$synchash){
        $synchash = [hashtable]::Synchronized(@{})
      }
      Add-Type -AssemblyName System.Runtime.Caching
      #Caching Policies
      [int]$CacheTimeMilliseconds = 1000
      $synchash.ChangedCachingPolicy = [System.Runtime.Caching.CacheItemPolicy]::new()

      #MemoryCache
      $synchash.ChangedMemoryCache = [system.runtime.caching.MemoryCache]::Default

      #FileWatcher Changed Events
      $synchash.Changedfilewatcher = [System.IO.FileSystemWatcher]::new($FolderPath)
      $synchash.Changedfilewatcher.IncludeSubdirectories = $MonitorSubFolders
      $synchash.Changedfilewatcher.Filter = $Filter
      $synchash.Changedfilewatcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite

      #FileWatcher other Events
      $synchash.filewatcher = [System.IO.FileSystemWatcher]::new($FolderPath)
      $synchash.filewatcher.IncludeSubdirectories = $MonitorSubFolders
      $synchash.filewatcher.Filter = $Filter
      $synchash.filewatcher.NotifyFilter = [System.IO.NotifyFilters]::FileName,[System.IO.NotifyFilters]::DirectoryName

      #Check for and remove existin registered events
      $Registered_Events = Get-EventSubscriber -force
      $Changed = $Registered_Events | where {$_.EventName -eq 'Changed'}
      if($Changed){
        if($thisApp.Config.Dev_mode){write-ezlogs "Unregistering existing event: $($Changed.EventName)" -LogLevel 2 -Dev_mode}
        Unregister-Event -SourceIdentifier $Changed.SourceIdentifier -Force
      }
      #Caching Policy Callbacks
      $CachingPolicy_Scriptblock = { 
        try{
          $path = $args.CacheItem.Value.FullPath              
          if($args.RemovedReason -ne [system.runtime.caching.CacheEntryRemovedReason]::Expired){
            return
          } 
          $changetype = $args.CacheItem.Value.ChangeType
          $isFile = [system.io.path]::HasExtension($path) -or [System.IO.File]::Exists($path)      
          if($isFile){
            write-ezlogs "File $($changetype): $($path)"
          }else{
            #write-ezlogs "Directory $($changetype): $($path)"
          }                            
          #$fileinfo = [System.IO.FileInfo]::new($FileChanged)    
        }catch{
          write-ezlogs "An exception occurred in vlc EndReached event" -showtime -catcherror $_ 
        }   
      }

      $ChangedEvent_Scriptblock = { 
        try{        
          $synchash = $Event.MessageData           
          $synchash.ChangedCachingPolicy.AbsoluteExpiration = [datetime]::Now.AddMilliseconds($CacheTimeMilliseconds)
          $synchash.ChangedMemoryCache.AddOrGetExisting($event.SourceEventArgs.Name,$event.SourceEventArgs,$synchash.ChangedCachingPolicy)              
          #$fileinfo = [System.IO.FileInfo]::new($FileChanged)    
        }catch{
          write-ezlogs "An exception occurred in vlc EndReached event" -showtime -catcherror $_ 
        }   
      }

      $synchash.ChangedCachingPolicy.RemovedCallback = $CachingPolicy_Scriptblock
      
      #FileWatcher Events
      $FileWatcherAction_Scripblock = { 
        $synchash = $Event.MessageData
        try{            
          $path = $event.SourceEventArgs.fullpath
          $changetype = $event.SourceEventArgs.ChangeType
          $isFile = [system.io.path]::HasExtension($path) -or [System.IO.File]::Exists($path)
          if($isFile){
            write-ezlogs "File $($changetype): $($path)"
          }else{
            write-ezlogs "Directory $($changetype): $($path)" 
            #Sync-Files 
          }
        }catch{
          write-ezlogs "An exception occurred in vlc EndReached event" -showtime -catcherror $_
        }   
      }
      $Null = Register-ObjectEvent -InputObject $synchash.Changedfilewatcher -EventName Changed -MessageData $synchash -Action $ChangedEvent_Scriptblock
      $Null = Register-ObjectEvent -InputObject $synchash.filewatcher -EventName Deleted -MessageData $synchash -Action $FileWatcherAction_Scripblock
      $Null = Register-ObjectEvent -InputObject $synchash.filewatcher -EventName Renamed -MessageData $synchash -Action $FileWatcherAction_Scripblock
      $Null = Register-ObjectEvent -InputObject $synchash.filewatcher -EventName Created -MessageData $synchash -Action $FileWatcherAction_Scripblock
    }catch{
      write-ezlogs "An exception occurred in MediaTransportControls_scriptblock" -showtime -catcherror $_
    }
    while($synchash.Changedfilewatcher.EnableRaisingEvents -or $synchash.filewatcher.EnableRaisingEvents){
      start-sleep -Milliseconds 10
    }
    write-ezlogs "filewatcher has ended!" -warning
    if($error){
      write-ezlogs -showtime -PrintErrors -ErrorsToPrint $error 
      $error.clear()
    }       
  }.GetNewClosure()
  if($use_Runspace){ 
    Start-Runspace $filewatcher_ScriptBlock -StartRunspaceJobHandler -synchash $synchash -logfile $thisApp.Log_File -runspace_name "filewatcher_Runspace" -thisApp $thisapp -No_Cancel_Existing
  }else{
    Invoke-Command -ScriptBlock $filewatcher_ScriptBlock
  }
}
#---------------------------------------------- 
#endregion Start-FileWatcher Function
#----------------------------------------------
Export-ModuleMember -Function @('Start-FileWatcher')