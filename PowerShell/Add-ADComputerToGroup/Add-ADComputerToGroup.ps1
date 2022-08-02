<#
.SYNOPSIS
    Adds Active Directory devices to a group.
.DESCRIPTION
    Adds Active Directory devices to a group, if they match a specified criteria and are not already part of the group.
.PARAMETER ConfigFilePath
    Specifies the script configuration json file path.
    Default is: 'ScriptPath\ScriptName.json'.
.PARAMETER NewConfigFile
    Specifies to create a new json configuration file. This switch must be used in conjunction with the 'ConfigFilePath' parameter.
.EXAMPLE
    Add-ADComputerToGroup.ps1 -ConfigFilePath 'C:\Scripts\Add-ADComputerToGroup.json'
.EXAMPLE
    Add-ADComputerToGroup.ps1 -ConfigFilePath 'C:\Scripts\Add-ADComputerToGroup.json' -NewConfigFile
.INPUTS
    None.
.OUTPUTS
    System.IO
    System.String
.NOTES
    Created by Ioan Popovici
    !! IMPORTANT !!
        Multiple domain entries using the same group are not supported!
        If you use the same group name in multiple entries, the last entry will overwrite the previous ones.
.LINK
    https://MEM.Zone/Add-ADComputerToGroup
.LINK
    https://MEM.Zone/Add-ADComputerToGroup/CHANGELOG
.LINK
    https://MEM.Zone/Add-ADComputerToGroup/GIT
.LINK
    https://MEM.Zone/Issues
.COMPONENT
    Active Directory
.FUNCTIONALITY
    Adds Computers to a group.
#>

## Set script requirements
#Requires -Version 5.0

##*=============================================
##* VARIABLE DECLARATION
##*=============================================
#region VariableDeclaration

## Get script parameters
[CmdletBinding(SupportsShouldProcess=$true)]
Param (
    [Parameter(Mandatory=$false,HelpMessage='Specify script json config file path.',Position=0)]
    [ValidateNotNullorEmpty()]
    [Alias('Config')]
    [string]$ConfigFilePath = $null,
    [Parameter(Mandatory=$false,HelpMessage='Specify to create a new config json file.',Position=1)]
    [ValidateScript({ If ([string]::IsNullOrEmpty($ConfigFilePath)) { Throw 'ConfigFilePath parameter is mandatory, when using this switch!' } })]
    [Alias('NewConfig')]
    [switch]$NewConfigFile
)

## Get script path, name and configuration file path
[string]$ScriptName       = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)
[string]$ScriptFullName   = [System.IO.Path]::GetFullPath($MyInvocation.MyCommand.Definition)
If ([string]::IsNullOrEmpty($ConfigFilePath)) { $ConfigFilePath = [IO.Path]::ChangeExtension($ScriptFullName, 'json') }

## Get Show-Progress steps
$ProgressSteps = $(([System.Management.Automation.PsParser]::Tokenize($(Get-Content -Path $ScriptFullName), [ref]$null) | Where-Object { $PSItem.Type -eq 'Command' -and $PSItem.Content -eq 'Show-Progress' }).Count)
## Set Show-Progress steps
$Script:Steps = $ProgressSteps
$Script:Step  = 0

## Set script global variables
$Script:RunPhase         = 'Main'
$Script:LoggingOptions   = @('Host', 'File', 'EventLog')
$Script:LogName          = 'Endpoint Management Scripts'
$Script:LogSource        = $ScriptName
$Script:LogDebugMessages = $false
$Script:LogFileDirectory = Split-Path -Path $ScriptFullName -Parent
$Script:LogFilePath      = [IO.Path]::ChangeExtension($ScriptFullName, 'log')

## Initialize ordered hashtables
[System.Collections.Specialized.OrderedDictionary]$HTMLReportConfig = @{}
[System.Collections.Specialized.OrderedDictionary]$DomainConfig     = @{}
[System.Collections.Specialized.OrderedDictionary]$NewTableHeaders  = @{}
[System.Collections.Specialized.OrderedDictionary]$Params           = @{}


#endregion
##*=============================================
##* END VARIABLE DECLARATION
##*=============================================

##*=============================================
##* FUNCTION LISTINGS
##*=============================================
#region FunctionListings

#region Function Resolve-Error
Function Resolve-Error {
<#
.SYNOPSIS
    Enumerate error record details.
.DESCRIPTION
    Enumerate an error record, or a collection of error record, properties. By default, the details for the last error will be enumerated.
.PARAMETER ErrorRecord
    The error record to resolve. The default error record is the latest one: $global:Error[0]. This parameter will also accept an array of error records.
.PARAMETER Property
    The list of properties to display from the error record. Use "*" to display all properties.
    Default list of error properties is: Message, FullyQualifiedErrorId, ScriptStackTrace, PositionMessage, InnerException
.PARAMETER GetErrorRecord
    Get error record details as represented by $PSItem.
.PARAMETER GetErrorInvocation
    Get error record invocation information as represented by $PSItem.InvocationInfo.
.PARAMETER GetErrorException
    Get error record exception details as represented by $PSItem.Exception.
.PARAMETER GetErrorInnerException
    Get error record inner exception details as represented by $PSItem.Exception.InnerException. Will retrieve all inner exceptions if there is more than one.
.EXAMPLE
    Resolve-Error
.EXAMPLE
    Resolve-Error -Property *
.EXAMPLE
    Resolve-Error -Property InnerException
.EXAMPLE
    Resolve-Error -GetErrorInvocation:$false
.NOTES
.LINK
    http://psappdeploytoolkit.com
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [AllowEmptyCollection()]
        [array]$ErrorRecord,
        [Parameter(Mandatory=$false,Position=1)]
        [ValidateNotNullorEmpty()]
        [string[]]$Property = ('Message','InnerException','FullyQualifiedErrorId','ScriptStackTrace','PositionMessage'),
        [Parameter(Mandatory=$false,Position=2)]
        [switch]$GetErrorRecord = $true,
        [Parameter(Mandatory=$false,Position=3)]
        [switch]$GetErrorInvocation = $true,
        [Parameter(Mandatory=$false,Position=4)]
        [switch]$GetErrorException = $true,
        [Parameter(Mandatory=$false,Position=5)]
        [switch]$GetErrorInnerException = $true
    )

    Begin {
        ## If function was called without specifying an error record, then choose the latest error that occurred
        If (-not $ErrorRecord) {
            If ($global:Error.Count -eq 0) {
                #Write-Warning -Message "The `$Error collection is empty"
                Return
            }
            Else {
                [array]$ErrorRecord = $global:Error[0]
            }
        }

        ## Allows selecting and filtering the properties on the error object if they exist
        [scriptblock]$SelectProperty = {
            Param (
                [Parameter(Mandatory=$true)]
                [ValidateNotNullorEmpty()]
                $InputObject,
                [Parameter(Mandatory=$true)]
                [ValidateNotNullorEmpty()]
                [string[]]$Property
            )

            [string[]]$ObjectProperty = $InputObject | Get-Member -MemberType '*Property' | Select-Object -ExpandProperty 'Name'
            ForEach ($Prop in $Property) {
                If ($Prop -eq '*') {
                    [string[]]$PropertySelection = $ObjectProperty
                    Break
                }
                ElseIf ($ObjectProperty -contains $Prop) {
                    [string[]]$PropertySelection += $Prop
                }
            }
            Write-Output -InputObject $PropertySelection
        }

        #  Initialize variables to avoid error if 'Set-StrictMode' is set
        $LogErrorRecordMsg = $null
        $LogErrorInvocationMsg = $null
        $LogErrorExceptionMsg = $null
        $LogErrorMessageTmp = $null
        $LogInnerMessage = $null
    }
    Process {
        If (-not $ErrorRecord) { Return }
        ForEach ($ErrRecord in $ErrorRecord) {
            ## Capture Error Record
            If ($GetErrorRecord) {
                [string[]]$SelectedProperties = & $SelectProperty -InputObject $ErrRecord -Property $Property
                $LogErrorRecordMsg = $ErrRecord | Select-Object -Property $SelectedProperties
            }

            ## Error Invocation Information
            If ($GetErrorInvocation) {
                If ($ErrRecord.InvocationInfo) {
                    [string[]]$SelectedProperties = & $SelectProperty -InputObject $ErrRecord.InvocationInfo -Property $Property
                    $LogErrorInvocationMsg = $ErrRecord.InvocationInfo | Select-Object -Property $SelectedProperties
                }
            }

            ## Capture Error Exception
            If ($GetErrorException) {
                If ($ErrRecord.Exception) {
                    [string[]]$SelectedProperties = & $SelectProperty -InputObject $ErrRecord.Exception -Property $Property
                    $LogErrorExceptionMsg = $ErrRecord.Exception | Select-Object -Property $SelectedProperties
                }
            }

            ## Display properties in the correct order
            If ($Property -eq '*') {
                #  If all properties were chosen for display, then arrange them in the order the error object displays them by default.
                If ($LogErrorRecordMsg) { [array]$LogErrorMessageTmp += $LogErrorRecordMsg }
                If ($LogErrorInvocationMsg) { [array]$LogErrorMessageTmp += $LogErrorInvocationMsg }
                If ($LogErrorExceptionMsg) { [array]$LogErrorMessageTmp += $LogErrorExceptionMsg }
            }
            Else {
                #  Display selected properties in our custom order
                If ($LogErrorExceptionMsg) { [array]$LogErrorMessageTmp += $LogErrorExceptionMsg }
                If ($LogErrorRecordMsg) { [array]$LogErrorMessageTmp += $LogErrorRecordMsg }
                If ($LogErrorInvocationMsg) { [array]$LogErrorMessageTmp += $LogErrorInvocationMsg }
            }

            If ($LogErrorMessageTmp) {
                $LogErrorMessage = 'Error Record:'
                $LogErrorMessage += "`n-------------"
                $LogErrorMsg = $LogErrorMessageTmp | Format-List | Out-String
                $LogErrorMessage += $LogErrorMsg
            }

            ## Capture Error Inner Exception(s)
            If ($GetErrorInnerException) {
                If ($ErrRecord.Exception -and $ErrRecord.Exception.InnerException) {
                    $LogInnerMessage = 'Error Inner Exception(s):'
                    $LogInnerMessage += "`n-------------------------"

                    $ErrorInnerException = $ErrRecord.Exception.InnerException
                    $Count = 0

                    While ($ErrorInnerException) {
                        [string]$InnerExceptionSeperator = '~' * 40

                        [string[]]$SelectedProperties = & $SelectProperty -InputObject $ErrorInnerException -Property $Property
                        $LogErrorInnerExceptionMsg = $ErrorInnerException | Select-Object -Property $SelectedProperties | Format-List | Out-String

                        If ($Count -gt 0) { $LogInnerMessage += $InnerExceptionSeperator }
                        $LogInnerMessage += $LogErrorInnerExceptionMsg

                        $Count++
                        $ErrorInnerException = $ErrorInnerException.InnerException
                    }
                }
            }

            If ($LogErrorMessage) { $Output = $LogErrorMessage }
            If ($LogInnerMessage) { $Output += $LogInnerMessage }

            Write-Output -InputObject $Output

            If (Test-Path -LiteralPath 'variable:Output') { Clear-Variable -Name 'Output' }
            If (Test-Path -LiteralPath 'variable:LogErrorMessage') { Clear-Variable -Name 'LogErrorMessage' }
            If (Test-Path -LiteralPath 'variable:LogInnerMessage') { Clear-Variable -Name 'LogInnerMessage' }
            If (Test-Path -LiteralPath 'variable:LogErrorMessageTmp') { Clear-Variable -Name 'LogErrorMessageTmp' }
        }
    }
    End {
    }
}
#endregion

#region Function Write-Log
Function Write-Log {
<#
.SYNOPSIS
    Write messages to a log file in CMTrace.exe compatible format or Legacy text file format.
.DESCRIPTION
    Write messages to a log file in CMTrace.exe compatible format or Legacy text file format and optionally display in the console.
.PARAMETER Message
    The message to write to the log file or output to the console.
.PARAMETER Severity
    Defines message type. When writing to console or CMTrace.exe log format, it allows highlighting of message type.
    Options: 1 = Information (default), 2 = Warning (highlighted in yellow), 3 = Error (highlighted in red)
.PARAMETER Source
    The source of the message being logged. Also used as the event log source.
.PARAMETER ScriptSection
    The heading for the portion of the script that is being executed. Default is: $Script:installPhase.
.PARAMETER LogType
    Choose whether to write a CMTrace.exe compatible log file or a Legacy text log file.
.PARAMETER LoggingOptions
    Choose where to log 'Console', 'File', 'EventLog' or 'None'. You can choose multiple options.
.PARAMETER LogFileDirectory
    Set the directory where the log file will be saved.
.PARAMETER LogFileName
    Set the name of the log file.
.PARAMETER MaxLogFileSizeMB
    Maximum file size limit for log file in megabytes (MB). Default is 10 MB.
.PARAMETER LogName
    Set the name of the event log.
.PARAMETER EventID
    Set the event id for the event log entry.
.PARAMETER WriteHost
    Write the log message to the console.
.PARAMETER ContinueOnError
    Suppress writing log message to console on failure to write message to log file. Default is: $true.
.PARAMETER PassThru
    Return the message that was passed to the function
.PARAMETER VerboseMessage
    Specifies that the message is a debug message. Verbose messages only get logged if -LogDebugMessage is set to $true.
.PARAMETER DebugMessage
    Specifies that the message is a debug message. Debug messages only get logged if -LogDebugMessage is set to $true.
.PARAMETER LogDebugMessage
    Debug messages only get logged if this parameter is set to $true in the config XML file.
.EXAMPLE
    Write-Log -Message "Installing patch MS15-031" -Source 'Add-Patch' -LogType 'CMTrace'
.EXAMPLE
    Write-Log -Message "Script is running on Windows 8" -Source 'Test-ValidOS' -LogType 'Legacy'
.NOTES
    Slightly modified version of the PSADT logging cmdlet. I did not write the original cmdlet, please do not credit me for it.
.LINK
    https://psappdeploytoolkit.com
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowEmptyCollection()]
        [Alias('Text')]
        [string[]]$Message,
        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateRange(1, 3)]
        [int16]$Severity = 1,
        [Parameter(Mandatory = $false, Position = 2)]
        [ValidateNotNullorEmpty()]
        [string]$Source = $Script:LogSource,
        [Parameter(Mandatory = $false, Position = 3)]
        [ValidateNotNullorEmpty()]
        [string]$ScriptSection = $Script:RunPhase,
        [Parameter(Mandatory = $false, Position = 4)]
        [ValidateSet('CMTrace', 'Legacy')]
        [string]$LogType = 'Legacy',
        [Parameter(Mandatory = $false, Position = 5)]
        [ValidateSet('Host', 'File', 'EventLog', 'None')]
        [string[]]$LoggingOptions = $Script:LoggingOptions,
        [Parameter(Mandatory = $false, Position = 6)]
        [ValidateNotNullorEmpty()]
        [string]$LogFileDirectory = $Script:LogFileDirectory,
        [Parameter(Mandatory = $false, Position = 7)]
        [ValidateNotNullorEmpty()]
        [string]$LogFileName = $($Script:LogSource + '.log'),
        [Parameter(Mandatory = $false, Position = 8)]
        [ValidateNotNullorEmpty()]
        [int]$MaxLogFileSizeMB = 5,
        [Parameter(Mandatory = $false, Position = 9)]
        [ValidateNotNullorEmpty()]
        [string]$LogName = $Script:LogName,
        [Parameter(Mandatory = $false, Position = 10)]
        [ValidateNotNullorEmpty()]
        [int32]$EventID = 1,
        [Parameter(Mandatory = $false, Position = 11)]
        [ValidateNotNullorEmpty()]
        [boolean]$ContinueOnError = $false,
        [Parameter(Mandatory = $false, Position = 12)]
        [switch]$PassThru = $false,
        [Parameter(Mandatory = $false, Position = 13)]
        [switch]$VerboseMessage = $false,
        [Parameter(Mandatory = $false, Position = 14)]
        [switch]$DebugMessage = $false,
        [Parameter(Mandatory = $false, Position = 15)]
        [boolean]$LogDebugMessage = $Script:LogDebugMessages
    )

    Begin {
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

        ## Logging Variables
        #  Log file date/time
        [string]$LogTime = (Get-Date -Format 'HH:mm:ss.fff').ToString()
        [string]$LogDate = (Get-Date -Format 'MM-dd-yyyy').ToString()
        If (-not (Test-Path -LiteralPath 'variable:LogTimeZoneBias')) { [int32]$Script:LogTimeZoneBias = [timezone]::CurrentTimeZone.GetUtcOffset([datetime]::Now).TotalMinutes }
        [string]$LogTimePlusBias = $LogTime + '-' + $Script:LogTimeZoneBias
        #  Initialize variables
        [boolean]$WriteHost = $false
        [boolean]$WriteFile = $false
        [boolean]$WriteEvent = $false
        [boolean]$DisableLogging = $false
        [boolean]$ExitLoggingFunction = $false
        If ('Host' -in $LoggingOptions -and -not ($VerboseMessage -or $DebugMessage)) { $WriteHost = $true }
        If ('File' -in $LoggingOptions) { $WriteFile = $true }
        If ('EventLog' -in $LoggingOptions) { $WriteEvent = $true }
        If ('None' -in $LoggingOptions) { $DisableLogging = $true }
        #  Check if the script section is defined
        [boolean]$ScriptSectionDefined = [boolean](-not [string]::IsNullOrEmpty($ScriptSection))
        #  Check if the event log and event source exit
        [boolean]$LogNameNotExists = (-not [System.Diagnostics.EventLog]::Exists($LogName))
        [boolean]$LogSourceNotExists = (-not [System.Diagnostics.EventLog]::SourceExists($Source))

        ## Create script block for generating CMTrace.exe compatible log entry
        [scriptblock]$CMTraceLogString = {
            Param (
                [string]$lMessage,
                [string]$lSource,
                [int16]$lSeverity
            )
            "<![LOG[$lMessage]LOG]!>" + "<time=`"$LogTimePlusBias`" " + "date=`"$LogDate`" " + "component=`"$lSource`" " + "context=`"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " + "type=`"$lSeverity`" " + "thread=`"$PID`" " + "file=`"$Source`">"
        }

        ## Create script block for writing log entry to the console
        [scriptblock]$WriteLogLineToHost = {
            Param (
                [string]$lTextLogLine,
                [int16]$lSeverity
            )
            If ($WriteHost) {
                #  Only output using color options if running in a host which supports colors.
                If ($Host.UI.RawUI.ForegroundColor) {
                    Switch ($lSeverity) {
                        3 { Write-Host -Object $lTextLogLine -ForegroundColor 'Red' -BackgroundColor 'Black' }
                        2 { Write-Host -Object $lTextLogLine -ForegroundColor 'Yellow' -BackgroundColor 'Black' }
                        1 { Write-Host -Object $lTextLogLine }
                    }
                }
                #  If executing "powershell.exe -File <filename>.ps1 > log.txt", then all the Write-Host calls are converted to Write-Output calls so that they are included in the text log.
                Else {
                    Write-Output -InputObject $lTextLogLine
                }
            }
        }

        ## Create script block for writing log entry to the console as verbose or debug message
        [scriptblock]$WriteLogLineToHostAdvanced = {
            Param (
                [string]$lTextLogLine
            )
            #  Only output using color options if running in a host which supports colors.
            If ($Host.UI.RawUI.ForegroundColor) {
                If ($VerboseMessage) {
                    Write-Verbose -Message $lTextLogLine
                }
                Else {
                    Write-Debug -Message $lTextLogLine
                }
            }
            #  If executing "powershell.exe -File <filename>.ps1 > log.txt", then all the Write-Host calls are converted to Write-Output calls so that they are included in the text log.
            Else {
                Write-Output -InputObject $lTextLogLine
            }
        }

        ## Create script block for event writing log entry
        [scriptblock]$WriteToEventLog = {
            If ($WriteEvent) {
                $EventType = Switch ($Severity) {
                    3 { 'Error' }
                    2 { 'Warning' }
                    1 { 'Information' }
                }

                If ($LogNameNotExists -and (-not $LogSourceNotExists)) {
                    Try {
                        #  Delete event source if the log does not exist
                        $null = [System.Diagnostics.EventLog]::DeleteEventSource($Source)
                        $LogSourceNotExists = $true
                    }
                    Catch {
                        [boolean]$ExitLoggingFunction = $true
                        #  If error deleting event source, write message to console
                        If (-not $ContinueOnError) {
                            Write-Host -Object "[$LogDate $LogTime] [${CmdletName}] $ScriptSection :: Failed to create the event log source [$Source]. `n$(Resolve-Error)" -ForegroundColor 'Red'
                        }
                    }
                }
                If ($LogNameNotExists -or $LogSourceNotExists) {
                    Try {
                        #  Create event log
                        $null = New-EventLog -LogName $LogName -Source $Source -ErrorAction 'Stop'
                    }
                    Catch {
                        [boolean]$ExitLoggingFunction = $true
                        #  If error creating event log, write message to console
                        If (-not $ContinueOnError) {
                            Write-Host -Object "[$LogDate $LogTime] [${CmdletName}] $ScriptSection :: Failed to create the event log [$LogName`:$Source]. `n$(Resolve-Error)" -ForegroundColor 'Red'
                        }
                    }
                }
                Try {
                    #  Write to event log
                    Write-EventLog -LogName $LogName -Source $Source -EventId $EventID -EntryType $EventType -Category '0' -Message $EventLogLine -ErrorAction 'Stop'
                }
                Catch {
                    [boolean]$ExitLoggingFunction = $true
                    #  If error creating directory, write message to console
                    If (-not $ContinueOnError) {
                        Write-Host -Object "[$LogDate $LogTime] [${CmdletName}] $ScriptSection :: Failed to write to event log [$LogName`:$Source]. `n$(Resolve-Error)" -ForegroundColor 'Red'
                    }
                }
            }
        }

        ## Exit function if it is a debug message and logging debug messages is not enabled in the config XML file
        If (($DebugMessage -or $VerboseMessage) -and (-not $LogDebugMessage)) { [boolean]$ExitLoggingFunction = $true; Return }
        ## Exit function if logging to file is disabled and logging to console host is disabled
        If (($DisableLogging) -and (-not $WriteHost)) { [boolean]$ExitLoggingFunction = $true; Return }
        ## Exit Begin block if logging is disabled
        If ($DisableLogging) { Return }

        ## Create the directory where the log file will be saved
        If (-not (Test-Path -LiteralPath $LogFileDirectory -PathType 'Container')) {
            Try {
                $null = New-Item -Path $LogFileDirectory -Type 'Directory' -Force -ErrorAction 'Stop' -WhatIf:$false
            }
            Catch {
                [boolean]$ExitLoggingFunction = $true
                #  If error creating directory, write message to console
                If (-not $ContinueOnError) {
                    Write-Host -Object "[$LogDate $LogTime] [${CmdletName}] $ScriptSection :: Failed to create the log directory [$LogFileDirectory]. `n$(Resolve-Error)" -ForegroundColor 'Red'
                }
                Return
            }
        }

        ## Assemble the fully qualified path to the log file
        [string]$LogFilePath = Join-Path -Path $LogFileDirectory -ChildPath $LogFileName
    }
    Process {

        ForEach ($Msg in $Message) {
            ## If the message is not $null or empty, create the log entry for the different logging methods
            [string]$CMTraceMsg = ''
            [string]$ConsoleLogLine = ''
            [string]$EventLogLine = ''
            [string]$LegacyTextLogLine = ''
            If ($Msg) {
                #  Create the CMTrace log message
                If ($ScriptSectionDefined) { [string]$CMTraceMsg = "[$ScriptSection] :: $Msg" }

                #  Create a Console and Legacy "text" log entry
                [string]$LegacyMsg = "[$LogDate $LogTime]"
                If ($ScriptSectionDefined) { [string]$LegacyMsg += " [$ScriptSection]" }
                If ($Source) {
                    [string]$EventLogLine = $Msg
                    [string]$ConsoleLogLine = "$LegacyMsg [$Source] :: $Msg"
                    Switch ($Severity) {
                        3 { [string]$LegacyTextLogLine = "$LegacyMsg [$Source] [Error] :: $Msg" }
                        2 { [string]$LegacyTextLogLine = "$LegacyMsg [$Source] [Warning] :: $Msg" }
                        1 { [string]$LegacyTextLogLine = "$LegacyMsg [$Source] [Info] :: $Msg" }
                    }
                }
                Else {
                    [string]$ConsoleLogLine = "$LegacyMsg :: $Msg"
                    [string]$EventLogLine = $Msg
                    Switch ($Severity) {
                        3 { [string]$LegacyTextLogLine = "$LegacyMsg [Error] :: $Msg" }
                        2 { [string]$LegacyTextLogLine = "$LegacyMsg [Warning] :: $Msg" }
                        1 { [string]$LegacyTextLogLine = "$LegacyMsg [Info] :: $Msg" }
                    }
                }
            }

            ## Execute script block to write the log entry to the console as verbose or debug message
            & $WriteLogLineToHostAdvanced -lTextLogLine $ConsoleLogLine -lSeverity $Severity

            ## Exit function if logging is disabled
            If ($ExitLoggingFunction) { Return }

            ## Execute script block to create the CMTrace.exe compatible log entry
            [string]$CMTraceLogLine = & $CMTraceLogString -lMessage $CMTraceMsg -lSource $Source -lSeverity $lSeverity

            ## Choose which log type to write to file
            If ($LogType -ieq 'CMTrace') {
                [string]$LogLine = $CMTraceLogLine
            }
            Else {
                [string]$LogLine = $LegacyTextLogLine
            }

            ## Write the log entry to the log file and event log if logging is not currently disabled
            If ((-not $ExitLoggingFunction) -and (-not $DisableLogging)) {
                #  Write to file log
                If ($WriteFile) {
                    Try {
                        $LogLine | Out-File -FilePath $LogFilePath -Append -NoClobber -Force -Encoding 'UTF8' -ErrorAction 'Stop' -WhatIf:$false
                    }
                    Catch {
                        If (-not $ContinueOnError) {
                            Write-Host -Object "[$LogDate $LogTime] [$ScriptSection] [${CmdletName}] :: Failed to write message [$Msg] to the log file [$LogFilePath]. `n$(Resolve-Error)" -ForegroundColor 'Red'
                        }
                    }
                }
                #  Write to event log
                If ($WriteEvent) {
                    Try {
                        & $WriteToEventLog -lMessage $ConsoleLogLine -lName $LogName -lSource $Source -lSeverity $Severity
                    }
                    Catch {
                        If (-not $ContinueOnError) {
                            Write-Host -Object "[$LogDate $LogTime] [$ScriptSection] [${CmdletName}] :: Failed to write message [$Msg] to the log file [$LogFilePath]. `n$(Resolve-Error)" -ForegroundColor 'Red'
                        }
                    }
                }
            }

            ## Execute script block to write the log entry to the console if $WriteHost is $true and $LogLogDebugMessage is not $true
            & $WriteLogLineToHost -lTextLogLine $ConsoleLogLine -lSeverity $Severity
        }
    }
    End {
        ## Archive log file if size is greater than $MaxLogFileSizeMB and $MaxLogFileSizeMB > 0
        Try {
            If ((-not $ExitLoggingFunction) -and (-not $DisableLogging)) {
                [IO.FileInfo]$LogFile = Get-ChildItem -LiteralPath $LogFilePath -ErrorAction 'Stop'
                [decimal]$LogFileSizeMB = $LogFile.Length / 1MB
                If (($LogFileSizeMB -gt $MaxLogFileSizeMB) -and ($MaxLogFileSizeMB -gt 0)) {
                    ## Change the file extension to "lo_"
                    [string]$ArchivedOutLogFile = [IO.Path]::ChangeExtension($LogFilePath, 'lo_')
                    [hashtable]$ArchiveLogParams = @{ ScriptSection = $ScriptSection; Source = $Source; Severity = 2; LogFileDirectory = $LogFileDirectory; LogFileName = $LogFileName; LogType = $LogType; MaxLogFileSizeMB = 0; ContinueOnError = $ContinueOnError; PassThru = $false }

                    ## Log message about archiving the log file
                    $ArchiveLogMessage = "Maximum log file size [$MaxLogFileSizeMB MB] reached. Rename log file to [$ArchivedOutLogFile]."
                    Write-Log -Message $ArchiveLogMessage @ArchiveLogParams

                    ## Archive existing log file from <filename>.log to <filename>.lo_. Overwrites any existing <filename>.lo_ file. This is the same method SCCM uses for log files.
                    Move-Item -LiteralPath $LogFilePath -Destination $ArchivedOutLogFile -Force -ErrorAction 'Stop' -WhatIf:$false

                    ## Start new log file and Log message about archiving the old log file
                    $NewLogMessage = "Previous log file was renamed to [$ArchivedOutLogFile] because maximum log file size of [$MaxLogFileSizeMB MB] was reached."
                    Write-Log -Message $NewLogMessage @ArchiveLogParams
                }
            }
        }
        Catch {
            ## If renaming of file fails, script will continue writing to log file even if size goes over the max file size
        }
        Finally {
            If ($PassThru) { Write-Output -InputObject $Message }
        }
    }
}
#endregion

#region Function Show-Progress
Function Show-Progress {
<#
.SYNOPSIS
    Displays progress info.
.DESCRIPTION
    Displays progress info and maximizes code reuse by automatically calculating the progress steps.
.PARAMETER Actity
    Specifies the progress activity. Default: 'Running Cleanup Please Wait...'.
.PARAMETER Status
    Specifies the progress status.
.PARAMETER CurrentOperation
    Specifies the current operation.
.PARAMETER Step
    Specifies the progress step. Default: $Script:Step ++.
.PARAMETER Steps
    Specifies the progress steps. Default: $Script:Steps ++.
.PARAMETER ID
    Specifies the progress bar id.
.PARAMETER Delay
    Specifies the progress delay in milliseconds. Default: 0.
.PARAMETER Loop
    Specifies if the call comes from a loop.
.EXAMPLE
    Show-Progress -Activity 'Running Install Please Wait' -Status 'Uploading Report' -Step ($Step++) -Delay 200
.EXAMPLE
    Show-Progress -Status "Downloading [$File.Name] --> [$($RSDataSource.Name)]" -Loop
.INPUTS
    None.
.OUTPUTS
    None.
.NOTES
    Created by Ioan Popovici.
    v1.0.0 - 2021-01-01

    This is an private function should tipically not be called directly.
    Credit to Adam Bertram.

    ## !! IMPORTANT !! ##
    #  You need to tokenize the scripts steps at the begining of the script in order for Show-Progress to work:

    ## Get script path and name
    [string]$ScriptPath = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Definition)
    [string]$ScriptName = [System.IO.Path]::GetFileName($MyInvocation.MyCommand.Definition)
    [string]$ScriptFullName = Join-Path -Path $ScriptPath -ChildPath $ScriptName
    #  Get progress steps
    $ProgressSteps = $(([System.Management.Automation.PsParser]::Tokenize($(Get-Content -Path $ScriptFullName), [ref]$null) | Where-Object { $PSItem.Type -eq 'Command' -and $PSItem.Content -eq 'Show-Progress' }).Count)
    $ForEachSteps = $(([System.Management.Automation.PsParser]::Tokenize($(Get-Content -Path $ScriptFullName), [ref]$null) | Where-Object { $PSItem.Type -eq 'Keyword' -and $PSItem.Content -eq 'ForEach' }).Count)
    #  Set progress steps
    $Script:Steps = $ProgressSteps - $ForEachSteps
    $Script:Step = 0
.LINK
    https://adamtheautomator.com/building-progress-bar-powershell-scripts/
.LINK
    https://MEM.Zone/
.LINK
    https://MEM.Zone/GIT
.LINK
    https://MEM.Zone/ISSUES
.COMPONENT
    Powershell
.FUNCTIONALITY
    Show Progress
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false,Position=0)]
        [ValidateNotNullorEmpty()]
        [Alias('act')]
        [string]$Activity = 'Running Active Directory Maintenance, Please Wait...',
        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullorEmpty()]
        [Alias('sta')]
        [string]$Status,
        [Parameter(Mandatory=$false,Position=2)]
        [ValidateNotNullorEmpty()]
        [Alias('cro')]
        [string]$CurrentOperation,
        [Parameter(Mandatory=$false,Position=3)]
        [ValidateNotNullorEmpty()]
        [Alias('pid')]
        [int]$ID = 0,
        [Parameter(Mandatory=$false,Position=4)]
        [ValidateNotNullorEmpty()]
        [Alias('ste')]
        [int]$Step = $Script:Step,
        [Parameter(Mandatory=$false,Position=5)]
        [ValidateNotNullorEmpty()]
        [Alias('sts')]
        [int]$Steps = $Script:Steps,
        [Parameter(Mandatory=$false,Position=6)]
        [ValidateNotNullorEmpty()]
        [Alias('del')]
        [string]$Delay = 0,
        [Parameter(Mandatory=$false,Position=7)]
        [ValidateNotNullorEmpty()]
        [Alias('lp')]
        [switch]$Loop
    )
    Begin {
        If ($Loop) {
            $Steps ++
            $Script:Steps ++
        }
        If ($Step -eq 0) {
            $Step ++
            $Script:Step ++
            $Steps ++
            $Script:Steps ++
        }
        If ($Steps -eq 0) {
            $Steps ++
            $Script:Steps ++
        }

        [int]$PercentComplete = $($($Step / $Steps) * 100)

        ## Debug information
        Write-Debug -Message "Percent Step: $Step"
        Write-Debug -Message "Percent Steps: $Steps"
        Write-Debug -Message "Percent Complete: $PercentComplete"
    }
    Process {
        Try {
            ##  Show progress
            Write-Progress -Activity $Activity -Status $Status -CurrentOperation $CurrentOperation -ID $ID -PercentComplete $PercentComplete
            Start-Sleep -Milliseconds $Delay
        }
        Catch {
            Throw (New-Object System.Exception("Could not Show progress status [$Status]! $($PSItem.Exception.Message)", $PSItem.Exception))
        }
    }
}
#endregion

#region  New-JsonConfigurationFile
Function New-JsonConfigurationFile {
<#
.SYNOPSIS
    Creates a json configuration file.
.DESCRIPTION
    Creates a new json configuration file in a specified location.
.PARAMETER Path
    Specifies the output path.
.EXAMPLE
    New-JsonConfigurationFile -Path 'C:\Temp\Config.json'
.INPUTS
    None
.OUTPUTS
    System.Object
.NOTES
    Created Ioan Popovici
.LINK
    https://MEM.Zone
.LINK
    https://MEM.Zone/Issues
.COMPONENT
    Configuration
.FUNCTIONALITY
    Create Json Configuration File
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Position=0)]
        [pscustomobject]$Path
    )
    Begin {
        [string]$Configuration = @'
{
    "HTMLReportConfig":  {
        "ReportName":    "Report for AD Certificate Autoenrollment",
        "ReportHeader":  "Devices added to certificate autoenrollment groups",
        "ReportFooter":  "For more information write to: \u003ci\u003e\u003ca href = \u0027mailto:servicedesk@company.com\u0027\u003eit-servicedesk@company.com\u003c/a\u003e\u003c/i\u003e"
    },
    "DomainConfig":  {
        "ULBSDomainConfig":  {
            "Description":  "Company Devices",
            "Server":       "companydomain.com",
            "Group":        "US-CertificateAutoenrollment",
            "SearchBase":   [
                "OU=Computers,OU=DEPARTMENT,OU=DIVISION,OU=COMPANY ROOT,DC=company,DC=com",
                "OU=Special Computers,OU=DEPARTMENT,OU=DIVISION,OU=COMPANY ROOT,DC=company,DC=com"
            ],
            "SearchScope":  "Subtree",
            "Filter":  "operatingSystem -notlike \"*server*\" -and objectClass -eq \"computer\"",
            "SkipOSCheck":  false
        }
    }
}
'@
    }
    Process {
        Out-File -Path $Path -Encoding 'UTF8' -Content $Configuration -ErrorAction 'Stop'
    }
}
#endregion

#region  ConvertTo-HashtableFromPsCustomObject
Function ConvertTo-HashtableFromPsCustomObject {
<#
.SYNOPSIS
    Converts a custom object to a hashtable.
.DESCRIPTION
    Converts a custom powershell object to a hashtable.
.PARAMETER PsCustomObject
    Specifies the custom object to be converted.
.EXAMPLE
    ConvertTo-HashtableFromPsCustomObject -PsCustomObject $PsCustomObject
.EXAMPLE
    $PsCustomObject | ConvertTo-HashtableFromPsCustomObject
.INPUTS
    System.Object
.OUTPUTS
    System.Object
.NOTES
    Created Ioan Popovici
.LINK
    https://MEM.Zone
.LINK
    https://MEM.Zone/Issues
.COMPONENT
    Conversion
.FUNCTIONALITY
    Convert custom object to hashtable
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Position=0)]
        [pscustomobject]$PsCustomObject
    )
    Begin {

        ## Preservers hashtable parameter order
        [System.Collections.Specialized.OrderedDictionary]$Output = @{}
    }
    Process {

        ## The '.PsObject.Members' method preservers the order of the members, Get-Member does not.
        [object]$ObjectProperties = $PsCustomObject.PsObject.Members | Where-Object -Property 'MemberType' -eq 'NoteProperty'
        ForEach ($Property in $ObjectProperties) { $Output.Add($Property.Name, $PsCustomObject.$($Property.Name)) }
        Write-Output -InputObject $Output
    }
}
#endregion

#region  Set-HtmlTableAlternatingRow
Function Set-HtmlTableAlternatingRow {
<#
.SYNOPSIS
    Sets an alternating css class for a each row in a specified html array object.
.DESCRIPTION
    Sets an alternating css class for a each row in a specified html array object by alternatively replacing two css classes for each new row.
    The object must be piped (IEnumerable) or a for-each must be used.
.PARAMETER Line
    Specifies the Line to parse. Supports pipeline input.
.PARAMETER CSSEvenClass
    Specifies the css class name to be used for 'even' replacement.
.PARAMETER CSSOddClass
    Specifies the css class name to be used for 'odd' replacements.
.EXAMPLE
    HTMLArrayObject | Set-HtmlTableAlternatingRow -CSSEvenClass 'Even' -CSSOddClass 'Odd'
.INPUTS
    System.Object
.OUTPUTS
    System.Object
.NOTES
    Created by Rob Sheppard
    Addapted by Ioan Popovici
.LINK
    https://github.com/MEM-Zone/MEM.Zone/issues/3
.LINK
    https://MEM.Zone
.LINK
    https://MEM.Zone/Issues
.COMPONENT
    HTML
.FUNCTIONALITY
    Sets alternating html table row class
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [ValidateNotNullorEmpty()]
        [string]$Line,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [string]$CSSEvenClass,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [string]$CSSOddClass
    )
    Begin {
        [string]$ClassName = $CSSEvenClass
    }
    Process {
        If ($Line.Contains('<tr><td>')) {
            $Line = $Line.Replace('<tr>',"<tr class=""$ClassName"">")
            If ($ClassName -eq $CSSEvenClass) { $ClassName = $CSSOddClass }
            Else { $ClassName = $CSSEvenClass }
        }
        Write-Output -InputObject $Line
    }
}
#endregion

#region Function Format-HTMLReport
Function Format-HTMLReport {
<#
.SYNOPSIS
    Formats a provided object to an HTML report.
.DESCRIPTION
    Formats a provided object to an HTML report, by formating table headers, html head and body.
.PARAMETER ReportContent
    Specifies the report content object to format. Supports pipeline input.
    Default value is an empty string.
.PARAMETER HTMLHeader
    Specifies the HTML Head. Optional, should not be used if you don't know what you are doing.
.PARAMETER HTMLBody
    Specifies the HTML Body. Optional, should not be used if you don't know what you are doing.
.PARAMETER ReportName
    Specifies the HTML page name header.
.PARAMETER ReportHeader
    Specifies the HTML page header paragraph.
.PARAMETER ReportFooter
    Specifies the HTML pager footer paragraph.
.PARAMETER NewTableHeaders
    Specifies new table headers if desired. Default is: Original object property names are used as table headers.
.EXAMPLE
    [string]$ReportName = 'Report from AD Inactive Device Maintenance'
    [string]$ReportHeader = "Devices with an inactivity threshold greater than <b>$DaysInactive</b> days"
    [string]$ReportFooter = "For more information write to: <i><a href = 'mailto:servicedesk@company.com'>it-servicedesk@company.com</a></i>"
    [hashtable]$NewTableHeaders = [ordered]@{
        'Last Logon (Days)' = DaysSinceLastLogon
        'Last Logon (Date)' = LastLogonDate
        'Path (DN)'         = DistinguishedName
    }
    Format-HTMLReport -ReportName $ReportName -ReportHeader $ReportHeader -ReportFooter $ReportFooter -NewTableHeaders $NewTableHeaders
.INPUTS
    System.Object
.OUTPUTS
    System.String
.NOTES
    Created by Ioan Popovici
.LINK
    https://MEM.Zone
.LINK
    https://MEM.Zone/Issues
.COMPONENT
    HTML
.FUNCTIONALITY
    Formats object to HTML
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,ParameterSetName='CustomTemplate',Position=1)]
        [ValidateNotNullorEmpty()]
        [Alias('Head')]
        [string]$HTMLHeader,
        [Parameter(Mandatory=$true,ParameterSetName='CustomTemplate',Position=2)]
        [ValidateNotNullorEmpty()]
        [Alias('Body')]
        [string]$HTMLBody,
        [Parameter(Mandatory=$false,ParameterSetName='CustomTemplate',ValueFromPipeline = $true,Position=0)]
        [Parameter(Mandatory=$false,ParameterSetName='DefaultTemplate',ValueFromPipeline = $true,Position=0)]
        [Alias('Input')]
        [object]$ReportContent = '',
        [Parameter(Mandatory=$true,ParameterSetName='DefaultTemplate',HelpMessage='Specify the report name',Position=1)]
        [ValidateNotNullorEmpty()]
        [Alias('Name')]
        [string]$ReportName,
        [Parameter(Mandatory=$true,ParameterSetName='DefaultTemplate',HelpMessage='Specify the report header',Position=2)]
        [ValidateNotNullorEmpty()]
        [Alias('Header')]
        [string]$ReportHeader,
        [Parameter(Mandatory=$false,ParameterSetName='DefaultTemplate',HelpMessage='Specify the report footer',Position=3)]
        [ValidateNotNullorEmpty()]
        [Alias('Footer')]
        [string]$ReportFooter = $null,
        [Parameter(Mandatory=$false,ParameterSetName='DefaultTemplate',HelpMessage='Specify the new table headers as a hashtable',Position=3)]
        [Alias('NewTH')]
        [System.Collections.Specialized.OrderedDictionary]$NewTableHeaders = $null
    )
    Begin {

        ## Check if we need to use a custom template, else use the default
        If ($($PSCmdlet.ParameterSetName) -eq 'CustomTemplate') {
            [string]$Head = $HTMLHeader
            [string]$Body = $HTMLBody
        }
        Else {

            ## Get current date and time using ISO 8601
            [string]$CurrentDateTime = Get-Date -Format 'yyyy-MM-dd'

            ## Set default head
            [string]$Head = $('
            <style>
                body {
                    background-color: #ffffff;
                    color: #000000;
                    font-family: Arial;
                }

                h1 {
                    color: #0C71C3
                }

                p {
                    font-size: 120%;
                    font-family: Calibri;
                    border-left: 4px solid #1a75ff;
                    padding-left: 5px;
                }

                a {
                    color: blue;
                }

                table {
                    cellpadding: 5px;
                    font-family: "Verdana";
                    font-size: 100%;
                    margin-left: 10px;
                    border: 1px solid DimGray;
                    border-collapse: collapse;
                }

                th {
                    padding: 5px;
                    font-weight: normal;
                    border: 1px solid DimGray;
                    border-collapse: collapse;
                    background-color: #2ECC71;
                    color: #ffffff;
                }

                td {
                    text-align: center;
                    padding-left: 10px;
                    padding-right: 10px;
                    border: 1px solid DimGray;
                    border-collapse: collapse;
                }

                .even {
                    font-family: "Lucida Console", Courier, monospace;
                    font-size: 80%;
                    background-color: white;
                    color: black;
                }

                .odd {
                    font-family: "Lucida Console", Courier, monospace;
                    font-size: 80%;
                    background-color: lightgrey;
                    color: black;
                }


                #success {
                    background-color: #2ECC71;
                    color: #ffffff;
                }

                #failed {
                    background-color: #FF0000;
                    color: #ffffff;
                }
            </style>
            ')

            ## Set default body
            [string]$Body = ("
                <h1>$ReportName</h1>
                <p>Report as of $CurrentDateTime from <b>$Env:ComputerName</b> - $ReportHeader </p>
            ")

            ## Set report footer
            [string]$Footer = ("<p>$ReportFooter</p>")
        }
    }
    Process {
        Try {

            ## Set new table headers if specified
            If (-not [string]::IsNullOrWhiteSpace($NewTableHeaders)) {
                ForEach ($TableHeader in $NewTableHeaders.GetEnumerator()) {
                    $ReportContent | Add-Member -MemberType 'AliasProperty' -Name $TableHeader.Name -Value $TableHeader.Value -ErrorAction 'SilentlyContinue'
                }

                ## Select result properties
                $ReportContent =  $ReportContent | Select-Object -Property $NewTableHeaders.GetEnumerator().Name
            }

            ## Convert result to html and set alternating row background colors
            [object]$HTMLReport = $ReportContent | ConvertTo-Html -Head $Head -Body $Body -PostContent $Footer |
                Set-HtmlTableAlternatingRow -CSSEvenClass 'even' -CSSOddClass 'odd' |
                    Out-String
        }
        Catch {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
        Finally {
            Write-Output -InputObject $HTMLReport
        }
    }
    End {
    }
}
#endregion

#region Function Get-ADGroupMember
Function Get-ADGroupMember {
<#
.SYNOPSIS
    Gets the members for an Active Directory group.
.DESCRIPTION
    Gets the members for an Active Directory group.
.PARAMETER Server
    Specifies the domain or server to query.
.PARAMETER Group
    Specifies the group to add the device to.
.PARAMETER MemberType
    Specifies the group members type.
    Allowed values:
        'User'
        'Computer'
.EXAMPLE
    GetADGroupMember -Server 'somedomain.com' -Group 'SomeGroup' -MemberType 'User'
.EXAMPLE
    GetADGroupMember -Server 'somedomain.com' -Group 'SomeGroup' -MemberType 'Computer'
.INPUTS
    None.
.OUTPUTS
    System.Object
.NOTES
    Created by Ioan Popovici
.LINK
    https://MEM.Zone
.LINK
    https://MEM.Zone/Issues
.COMPONENT
    AD
.FUNCTIONALITY
    Get group members
#>
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param (
        [Parameter(Mandatory=$true,HelpMessage='Enter a valid Domain or Domain Controller.',Position=0)]
        [ValidateNotNullorEmpty()]
        [Alias('ServerName')]
        [string]$Server,
        [Parameter(Mandatory=$true,HelpMessage='Specify Group Common Name (CN).',Position=1)]
        [ValidateNotNullorEmpty()]
        [Alias('GroupName')]
        [string]$Group,
        [Parameter(Mandatory=$true,HelpMessage='Specify Group Member type (User/Computer).',Position=2)]
        [ValidateNotNullorEmpty()]
        [Alias('Type')]
        [string]$MemberType
    )
    Begin {

        ## Print parameters if verbose is enabled
        Write-Log -Message $PSBoundParameters.GetEnumerator() -DebugMessage
    }
    Process {
        Try {
            ## Get the group Distinguished Name (DN)
            [string]$GroupDN = (Get-ADGroup -Server $Params.Server -Identity $Params.Group).DistinguishedName

            ## Set LDAP Filter to get all users or computers (including due to group nesting) that are members of the group
            [string]$LDAPFilter = "(&(objectCategory=$MemberType)(memberOf:1.2.840.113556.1.4.1941:=$GroupDN))"

            ## Get current group members. Get-ADComputer is used because the Get-ADGroupMember, Get-ADPrincipalGroupMembershipscope, and Get-ADAccountAuthorizationGroup
            ## cmdleds return is limited by the Active Directory Web Services to 5000 results per query by default
            Write-Log -Message "Searching [$Server] --> [$Group] Members..." -VerboseMessage
            If ($MemberType -eq 'Computer') {
                $GroupMembers = Get-ADComputer -Server $Server -LDAPFilter $LDAPFilter -Properties 'SID', 'Name', 'OperatingSystem', 'DistinguishedName'
            }
            Else {
                $GroupMembers = Get-ADUser -Server $Server -LDAPFilter $LDAPFilter -Properties 'SID', 'Name', 'OperatingSystem', 'DistinguishedName'
            }
        }
        Catch {
            Throw $PSItem
        }
        Finally {
            Write-Output -InputObject $GroupMembers
        }
    }
    End {
    }
}
#endregion

#region Function Add-ADDeviceToGroup
Function Add-ADDeviceToGroup {
<#
.SYNOPSIS
    Adds an Active Directory device to a group.
.DESCRIPTION
    Adds an Active Directory device to a group, using a specified OU, filter and group name
.PARAMETER Server
    Specifies the domain or server to query.
.PARAMETER Group
    Specifies the group to add the device to.
.PARAMETER GroupMembers
    Specifies the group members to check if the member is not already added.
    Should be used only when getting the group membership outside the function for very large groups. Default is '$null'
.PARAMETER SearchBase
    Specifies the search start location. Default is '$null'.
.PARAMETER SearchScope
    Specifies the scope of an Active Directory search. The acceptable values for this parameter are:
        * 'Base'     or '0'
        * 'OneLevel' or '1'
        * 'Subtree'  or '2'
    Default is 'Base'.
.PARAMETER Filter
    Specifies the filtering options. Default is 'Enabled -eq $true'.
.PARAMETER SkipOSCheck
    Specifies to skip the OS empty check.
.EXAMPLE
    Add-ADDeviceToGroup -Server 'somedomain.com' -Group 'AddToThisGroup' -SearchBase 'CN=Computers,DC=somedomain,DC=com' -Filter 'operatingSystem -notlike "*server*" -and objectClass -eq "computer"' -SkipOSCheck
.INPUTS
    None.
.OUTPUTS
    System.Object
.NOTES
    Created by Ioan Popovici
.LINK
    https://MEM.Zone
.LINK
    https://MEM.Zone/Issues
.COMPONENT
    AD
.FUNCTIONALITY
    Add Devices to a group
#>
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param (
        [Parameter(Mandatory=$true,HelpMessage='Enter a valid Domain or Domain Controller.',Position=0)]
        [ValidateNotNullorEmpty()]
        [Alias('ServerName')]
        [string]$Server,
        [Parameter(Mandatory=$true,HelpMessage='Specify Group Common Name (CN).',Position=1)]
        [ValidateNotNullorEmpty()]
        [Alias('GroupName')]
        [string]$Group,
        [Parameter(Mandatory=$false,HelpMessage='Specify Group Mebers.',Position=2)]
        [Alias('Members')]
        [pscustomobject]$GroupMembers = @{},
        [Parameter(Mandatory=$false,HelpMessage='Specify OU Common Name (CN).',Position=3)]
        [ValidateNotNullorEmpty()]
        [Alias('OU')]
        [string[]]$SearchBase = @(),
        [Parameter(Mandatory=$false,HelpMessage='Specify a search Scope (Base, OneLevel or Subtree).',Position=4)]
        [ValidateNotNullorEmpty()]
        [Alias('Scope')]
        [string]$SearchScope = 'Base',
        [Parameter(Mandatory=$false,HelpMessage='Specify filtering options.',Position=5)]
        [ValidateNotNullorEmpty()]
        [Alias('FilterOption')]
        [string]$Filter = "Enabled -eq 'true'",
        [Parameter(Mandatory=$false,HelpMessage='Specify if to skip OS check.',Position=6)]
        [switch]$SkipOSCheck
    )
    Begin {

        ## Print parameters if verbose is enabled
        Write-Log -Message $PSBoundParameters.GetEnumerator() -DebugMessage
    }
    Process {
        Try {
            ## Get date and time
            [string]$Date = (Get-Date -Format 'yyyy-dd-mm').ToString()
            [string]$Time = (Get-Date -Format 'HH:mm:ss.fff').ToString()

            ## Get the group members if not already specified
            If (-not $GroupMember) { $GroupMember = Get-ADGroupMember -Server $Server -Group $Group -MemberType 'Computer' }
            Write-Log -Message "Processing [$Group] Group (Members: $($GroupMembers.Count))..." -VerboseMessage

            ## Set the progress indicators for the loop
            [int]$OUSteps = $SearchBase.Count
            [int]$OUStep  = 0

            ## Process all OUs specified in the SearchBase parameter and add mathching devices to the group
            $AddADComputerToGroup = ForEach ($OU in $SearchBase) {

                ## Show progress
                [string]$Status = "Searching [$Server] --> [$OU]"
                Show-Progress -Activity "Retrieving Devices in OU..." -Status $Status -Step $OUStep -Steps $OUSteps -ID 1
                Write-Log -Message $Status -VerboseMessage

                ## Get all devices in the specified OU and tag them for 'Processing'.
                $ADComputersInfo = Get-ADComputer -Server $Server -Filter $Filter -SearchBase $OU -SearchScope $SearchScope -Property 'SID', 'Name', 'OperatingSystem', 'DistinguishedName'
                #  Create custom object to hold the group members
                $ADComputers = ForEach ($ADComputer in $ADComputersInfo) {
                    [pscustomobject]@{
                        SID = $ADComputer.SID.Value
                        Name = $ADComputer.Name
                        OperatingSystem = $ADComputer.OperatingSystem
                        Group = $Group
                        Server = $Server
                        DistinguishedName = $ADComputer.DistinguishedName
                        Operation = 'Processing'
                        Date = $Date
                        Time = $Time
                    }
                }

                ## Set the progress indicators for the loop
                [int]$AddSteps = $ADComputers.Count
                [int]$AddStep  = 0

                ## Add the device to the group if it's not already a member
                ForEach ($ADComputer in $ADComputers) {

                    ## Add operation time to the computer object
                    [string]$Time = (Get-Date -Format 'HH:mm:ss.fff').ToString()
                    $ADComputer.Time = $Time

                    ## If SkipOScheck is not specified, skip all computers with no operating system defined
                    If (-not $SkipOSCheck -and [string]::IsNullOrWhiteSpace($ADComputer.OperatingSystem)) {

                        ## Show progress
                        [string]$Status = "Skipping [$($ADComputer.Name)] --> [$Server\$Group]"
                        Show-Progress -Activity "Skipping Devices as tey have no Operating System defined..." -Status $Status -Step $AddStep -Steps $AddSteps -ID 2
                        Write-Log -Message $Status -VerboseMessage

                        ## Set operation status
                        $ADComputer.Operation = 'Skipped'
                    }

                    ## If the computer is not already a member of the group add and tag it as 'Added'
                    ElseIf ($ADComputer.SID -notin $GroupMember.SID.Value) {

                        ## Show progress
                        [string]$Status = "Adding [$($ADComputer.Name)] --> [$Server\$Group]"
                        Show-Progress -Activity "Adding Devices to Security Group..." -Status $Status -Step $AddStep -Steps $AddSteps -ID 2
                        Write-Log -Message $Status -VerboseMessage

                        ##  Add computer to group and support for ShouldProcess
                        [boolean]$ShouldProcess = $PSCmdlet.ShouldProcess("$Server\$Group", "Add $($ADComputer.Name)")
                        If ($ShouldProcess) { Add-ADGroupMember -Server $Server -Identity $Group -Members $ADComputer.SID -Confirm:$false }
                        #  If operation is successful, set the opration status to 'Added' otherwise set it to 'Failed'
                        If ($?) { $ADComputer.Operation = 'Added' } Else { $ADComputer.Operation = 'AddFailed' }
                    }

                    ## If the computer is already a member of the group tag it as 'Present'
                    Else { $ADComputer.Operation = 'Present' }

                    ## Return the computer object to the pipeline
                    Write-Output -InputObject $ADComputer

                    ## Increment the add progress step
                    $AddStep ++
                }

                ## Increment the OU progress step
                $OUStep ++
            }
        }
        Catch {
            Throw $PSItem
        }
        Finally {
            Write-Output -InputObject $AddADComputerToGroup
        }
    }
    End {
    }
}
#endregion

#region Function Remove-ADDeviceFromGroup
Function Remove-ADDeviceFromGroup {
<#
.SYNOPSIS
    Removes an Active Directory device to a group.
.DESCRIPTION
    Removes an Active Directory device to a group, using a specified OU, filter and group name
.PARAMETER Server
    Specifies the domain or server to query.
.PARAMETER Group
    Specifies the group to add the device to.
.PARAMETER GroupMembers
    Specifies the group members to process.
    Should be used only when getting the group membership outside the function for very large groups. Default is '$null'
.PARAMETER SkipSID
    Specifies whether to skip one or more SIDs. Default is '$null'.
.EXAMPLE
    Remove-ADDeviceFromGroup -Server 'somedomain.com' -Group 'RemoveFromThisGroup' -SkipSID 'S-1-5-32-543'
.INPUTS
    None.
.OUTPUTS
    System.Object
.NOTES
    Created by Ioan Popovici
.LINK
    https://MEM.Zone
.LINK
    https://MEM.Zone/Issues
.COMPONENT
    AD
.FUNCTIONALITY
    Remove Devices from a group
#>
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param (
        [Parameter(Mandatory=$true,HelpMessage='Enter a valid Domain or Domain Controller.',Position=0)]
        [ValidateNotNullorEmpty()]
        [Alias('ServerName')]
        [string]$Server,
        [Parameter(Mandatory=$true,HelpMessage='Specify Group Common Name (CN).',Position=1)]
        [ValidateNotNullorEmpty()]
        [Alias('GroupName')]
        [string]$Group,
        [Parameter(Mandatory=$false,HelpMessage='Specify Group Members.',Position=2)]
        [Alias('Members')]
        [pscustomobject]$GroupMembers = @{},
        [Parameter(Mandatory=$false,HelpMessage='Specify a SID or SIDs to skip.',Position=5)]
        [ValidateNotNullorEmpty()]
        [Alias('Skip')]
        [string[]]$SkipSID = @()
    )
    Begin {

        ## Print parameters if verbose is enabled
        Write-Log -Message $PSBoundParameters.GetEnumerator() -DebugMessage
    }
    Process {
        Try {
            ## Get date and time
            [string]$Date = (Get-Date -Format 'yyyy-dd-mm').ToString()
            [string]$Time = (Get-Date -Format 'HH:mm:ss.fff').ToString()

            ## Get the group members if not already specified
            If ($GroupMembers.Count -eq 0) { $GroupMembers = Get-ADGroupMember -Server $Server -Group $Group -MemberType 'Computer' }

            ## Create custom object to hold the group members and tag them for 'Processing'.
            $GroupMembers = ForEach ($GroupMember in $GroupMembers) {
                [pscustomobject]@{
                    SID = $GroupMember.SID.Value
                    Name = $GroupMember.Name
                    OperatingSystem = $GroupMember.OperatingSystem
                    Group = $Group
                    Server = $Server
                    DistinguishedName = $GroupMember.DistinguishedName
                    Operation = 'Processing'
                    Date = $Date
                    Time = $Time
                }
            }
            Write-Log -Message "Processing [$Group] Group (Members: $($GroupMembers.Count))..." -VerboseMessage

            ## Set the progress indicators for the loop
            [int]$RemoveSteps = $GroupMembers.Count
            [int]$RemoveStep  = 0

            ## Remove devices
            $RemoveADComputerFromGroup = ForEach ($GroupMember in $GroupMembers) {

                ## Add operation time to the computer object
                [string]$Time = (Get-Date -Format 'HH:mm:ss.fff').ToString()
                $GroupMember.Time = $Time

                ## If the computer is not the $SkipSID list, then remove it from the group
                If ($GroupMember.SID -notin $SkipSID) {

                    ## Show progress
                    [string]$Status = "Removing [$($GroupMember.Name)] --> [$Server\$Group]"
                    Show-Progress -Activity "Removing Devices from Security Group..." -Status $Status -Step $RemoveStep -Steps $RemoveSteps -ID 2
                    Write-Log -Message $Status -VerboseMessage

                    ##  Remove computer to group and support for ShouldProcess
                    [boolean]$ShouldProcess = $PSCmdlet.ShouldProcess("$Server\$Group", "Remove $($GroupMember.Name)")
                    If ($ShouldProcess) { Remove-ADGroupMember -Server $Server -Identity $Group -Members $GroupMember.SID -Confirm:$false }
                    #  If operation is successful, set the opration status to 'Remove' otherwise set it to 'RemoveFailed'
                    If ($?) { $GroupMember.Operation = 'Removed' } Else { $GroupMember.Operation = 'RemoveFailed' }

                    ## Return result to the pipeline
                    Write-Output -InputObject $GroupMember
                }

                ## Increment the remove progress step
                $RemoveStep ++
            }
        }
        Catch {
            Throw $PSItem
        }
        Finally {
            Write-Output -InputObject $RemoveADComputerFromGroup
        }
    }
    End {
    }
}
#endregion

#endregion
##*=============================================
##* END FUNCTION LISTINGS
##*=============================================

##*=============================================
##* SCRIPT BODY
##*=============================================
#region ScriptBody

Try {

    ## Write execution to log
    Write-Log -Message "Script [$ScriptFullName] started!" -VerboseMessage -LogDebugMessage $true

    ## Check if the configuratin file exists
    [boolean]$ConfigExists = Test-Path -Path $ConfigFilePath

    ## Create a new configuration file if specified
    If (-not $ConfigExists -or $NewConfigFile) {
        New-JsonConfigurationFile -Path $ConfigFilePath
        Write-Log -Message "New configuration file [$ConfigFilePath] created!" -VerboseMessage -LogDebugMessage $true
        Write-Log -Message "Script [$ScriptFullName] finished!" -VerboseMessage -LogDebugMessage $true
        Return
    }

    ## Get configuration file content
    [object]$ScriptConfig = $(Get-Content -Path $ConfigFilePath | ConvertFrom-Json)

    ## Set script configuration from json object and convert them to hashtables. Hashtables are declared in the script initialization.
    $NewTableHeaders  = $ScriptConfig.MainConfig.ReportHeaderColumns | ConvertTo-HashtableFromPsCustomObject
    $HTMLReportConfig = $ScriptConfig.HTMLReportConfig               | ConvertTo-HashtableFromPsCustomObject
    $DomainConfig     = $ScriptConfig.DomainConfig                   | ConvertTo-HashtableFromPsCustomObject

    ## Set log file path and fullname if it exists in the config file
    If (-not [string]::IsNullOrEmpty($ScriptConfig.MainConfig.LogFolderPath)) {
        $Script:LogFileDirectory = $ScriptConfig.MainConfig.LogFolderPath
        $Script:LogFilePath      = $(Join-Path -Path $Script:LogFileDirectory -ChildPath $($Script:LogSource + '.log'))
    }

    ## Get domain configuration from the config file
    [string[]]$Domains = $DomainConfig.GetEnumerator() | Select-Object -ExpandProperty 'Name'

    ## Set the progress indicators for the loop
    [int]$DomainSteps = $Domains.Count
    [int]$DomainStep  = 0

    ## Process domains
    $Output = ForEach ($Domain in $Domains) {

        ## Show Progress and write it to log
        [string]$Progress = "Processing [$($DomainConfig.$Domain.Server)] --> [$($DomainConfig.$Domain.Group)]"
        Show-Progress -Status $Progress -Step $DomainStep -Steps $DomainSteps -ID 0
        Write-Log -Message $Progress -VerboseMessage

        ## Convert the domain config to a hashtable for loop AddDeviceToGroup call. '$Param' is declared in the script initializtion.
        $Params = $DomainConfig.$Domain | ConvertTo-HashtableFromPsCustomObject
        #  Splat aditional parameters
        $Params.Add('WhatIf', $WhatIfPreference)
        $Params.Add('Verbose', $VerbosePreference)
        $Params.Add('Debug', $DebugPreference)
        $Params.Remove('Description')

        ## Get group members
        $GroupMembers = Get-ADGroupMember -Server $Params.Server -Group $Params.Group -MemberType 'Computer'

        ## Splat parameters for AddDeviceToGroup
        $Params.Add('GroupMembers', $GroupMembers )

        ## Call Add-ADDeviceToGroup function with loop variables
        $AddADDeviceToGroup = Add-ADDeviceToGroup @Params

        ## Build the skip SID list to be used in the Remove-ADDeviceFromGroup function
        $SkipSID = $AddADDeviceToGroup | Where-Object -Property 'Operation' -in ('Added','Present')|  Select-Object -ExpandProperty 'SID'

        ## Splat parameeters for Remove-ADDeviceFromGroup
        $Params.Add('SkipSID', $SkipSID )
        $Params.Remove('SkipOSCheck')
        $Params.Remove('SearchScope')
        $Params.Remove('SearchBase')
        $Params.Remove('Filter')

        ## Call Remove-ADDeviceFromGroup function with loop variables
        $RemoveADDeviceFromGroup = Remove-ADDeviceFromGroup @Params

        ## Return result to the pipeline if it is not empty
        If ($RemoveADDeviceFromGroup.Count -gt 0) { Write-Output $RemoveADDeviceFromGroup }
        Write-Output $AddADDeviceToGroup

        ## Increment the domain progress step
        $DomainStep ++
    }
}
Catch {
    Write-Log -Message "Script [$ScriptFullName] Failed!`n$(Resolve-Error)" -Severity 3
    Throw $PSItem
}
Finally {

    ## Get number of devices added, removed, present and failed
    [int]$TotalDeviceCount   = $($Output | Measure-object).Count
    [int]$PresentDeviceCount = $($Output | Where-Object { $PsItem.Operation -eq 'Present' } | Measure-object).Count
    [int]$AddedDeviceCount   = $($Output | Where-Object { $PsItem.Operation -eq 'Added'   } | Measure-object).Count
    [int]$SkippedDeviceCount = $($Output | Where-Object { $PsItem.Operation -eq 'Skipped' } | Measure-object).Count
    [int]$RemovedDeviceCount = $($Output | Where-Object { $PsItem.Operation -eq 'Removed' } | Measure-object).Count + $SkippedDeviceCount
    [int]$FailedDeviceCount  = $($Output | Where-Object { $PsItem.Operation -match 'Fail' } | Measure-object).Count

    ## Write device counts to log
    [string]$LogMessage = [ordered]@{
        'PresentDevices' = $PresentDeviceCount
        'AddedDevices'   = $AddedDeviceCount
        'SkippedDevices' = $SkippedDeviceCount
        'RemovedDevices' = $RemovedDeviceCount
        'FailedDevices'  = $FailedDeviceCount
        'TotalDevices'   = $TotalDeviceCount
    } | Out-String
    Write-Log -Message $LogMessage -VerboseMessage -LogDebugMessage $true -PassThru

    ## Set the output to empty string if there are no devices found else, remove the 'Present' devices from the output
    $Output = $Output | Where-Object { $PsItem.Operation -ne 'Present' }

    ## Set the output to '' if it's null so we can show the table headers
    If (-not $Output) { $Output = '' }

    ## Splatting Format-HTMLReport table headers
    $HTMLReportConfig.Add('ReportContent', $Output)
    If (-not [string]::IsNullOrEmpty($NewTableHeaders))  { $HTMLReportConfig.Add('NewTableHeaders', $NewTableHeaders) }

    ## Formating html report
    [object]$OutputHTML = Format-HTMLReport @HTMLReportConfig

    ## Write html report to disk
    [string]$HTMLFileName = -join ($ScriptName, '.html')
    [string]$HTMLFilePath = Join-Path -Path $Script:LogFileDirectory -ChildPath $HTMLFileName
    Out-File -InputObject $OutputHTML -FilePath $HTMLFilePath -Force -WhatIf:$false

    ## If any matching devices are found, write the result to log
    If ($TotalDeviceCount -gt 0) {
        $OutputCSV = "`n$($Output | ForEach-Object { If ($PsItem) { ConvertTo-Csv -InputObject $PsItem -NoTypeInformation}} | Out-String)"
        Write-Log -Message $OutputCSV -LoggingOptions 'File'
    }

    ## Show progress status and write it to the event log
    Show-Progress -Status "$($ScriptConfig.HTMLReportConfig.ReportName) completed!" -Delay 1000 -Step 100 -Steps 100 -ID 0
    ## Write execution to log
    Write-Log -Message "Check the log [$Script:LogFilePath] for more information!" -VerboseMessage -LogDebugMessage $true -LoggingOptions 'EventLog'
    Write-Log -Message "Script [$ScriptFullName] finished!" -VerboseMessage -LogDebugMessage $true
}

#endregion
##*=============================================
##* END SCRIPT BODY
##*=============================================