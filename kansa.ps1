﻿<#
.SYNOPSIS
Kansa is a Powershell based incident response framework for Windows environments.
.DESCRIPTION
In this modular version of Mal-Seine, Kansa looks for a modules.conf
file in the -Modules directory. If one is found, it will control which 
modules execute and in what order. If no modules.conf is found, all 
modules will be executed in the order that ls reads them.

After parsing modules.conf or the -Modules path, Kansa will execute
each module on each target (remote hosts) and write the output to a
folder named for each module in the -Output path. Each target will have
its data written to separate files.

For example, the Get-PrefetchListing.ps1 module data will be written
to Output\PrefetchListing\Hostname-PrefetchListing.txt.

If a module returns Powershell objects, its data can be written out in
one of several file formats, including bin, csv, tsv and xml. Modules that
return text should choose the txt output format. The first line of each 
module should contain a comment specifying the output format, following
this format:

# OUTPUT xml

This script was written to avoid the need for CredSSP, therefore 
"second-hops" must be avoided. For more details on this see:

http://trustedsignal.blogspot.com/2014/04/kansa-modular-live-response-tool-for.html

The script assumes you will have administrator level privileges on
target hosts, though such privileges may not be required by all modules.

If you run this script without the -TargetList argument, Remote Server
Administration Tools (RSAT), is required. These are available from Microsoft's 
Download Center for Windows 7 and 8. You can search for RSAT at:

http://www.microsoft.com/en-us/download/default.aspx

.PARAMETER ModulePath
An optional parameter that specifies the path to the collector modules.
.PARAMETER TargetList
An optional argument, the name of a file containing a list of servers 
from the current forest to collect data from.
PARAMETER Target
An optional argument, the name of a single system to collect data from.
.PARAMETER TargetCount
An optional parameter that specifies the maximum number of targets.

In the absence of the TargetList and / or Target arguments, Kansa will use
Remote System Administration Tools (a separate installed package) to query
Active Directory and will build a list of hosts to target automatically.

.PARAMETER Credential
An optional credential that the script will use for execution. Use the
$Credential = Get-Credential convention to populate a suitable variable.
.PARAMETER Pushbin
An optional flag that causes Kansa to push required binaries to the 
ADMIN$ shares of targets. Modules that need to work with Pushbin, must 
include the "# BINDEP <binary>" directive on the second line of their 
script and users of Kansa must copy the required <binary> to the 
Modules\bin\ folder.

For example, the Get-Autorunsc.ps1 collector has a binary dependency on
Sysinternals Autorunsc.exe. The second line of Get-Autorunsc.ps1 contains
the "# BINDEP autorunsc.exe" directive and a copy of autorunsc.exe is placed 
in the Modules\bin folder. If Kansa is run with the -Pushbin flag, it will 
attempt to copy autorunsc.exe from the Modules\bin path to the ADMIN$ share 
of each remote host. If your required binaries are already present on
each target and in the path where the modules expect them to be, you can 
omit the -Pushbin flag and save the step of copying binaries.
.PARAMETER Ascii
An optional switch that tells Kansa you want all text output (i.e. txt,
csv and tsv) and errors be written as Ascii. Unicode is the default.
.PARAMETER UpdatePath
An option switch that adds Analysis script paths to the user's path and
then exits. Kansa will automatically add Analysis script paths to the 
user's path when run normally, this switch is just for convenience when
coming back to the data for analysis.
.PARAMETER ListModules
An optional switch that lists the available modules. Useful for
constructing a modules.conf file. Kansa exits after listing.
You'll likely want to sort the according to the order of volatility.
.PARAMETER ListAnalysis
An optional switch that lists the available analysis scripts. Useful for
constructing an analysis.conf file. Kansa exits after listing. If you 
use this switch to build an analysis.conf file, you'll likely want to
edit the list so you're only running the analysis scripts you want to
run.
.PARAMETER Analysis
An optional switch that causes Kansa to run automated analysis based on
the contents of the Analysis\Analysis.conf file.
.PARAMETER Transcribe
An optional flag that causes Start-Transcript to run at the start
of the script, writing to $OutputPath\yyyyMMddhhmmss.log
.INPUTS
None
You cannot pipe objects to this cmdlet
.OUTPUTS
Various and sundry.
.NOTES
In the absence of a configuration file, specifying which modules to run, 
this script will run each module across all hosts.

Each module should return objects, ideally, though text is supported. See
the discussion above about OUTPUT formats.

Because modules should only COLLECT data from remote hosts, their filenames
must begin with "Get-". Examples:
Get-PrefetchListing.ps1
Get-Netstat.ps1

Any module not beginning with "Get-" will be ignored.

Note this read-only aspect is unenforced, therefore Kansa can be used to
make changes to remote hosts. As a result, it can be used to facilitate
remediation.

The script can take a list of targets, read from a text file, via the -Target
argument. You may also supply the -TargetCount argument to limit how many hosts
from the file will be targeted. 

In the absence of the -Target argument containing a list of targets, the script
will query Acitve Directory for a complete list of hosts and will attempt to 
target all of them. As of this writing, failures are silently ignored.

.EXAMPLE
Kansa.ps1 -ModulePath .\Kansas 
In the above example the user has specified the module path and a path
for the tool's output. Note that error logging and transcriptions (if
specified using -transcribe) are written to the output path. Kansa will
query active directory for a list of targets in the current forest.
.EXAMPLE
Kansa.ps1 -ModulePath .\Modules -TargetList hosts.txt -Credential $Credential -Transcribe -Verbose
In this example the user has specified a module path, a list of hosts to
target, a user credential under which to execute. The -Transcribe and 
-Verbose flags are also supplied causing all script output to be written
to a transcript and for the script to be more verbose.
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$False,Position=0)]
        [String]$ModulePath="Modules\",
    [Parameter(Mandatory=$False,Position=1)]
        [String]$TargetList=$Null,
    [Parameter(Mandatory=$False,Position=2)]
        [String]$Target=$Null,
    [Parameter(Mandatory=$False,Position=3)]
        [int]$TargetCount=0,
    [Parameter(Mandatory=$False,Position=4)]
        [PSCredential]$Credential=$Null,
    [Parameter(Mandatory=$False,Position=5)]
        [Switch]$Pushbin,
    [Parameter(Mandatory=$False,Position=6)]
        [Int]$ThrottleLimit=0,
    [Parameter(Mandatory=$False,Position=7)]
        [Switch]$Ascii,
    [Parameter(Mandatory=$False,Position=8)]
        [Switch]$UpdatePath,
    [Parameter(Mandatory=$False,Position=9)]
        [Switch]$ListModules,
    [Parameter(Mandatory=$False,Position=10)]
        [Switch]$ListAnalysis,
    [Parameter(Mandatory=$False,Position=11)]
        [Switch]$Analysis,
    [Parameter(Mandatory=$False,Position=12)]
        [Switch]$Transcribe
)

# Opening with a Try so the Finally block at the bottom will always call
# the Exit-Script function and clean up things as needed.
Try {

function FuncTemplate {
<#
.SYNOPSIS
Default function template, copy when making new function
#>
Param(
    [Parameter(Mandatory=$False,Position=0)]
        [String]$ParamTemplate=$Null
)
    Write-Debug "Entering $($MyInvocation.MyCommand)"
    $Error.Clear()
    # Non-terminating errors can be checked via
    if ($Error) {
        # Write the $Error to the $Errorlog
        $Error | Add-Content -Encoding $Encoding $ErrorLog
        $Error.Clear()
    }

    Try {
        <# Only terminating error code needs to go in a try/catch #>
    } Catch [Exception] {
        $Error | Add-Content -Encoding $Encoding $ErrorLog
        $Error.Clear()
    }
    Write-Debug "Exiting $($MyInvocation.MyCommand)"    
}
<# End FuncTemplate #>

function Exit-Script {
<#
.SYNOPSIS
Exit the script somewhat gracefully, closing any open transcript.
#>
    Set-Location $StartingPath
    if ($Transcribe) {
        $Suppress = Stop-Transcript
    }
    if (Test-Path($ErrorLog)) {
        Write-Output "Script completed with errors. See ${ErrorLog} for details."
    }
    if (!(Get-ChildItem $OutputPath)) {
        # $OutputPath is empty, nuke it
        "Output path was created, but Kansa finished with no hits, no runs and no errors. Nuking the folder."
        $suppress = Remove-Item $OutputPath -Force
    }
    $Error.Clear()
    Exit
}

function Get-Modules {
<#
.SYNOPSIS
Looks for modules.conf in the $Modulepath, default is Modules.
If found, returns the list of uncommented modules in the order
they are listed in the file. If no modules.conf is found, returns
a list of all modules found in $Modulepath, where a module is a
.ps1 script starting with Get-.
#>
Param(
    [Parameter(Mandatory=$True,Position=0)]
        [String]$ModulePath
)
    Write-Debug "Entering $($MyInvocation.MyCommand)"
    Write-Debug "`$ModulePath is ${ModulePath}."
    $Modules = $FoundModules = @()
    if (!(ls $ModulePath -ErrorAction SilentlyContinue).PSIsContainer) {
        # User may have provided full path to a .ps1 module, this is how you run a single module explicitly
        if (Test-Path($ModulePath)) {
            $Module = ls $ModulePath | Select-Object -ExpandProperty BaseName
            Write-Verbose "Running module: $Module"
            Return ls $ModulePath
        }
    }
    $ModConf = $ModulePath + "\" + "Modules.conf"
    if (Test-Path($Modconf)) {
        Write-Verbose "Found ${ModulePath}\Modules.conf."
        # ignore blank and commented lines, trim misc. white space
        $Modules = Get-Content $ModulePath\Modules.conf | % { $_.Trim() } | ? { $_ -gt 0 -and (!($_.StartsWith("#"))) }
        foreach ($Module in $Modules) {
            # verify listed modules exist
            $Modpath = $ModulePath + "\" + $Module
            if (!(Test-Path($Modpath))) {
                "Could not find module specified in ${ModulePath}\Modules.conf: $Module. Skipping." | Add-Content -Encoding $Encoding $ErrorLog
            }
            # module found add it to the list
            $FoundModules += ls $ModPath   
        }
        $Modules = $FoundModules
    } else {
        # we had no modules.conf
        $Modules = ls -r $ModulePath\Get-*.ps1
    }
    Write-Verbose "Running modules: $(($Modules | Select-Object -ExpandProperty BaseName) -join "`n")"
    $Modules
    Write-Debug "Exiting $($MyInvocation.MyCommand)"
}

function Load-AD {
    # no targets provided so we'll query AD to build it, need to load the AD module
    Write-Debug "Entering $($MyInvocation.MyCommand)"
    if (Get-Module -ListAvailable | ? { $_.Name -match "ActiveDirectory" }) {
        $Error.Clear()
        Import-Module ActiveDirectory
        if ($Error) {
            "Could not load the required Active Directory module. Please install the Remote Server Administration Tool for AD. Quitting." | Add-Content -Encoding $Encoding $ErrorLog
            $Error.Clear()
            Exit
        }
    } else {
        "Could not load the required Active Directory module. Please install the Remote Server Administration Tool for AD. Quitting." | Add-Content -Encoding $Encoding $ErrorLog
        Exit
    }
    Write-Debug "Exiting $($MyInvocation.MyCommand)"
}

function Get-Forest {
    # what forest are we in?
    Write-Debug "Entering $($MyInvocation.MyCommand)"
    try {
        $Forest = (Get-ADForest).Name
        Write-Verbose "Forest is ${forest}."
        $Forest
    } catch {
        "Get-Forest could not find current forest." | Add-Content -Encoding $Encoding $ErrorLog
        Exit
    }
}

function Get-Targets {
Param(
    [Parameter(Mandatory=$False,Position=0)]
        [String]$TargetList=$Null,
    [Parameter(Mandatory=$False,Position=1)]
        [int]$TargetCount=0
)
    Write-Debug "Entering $($MyInvocation.MyCommand)"
    if ($TargetList) {
        # user provided a list of targets
        if ($TargetCount -eq 0) {
            $Targets = Get-Content $TargetList | % { $_.Trim() } | Where-Object { $_.Length -gt 0 }
        } else {
            $Targets = Get-Content $TargetList | % { $_.Trim() } | Where-Object { $_.Length -gt 0 } | Select-Object -First $TargetCount
        }
        Write-Verbose "`$Targets are ${Targets}."
        return $Targets
    } 
        
    Try {
        # no target list provided, we'll query AD for it
        Write-Verbose "`$TargetCount is ${TargetCount}."
        if ($TargetCount -eq 0 -or $TargetCount -eq $Null) {
            $Targets = Get-ADComputer -Filter * | Select-Object -ExpandProperty Name 
        } else {
            $Targets = Get-ADComputer -Filter * -ResultSetSize $TargetCount | Select-Object -ExpandProperty Name
        }
        Write-Verbose "`$Targets are ${Targets}."
        return $Targets
    } Catch [Exception] {
        "Get-Targets failed. Quitting." | Add-Content -Encoding $Encoding $ErrorLog
        $Error | Add-Content -Encoding $Encoding $ErrorLog
        $Error.Clear()
        Exit
    }
    Write-Debug "Exiting $($MyInvocation.MyCommand)"
}

function Get-TargetData {
<#
.SYNOPSIS
Runs each module against each target. Writes out the returned data to host where Kansa is run from.
#>
Param(
    [Parameter(Mandatory=$True,Position=0)]
        [Array]$Targets,
    [Parameter(Mandatory=$True,Position=1)]
        [Array]$Modules,
    [Parameter(Mandatory=$False,Position=2)]
        [PSCredential]$Credential=$False,
    [Parameter(Mandatory=$False,Position=3)]
        [Int]$ThrottleLimit
)
    Write-Debug "Entering $($MyInvocation.MyCommand)"

    Try {
        # Create our sessions with targets
        if ($Credential) {
            $PSSessions = New-PSSession -ComputerName $Targets -SessionOption (New-PSSessionOption -NoMachineProfile) -Credential $Credential
            $Error | Add-Content -Encoding $Encoding $ErrorLog
            $Error.Clear()
        } else {
            $PSSessions = New-PSSession -ComputerName $Targets -SessionOption (New-PSSessionOption -NoMachineProfile)
            $Error | Add-Content -Encoding $Encoding $ErrorLog
            $Error.Clear()
        }

        foreach($Module in $Modules) {
            $ModuleName = $Module | Select-Object -ExpandProperty BaseName
            # we'll use $GetlessMod for the output folder
            $GetlessMod = $($ModuleName -replace "Get-") 
            $Suppress = New-Item -Path $OutputPath -name $GetlessMod -ItemType Directory
            # First line of each modules can specify how output should be handled
            $OutputMethod = Get-Content $Module -TotalCount 1 
            # run the module on the targets
            $Job = Invoke-Command -Session $PSSessions -FilePath $Module -AsJob -ThrottleLimit $ThrottleLimit
            Write-Verbose "Waiting for $ModuleName to complete."
            # Wait-Job does return data to stdout, add $suppress = to start of next line, if needed
            Wait-Job $Job
            foreach($ChildJob in $Job.ChildJobs) { 
                $Recpt = Receive-Job $ChildJob
                $Outfile = $OutputPath + $GetlessMod + "\" + $ChildJob.Location + "-" + $GetlessMod
                # save the data
                switch -Wildcard ($OutputMethod) {
                    "*csv" {
                        $Outfile = $Outfile + ".csv"
                        $Recpt | ConvertTo-Csv -NoTypeInformation | % { $_ -replace "`"" } | Set-Content -Encoding $Encoding $Outfile
                    }
                    "*tsv" {
                        $Outfile = $Outfile + ".tsv"
                        $Recpt | ConvertTo-Csv -NoTypeInformation -Delimiter "`t" | % { $_ -replace "`"" } | Set-Content -Encoding $Encoding $Outfile
                    }
                    "*xml" {
                        $Outfile = $Outfile + ".xml"
                        $Recpt | Export-Clixml $Outfile -Encoding $Encoding
                    }
                    "*bin" {
                        $Outfile = $Outfile + ".bin"
                        $Recpt | Set-Content -Encoding Byte $Outfile
                    }
                    "*zip" {
                        # Compression should be done in the collector
                        # Default collector template has a function
                        # for compressing data as an example
                        $Outfile = $Outfile + ".zip"
                        $Recpt | Set-Content -Encoding Byte $Outfile
                    }
                    default {
                        $Outfile = $Outfile + ".txt"
                        $Recpt | Set-Content -Encoding $Encoding $Outfile
                    }
                }
            }
        }
        Remove-PSSession $PSSessions
    } Catch [Exception] {
        $Error | Add-Content -Encoding $Encoding $ErrorLog
        $Error.Clear()
    }
    Write-Debug "Exiting $($MyInvocation.MyCommand)"    
}

function Push-Bindep {
<#
.SYNOPSIS
Attempts to copy required binaries to targets.
If a module depends on an external binary, the binary should be copied to
.\Modules\bin\ and the module should reference the binary on it's second line
through the use of a comment such as the following:
# BINDEP .\Modules\bin\autorunsc.exe

Some Modules may require multiple binary files, say an executable and required
dlls. See the .\Modules\Disk\Get-FlsBodyFile.ps1 as an example. The # BINDEP
line in that module references .\Modules\bin\fls.zip. Kansa will copy that zip
file to the targets, but the module itself handles the unzipping of the fls.zip
file.

# BINDEP must include the path to the binary, relative to Kansa.ps1's path.
#>
Param(
    [Parameter(Mandatory=$True,Position=0)]
        [Array]$Targets,
    [Parameter(Mandatory=$True,Position=1)]
        [Array]$Modules,
    [Parameter(Mandatory=$False,Position=2)]
        [PSCredential]$Credential
        
)
    Write-Debug "Entering $($MyInvocation.MyCommand)"
    foreach($Module in $Modules) {
        $ModuleName = $Module | Select-Object -ExpandProperty BaseName
        # read the second line to determine binary dependency, not required
        $bindepline = Get-Content $Module -TotalCount 2 | Select-Object -Skip 1
        if ($bindepline -match '#\sBINDEP\s(.*)') {
            $Bindep = $($Matches[1])
            Write-Verbose "${ModuleName} has dependency on ${Bindep}."
            if (-not (Test-Path("$Bindep"))) {
                Write-Verbose "${Bindep} not found in ${ModulePath}bin, skipping."
                "${Bindep} not found in ${ModulePath}\bin, skipping." | Add-Content -Encoding $Encoding $ErrorLog
                Continue
            }
            Write-Verbose "Attempting to copy ${Bindep} to targets..."
            foreach($Target in $Targets) {
                Try {
                    if ($Credential) {
                        $suppress = New-PSDrive -PSProvider FileSystem -Name "KansaDrive" -Root "\\$Target\ADMIN$" -Credential $Credential
                        Copy-Item "$Bindep" "KansaDrive:"
                        $suppress = Remove-PSDrive -Name "KansaDrive"
                    } else {
                        $suppress = New-PSDrive -PSProvider FileSystem -Name "KansaDrive" -Root "\\$Target\ADMIN$"
                        Copy-Item "$Bindep" "KansaDrive:"
                        $suppress = Remove-PSDrive -Name "KansaDrive"
                    }
                } Catch [Exception] {
                    "Failed to copy ${Bindep} to ${Target}." | Add-Content -Encoding $Encoding $ErrorLog
                    $Error | Add-Content -Encoding $Encoding $ErrorLog
                    $Error.Clear()
                }
            }
        }
    }
    Write-Debug "Exiting $($MyInvocation.MyCommand)"    
}

function List-Modules {
Param(
    [Parameter(Mandatory=$True,Position=0)]
        [String]$ModulePath
)
    Write-Debug "Entering $($MyInvocation.MyCommand)"
    $Error.Clear()

    foreach ($dir in (ls $ModulePath)) {
        if ($dir.PSIsContainer -and $dir.name -ne "bin") {
            foreach($file in (ls $ModulePath\$dir\Get-*)) {
                $($dir.Name + "\" + (split-path -leaf $file))
            }
        } else {
            foreach($file in (ls $ModulePath\Get-*)) {
                $file.Name
            }
        }
    }
    if ($Error) {
        # Write the $Error to the $Errorlog
        $Error | Add-Content -Encoding $Encoding $ErrorLog
        $Error.Clear()
    }
    Write-Debug "Exiting $($MyInvocation.MyCommand)"    
}

function Set-KansaPath {
    # Update the path to inlcude Kansa analysis script paths, if they aren't already
    $kansapath = Split-Path -Path $MyInvocation.MyCommand.Definition
    $found = $False
    foreach($path in ($env:path -split ";")) {
        if ([regex]::escape($kansapath) -match [regex]::escape($path)) {
            $found = $True
        }
    }
    if (-not($found)) {
        $env:path = $env:path + ";$pwd\Analysis\ASEP;$pwd\Analysis\Meta;$pwd\Analysis\Net;$pwd\Analysis\Process;$pwd\Analysis\Log;"
    }
}


function Get-Analysis {
<#
.SYNOPSIS
Runs analysis scripts as specified in .\Analyais\Analysis.conf
Saves output to AnalysisReports folder under the output path
Fails silently, but logs errors to Error.log file
#>
Param(
    [Parameter(Mandatory=$True,Position=0)]
        [String]$OutputPath
)
    Write-Debug "Entering $($MyInvocation.MyCommand)"
    $Error.Clear()

    $AnalysisScripts = @()
    $AnalysisScripts = Get-Content .\Analysis\Analysis.conf | % { $_.Trim() } | ? { $_ -gt 0 -and (!($_.StartsWith("#"))) }

    $AnalysisOut = $OutputPath + "\AnalysisReports\"
    $Suppress = New-Item -Name $AnalysisOut -ItemType Directory -Force

    foreach($AnalysisScript in $AnalysisScripts) {
        $lineone = gc (".\Analysis\" + $AnalysisScript) -TotalCount 1
        if ($lineone -match 'DATADIR (.*)$') {
            $DataDir = $($matches[1])
            Push-Location
            "$OutputPath$DataDir"
            if (Set-Location "$OutputPath$DataDir") {
                & "..\..\Analysis\${AnalysisScript}" | Set-Content -Encoding $Encoding ("..\AnalysisReports\" + ($AnalysisScript -split ".ps1")[0])
                Pop-Location
            } else {
                "Analysis: No data found for ${AnalysisScript}." | Add-Content -Encoding $Encoding $ErrorLog
                Continue
            }
        } else {
            "Analysis script, .\Analysis\${AnalysisScript}, missing # DATADIR directive, skipping analysis." | Add-Content -Encoding $Encoding $ErrorLog
            Continue
        }
        

        # figure out where the data is for the given script
        # this will be hard, thinking of adding a comment
        # to the top of each analysis script indicating
        # the directory where the data will be, like a directive

        # move to that directory
        # execute the script and save the output to 
        # output directory        
        
    }
    # Non-terminating errors can be checked via
    if ($Error) {
        # Write the $Error to the $Errorlog
        $Error | Add-Content -Encoding $Encoding $ErrorLog
        $Error.Clear()
    }
    Write-Debug "Exiting $($MyInvocation.MyCommand)"    
} # End Get-Analysis


# Do not stop or report errors as a matter of course.   #
# Instead write them out the error.log file and report  #
# that there were errors at the end, if there were any. #
$Error.Clear()
$ErrorActionPreference = "SilentlyContinue"
$StartingPath = Get-Location


# Create timestamped output path. Write transcript and error log #
# to output path. Keep this first in the script so we can catch  #
# errors in the error log of the output directory. We may create #
$Runtime = ([String] (Get-Date -Format yyyyMMddHHmm))
$OutputPath = ".\Output_$Runtime\"
$Suppress = New-Item -Name $OutputPath -ItemType Directory -Force 

If ($Transcribe) {
    $TransFile = $OutputPath + ([string] (Get-Date -Format yyyyMMddHHmmss)) + ".log"
    $Suppress = Start-Transcript -Path $TransFile
}
Set-Variable -Name ErrorLog -Value ($OutputPath + "Error.Log") -Scope Script

if (Test-Path($ErrorLog)) {
    Remove-Item -Path $ErrorLog
}
# Done setting up output. #


# Set the output encoding #
if ($Ascii) {
    Set-Variable -Name Encoding -Value "Ascii" -Scope Script
} else {
    Set-Variable -Name Encoding -Value "Unicode" -Scope Script
}
# End set output encoding #


# Sanity check some parameters #
Write-Debug "Sanity checking parameters"
$Exit = $False
if (-not (Test-Path($ModulePath))) {
    "User supplied ModulePath, $ModulePath, was not found." | Add-Content -Encoding $Encoding $ErrorLog
    $Exit = $True
}
if ($TargetList -and -not (Test-Path($TargetList))) {
    "User supplied TargetList, $TargetList, was not found." | Add-Content -Encoding $Encoding $ErrorLog
    $Exit = $True
}
if ($TargetCount -lt 0) {
    "User supplied TargetCount, $TargetCount, was negative." | Add-Content -Encoding $Encoding $ErrorLog
    $Exit = $True
}
#TKTK Add test for $Credential
if ($Exit) {
    "One or more errors were encountered with user supplied arguments. Exiting." | Add-Content -Encoding $Encoding $ErrorLog
    Exit
}
Write-Debug "Parameter sanity check complete."
# End paramter sanity checks #


# Update the user's path with Kansa Analysis paths. #
# Exit if that's all they wanted us to do.          #
Set-KansaPath
if ($UpdatePath) {
    # User provided UpdatePath switch so
    # exit after updating the path
    Exit
}
# Done updating the path. #


# If we're -Debug, show some settings. #
Write-Debug "`$ModulePath is ${ModulePath}."
Write-Debug "`$OutputPath is ${OutputPath}."
Write-Debug "`$ServerList is ${TargetList}."


# Get our modules #
if ($ListModules) {
    # User provided ListModules switch so exit
    # after returning the full list of modules
    List-Modules $ModulePath
    Exit
}
# Get-Modules reads the modules.conf file, if
# it exists, otherwise will have same data as
# List-Modules command above.
$Modules = Get-Modules -ModulePath $ModulePath
# Done getting modules #


# Get our analysis scripts #
if ($ListAnalysis) {
    # User provided ListAnalysis switch so exit
    # after returning a list of analysis scripts
    List-Modules ".\Analysis\"
    Exit
}


# Get our targets. #
if ($TargetList) {
    $Targets = Get-Targets -TargetList $TargetList -TargetCount $TargetCount
} elseif ($Target) {
    $Targets = $Target
} else {
    Write-Verbose "No Targets specified. Building one requires RAST and will take some time."
    $suppress = Load-AD
    $Targets  = Get-Targets -TargetCount $TargetCount
}
# Done getting targets #


# Copy binaries to targets if requested #
if ($PushBin) {
    Push-Bindep -Targets $Targets -Modules $Modules -Credential $Credential
}
# Done pushing bins #


# Finally, let's gather some data. #
Get-TargetData -Targets $Targets -Modules $Modules -Credential $Credential -ThrottleLimit $ThrottleLimit
# Done gathering data. #

# Are we running analysis scripts? #
if ($Analysis) {
    Get-Analysis $OutputPath
}
# Done running analysis #


# Clean up #
Exit
# We're done. #

} Finally {
    Exit-Script
}