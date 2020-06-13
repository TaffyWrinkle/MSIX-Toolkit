############################
##  Variable Declaration  ##
############################

#Script Libraries required to run this script.
. $PSScriptRoot\batch_convert.ps1
. $PSScriptRoot\sign_deploy_run.ps1

$SupportedInstallerType = @("MSI")
$SupportedConfigMgrVersion = ""
$InitialLocation = Get-Location
$VerboseLogging = $true


##################################################################################
## Function: LogEntry
##
## Description:
##    Processes the information that it receives and translates it into a Trace32
##    style log file configured with the appropriate values
##################################################################################
Function New-LogEntry
{
Param(
    [Parameter(Position=0)] [string]$LogValue,
    [Parameter(Position=1)] [string]$Component = "",
    [Parameter(Position=2)] [int]$Severity = 1,
    [Parameter(Position=3)] [boolean]$WriteHost = $true,
    [string]$Path = $InitialLocation
)
    #Records previously existing execution location to return back afterwards.
    #$PreviousLocation = Get-Location

    #Sets the execution location to the FileSystem to allow for log entries to be made
    $PreviousLocation = Disconnect-CMEnvironment -ReturnPreviousLocation $true
    
    #Formats the values required to enter for Trace32 Format
    $TimeZoneBias = Get-WmiObject -Query "Select Bias from Win32_TimeZone"
    [string]$Time = Get-Date -Format "HH:mm:ss.ffff"
    [string]$Date = Get-Date -Format "MM-dd-yyyy"

    #Appends the newest log entry to the end of the log file in a Trace32 Formatting
    $('<![LOG['+$LogValue+']LOG]!><time="'+$Time+'" date="'+$Date+'" component="'+$component+'" context="Empty" type="'+$severity+'" thread="Empty" file="'+"Empty"+'">') | out-file -FilePath $($Path+"\MSIXConnect.log") -Append -NoClobber -encoding default

    IF($WriteHost)
    {
        Write-Host $LogValue -ForegroundColor $(switch ($Severity) {3 {"Red"} 2 {"Yellow"} 1 {"White"}})
    }

    #Returns to the original execution location
    Set-Location $PreviousLocation
}

Function Test-PSArchitecture
{
    If([intPtr]::size -eq 4) { New-LogEntry "PowerShell Architecture matches." -Component Test-PSArchitecture }
    ELSE { Throw "Incorrect PowerShell Architecture, please review ReadMe for requirements." }
}

function Connect-CMEnvironment ([Parameter(Mandatory=$True,HelpMessage="Please Enter CM SiteCode.",ParameterSetName=$('Execution'),Position=0)] [String]$CMSiteCode)
{
    Import-Module $ENV:SMS_ADMIN_UI_PATH.replace("bin\i386","bin\ConfigurationManager.psd1")
    New-LogEntry -LogValue "Connecting to the $($CMSiteCode) ConfigMgr PowerShell Environment..." -Component "Connect-CMEnvironment"

    $SiteLocation = Get-PSDrive -PSProvider CMSITE | Where-Object {$_.Name -eq $CMSiteCode}
    IF($SiteLocation)
    {
        Set-Location "$($SiteLocation):"
        IF($(Get-Location) -like "$($SiteLocation.Name)*") 
        {
            New-LogEntry -LogValue "Connected Successfully to $($CMSiteCode) ConfigMgr PowerShell Environment..." -Component "Connect-CMEnvironment"
            Return $True
        }
        else 
        {
            New-LogEntry -LogValue "Connection Failed..." -Component "Connect-CMEnvironment" -Severity 2
            Return $False
        }
    } 
    ELSE 
    { 
        New-LogEntry -LogValue "Could not identify ConfigMgr Site using ""$CMSiteCode"" Site Code." -Component "Connect-CMEnvironment" -Severity 2
        Return $False
    }
}

function Disconnect-CMEnvironment ([boolean]$ReturnPreviousLocation=$false)
{
    $PreviousLocation = Get-Location
    Set-Location $InitialLocation

    IF($ReturnPreviousLocation){Return $PreviousLocation}
}

Function Get-AppMetaData ([Parameter(Mandatory=$True, HelpMessage="Please provide the Name of the CM Application.", ParameterSetName=$('Execution'), Position=0)] [string]$AppName)
{
    $CMApplication = Get-CMApplication -Name $AppName
    $CMApplicationDeploymentTypes = Get-CMDeploymentType -InputObject $CMApplication
    
    New-LogEntry -LogValue "Collecting information from ConfigMgr for application: $AppName" -Component "Get-AppMetaData"
    $CMApplicationDeploymentTypes = Get-CMDeploymentType -InputObject $CMApplication
    $AppDetails = @()

    IF($($CMApplicationDeploymentTypes.count -le 1))
    { $XML = [XML]$($CMApplicationDeploymentTypes.SDMPackageXML) }
    else 
    { $XML = [XML]$($CMApplicationDeploymentTypes[0].SDMPackageXML) }
    
    Foreach($Deployment IN $($XML.AppMgmtDigest.DeploymentType))
    {
        New-LogEntry -LogValue "Parsing through the Deployment Types of $AppName application." -Component "Get-AppMetaData" -WriteHost $VerboseLogging

        $MSIXAppDetails = New-Object PSObject
        $XML = [XML]$($DeploymentType.SDMPackageXML)

        $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "PackageDisplayName" -Value $($CMApplication.LocalizedDisplayName)
        $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "PackageName" -Value $(Format-MSIXPackagingName -AppName $($CMApplication.LocalizedDisplayName))
        $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "PublisherName" -Value $("CN=" + $CMApplication.Manufacturer)
        $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "PublisherDisplayName" -Value $($CMApplication.Manufacturer)
        $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "PackageVersion" -Value $($CMApplication.SoftwareVersion)
        $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "AppDescription" -Value $($CMApplication.LocalizedDescription)
        $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "CMAppPackageID" -Value $($CMApplication.PackageID)
        $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "RequiresUserInteraction" -Value $($XML.AppMgmtDigest.DeploymentType.Installer.CustomData.RequiresUserInteraction)
        $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "AppFolderPath" -Value $($Deployment.Installer.Contents.Content.Location)
        $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "AppFileName" -Value $($Deployment.Installer.Contents.Content.File.Name)
        $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "AppIntallerType" -Value $($Deployment.Installer.Technology)
        $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "InstallerPath" -Value $("$($Deployment.Installer.Contents.Content.Location)" + "$($Deployment.Installer.Contents.Content.File.Name)")

        New-LogEntry -LogValue "Parsing Application: ""$($CMApplication.LocalizedDisplayName)"", currently recording information from ""$($DeploymentType.LocalizedDisplayName)"" Deployment Type." -Component "Get-AppMetaData" -WriteHost $VerboseLogging
     
        Foreach($Arg IN $($DeploymentInstaller.InstallAction.Args.Arg))
        {
            IF($Arg.Name -eq "InstallCommandLine") { $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "AppInstallString" -Value $($Arg.'#text') }
            IF($Arg.Name -eq "ExecutionContext")   { $MSIXAppDetails | Add-Member -MemberType NoteProperty -Name "ExecutionContext" -Value $($Arg.'#text') }
        }

        New-LogEntry -LogValue "Adding the following information to the App XML:`n`n$MSIXAppDetails" -Component "Get-AppMetaData" -WriteHost $VerboseLogging
        
        IF ($SupportedInstallerType.Contains($($Deployment.Installer.Technology)))
        {
            $AppDetails += $MSIXAppDetails
        }
        ELSE
        {
            New-LogEntry -LogValue "The ""$($CMApplication.LocalizedDisplayName)"" application type is currently unsupported." -Component "Get-AppMetaData" -Severity 3
        }
    }
    
    Return $AppDetails
}

<#
Requirements
    - Name must be 3 Characters long
    - No Special Charachters
#>

Function Format-MSIXPackagingName ([Parameter(Mandatory=$True,Position=0)] [string]$AppName)
{
    New-LogEntry -LogValue "Removing Special Characters from the Application Package Name.
    " -Component "Format-MSIXPackagingName" -Severity 1 -WriteHost $VerboseLogging
    $MSIXPackageName = $AppName -replace '[!,@,#,$,%,^,&,*,(,),+,=,~,`]',''
    $MSIXPackageName = $MSIXPackageName -replace '_','-'
    $MSIXPackageName = $MSIXPackageName -replace ' ','-'

    Return $MSIXPackageName
}


Function Validate-MSIXPackagingName ([Parameter(Mandatory=$True,Position=0)] [string]$AppName)
{
    New-LogEntry -LogValue "Validating that the name of the application does not contain any special characters. Special Characters include:`n`t!,@,#,$,%,^,&,*,(,),+,=,~,`, ,_" -Component "Validate-MSIXPackaingName" -WriteHost $VerboseLogging
    $SpecialCharacters = $($MSIXPackageName = $AppName -match '[!,@,#,$,%,^,&,*,(,),+,=,~,`, ,_]')

    IF($SpecialCharacters)
    {
        New-LogEntry -LogValue "The name does not contain any special characters." -Component "Validate-MSIXPackagingName" -WriteHost $VerboseLogging
        Return $SpecialCharacters
    }
    else
    {
        New-LogEntry -LogValue "Error: Name contains special characters - MSIX App Name does not support the use of special characters." -Component "Validate-MSIXPackagingName" -Severity 3
        Return $SpecialCharacters
    }

    Return $($MSIXPackageName = $AppName -match '[!,@,#,$,%,^,&,*,(,),+,=,~,`, ,_]')
}

Function New-MSIXConnectMakeApp ([Parameter(Mandatory=$True)] $SiteCode = "CM1", 
                                 [Parameter(Mandatory=$True)] $SiteServerServerName = "CL-CM01",
                                 [Parameter(Mandatory=$True)] $ApplicationName = "Notepad++")
{
    $VMcredential = Get-Credential
    IF(!$VMcredential)
    {
        New-LogEntry -LogValue "Failed to retrieve Credentials, exiting script..." -Component "New-MSIXConnectMakeApp" -Severity 3
        Return
    }

    $virtualMachines = @( @{ Name = "MSIX Packaging Tool Environment1"; credential = $VMcredential } )
    $remoteMachines =  @( @{ ComputerName = "YourVMNameHere.westus.cloudapp.azure.com"; Credential = $VMcredential } )

    Test-PSArchitecture
    IF(!$(Connect-CMEnvironment $SiteCode)) {Return}
    $MSIXAppMetaData = Get-AppMetaData $ApplicationName
    Disconnect-CMEnvironment

    $workingDirectory = [System.IO.Path]::Combine($PSScriptRoot, "out")

    RunConversionJobs -conversionsParameters $MSIXAppMetaData -virtualMachines $virtualMachines -remoteMachines $remoteMachines $workingDirectory

    SignAndDeploy "$workingDirectory\MSIX"

}