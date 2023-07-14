<#
    .Name
    Write-EZLogs

    .Version 
    0.3.2

    .SYNOPSIS
    Module that allows advanced (fancy) console and log message output utilizing runspaces for background IO operations.  

    .DESCRIPTION
       
    .Configurable Variables

    .Requirements
    - Powershell v3.0 or higher

    .RequiredModules
    /Modules/Start-RunSpace/Start-Runspace.psm1

    .EXAMPLE
    - $logfile = Start-EZLogs -logfile_directory "C:\Logs" -- Creates log file and directory (if not exists) and returns path to the log file. Log file name is "ScriptName-ScriptVersion.log" (requires module Get-thisScriptInfo)
    - Write-EZLogs "Message text I want output to console (as yellow) and log file, both with a timestamp" -color yellow -showtime

    .OUTPUTS
    System.Management.Automation.PSObject

    .Author
    EZTechhelp - https://www.eztechhelp.com

    .NOTES
    - Added ability to allow outputting to console only if no log file or directory is given vs trying to create a default log file
    - Added parameter catcherror for write-logs for quick error handling and logging
    - Added parameter verbosedebug to simulate write-verbose formatting
    - Added output of 'hours' for StopWatch timer logging
    - Set default of parameter LogDateFormat for Stop-EZLogs to match Start-EZLogs

#>
$Global:thisApp = [hashtable]::Synchronized(@{})
#----------------------------------------------
#region Get-ThisScriptInfo Function
#----------------------------------------------
function Get-thisScriptInfo
{
  <#
      .SYNOPSIS
      Retreives information about current running script such as path, name, details from comment headers and more.
  #>
  param (
    [switch]$VerboseDebug,
    [string]$logfile_directory,
    [string]$ScriptPath,
    [string]$Script_Temp_Folder,
    [switch]$GetFunctions,
    [switch]$IncludeDetail,    
    [switch]$No_Script_Temp_Folder
  )
  if(!$ScriptPath){$ScriptPath = $((Get-PSCallStack).ScriptName | where {$_ -notmatch '.psm1'} | select -First 1)}
  $thisScript = @{File = [System.IO.FileInfo]::new($ScriptPath); Contents = ([System.IO.FIle]::ReadAllText($ScriptPath))}
  if($thisScript.Contents -Match '^\s*\<#([\s\S]*?)#\>') 
  {
    $thisScript.Help = $Matches[1].Trim()
  }
  [RegEx]::Matches($thisScript.Help, "(^|[`r`n])\s*\.(.+)\s*[`r`n]|$") | ForEach {
    If ($Caption) 
    {$thisScript.$Caption = $thisScript.Help.SubString($Start, $_.Index - $Start)}
    $Caption = $_.Groups[2].ToString().Trim()
    $Start = $_.Index + $_.Length
  }  
  if($IncludeDetail){

    if($thisScript.example){$thisScript.example = $thisScript.example -split("`n") | ForEach {$_.trim()}}else{$thisScript.example = "None"}
    if($thisScript.RequiredModules){$thisScript.RequiredModules = $thisScript.RequiredModules -split("`n") | ForEach {$_.trim()}}else{$thisScript.RequiredModules = "None"}
    if($thisScript.Author){$thisScript.Author = $thisScript.Author.Trim()}else{$thisScript.Author = "Unknown"}
    if($thisScript.credits){$thisScript.credits = $thisScript.credits -split("`n") | ForEach {$_.trim()}}else{$thisScript.credits = "None"}
    if($thisScript.SYNOPSIS){$thisScript.SYNOPSIS = $thisScript.SYNOPSIS -split("`n") | ForEach {$_.trim()}}else{$thisScript.SYNOPSIS = "None"}
    if($thisScript.Description){$thisScript.Description = $thisScript.Description -split("`n") | ForEach {$_.trim()}}else{$thisScript.Description = "None"}
    if($thisScript.Notes){$thisScript.Notes = $thisScript.Notes -split("`n") | ForEach {$_.trim()}}else{$thisScript.Notes = "None"} 
    $thisScript.Arguments = (($Invocation.Line + ' ') -Replace ('^.*\\' + $thisScript.File.Name.Replace('.', '\.') + "['"" ]"), '').Trim() 
    $thisScript.PSCallStack = Get-PSCallStack   
  } 
  if($thisScript.Version){$thisScript.Version = $thisScript.Version.Trim()}
  if($thisScript.Build){$thisScript.Build = $thisScript.Build.Trim()}
  if($thisScript.Name){$thisScript.Name = $thisScript.Name.Trim()}else{$thisScript.Name = $thisScript.File.BaseName.Trim()}
  $thisScript.Path = $thisScript.File.FullName; $thisScript.Folder = $thisScript.File.DirectoryName; $thisScript.BaseName = $thisScript.File.BaseName  
  if($GetFunctions){
    [System.Collections.Generic.List[String]]$FX_NAMES = New-Object System.Collections.Generic.List[String]
    if(!([System.String]::IsNullOrWhiteSpace($thisScript.file)))
    { 
      Select-String -Path $thisScript.file -Pattern "function" |
      ForEach {
        [System.Text.RegularExpressions.Regex] $regexp = New-Object Regex("(function)( +)([\w-]+)")
        [System.Text.RegularExpressions.Match] $match = $regexp.Match("$_")
        if($match.Success)
        {
          $FX_NAMES.Add("$($match.Groups[3])")
        }  
      }
      $thisScript.functions = $FX_NAMES.ToArray()  
    }
  }
  if(!$No_Script_Temp_Folder)
  {
    if(!$Script_Temp_Folder)
    {
      $Script_Temp_Folder = [System.IO.Path]::Combine($env:TEMP, $($thisScript.Name))
    }
    else
    {
      $Script_Temp_Folder = [System.IO.Path]::Combine($Script_Temp_Folder, $($thisScript.Name))
    }
    if(!([System.IO.Directory]::Exists($Script_Temp_Folder)))
    {
      try
      {
        $null = New-Item $Script_Temp_Folder -ItemType Directory -Force
      }
      catch
      {
        Write-error "[ERROR] Exception creating script temp directory $Script_Temp_Folder - $($_ | out-string)"
      }
    }
    $thisScript.TempFolder = $Script_Temp_Folder
  }
  return $thisScript
}
#---------------------------------------------- 
#endregion Get-ThisScriptInfo Function
#----------------------------------------------

#---------------------------------------------- 
#region Start EZLogs Function
#----------------------------------------------
function Start-EZLogs
{
  <#
      .SYNOPSIS
      Initializes various global variables needed and starts a new session of Get-LogWriter for background log writing
  #>
  param (
    [switch]$Verboselog,
    [switch]$DevlogOnly,
    $thisApp = $thisApp,
    [string]$Logfile_Directory,
    [string]$Logfile_Name,
    [string]$Script_Name,
    $thisScript,
    [switch]$UseRunspacePool,
    [switch]$UseGlobalLogFile,
    [switch]$noheader,
    [switch]$Wait,
    [string]$Script_Description,
    [string]$Script_Version,
    [string]$ScriptPath,
    [switch]$Start_Timer = $true,
    [switch]$StartLogWriter,
    [string]$Global_Log_Level,
    [ValidateSet('ascii','bigendianunicode','default','oem','string','unicode','unknown','utf32','utf7','utf8')]
    [string]$Encoding = 'unicode'
  )

  $thisApp.LogMessageQueue = [System.Collections.Concurrent.ConcurrentQueue`1[object]]::New()
  if($Start_Timer -and !$globalstopwatch){$Global:globalstopwatch = [system.diagnostics.stopwatch]::StartNew()}
  if(!$ScriptPath){$ScriptPath = $PSCommandPath} 
  if(!$thisScript){$thisScript = Get-thisScriptinfo -ScriptPath $ScriptPath -No_Script_Temp_Folder}
  if(-not [string]::IsNullOrEmpty($Global_Log_Level) -and $thisApp.Config){
    $thisApp.Config.Log_Level = $Global_Log_Level
  }elseif(-not [string]::IsNullOrEmpty($Global_Log_Level) -and $thisApp){
    $thisApp.Log_Level = $Global_Log_Level
  }elseif($Global:thisApp.Config){
    $thisApp.Config.Log_Level = '2'
  }
  if(!$logfile_directory){
    <#    if([System.IO.Path]::HasExtension($ScriptPath)){
        $logfile_directory = [System.IO.Directory]::GetParent($ScriptPath).FullName
        if([System.IO.Path]::HasExtension($logfile_directory)){
        $logfile_directory = [System.IO.Directory]::GetParent($logfile_directory).FullName
        }
        }else{
        $logfile_directory = $ScriptPath
    } #> 
  }
  if(!$logfile_name){
    if(!$thisScript.Name){  
      $logfile_name = "$([System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)).log"
    }else{
      $logfile_name = "$($thisScript.Name)-$($thisScript.Version).log"
    }
  }   
  $script:logfile = [System.IO.Path]::Combine($logfile_directory, $logfile_name)
  if ($logfile_directory -and !([System.IO.Directory]::Exists($logfile_directory)))
  {
    $null = New-Item -Path $logfile_directory -ItemType directory -Force
  }
  if(!$logfile){
    write-warning "No log file or directory was provided. You can Specify a log directory with Start-EZLogs -Logfile_Directory or specify a log file with write-ezlogs -logfile"
    $enablelogs = $false
  }
  if($DevlogOnly){
    $Global:thisApp.Dev = $true
  }
  if($StartLogWriter){
    if($UseRunspacePool){
      Get-LogWriter -synchash $synchash -logfile $logfile -Startup -thisApp $thisApp -thisScript $thisScript -UseRunspacePool -StartupWait:$Wait
    }else{
      Get-LogWriter -synchash $synchash -logfile $logfile -Startup -thisApp $thisApp -thisScript $thisScript -StartupWait:$Wait
    }
  }
  if(!$noheader){
    Write-ezlogs -showtime:$false -CallBack:$false -logOnly -Logheader -thisScript $thisScript -logfile $logfile
  }
  if($UseGlobalLogFile -and $thisApp){
    $thisApp.Log_File = $logfile
  }else{
    return $logfile
  }  
}
#---------------------------------------------- 
#endregion Start EZLogs Function
#----------------------------------------------

#---------------------------------------------- 
#region Write-EZLogs Function
#----------------------------------------------
function Write-EZLogs 
{
  <#
      .SYNOPSIS
      Primary function used to execute log writing and output 

      .CatchError
      Always Output to console/host and log file

      .Log Levels
      0  - No output to host or log file (disable all logging)
      1  - Output to console/host only
      2  - Ouput to log file only (Default)
      3  - Output to host and log file

  #>
  [CmdletBinding(DefaultParameterSetName = 'text')]
  param (
    [Parameter(Position=0, Mandatory=$false, ValueFromPipeline=$true)]
    [string]$text,
    $thisApp = $thisApp,
    [switch]$VerboseDebug,
    [switch]$Dev_mode,
    [switch]$enablelogs = $true,
    [string]$logfile,
    [switch]$Warning,
    [switch]$Success,
    [switch]$Perf,
    [switch]$PrintErrors,
    [array]$ErrorsToPrint,    
    [switch]$CallBack = $true,
    [switch]$Logheader,
    [switch]$isError,
    $PerfTimer,
    $CatchError,
    [switch]$ClearErrors = $true,
    $thisScript = $thisScript,
    $callpath = $callpath,
    [switch]$logOnly,
    [string]$DateTimeFormat = 'MM/dd/yyyy h:mm:ss tt',
    [ValidateSet('Black','Blue','Cyan','Gray','Green','Magenta','Red','White','Yellow','DarkBlue','DarkCyan','DarkGreen','DarkMagenta','DarkRed','DarkYellow')]
    [string]$color = 'white',
    [ValidateSet('Black','Blue','Cyan','Gray','Green','Magenta','Red','White','Yellow','DarkBlue','DarkCyan','DarkGreen','DarkMagenta','DarkRed','DarkYellow')]
    [string]$foregroundcolor,
    [switch]$showtime = $true,
    [switch]$logtime,
    [switch]$AlertUI,
    [switch]$NoNewLine,
    [switch]$GetMemoryUsage,
    [switch]$forceCollection,
    [int]$StartSpaces,
    [ValidateSet('Main','Twitch','Spotify','Youtube','Startup','Launcher','LocalMedia','VLC','Streamlink','Error','Discord','Libvlc','Perf','Webview2','Setup','Threading','Tor')]
    [string]$logtype = 'Main',
    [string]$Separator,
    [ValidateSet('Black','Blue','Cyan','Gray','Green','Magenta','Red','White','Yellow','DarkBlue','DarkCyan','DarkGreen','DarkMagenta','DarkRed','DarkYellow')]
    [string]$BackgroundColor,
    [int]$linesbefore,
    [int]$linesafter,
    [ValidateSet('ascii','bigendianunicode','default','oem','string','unicode','unknown','utf32','utf7','utf8')]
    [string]$Encoding = 'unicode',
    [ValidateSet('0','1','2','3','4')]
    [string]$LogLevel,
    [ValidateSet('0','1','2','3','4')]
    [string]$PriorityLevel = '0',
    $synchash = $synchash
  )

  if($GetMemoryUsage){
    #$MemoryUsage = " | $(Get-MemoryUsage -forceCollection:$forceCollection)"
  }
  if(-not [string]::IsNullOrEmpty($thisApp.Log_Level) -and [string]::IsNullOrEmpty($LogLevel)){
    $LogLevel = $thisApp.Log_Level
  }

  if($CatchError -or $isError -or $PrintErrors){
    $enablelogs = $true
    $logtype = 'Error'
  }elseif($PerfTimer -or $Perf){
    $enablelogs = $true
    $logtype = 'Perf'
    $logOnly = $true
  }elseif($thisApp.Config.Log_Level -eq 0 -or $loglevel -eq 0){
    $enablelogs = $false
    return
  }elseif($LogLevel -eq 1 -and ($LogLevel -le $thisApp.Config.Log_Level -or $logLevel -le $thisApp.Log_Level)){
    $enablelogs = $false
  }elseif($LogLevel -eq 2 -and ($logLevel -le $thisApp.Config.Log_Level -or $logLevel -le $thisApp.Log_Level)){
    $enablelogs = $true
    $logOnly = $true
  }elseif($LogLevel -eq 3 -and ($logLevel -le $thisApp.Config.Log_Level -or $logLevel -le $thisApp.Log_Level)){
    $enablelogs = $true
  }elseif($LogLevel -eq 4 -and ($logLevel -le $thisApp.Config.Log_Level -or $logLevel -le $thisApp.Log_Level)){
    $enablelogs = $true
    $VerboseDebug = $true
  }elseif(($LogLevel -gt $thisApp.Config.Log_Level -or $LogLevel -gt $thisApp.Log_Level) -and -not [string]::IsNullOrEmpty($thisApp.Config.Log_Level) -and -not [string]::IsNullOrEmpty($thisApp.Log_Level)){
    $enablelogs = $false
    return
  }elseif([string]::IsNullOrEmpty($thisApp.Config.Log_Level) -and -not [string]::IsNullOrEmpty($LogLevel)){
    $enablelogs = $true
  }
 
  if($Dev_mode -and $thisApp.Config.Dev_mode){
    $enablelogs = $true
    $logOnly = $true
    $VerboseDebug = $true
  }elseif($Dev_mode -and !$thisApp.Dev){
    $enablelogs = $false
    return
  }

  if(!$thisApp.Dev -and [string]::IsNullOrEmpty($logfile) -and [string]::IsNullOrEmpty($thisApp.Log_File)){
    switch ($logtype) {
      'Main' {
        if(-not [string]::IsNullOrEmpty($thisApp.Config.Log_file)){
          $logfile = $thisApp.Config.Log_file
        }elseif($thisScript.Name -and -not [string]::IsNullOrEmpty($logfile_directory)){
          $logfile = "$logfile_directory\$($thisScript.Name)-$($thisScript.Version).log"
        }elseif($thisScript.Name -and [string]::IsNullOrEmpty($logfile)){
          $logfile = "$env:appdata\$($thisScript.Name)\Logs\$($thisScript.Name)-$($thisScript.Version).log"
        }
      }
      'Twitch' {
        $logfile = $thisApp.Config.TwitchMedia_logfile
      }
      'Spotify' {
        $logfile = $thisApp.Config.SpotifyMedia_logfile
      }
      'Youtube' {
        $logfile = $thisApp.Config.YoutubeMedia_logfile
      }
      'Startup' {
        if(-not [string]::IsNullOrEmpty($thisApp.Config.Startup_Log_File)){
          $logfile = $thisApp.Config.Startup_Log_File
        }elseif($thisScript.Name){
          $logfile = "$env:appdata\$($thisScript.Name)\Logs\$($thisScript.Name)-$($thisScript.Version)-Startup.log"
        }
      }
      'Launcher' {
        if(-not [string]::IsNullOrEmpty($thisApp.Config.Launcher_Log_File)){
          $logfile = $thisApp.Config.Launcher_Log_File
        }elseif($thisScript.Name){
          $logfile = "$env:appdata\$($thisScript.Name)\Logs\$($thisScript.Name)-$($thisScript.Version)-Launcher.log"
        }
      }
      'LocalMedia' {
        $logfile = $thisApp.Config.LocalMedia_Log_File
      }
      'VLC' {
        $logfile = $thisApp.Config.VLC_Log_File
      }
      'Streamlink' {
        $logfile = $thisApp.Config.Streamlink_Log_File
        $Encoding = 'utf8'
      }
      'Error' {
        if(-not [string]::IsNullOrEmpty($thisApp.Config.Error_Log_File)){
          $logfile = $thisApp.Config.Error_Log_File
        }elseif($thisScript.Name){
          $logfile = "$env:appdata\$($thisScript.Name)\Logs\$($thisScript.Name)-$($thisScript.Version)-Errors.log"
        }
      }
      'Discord' {
        $logfile = $thisApp.Config.Discord_Log_File
      }
      'Libvlc' {
        $logfile = $thisApp.Config.Libvlc_Log_File
      }
      'Perf' {
        if(-not [string]::IsNullOrEmpty($thisApp.Config.Perf_Log_File)){
          $logfile = $thisApp.Config.Perf_Log_File
        }elseif($thisScript.Name){
          $logfile = "$env:appdata\$($thisScript.Name)\Logs\$($thisScript.Name)-$($thisScript.Version)-Perf.log"
        }
        $Perf = $true
      }
      'Webview2' {
        if(-not [string]::IsNullOrEmpty($thisApp.Config.Webview2_Log_File)){
          $logfile = $thisApp.Config.Webview2_Log_File
        }elseif($thisScript.Name){
          $logfile = "$env:appdata\$($thisScript.Name)\Logs\$($thisScript.Name)-$($thisScript.Version)-Webview2.log"
        }
      }
      'Setup' {
        if(-not [string]::IsNullOrEmpty($thisApp.Config.Setup_Log_File)){
          $logfile = $thisApp.Config.Setup_Log_File
        }elseif($thisScript.Name){
          $logfile = "$env:appdata\$($thisScript.Name)\Logs\$($thisScript.Name)-$($thisScript.Version)-Setup.log"
        }
      }
      'Threading' {
        if(-not [string]::IsNullOrEmpty($thisApp.Config.Threading_Log_File)){
          $logfile = $thisApp.Config.Threading_Log_File
        }elseif($thisScript.Name){
          $logfile = "$env:appdata\$($thisScript.Name)\Logs\$($thisScript.Name)-$($thisScript.Version)-Threading.log"
        } 
      }
      'Tor' {
        $logfile = $thisApp.Config.Tor_Log_File
      }
    }
  }elseif(-not [string]::IsNullOrEmpty($thisApp.Log_File)){
    $logfile = $thisApp.Log_File
  }

  if([string]::IsNullOrEmpty($thisApp.Config.Log_file) -and [string]::IsNullOrEmpty($logfile)){
    $logfile = Start-EZLogs -logfile_directory $logfile_directory -ScriptPath $PSCommandPath -thisScript $thisScript -Global_Log_Level $thisApp.Config.Log_Level -thisApp $thisApp -Logfile_Name "$($thisScript.Name)-$($thisScript.version).log" -noheader
  }
  if(!$AlertUI){
    switch ($PriorityLevel) {
      '0' {
        $AlertUI = $false
      }
      '4' {
        $AlertUI = $false
      }
      '3' {
        $AlertUI = $false
      }
      '2' {
        $AlertUI = $true
      }
      '1' {
        $AlertUI = $true
      }
    }
  }  
  if(!$logfile){$logfile = $thisApp.Config.Log_file}
  if(!$logfile){$enablelogs = $false}
  if($showtime -and !$logtime){$logtime = $true}else{$logtime = $false}
  if($success){
    $color = 'Green'
  }elseif($foregroundcolor){
    $color = $foregroundcolor
  }

  try{
    if($CallBack -and $($MyInvocation)){  
      if($callpath){
        $invocation = "$callpath"
      }elseif($($MyInvocation.PSCommandPath -match "(?<value>.*)\\(?<value>.*).ps")){
        $invocation = "$($matches.Value):$($MyInvocation.ScriptLineNumber)"
      }elseif($((Get-PSCallStack)[1].Command) -notmatch 'ScriptBlock'){
        $invocation = "$((Get-PSCallStack)[1].Command):$((Get-PSCallStack).Position.StartLineNumber -join ':')"
      }
      if($invocation){
        $text = "[$($invocation)] $text"
        $callpath = "[$($invocation)]"
      }elseif($CallBack -and $text -notmatch "\[$((Get-PSCallStack)[1].FunctionName)\]"){
        if($((Get-PSCallStack)[1].FunctionName) -match 'ScriptBlock'){
          $callpath = "[$((Get-PSCallStack)[1].FunctionName) - $((Get-PSCallStack).Position.StartLineNumber)]"
          $text = "$callpath $text"
        }else{
          $callpath = "[$((Get-PSCallStack)[1].FunctionName)]"
          $text = "$callpath $text"
        }    
      } 
    }  
  }catch{
    write-output "An exception occurred processing callpaths in Write-ezlogs: $($_ | out-string)" | Out-File -FilePath $logfile -Encoding $Encoding -Append -Force
  }
  if($showtime){
    $timestamp = "[$([datetime]::Now)] " 
  }else{
    $timestamp = $Null
  } 
  if($AlertUI -and $synchash.Window.isVisible){
    if($Warning){
      $Level = 'WARNING'
    }elseif($Success){
      $Level = 'SUCCESS'
    }elseif($logtype -eq 'Error'){
      $Level = 'ERROR'
      if($CatchError){
        $text = "$text`: $($CatchError | select *)`n"
      }
    }else{
      $Level = 'INFO'
    }
    try{
      Update-Notifications -Level $Level -Message "$logtype`: $text" -thisApp $thisapp -synchash $synchash -Open_Flyout -MessageFontWeight bold -LevelFontWeight Bold
    }catch{
      write-output "An exception occurred calling Update-Notifications in Write-ezlogs: $($_ | out-string)" | Out-File -FilePath $logfile -Encoding $Encoding -Append -Force
    }
  }
  #Log output
  $newMessage = New-Object PsObject -Property @{
    'text' = $text
    'VerboseDebug' = $VerboseDebug
    'enablelogs' = $enablelogs
    'logfile' = $logfile
    'Warning' = $Warning
    'PERF' = $Perf
    'Dev_mode' = $Dev_mode
    'MemoryUsage' = $MemoryUsage
    'PerfTimer' = $Perftimer
    'Success' = $Success
    'iserror' = $iserror
    'PrintErrors' = $PrintErrors
    'ErrorsToPrint' = $ErrorsToPrint
    'CallBack' = $CallBack
    'callpath' = $callpath
    'logOnly' = $logOnly
    'Logheader' = $Logheader
    'timestamp' = $timestamp
    'DateTimeFormat' = $DateTimeFormat
    'color' = $color
    'foregroundcolor' = $foregroundcolor
    'showtime' = $showtime
    'logtime' = $logtime
    'NoNewLine' = $NoNewLine    
    'StartSpaces' = $StartSpaces
    'Separator' = $Separator
    'BackgroundColor' = $BackgroundColor
    'linesbefore' = $linesbefore
    'linesafter' = $linesafter
    'CatchError' = $CatchError
    'ClearErrors' = $ClearErrors
    'Encoding' = $Encoding
    'LogLevel' = $LogLevel
    'ProcessMessage' = $true
  }

  try{
    $Null = $thisApp.LogMessageQueue.Enqueue($newMessage)
  }catch{
    write-output "An exception occurred enqueue of new message: $($newMessage | out-string):`n$($_ | out-string)" | Out-File -FilePath $logfile -Encoding $Encoding -Append -Force
  }

  if(!$logOnly){
    if($LinesBefore -ne 0){ for ($i = 0; $i -lt $LinesBefore; $i++) {
        write-host "`n" -NoNewline      
      }
    }
    if($CatchError){
      $text = "[ERROR] $text at: $($CatchError | out-string)`n";$color = "red"
    }
    if($PrintErrors -and $ErrorsToPrint -as [array]){   
      Write-Host -Object "$text$timestamp[PRINT ALL ERRORS]" -ForegroundColor Red
      $e_index = 0
      foreach ($e in $ErrorsToPrint)
      {
        $e_index++
        Write-Host -Object "[$([datetime]::Now)] [ERROR $e_index Message] =========================================================================`n$($e.Exception | out-string)`n |+ $($e.InvocationInfo.PositionMessage)`n |+ $($e.ScriptStackTrace)`n`n" -ForegroundColor Red;        
      }
      return  
    }   

    if($enablelogs)
    {

      if($Warning -and $VerboseDebug){
        if(!$logOnly)
        { 
          Write-Warning ($wrn = "[DEBUG] $text")
        } 
      }
      elseif($Warning)
      {
        if(!$logOnly)
        { 
          Write-Warning ($wrn = "$text")
        }    
      }
      elseif($Success)
      {
        if(!$logOnly)
        { 
          if($BackGroundColor){
            Write-Host -Object "$timestamp[SUCCESS] $text" -ForegroundColor:Green -NoNewline:$NoNewLine -BackgroundColor:$BackGroundColor
          }else{
            Write-Host -Object "$timestamp[SUCCESS] $text" -ForegroundColor:Green -NoNewline:$NoNewLine
          }
        }  
      }
      elseif($VerboseDebug)
      {
        if($BackGroundColor){
          Write-Host -Object "$timestamp[DEBUG] $text" -ForegroundColor:Cyan -NoNewline:$NoNewLine -BackgroundColor:$BackGroundColor
        }else{
          Write-Host -Object "$timestamp[DEBUG] $text" -ForegroundColor:Cyan -NoNewline:$NoNewLine
        }    
      }
      else
      {
        if(!$logOnly)
        {
          if($BackGroundColor){
            Write-Host -Object ($timestamp + $text) -ForegroundColor:$Color -NoNewline:$NoNewLine -BackgroundColor:$BackGroundColor
          }else{
            Write-Host -Object ($timestamp + $text) -ForegroundColor:$Color -NoNewline:$NoNewLine
          }      
        }
      }
    }
    else
    {
      if($Warning -and $VerboseDebug){
        if($showtime){
          Write-Host -Object "[$([datetime]::Now.ToString($DateTimeFormat))] " -NoNewline
        }
        Write-Warning ($wrn = "[DEBUG] $text")
      }
      elseif($warning)
      {
        if($showtime){
          Write-Host -Object "[$([datetime]::Now.ToString($DateTimeFormat))] " -NoNewline
        }
        Write-Warning ($wrn = "$text")  
      }
      elseif($Success)
      {
        if($showtime){
          Write-Host -Object "[$([datetime]::Now.ToString($DateTimeFormat))] " -NoNewline
        }
        if($BackGroundColor){
          Write-Host -Object "[SUCCESS] $text" -ForegroundColor:$Color -NoNewline:$NoNewLine -BackgroundColor:$BackGroundColor
        }else{
          Write-Host -Object "[SUCCESS] $text" -ForegroundColor:$Color -NoNewline:$NoNewLine
        }
      }
      elseif($Perf)
      {
        if($showtime){
          Write-Host -Object "[$([datetime]::Now.ToString($DateTimeFormat))] " -NoNewline
        }
        try{
          if($Perftimer -as [system.diagnostics.stopwatch]){
            Write-Host -Object "[PERF] $text`:`n| Mins: $($Perftimer.Elapsed.Minutes)`n| Secs: $($Perftimer.Elapsed.Seconds)`n| Mils: $($Perftimer.Elapsed.Milliseconds)$($MemoryUsage)" -ForegroundColor:$Color -NoNewline:$NoNewLine
          }elseif($Perftimer -as [Timespan]){
            Write-Host -Object "[PERF] $text`: | Mins: $($Perftimer.Minutes) Secs: $($Perftimer.Seconds) Ms: $($Perftimer.Milliseconds)$($MemoryUsage)" -ForegroundColor:$Color -NoNewline:$NoNewLine
          }else{
            Write-Host -Object "[PERF] $text$($MemoryUsage)" -ForegroundColor:$Color -NoNewline:$NoNewLine
          }
        }catch{
          start-sleep -Milliseconds 100
          Write-Output "$($timestamp)[PERF] $text`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS-LOGONLY-PERF] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $logfile -Encoding $Encoding -Append -NoNewline:$NoNewLine
        }
      }
      else
      {
        if($showtime){
          Write-Host -Object "[$([datetime]::Now.ToString($DateTimeFormat))] " -NoNewline
        }
        if($BackGroundColor){
          Write-Host -Object $text -ForegroundColor:$Color -NoNewline:$NoNewLine -BackgroundColor:$BackGroundColor
        }else{
          Write-Host -Object $text -ForegroundColor:$Color -NoNewline:$NoNewLine
        }    
      }     
    }
    if($LinesAfter -ne 0){
      for ($i = 0; $i -lt $LinesAfter; $i++) {
        write-host "`n" -NoNewline  
      }
    }
  }
  return

}
#---------------------------------------------- 
#endregion Write-EZLogs Function
#----------------------------------------------

#---------------------------------------------- 
#region Get-LogWriter Function
#----------------------------------------------
function Get-LogWriter{
  <#
      .SYNOPSIS
      Performs log writing operations within a runspace that monitors for and writes messages as enqueued by Write-ezlogs
  #>

  param (
    [Parameter(Position=0, Mandatory=$false, ValueFromPipeline=$true)]
    $thisApp = $thisApp,
    [string]$logfile = $thisApp.Config.Log_file,
    $synchash = $synchash,
    $thisScript = $thisScript,
    [switch]$UseRunspacePool,
    [switch]$Startup,
    [switch]$shutdownWait,
    [switch]$StartupWait,
    [switch]$shutdown
  )
  if($startup){
    $log_Writer_ScriptBlock = {  
      try{
        $thisApp.LogWriterEnabled = $true
        if([string]::IsNullOrEmpty($thisApp.Config.Log_File) -and -not [string]::IsNullOrEmpty($thisApp.Log_File)){
          $logfile = $thisApp.Log_File
        }else{
          $logfile = $thisApp.Config.Log_File
        }
        do
        {
          try{
            $Message = @{}
            $ProcessMessage = $thisApp.LogMessageQueue.TryDequeue([ref]$message)
            $text = $($message.text)
            if($ProcessMessage -and $Message.ProcessMessage){
              if($Message.LinesBefore -ne 0){ for ($i = 0; $i -lt $Message.LinesBefore; $i++) {
                  try{
                    if($Message.enablelogs){
                      write-output "" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -Force
                    }
                  }catch{
                    start-sleep -Milliseconds 100
                    if($message.enablelogs){
                      write-output "`n$($message.timestamp)[ERROR] [WRITE-EZLOGS-LinesBefore] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -Force
                    }
                  }       
                }
              }
              if($message.Logheader){
                if(!$thisApp.Config.App_Name){
                  $Script_Name = $($thisScript.Name)
                }else{
                  $Script_Name = $($thisApp.Config.App_Name)
                }
                if(-not [string]::IsNullOrEmpty($thisScript.SYNOPSIS)){
                  $Script_Description = $($thisScript.SYNOPSIS).trim()
                }
                if(!$thisApp.Config.App_Version){
                  $Script_Version = $($thisScript.Version)
                }else{
                  $Script_Version = $($thisApp.Config.App_Version)
                }
                if(!$thisApp.Config.App_Build){
                  $Script_Build = $($thisScript.Build)
                }else{
                  $Script_Build = $($thisApp.Config.App_Build)
                }
                $OriginalPref = $ProgressPreference
                $ProgressPreference = 'SilentlyContinue'
                #ManagementObjectSearcher is 'slightly' faster than Get-CimInstance
                $query = [System.Management.ObjectQuery]::new("SELECT * FROM Win32_OperatingSystem")
                $searcher = [System.Management.ManagementObjectSearcher]::new($query)
                $results = $searcher.get()    
                $searcher.Dispose()
                if($thisApp.Config.Log_Level -ge 2){
                  $query = [System.Management.ObjectQuery]::new("SELECT * FROM Win32_BIOS")
                  $searcher = [System.Management.ManagementObjectSearcher]::new($query)
                  $bios_info = $searcher.get()  
                  $searcher.Dispose()         
                  $query = [System.Management.ObjectQuery]::new("SELECT * FROM Win32_Processor")
                  $searcher = [System.Management.ManagementObjectSearcher]::new($query)
                  $cpu_info = $searcher.get()    
                  $searcher.Dispose()
                }
                #Used for EZT-MediaPlayer
                if($message.LogHeader_Audio){
                  try{
                    $default_output_Device = [CSCore.CoreAudioAPI.MMDeviceEnumerator]::DefaultAudioEndpoint([CSCore.CoreAudioAPI.DataFlow]::Render,[CSCore.CoreAudioAPI.Role]::Multimedia)
                  }catch{
                    write-output "`n$($message.timestamp)[ERROR] [WRITE-EZLOGS-Logheader] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -Force
                  }
                }
                $ProgressPreference = $OriginalPref
                $text = @"
`n###################### Logging Enabled ######################
Script Name          : $Script_Name
Synopsis             : $Script_Description
Log File             : $($message.logfile)
Log Level            : $($thisApp.Config.Log_Level)
Version              : $Script_Version
Build                : $Script_Build
Current Username     : $env:username
Powershell           : $($PSVersionTable.psversion)($($PSVersionTable.psedition))
Computer Name        : $env:computername
Operating System     : $($results.Caption)($($results.Version))
CPU                  : $($cpu_info.name) | Cores: $($env:NUMBER_OF_PROCESSORS)
RAM                  : $([Math]::Round([int64]($results.TotalVisibleMemorySize)/1MB,2)) GB (Available: $([Math]::Round([int64]($results.FreePhysicalMemory)/1MB,2)) GB)
Manufacturer         : $($bios_info.Manufacturer)
Model                : $($bios_info.Version)
Serial Number        : NA
Domain               : $env:USERDOMAIN
Install Date         : $($results.InstallDate)
Last Boot Up Time    : $($results.LastBootUpTime)
Windows Directory    : $env:windir
Default Audio Device : $($default_output_Device.FriendlyName)
###################### Logging Started - [$([datetime]::Now)] ##########################
"@
              
              }
              if($message.CatchError){
                try{
                  $text = "[ERROR] $text$($message.MemoryUsage)`:`n|+ [Exception]: $($message.CatchError.Exception)`n`n|+ [PositionMessage]: $($message.CatchError.InvocationInfo.PositionMessage | out-string)`n`n|+ [ScriptStackTrace]: $($message.CatchError.ScriptStackTrace  | out-string)`n$(`
                    if(-not [string]::IsNullOrEmpty(($message.CatchError.InvocationInfo.PSCommandPath | out-string))){"|+ [PSCommandPath]: $($message.CatchError.InvocationInfo.PSCommandPath | out-string)`n"})$(`
                    if(-not [string]::IsNullOrEmpty(($message.CatchError.InvocationInfo.InvocationName))){"|+ [InvocationName]: $($message.CatchError.InvocationInfo.InvocationName | out-string)`n"})$(`
                    if($message.CatchError.InvocationInfo.MyCommand){"|+ [MyCommand]: $($message.CatchError.InvocationInfo.MyCommand)`n"})$(`
                    if(-not [string]::IsNullOrEmpty(($message.CatchError.InvocationInfo.BoundParameters | out-string))){"|+ [BoundParameters]: $($message.CatchError.InvocationInfo.BoundParameters | out-string)`n"})$(`
                  if(-not [string]::IsNullOrEmpty(($message.CatchError.InvocationInfo.UnboundArguments | out-string))){"|+ [UnboundArguments]: $($message.CatchError.InvocationInfo.UnboundArguments | out-string)`n"})=========================================================================`n"
                  $message.color = "red"
                }catch{
                  start-sleep -Milliseconds 100
                  if($message.enablelogs){
                    write-output "`n$($message.timestamp)[ERROR] [WRITE-EZLOGS-CatchError] [$((Get-PSCallStack)[0].FunctionName) - $($message.callpath)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -Force
                  }
                }finally{
                  if($message.ClearErrors){
                    $error.clear()
                  }
                }  
              } 
              if($message.PrintErrors -and $message.ErrorsToPrint -as [array]){
                try{    
                  $e_index = 0
                  foreach ($e in $message.ErrorsToPrint)
                  {
                    $e_index++
                    if($message.enablelogs){
                      [System.IO.File]::AppendAllText($message.logfile, "[$([datetime]::Now)] [PRINT ERROR $e_index Message] =========================================================================`n[Exception]: $($e.Exception)`n`n|+ [PositionMessage]: $($e.InvocationInfo.PositionMessage)`n`n|+ [ScriptStackTrace]: $($e.ScriptStackTrace)`n-------------------------------------------------------------------------`n`n" + ([Environment]::NewLine),[System.Text.Encoding]::Unicode)
                    }        
                  }   
                }catch{ 
                  start-sleep -Milliseconds 100
                  $e_index = 0
                  foreach ($e in $message.ErrorsToPrint)
                  {
                    $e_index++
                    if($message.enablelogs){"[ERROR $e_index Message] =========================================================================`n$($e.Exception | select * | out-string)`n |+ $($e.InvocationInfo.PositionMessage)`n |+ $($e.ScriptStackTrace)`n`n" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -Force}        
                  }      
                  Write-host ("$text$($message.timestamp)[ERROR] [WRITE-EZLOGS] [$((Get-PSCallStack)[1].FunctionName)] `n $($_.Exception | out-string)`n |+ $($_.InvocationInfo.PositionMessage)`n |+ $($_.ScriptStackTrace)") -ForegroundColor Red
                  ("$text$($message.timestamp) [ERROR] [WRITE-EZLOGS] [$((Get-PSCallStack)[1].FunctionName)] `n $($_.Exception | out-string)`n |+ $($_.InvocationInfo.PositionMessage)`n |+ $($_.ScriptStackTrace)") | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -Force
                }finally{
                  if($message.ClearErrors){
                    $error.clear()
                  }
                }
                return  
              }  
              if($message.enablelogs)
              {
                if($message.VerboseDebug -and $message.warning)
                {
                  if($message.logOnly)
                  { 
                    try{
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)[DEBUG] [WARNING] $text$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }catch{
                      start-sleep -Milliseconds 100
                      Write-Output "$($message.timestamp)[DEBUG] [WARNING] $text$($message.MemoryUsage)`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS-LOGONLY-WARNING-DEBUG] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -NoNewline:$message.NoNewLine
                    }
                  }
                  else
                  {        
                    try{
                      Write-Warning ($wrn = "[DEBUG] $text")
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)[WARNING] $wrn$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }catch{
                      start-sleep -Milliseconds 100
                      Write-Output "$($message.timestamp)[DEBUG] [WARNING] $text$($message.MemoryUsage)`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS-WARNING-DEBUG] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append
                    }        
                  } 
                }
                elseif($message.Warning)
                {
                  if($message.logOnly)
                  { 
                    try{
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)[WARNING] $text$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }catch{
                      start-sleep -Milliseconds 100
                      Write-Output "$($message.timestamp)[WARNING] $text$($message.MemoryUsage)`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS-LOGONLY-WARNING] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -NoNewline:$message.NoNewLine
                    }
                  }
                  else
                  {        
                    try{
                      Write-Warning ($wrn = "$text")
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)[WARNING] $wrn$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }catch{
                      start-sleep -Milliseconds 100
                      Write-Output "$($message.timestamp)[WARNING] $text`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS-WARNING] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append
                    }        
                  }      
                }
                elseif($message.Success)
                {
                  if($message.logOnly)
                  { 
                    try{
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)[SUCCESS] $text$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }catch{
                      start-sleep -Milliseconds 100
                      Write-Output "$($message.timestamp)[SUCCESS] $text$($message.MemoryUsage)`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS-LOGONLY-SUCCESS] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -NoNewline:$message.NoNewLine
                    }
                  }
                  else
                  {        
                    try{
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)[SUCCESS] $text$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }catch{
                      start-sleep -Milliseconds 100
                      Write-Output "$($message.timestamp)[SUCCESS] $text$($message.MemoryUsage)`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS-SUCCESS] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append
                    }        
                  }      
                }
                elseif($message.isError)
                {
                  if($message.logOnly)
                  { 
                    try{
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)[ERROR] $text$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }catch{
                      start-sleep -Milliseconds 100
                      Write-Output "$($message.timestamp)[ERROR] $text$($message.MemoryUsage)`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS-LOGONLY-SUCCESS] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -NoNewline:$message.NoNewLine
                    }
                  }
                  else
                  {        
                    try{
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)[ERROR] $text$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }catch{
                      start-sleep -Milliseconds 100
                      Write-Output "$($message.timestamp)[ERROR] $text$($message.MemoryUsage)`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS-SUCCESS] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append
                    }        
                  }      
                }
                elseif($message.PERF)
                {
                  try{
                    if($message.Perftimer -as [system.diagnostics.stopwatch]){
                      if($message.Perftimer.Elapsed.Minutes -gt 0 -or $message.Perftimer.Elapsed.hours -gt 0){
                        $perfstate = '[+HIGHLOAD]: '
                      }elseif($message.Perftimer.Elapsed.Seconds -gt 0){
                        $perfstate = '[WARNING] '
                      }else{
                        $perfstate = ''
                      }                      
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)$perfstate[PERF] $text | Time: $($message.Perftimer.Elapsed.hours):$($message.Perftimer.Elapsed.Minutes):$($message.Perftimer.Elapsed.Seconds):$(([string]$message.Perftimer.Elapsed.Milliseconds).PadLeft(3,'0'))$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }elseif($message.Perftimer -as [Timespan]){
                      if($message.Perftimer.Minutes -gt 0 -or $message.Perftimer.hours -gt 0){
                        $perfstate = '[+HIGHLOAD]: '
                      }elseif($message.Perftimer.Seconds -gt 0){
                        $perfstate = '[WARNING] '
                      }else{
                        $perfstate = ''
                      }
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)$perfstate[PERF] $text | Time: $($message.Perftimer.hours):$($message.Perftimer.Minutes):$($message.Perftimer.Seconds):$(([string]$message.Perftimer.Milliseconds).PadLeft(3,'0'))$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }else{
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)[PERF] $text$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }
                  }catch{
                    start-sleep -Milliseconds 100
                    Write-Output "$($message.timestamp)[PERF] $text`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS-LOGONLY-PERF] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -NoNewline:$message.NoNewLine
                  }     
                }
                elseif($message.VerboseDebug)
                {
                  if($message.logOnly)
                  { 
                    try{
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)[DEBUG] $text$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }catch{
                      start-sleep -Milliseconds 100
                      Write-Output "$($message.timestamp)[DEBUG] $text`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS-LOGONLY-DEBUG] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -NoNewline:$message.NoNewLine
                    }
                  }
                  else
                  {        
                    try{
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)[DEBUG] $text$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }catch{
                      start-sleep -Milliseconds 100
                      Write-Output "$($message.timestamp)[DEBUG] $text`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS-DEBUG] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append
                    }        
                  }    
                }
                else
                {
                  if($message.logOnly)
                  {
                    try{
                      [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp)$text$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                    }catch{ 
                      start-sleep -Milliseconds 100
                      Write-host ("$($message.timestamp)[ERROR] [WRITE-EZLOGS] [$((Get-PSCallStack)[1].FunctionName)] $($_ | out-string)") -ForegroundColor Red
                      Write-Output "$($message.timestamp)[ERROR] [WRITE-EZLOGS] $text$($message.MemoryUsage)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -NoNewline:$message.NoNewLine
                    }         
                  }
                  else
                  {      
                    try{
                      if($message.BackGroundColor){
                        Write-Host -Object ($message.timestamp + $text) -ForegroundColor:$message.Color -NoNewline:$message.NoNewLine -BackgroundColor:$message.BackGroundColor
                        if($message.enablelogs){
                          [System.IO.File]::AppendAllText($message.logfile, "$($message.timestamp + $text)$($message.MemoryUsage)" + ([Environment]::NewLine),[System.Text.Encoding]::$($message.Encoding))
                        }
                      }else{
                        Write-Host -Object ($message.timestamp + $text) -ForegroundColor:$message.Color -NoNewline:$message.NoNewLine;if($message.enablelogs){$message.timestamp + $text + $($message.MemoryUsage) | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -NoNewline:$message.NoNewLine -Force}
                      }
                    }catch{ 
                      start-sleep -Milliseconds 100
                      Write-host ("$($message.timestamp)[ERROR] [WRITE-EZLOGS] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)") -ForegroundColor Red
                      ($message.timestamp + $text + $($message.MemoryUsage) + "`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)") | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -Force
                    }      
                  }
                }
              }
              else
              {
                if($message.warning)
                {
                  if($message.showtime){
                    Write-Host -Object "[$([datetime]::Now.ToString($message.DateTimeFormat))] " -NoNewline
                  }
                  Write-Warning ($wrn = "$text")  
                }
                elseif($message.success)
                {
                  if($message.showtime){
                    Write-Host -Object "[$([datetime]::Now.ToString($message.DateTimeFormat))] " -NoNewline
                  }
                  if($message.BackGroundColor){
                    Write-Host -Object "[SUCCESS] $text$($message.MemoryUsage)" -ForegroundColor:$message.Color -NoNewline:$message.NoNewLine -BackgroundColor:$message.BackGroundColor
                  }else{
                    Write-Host -Object "[SUCCESS] $text$($message.MemoryUsage)" -ForegroundColor:$message.Color -NoNewline:$message.NoNewLine
                  }  
                }
                else
                {
                  if($message.showtime){
                    Write-Host -Object "[$([datetime]::Now.ToString($message.DateTimeFormat))] " -NoNewline
                  }
                  if($message.BackGroundColor){
                    Write-Host -Object $text -ForegroundColor:$message.Color -NoNewline:$message.NoNewLine -BackgroundColor:$message.BackGroundColor
                  }else{
                    Write-Host -Object $text -ForegroundColor:$message.Color -NoNewline:$message.NoNewLine
                  }    
                }     
              }

              if($message.LinesAfter -ne 0){
                for ($i = 0; $i -lt $message.LinesAfter; $i++) {
                  try{
                    write-host "`n" -NoNewline
                    if($message.enablelogs){
                      write-output "" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -Force
                    }
                  }catch{
                    start-sleep -Milliseconds 100
                    write-host "`n" -NoNewline
                    if($message.enablelogs){
                      write-output "`n[$([datetime]::Now)] [ERROR] [WRITE-EZLOGS-LinesAfter] [$((Get-PSCallStack)[1].FunctionName)] `n $($_ | out-string)" | Out-File -FilePath $message.logfile -Encoding $message.Encoding -Append -Force
                    }
                  }    
                }
              }
            }
            Remove-Variable Message
            Remove-Variable text
            Start-Sleep -Milliseconds 50
          }catch{
            Start-Sleep -Milliseconds 500
            $While_loop_error_text = "[ERROR] An exception occurred in log_Writer_ScriptBlock while loop at: $($_ | out-string)`n"
            [System.IO.File]::AppendAllText($logfile, "$While_loop_error_text" + ([Environment]::NewLine),[System.Text.Encoding]::Unicode)
          } 
        } while($thisApp.LogWriterEnabled)  
        [System.IO.File]::AppendAllText($logfile, "[$([datetime]::Now)] [WARNING] LogWriter has ended!" + ([Environment]::NewLine),[System.Text.Encoding]::Unicode)
      }catch{
        Start-Sleep -Milliseconds 500
        $runspace_error_text = "[ERROR] An exception occurred in log_Writer_scriptblock at: $($_ | out-string)`n"
        [System.IO.File]::AppendAllText($logfile, "$runspace_error_text" + ([Environment]::NewLine),[System.Text.Encoding]::Unicode)
      }  
    }
    $Variable_list = Get-Variable | where {$_.Options -notmatch "ReadOnly" -and $_.Options -notmatch "Constant"}  
    if($useRunspacePool){
      $thisApp.runspacePool = Start-RunspacePool -CleanupInterval "00:00:1"
      $Null = Start-RunspacePoolJob -ScriptBlock $log_Writer_ScriptBlock -RunspacePool $thisApp.runspacePool -thisApp $thisApp -Variable_list $Variable_list
    }else{
      Start-Runspace $log_Writer_ScriptBlock -Variable_list $Variable_list -StartRunspaceJobHandler -synchash $synchash -logfile $logfile -runspace_name "LogWriter_Runspace" -thisApp $thisapp
    } 
    if($StartupWait){
      while(!$thisApp.LogMessageQueue -or !$thisApp.LogWriterEnabled){
        start-sleep -Milliseconds 100
      }   
    } 
    Remove-Variable Variable_list
  }elseif($shutdown){
    if($shutdownWait){
      $WaitTimer = 0
      while(!$thisApp.LogMessageQueue.IsEmpty -and $WaitTimer -lt 5){
        $WaitTimer++
        start-sleep 1
      }
    }
    $thisApp.LogWriterEnabled = $false
  }
}
#---------------------------------------------- 
#endregion Get-LogWriter Function
#----------------------------------------------

#---------------------------------------------- 
#region Stop EZLogs
#----------------------------------------------
function Stop-EZLogs
{
  <#
      .SYNOPSIS
      Terminates Logwriter runspace and performs other final cleanup
  #>
  param (
    [array]$ErrorSummary,
    $thisApp,
    [string]$logdateformat = 'MM/dd/yyyy h:mm:ss tt',
    [string]$logfile = $logfile,
    [switch]$logOnly,
    [switch]$enablelogs = $true,
    [switch]$stoptimer,
    [switch]$clearErrors,
    [switch]$PrintErrors,
    [ValidateSet('ascii','bigendianunicode','default','oem','string','unicode','unknown','utf32','utf7','utf8')]
    [string]$Encoding = 'unicode'
  )  
  if($ErrorSummary)
  {
    write-ezlogs -PrintErrors:$PrintErrors -ErrorsToPrint $ErrorSummary
    if($clearErrors)
    {
      $error.Clear()
    }
  }
  if($globalstopwatch.elapsed.Days -gt 0){
    $days = "Days        : $($globalstopwatch.elapsed.days)`n"
  }else{
    $days = $null
  }  
  Get-LogWriter -synchash $synchash -shutdown -thisApp $thisApp -shutdownWait
  [System.IO.File]::AppendAllText($thisApp.Config.Log_file, "`n======== Total Script Execution Time ========" + ([Environment]::NewLine),[System.Text.Encoding]::Unicode)
  [System.IO.File]::AppendAllText($thisApp.Config.Log_file, "$days`Hours        : $($globalstopwatch.elapsed.hours)`nMinutes      : $($globalstopwatch.elapsed.Minutes)`nSeconds      : $($globalstopwatch.elapsed.Seconds)`nMilliseconds : $($globalstopwatch.elapsed.Milliseconds)" + ([Environment]::NewLine),[System.Text.Encoding]::Unicode)
  if($stoptimer)
  {
    $($globalstopwatch.stop())
    $($globalstopwatch.reset()) 
  }
  [System.IO.File]::AppendAllText($thisApp.Config.Log_file, "###################### Logging Finished - [$([datetime]::Now)] ######################`n" + ([Environment]::NewLine),[System.Text.Encoding]::Unicode)  
}  
#---------------------------------------------- 
#endregion Stop EZLogs
#----------------------------------------------
Export-ModuleMember -Function @('Start-LogWriter','Start-EZLogs','Write-EZLogs','Stop-EZLogs','Get-thisScriptInfo','Get-LogWriter')