<#
    .Name
    Start-Runspace

    .Version 
    0.2.0

    .SYNOPSIS
    Allows invoking and managing new runspaces

    .DESCRIPTION
       
    .Configurable Variables

    .Requirements
    - Powershell v3.0 or higher

    .OUTPUTS
    System.Management.Automation.PSObject

    .Author
    EZTechhelp - https://www.eztechhelp.com

    .NOTES

    .RequiredModules
    /Modules/Write-EZlogs/Write-EZlogs.psm1
    
#>
#---------------------------------------------- 
#region Start Runspace Function
#----------------------------------------------
function Start-Runspace
{
  param (   
    $scriptblock,
    $thisApp = $thisApp,
    [switch]$StartRunspaceJobHandler, 
    $Variable_list,
    $logfile = $thisApp.Config.threading_Log_File,
    $thisScript,
    [string]$runspace_name,
    [switch]$cancel_runspace,
    [switch]$CheckforExisting,
    [switch]$JobCleanup_Startonly,
    $synchash,
    [switch]$RestrictedRunspace,
    [switch]$Set_stateChangeEvent,
    [switch]$startup_perf_timer,
    $modules_list,
    $function_list,
    [int]$maxRunspaces = [int]$env:NUMBER_OF_PROCESSORS + 1,
    $Script_Modules,
    $startup_stopwatch,
    [ValidateSet('STA','MTA')]
    $ApartmentState = 'STA',
    [switch]$Wait,
    [switch]$verboselog
  )

  if($StartRunspaceJobHandler -and !$JobCleanup)
  {
    if($RestrictedRunspace){
      $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::Create()
      $CmdletEntry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('WriteOutput', [Microsoft.PowerShell.Commands.WriteOutputCommand],$null)
      $null = $InitialSessionState.Commands.Add($CmdletEntry)
      $CmdletEntry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('WhereObject', [Microsoft.PowerShell.Commands.WhereObjectCommand],$null)
      $null = $InitialSessionState.Commands.Add($CmdletEntry)
      $CmdletEntry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('GetCommand', [Microsoft.PowerShell.Commands.GetCommandCommand],$null)
      $null = $InitialSessionState.Commands.Add($CmdletEntry)
      $CmdletEntry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('GetPSCallStack', [Microsoft.PowerShell.Commands.GetPSCallStackCommand],$null)
      $null = $InitialSessionState.Commands.Add($CmdletEntry)
      $CmdletEntry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('OutString', [Microsoft.PowerShell.Commands.OutStringCommand],$null)
      $null = $InitialSessionState.Commands.Add($CmdletEntry)
      $CmdletEntry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('OutFile', [Microsoft.PowerShell.Commands.OutFileCommand],$null)
      $null = $InitialSessionState.Commands.Add($CmdletEntry)
      $CmdletEntry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('SelectObject', [Microsoft.PowerShell.Commands.SelectObjectCommand],$null)
      $null = $InitialSessionState.Commands.Add($CmdletEntry)
      $CmdletEntry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('GetVariable', [Microsoft.PowerShell.Commands.GetVariableCommand],$null)
      $null = $InitialSessionState.Commands.Add($CmdletEntry)
      $CmdletEntry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('RemoveVariable', [Microsoft.PowerShell.Commands.RemoveVariableCommand],$null)
      $null = $InitialSessionState.Commands.Add($CmdletEntry)
      $CmdletEntry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('ForEachObject', [Microsoft.PowerShell.Commands.ForEachObjectCommand],$null)
      $null = $InitialSessionState.Commands.Add($CmdletEntry) 
      $CmdletEntry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('StartSleep', [Microsoft.PowerShell.Commands.StartSleepCommand],$null)
      $null = $InitialSessionState.Commands.Add($CmdletEntry) 
      $CmdletEntry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('ImportModule', [Microsoft.PowerShell.Commands.ImportModuleCommand],$null)
      $null = $InitialSessionState.Commands.Add($CmdletEntry)
    }else{
      $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault() 
    }
    $Global:JobCleanup = [hashtable]::Synchronized(@{})
    $Global:Jobs = [system.collections.arraylist]::Synchronized((New-Object System.Collections.ArrayList))
    $jobCleanup.Flag = $True   
    $jobCleanup_newRunspace =[runspacefactory]::CreateRunspace($InitialSessionState)
    $jobCleanup_newRunspace.ApartmentState = "STA"
    $jobCleanup_newRunspace.ThreadOptions = "ReuseThread"          
    $jobCleanup_newRunspace.Open()  
    $jobCleanup_newRunspace.name = 'JobCleanup_Runspace'      
    $jobCleanup_newRunspace.SessionStateProxy.SetVariable('PSModulePath',$env:PSModulePath)
    $jobCleanup_newRunspace.SessionStateProxy.SetVariable("jobCleanup",$jobCleanup)     
    $jobCleanup_newRunspace.SessionStateProxy.SetVariable("jobs",$jobs) 
    $jobCleanup_newRunspace.SessionStateProxy.SetVariable("logfile",$logfile) 
    $jobCleanup_newRunspace.SessionStateProxy.SetVariable("synchash",$synchash) 
    $jobCleanup_newRunspace.SessionStateProxy.SetVariable("thisScript",$thisScript) 
    #$jobCleanup_newRunspace.SessionStateProxy.SetVariable("Outputobject",$Outputobject) 
    $jobCleanup_newRunspace.SessionStateProxy.SetVariable("thisApp",$thisApp)
    $jobCleanup_newRunspace.SessionStateProxy.SetVariable("verboselog",$verboselog)
    #$Jobcleanup_Timer = 0    
    $jobCleanup.PowerShell = [PowerShell]::Create().AddScript({
        #Routine to handle completed runspaces
        Do 
        {  
          try
          {  
            $temphash = $jobs.clone() 
            Foreach($runspace in $temphash) 
            {            
              If ($runspace.Runspace.isCompleted) 
              {
                if(!$logfile){
                  if($thisApp.Config.Threading_Log_File){
                    $logfile = $thisApp.Config.Threading_Log_File
                  }elseif($thisApp.Config.Log_File){
                    $logfile = $thisApp.Config.Log_File
                  }elseif($thisScript){
                    $logfile = "$env:appdata\$($thisScript.Name)\Logs\$($thisScript.Name)-$($thisScript.Version)-Threading.log"
                    if(![system.io.directory]::Exists("$env:appdata\$($thisScript.Name)\Logs\")){
                      $null = New-item "$env:appdata\$($thisScript.Name)\Logs\" -ItemType Directory -Force
                    }
                  }
                }
                if($thisApp.Config.Error_Log_File){
                  $error_log = $thisApp.Config.Error_Log_File
                }else{
                  $error_log = $logfile
                }
                if((Get-command Write-ezlogs*) -and $thisApp.Config.Threading_Log_File -and $thisApp.LogWriterEnabled){
                  write-ezlogs ">>>> Runspace '$($runspace.powershell.runspace.name)' Completed" -logtype Threading
                }elseif($logfile){
                  write-output "[$([datetime]::Now)] >>>> Runspace '$($runspace.powershell.runspace.name)' Completed" | out-file $logfile -Force -Append -Encoding unicode
                } 
                if($($runspace.powershell.runspace.name) -eq 'log_Writer_runspace' -and $thisApp.LogWriterEnabled){
                  try{
                    if(!(Get-command Get-LogWriter*)){
                      Import-module "$($thisApp.config.Current_Folder)\Modules\Write-EZlogs\write-ezlogs.psm1"
                    }
                    write-output "[$([datetime]::Now)] [WARNING] Log Writer stopped unexpectedly (LogWriterEnabled: $($thisApp.LogWriterEnabled))...attempting to restart`n[$([datetime]::Now)] ERRORS: $($runspace.powershell.Streams.Error | out-string)" | out-file $logfile -Force -Append -Encoding unicode
                    Get-LogWriter -synchash $synchash -logfile $logfile -Startup -thisApp $thisApp
                  }catch{
                    write-output "[$([datetime]::Now)] [$((Get-PSCallStack)[1].Command):$((Get-PSCallStack)[1].InvocationInfo.ScriptLineNumber):$($runspace.powershell.runspace.name)] [ERROR] An exception occurred restarting the log writer: $($_ | out-string)" | out-file $logfile -Force -Append -Encoding unicode             
                  } 
                }        
                if($runspace.powershell.HadErrors){
                  write-output "[$([datetime]::Now)] [$((Get-PSCallStack)[1].Command):$((Get-PSCallStack)[1].InvocationInfo.ScriptLineNumber):$($runspace.powershell.runspace.name)] [========= RUNSPACE $($runspace.powershell.runspace.name) HAD ERRORS =========]" | out-file $error_log -Force -Append -Encoding unicode 
                  $e_index = 0
                  foreach ($e in $runspace.powershell.Streams.Warning)
                  {
                    $e_index++
                    if((Get-command Write-ezlogs*) -and $thisApp.Config.Error_Log_File -and $thisApp.LogWriterEnabled){
                      write-ezlogs "[Warning $e_index Message:$($runspace.powershell.runspace.name)] =========================================================================`n$($e | out-string)" -logtype Error -Warning
                    }else{
                      write-output "[$([datetime]::Now)] [Warning $e_index Message:$($runspace.powershell.runspace.name)] =========================================================================`n$($e | out-string)" | out-file $error_log -Force -Append -Encoding unicode
                    }                   
                  }
                  if($thisApp.Config.Dev_mode -or $thisApp.Config.Log_Level -ge 3){
                    $e_index = 0
                    foreach ($e in $runspace.powershell.Streams.Information)
                    {
                      $e_index++
                      if((Get-command Write-ezlogs*) -and $thisApp.Config.Error_Log_File -and $thisApp.LogWriterEnabled){
                        write-ezlogs "[Information $e_index Message:$($runspace.powershell.runspace.name)] =========================================================================`n$($e | out-string)" -logtype Error
                      }else{
                        write-output "[$([datetime]::Now)] [ERROR] [Information $e_index Message:$($runspace.powershell.runspace.name)] =========================================================================`n$($e | out-string)" | out-file $error_log -Force -Append -Encoding unicode
                      }                  
                    }
                    $e_index = 0
                    foreach ($e in $runspace.powershell.Streams.Progress)
                    {
                      $e_index++
                      if((Get-command Write-ezlogs*) -and $thisApp.Config.Error_Log_File -and $thisApp.LogWriterEnabled){
                        write-ezlogs "[DEBUG] [Progress $e_index Message:$($runspace.powershell.runspace.name)] =========================================================================`n$($e | out-string)" -logtype Error
                      }else{
                        write-output "[$([datetime]::Now)] [DEBUG] [Progress $e_index Message:$($runspace.powershell.runspace.name)] =========================================================================`n$($e | out-string)" | out-file $error_log -Force -Append -Encoding unicode
                      } 
                    }                
                    $e_index = 0
                    foreach ($e in $runspace.powershell.Streams.Verbose)
                    {
                      $e_index++
                      if((Get-command Write-ezlogs*) -and $thisApp.Config.Error_Log_File -and $thisApp.LogWriterEnabled){
                        write-ezlogs "[DEBUG] [Verbose $e_index Message:$($runspace.powershell.runspace.name)] =========================================================================`n$($e | out-string)" -logtype Error
                      }else{
                        write-output "[$([datetime]::Now)] [DEBUG] [Verbose $e_index Message:$($runspace.powershell.runspace.name)] =========================================================================`n$($e | out-string)" | out-file $error_log -Force -Append -Encoding unicode
                      }                     
                    }               
                    $e_index = 0
                    foreach ($e in $runspace.powershell.Streams.Debug)
                    {
                      $e_index++
                      if((Get-command Write-ezlogs*) -and $thisApp.Config.Error_Log_File -and $thisApp.LogWriterEnabled){
                        write-ezlogs "[DEBUG] [Debug $e_index Message:$($runspace.powershell.runspace.name)] =========================================================================`n$($e | out-string)" -logtype Error
                      }else{
                        write-output "[$([datetime]::Now)] [DEBUG] [Debug $e_index Message:$($runspace.powershell.runspace.name)] =========================================================================`n$($e | out-string)" | out-file $error_log -Force -Append -Encoding unicode
                      }
                    } 
                  }                                                                                                       
                  $e_index = 0
                  foreach ($e in $runspace.powershell.Streams.Error)
                  {
                    $e_index++
                    if((Get-command Write-ezlogs*) -and $thisApp.Config.Error_Log_File -and $thisApp.LogWriterEnabled){
                      write-ezlogs "[ERROR $e_index Message:$($runspace.powershell.runspace.name)] =========================================================================" -logtype Error -CatchError $e
                    }else{
                      write-output "[$([datetime]::Now)] [ERROR $e_index Message:$($runspace.powershell.runspace.name)] =========================================================================`n[Exception]: $($e.Exception)`n`n|+ [PositionMessage]: $($e.InvocationInfo.PositionMessage)`n`n|+ [ScriptStackTrace]: $($e.ScriptStackTrace)`n`n|+ [Innerexception]: $($e.Exception.InnerException)" | out-file $error_log -Force -Append -Encoding unicode
                    }
                  }
                  if($e_index -gt 0){
                    write-output "[$([datetime]::Now)] =========================================================================" | out-file $error_log -Force -Append -Encoding unicode
                  }                                
                }
                $runspace.powershell.Runspace.Dispose()
                $runspace.powershell.dispose()
                $runspace.Runspace = $null
                $runspace.powershell = $null 
              } 
            }
            #Clean out unused runspace jobs
            $temphash | where {$_.runspace -eq $Null} | foreach {
              $Null = $jobs.remove($_)
            } 
          }catch{
            write-output "[$([datetime]::Now)] [$((Get-PSCallStack)[1].Command):$((Get-PSCallStack)[1].InvocationInfo.ScriptLineNumber):$($runspace.powershell.runspace.name)] [ERROR] An exception occurred performing cleanup of runspace: $($runspace.powershell.runspace | out-string)`n $($_ | out-string)" | out-file $logfile -Force -Append -Encoding unicode  
            $error.clear()           
          } 
          #$Jobcleanup_Timer++                     
          Start-Sleep -Milliseconds 100
        }
        while ($jobCleanup.Flag)
    })
    $jobCleanup.PowerShell.Runspace = $jobCleanup_newRunspace
    if($verboselog){write-output "`n[$([datetime]::Now)] [Start-Runspace:117] ######## Starting New Jobcleanup Runspace: $($jobCleanup_newRunspace | out-string)" | out-file $logfile -Force  -Encoding unicode -Append}
    $jobCleanup.Thread = $jobCleanup.PowerShell.BeginInvoke()
    if($JobCleanup_Startonly){
      return
    }
  }
  if(![system.io.file]::Exists($logfile)){
    if([system.io.file]::Exists($thisApp.Config.Threading_Log_File)){
      $logfile = $thisApp.Config.Threading_Log_File
    }elseif([system.io.file]::Exists($thisApp.Config.Log_File)){
      $logfile = $thisApp.Config.Log_File
    }elseif($thisScript.Name){
      $logfile = "$env:appdata\$($thisScript.Name)\Logs\$($thisScript.Name)-$($thisScript.Version)-Threading.log"
      if(![system.io.directory]::Exists("$env:appdata\$($thisScript.Name)\Logs\")){
        $null = New-item "$env:appdata\$($thisScript.Name)\Logs\" -ItemType Directory -Force
      }
    }else{
      $logfile = ($Variable_list | where {$_.name -eq 'Logfile'}).value
    }
  }

  if($Runspace_Name -and $CheckforExisting){
    try{
      $existing_Runspace = Stop-Runspace -thisApp $thisApp -runspace_name $Runspace_Name -check
      if($existing_Runspace){
        write-ezlogs "Runspace ($Runspace_Name) already exists and is busy, halting another execution to avoid a race condition" -warning -logtype Threading
        return
      }
    }catch{
      write-ezlogs " An exception occurred checking for existing runspace '$Runspace_Name'" -showtime -catcherror $_
    }
  }

  if($cancel_runspace -and $runspace_name){
    $existingjob_check = Get-runspace -name $Runspace_Name
    if($existingjob_check){
      try{
        if(($existingjob_check.RunspaceAvailability -eq 'Busy') -and $existingjob_check.RunspaceStateInfo.state -eq 'Opened' -and $Runspace_Name -ne 'Start_SplashScreen' -and $Runspace_Name -notmatch 'Show_'){
          #write-output "[$([datetime]::Now)] [$((Get-PSCallStack)[1].Command):$((Get-PSCallStack)[1].InvocationInfo.ScriptLineNumber):$Runspace_Name] [WARNING] Existing Runspace '$Runspace_Name' found, attempting to cancel" | out-file $logfile -Force -Append -Encoding unicode 
          write-ezlogs "Existing Runspace '$Runspace_Name' found, attempting to cancel" -warning -logtype Threading
          $existingjobs = $jobs.clone()
          $Job_toRemove = $existingjobs | where {$_.powershell.runspace.name -eq $Runspace_Name -or $_.Name -eq $Runspace_Name}
          $null = $existingjob_check.Dispose()
          if($jobs -contains $Job_toRemove){
            $null = $jobs.remove($existingjob_check)    
          }           
        }
      }catch{
        write-output "[$([datetime]::Now)] [$((Get-PSCallStack)[1].Command):$((Get-PSCallStack)[1].InvocationInfo.ScriptLineNumber):$Runspace_Name] An exception occurred stopping existing runspace $runspace_name $($_ | out-string)" | out-file $logfile -Force -Append -Encoding unicode 
      }
    }
  }

  #Create session state for runspace
  if($RestrictedRunspace){
    #Restricted runspace requires manually adding various PS Commands needed
    $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::Create()
    $Commands = 'Write-Output',
    'Add-Member',
    'Add-Type',
    'ConvertFrom-Json',
    'Copy-Item',
    'Where-Object',
    'Export-Clixml',
    'Import-Clixml',
    'Get-Command',
    'Get-PSCallStack',
    'Out-String',
    'Out-File',
    'Get-Random',
    'Select-Object',
    'Get-Variable',
    'Remove-Variable',
    'Get-Process',
    'Stop-Process',
    'ForEach-Object',
    'Register-ObjectEvent',
    'Get-EventSubscriber',
    'Unregister-Event',
    'Start-Sleep',
    'Invoke-Command'
    $Commands | foreach {
      $command = Get-command $_
      $CmdletEntry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new($_, $command.ImplementingType,$null)
      $null = $InitialSessionState.Commands.Add($CmdletEntry) 
    }
  }else{
    $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
  }

  #list of Functions that will be passed to runspace
  if($Function_list){
    foreach($f in $function_list)
    {
      #Pass to runspace
      $DefinitionLogWindow = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $f, $(Get-Content  Function:\$f)
      $null = $InitialSessionState.Commands.Add($DefinitionLogWindow)
    } 
  }

  #Create the runspace
  $new_Runspace =[runspacefactory]::CreateRunspace($InitialSessionState)
  try{
    if($thisApp.LogMessageQueue -and $thisApp.Config.Threading_Log_File){
      write-ezlogs ">>>> Starting new runspace: $Runspace_Name" -loglevel 2 -logtype Threading
    }elseif($logfile){
      write-output "[$([datetime]::Now)] [Start-Runspace:368] >>>> Starting new runspace: $Runspace_Name" | out-file $logfile -Force -Append -Encoding unicode
    }   
  }catch{
    start-sleep -Milliseconds 100
    write-error "[$([datetime]::Now)] [$((Get-PSCallStack)[1].Command):$((Get-PSCallStack)[1].InvocationInfo.ScriptLineNumber):$((Get-PSCallStack)[0].Command):$((Get-PSCallStack)[0].InvocationInfo.ScriptLineNumber)] [ERROR: $_] >>>> Starting new runspace: $Runspace_Name"
  }

  #Set Apartment State making sure STA is used for runspaces containing UI
  if($ApartmentState -eq 'MTA' -and $Runspace_Name -notmatch 'Start_SplashScreen' -and $Runspace_Name -notmatch 'Show_WebLogin' -and $runspace_name -notmatch 'ProfileEditor_Runspace' -and $runspace_name -notmatch 'Show_' -and $runspace_name -notmatch 'Vlc_Play_media'){
    $new_Runspace.ApartmentState = $ApartmentState
  }else{
    $new_Runspace.ApartmentState = "STA"
  } 
  
  #Open runspace, set name and add variables needed 
  $new_Runspace.ThreadOptions = "ReuseThread"         
  $new_Runspace.Open()
  if($Runspace_Name){
    $new_Runspace.name = $Runspace_Name
  }
  $new_Runspace.SessionStateProxy.SetVariable('PSModulePath',$env:PSModulePath)
  #$new_Runspace.SessionStateProxy.SetVariable("jobCleanup",$jobCleanup)     
  $new_Runspace.SessionStateProxy.SetVariable("jobs",$jobs)  
  $new_Runspace.SessionStateProxy.SetVariable("logfile",$logfile)
  $new_Runspace.SessionStateProxy.SetVariable("thisApp",$thisApp)

  if($Variable_list){
    $Variable_list | foreach {
      $new_Runspace.SessionStateProxy.SetVariable($_.Name,$_.Value)
    }
  }else{
    $new_Runspace.SessionStateProxy.SetVariable("synchash",$synchash)
  }

  #Add scriptblock to run
  $psCmd = [PowerShell]::Create().AddScript($ScriptBlock)

  #Register state changed events
  if($Set_stateChangeEvent){
    $null = Register-ObjectEvent -InputObject $psCmd -EventName InvocationStateChanged -Action {
      param([System.Management.Automation.PowerShell] $ps)
      try{
        # NOTE: Use $EventArgs.InvocationStateInfo, not $ps.InvocationStateInfo, 
        #       as the latter is updated in real-time, so for a short-running script
        #       the state may already have changed since the event fired.
        $state = $EventArgs.InvocationStateInfo.State
        if ($state -eq 'Failed') {
          $message = "[ERROR] Runspace $($ps.Runspace.Name) changed state to error: $($ps | out-string)"
        }else{
          $message = $null
        }
        if($thisApp.LogMessageQueue -and $message){
          write-ezlogs $message -loglevel 2 -logtype Threading
          if($EventArgs.InvocationStateInfo.Reason){
            write-ezlogs "| Runspace '$($ps.Runspace.Name)' Reason: $($EventArgs.InvocationStateInfo.Reason | out-string)" -loglevel 2 -logtype Threading
          }
        }elseif($message){
          write-output "[$([datetime]::Now)] $message" | out-file $thisApp.Config.Startup_Log_File -Force -Append -Encoding unicode
        }  
      }catch{
        if($thisApp.LogMessageQueue){
          write-ezlogs "An exception occurred in InvocationStateChanged for runspace $($ps.Runspace.Name)" -CatchError $_
        }else{
          write-output "[$([datetime]::Now)] [Start-Runspace:232] An exception occurred in InvocationStateChanged for runspace $($ps.Runspace.Name): $($_ | out-string)" | out-file $thisApp.Config.Startup_Log_File -Force -Append -Encoding unicode
        }   
      }  
    }
  }

  #Add runspace to jobs monitor hashtable and execute
  $psCmd.Runspace = $new_Runspace
  $null = $Jobs.Add((
      [pscustomobject]@{
        PowerShell = $psCmd
        Name = $Runspace_Name
        Runspace = $psCmd.BeginInvoke()
      }
  ))
}
#---------------------------------------------- 
#endregion Start Runspace Function
#----------------------------------------------

#---------------------------------------------- 
#region Stop Runspace Function
#----------------------------------------------
function Stop-Runspace
{
  param (   
    $thisApp = $thisApp,
    [string]$runspace_name,
    [switch]$force,
    [switch]$Check,
    [switch]$StopAsync,
    [switch]$ReturnOutput,
    $synchash = $synchash,
    [switch]$Wait
  )
  if($runspace_name){
    $existingjob_check = Get-runspace -name $Runspace_Name
    if($existingjob_check){
      try{
        if(($existingjob_check.RunspaceAvailability -eq 'Busy') -and $existingjob_check.RunspaceStateInfo.state -eq 'Opened' -and $Runspace_Name -ne 'Start_SplashScreen' -and $Runspace_Name -notmatch 'Show_'){   
          if($Check){
            write-ezlogs "[RUNSPACE_CHECK] >>>> Existing Runspace '$Runspace_Name' found. Taking no further actions" -logtype Threading
            return $true
          }elseif($force){
            write-ezlogs "Existing Runspace '$Runspace_Name' found, force closing" -warning -logtype Threading
            $null = $existingjob_check.Dispose()   
            write-ezlogs "| Runspace disposed" -warning -logtype Threading
            if($ReturnOutput){
              $Job_toOutput = $jobs | where {$_.powershell.runspace.name -eq $Runspace_Name -or $_.Name -eq $Runspace_Name}
              if($Job_toOutput){
                if($Job_toOutput.OutputObject){
                  write-ezlogs "| Returning Runspace job output" -warning -logtype Threading
                  return $Job_toOutput.OutputObject 
                }
                #Alternate way to get output, shouldnt need
                <#                $BindingFlags = [Reflection.BindingFlags]'nonpublic','instance'
                    $Field = $Job_toOutput.powershell.GetType().GetField('invokeAsyncResult',$BindingFlags)   
                    if($Field){
                    $Handle = $Field.GetValue($Job_toOutput.Powershell)
                    if($Handle){
                    return $Job_toOutput.powershell.EndInvoke($Handle) 
                    }                                    
                } #>                                               
              }else{
                write-ezlogs "Unable to find Runspace job with name $Runspace_Name within Jobs synchash" -Warning -logtype Threading
              }
            }
          }else{
            write-ezlogs "Existing Runspace '$Runspace_Name' found, attempting to stop" -warning -logtype Threading
            $Job_toRemove = $jobs | where {$_.powershell.runspace.name -eq $Runspace_Name -or $_.Name -eq $Runspace_Name}
            if($Job_toRemove){
              write-ezlogs "| Calling Stop on Runspace job" -warning -logtype Threading
              $Job_toRemove.powershell.stop()  
              if($ReturnOutput){
                if($Job_toRemove.OutputObject){
                  write-ezlogs "| Returning Runspace job output" -warning -logtype Threading
                  return $Job_toRemove.OutputObject 
                }                                       
              }                    
            }else{
              write-ezlogs "Unable to find Runspace job with name $Runspace_Name within Jobs synchash" -Warning -logtype Threading
            } 
          }           
        }else{
          if($Check){
            write-ezlogs "[Stop-Runspace] Existing Runspace '$Runspace_Name' found, but is not busy or its state is not opened. Taking no action - State: $($existingjob_check.RunspaceStateInfo.state) -- Availability: $($existingjob_check.RunspaceAvailability)" -warning -logtype Threading
          }else{
            write-ezlogs "[Stop-Runspace] Existing Runspace '$Runspace_Name' found, but is not busy or its state is not opened. Disposing.." -warning -logtype Threading
            $null = $existingjob_check.Dispose()
          }
        }
      }catch{
        write-ezlogs "An exception occurred stopping existing runspace $runspace_name" -catcherror $_
      }
    }else{
      write-ezlogs "No Runspace found to stop with name $Runspace_Name" -loglevel 3 -logtype Threading
    }
    return
  } 
}
#---------------------------------------------- 
#endregion Stop Runspace Function
#----------------------------------------------

#---------------------------------------------- 
#region Start-RunspacePool Function
#TODO: For possible future use
#----------------------------------------------
function Start-RunspacePool
{
 <#
   #Nothing yet
 #>
  param (   
    $scriptblock,
    $thisApp = $thisApp,
    [switch]$StartRunspaceJobHandler, 
    $Variable_list,
    $logfile = $thisApp.Config.threading_Log_File,
    $thisScript,
    [string]$runspace_name,
    [switch]$cancel_runspace,
    [switch]$JobCleanup_Startonly,
    $synchash,
    [switch]$Set_stateChangeEvent,
    [switch]$startup_perf_timer,
    $modules_list,
    $function_list,
    [int]$maxRunspaces = [int]$env:NUMBER_OF_PROCESSORS + 1,
    $Script_Modules,
    $startup_stopwatch,
    [ValidateSet('STA','MTA')]
    $ApartmentState = 'STA',
    [switch]$Wait,
    [switch]$verboselog
  )

  try{

    # Need this for the runspaces.
    $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault() 

    # If you want to return data, use a synchronized hashtable and add it to the
    # initial session state variable.
    #$Data = [HashTable]::Synchronized(@{})

    # Add the synchronized hashtable to the "initial state".
    $InitialSessionState.Variables.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'synchash', $synchash, ''))

    # Create a runspace pool based on the initial session state variable,
    # maximum thread count and $Host variable (convenient).
    $RunspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $maxRunspaces, $InitialSessionState, $Host)

    # This seems to work best. Single-threaded apartment?
    $RunspacePool.ApartmentState = 'STA'

    # Open/prepare the runspace pool.
    $RunspacePool.Open()

    # Used for the collection of the runspaces that accumulate.
    $Runspaces = @()



  }catch{
    write-ezlogs "An exception occurred in Start-RunspacePool" -catcherror $_
  }

}
#---------------------------------------------- 
#endregion Start-RunspacePool Function
#----------------------------------------------
Export-ModuleMember -Function @('Start-Runspace','Stop-Runspace')