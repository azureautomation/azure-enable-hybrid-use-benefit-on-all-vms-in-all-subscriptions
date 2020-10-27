##########################################################################################################
<#
.SYNOPSIS
    Author:     Neil Bird, MSFT
    Version:    1.1.0
    Created:    20/11/2017
    Updated:    16/10/2018

.DESCRIPTION
    This script automates the process of enabling Azure Hybrid Use Benefit on all Windows VMs in All Subscriptions.
    
    The script updates the "LicenseType" of all Windows VMs in a given subscription, thus enabling Azure HUB.
    It excludes non-Windows Operating Systems and provides logging and totals for number of VMs that have been
    updated.

    Update: 16th October 2018 to allow better handling of Update-AzureRM failures. 

.EXAMPLE
    To run in Simulate mode (default), run the script with no parameters:

        .\azure-enable-hybrid-use-on-all-vms.ps1
    
    To run in Update mode, pass the the "-SimulateMode" parameter "$False" 

        .\azure-enable-hybrid-use-on-all-vms.ps1 -SimulateMode $False

.NOTES
    THIS CODE-SAMPLE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED 
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR 
    FITNESS FOR A PARTICULAR PURPOSE.

    This sample is not supported under any Microsoft standard support program or service. 
    The script is provided AS IS without warranty of any kind. Microsoft further disclaims all
    implied warranties including, without limitation, any implied warranties of merchantability
    or of fitness for a particular purpose. The entire risk arising out of the use or performance
    of the sample and documentation remains with you. In no event shall Microsoft, its authors,
    or anyone else involved in the creation, production, or delivery of the script be liable for 
    any damages whatsoever (including, without limitation, damages for loss of business profits, 
    business interruption, loss of business information, or other pecuniary loss) arising out of 
    the use of or inability to use the sample or documentation, even if Microsoft has been advised 
    of the possibility of such damages, rising out of the use of or inability to use the sample script, 
    even if Microsoft has been advised of the possibility of such damages. 

#>
##########################################################################################################

###############################
## SCRIPT OPTIONS & PARAMETERS
###############################

#Requires -Version 3
#Requires -Modules AzureRM

# Define and validate parameters
[CmdletBinding()]
Param(
	    # Optional. Azure Subscription Name, if you want to Scan or Update a single subscription use this parameter
	    [parameter(Position=1)]
	    [string]$SubscriptionName = "SUBSCRIPTION NAME",
	          
        # Set $SimulateMode = $True as Default, this will generate a report of WHAT WOULD HAPPEN, no changes are made to VMs
        # Set $SimulateMode = $False using Script Parameter if you only want update VMs
	    [parameter(Position=2)]
	    [bool]$SimulateMode = $True,

	    # Folder Path for Output, if not specified defaults to script folder
	    [parameter(Position=3)]
        [string]$OutputFolderPath = "FOLDERPATH",
        # Exmaple: C:\Scripts\

        # Unique file names for CSV files, optional Switch parameter as the script defaults to same file name
	    [parameter(Position=4)]
        [switch]$CSVUniqueFileNames

	)

# Set strict mode to identify typographical errors
Set-StrictMode -Version Latest

# Set Error and Warning action preferences
$ErrorActionPreference = "Stop"
$WarningPreference = "Stop"


##########################################################################################################


###################################
## FUNCTION 1 - Out-ToHostAndFile
###################################
# Function used to create a transcript of output, this is in addition to CSVs.
###################################
Function Out-ToHostAndFile {

    Param(
	    # Azure Subscription Name, can be passed as a Parametery or edit variable below
	    [parameter(Position=0,Mandatory=$True)]
	    [string]$Content,

        [parameter(Position=1)]
        [string]$FontColour,

        [parameter(Position=2)]
        [switch]$NoNewLine
    )

    # Write Content to Output File
    if($NoNewLine.IsPresent) {
        
        try {
            Out-File -FilePath $OutputFolderFilePath -Encoding UTF8 -Append -InputObject $Content -NoNewline -ErrorAction $ErrorActionPreference
        } catch [System.Management.Automation.CmdletInvocationException] {
            # being used by another process. ---> System.IO.IOException
            # timing issue with locked file, attempt to write again
            Start-Sleep -Milliseconds 250
            Out-File -FilePath $OutputFolderFilePath -Encoding UTF8 -Append -InputObject $Content -NoNewline -ErrorAction $ErrorActionPreference
        }

    } else {

        try {
            Out-File -FilePath $OutputFolderFilePath -Encoding UTF8 -Append -InputObject $Content -ErrorAction $ErrorActionPreference
        } catch [System.Management.Automation.CmdletInvocationException] {
            # being used by another process. ---> System.IO.IOException
            # timing issue with locked file, attempt to write again
            Start-Sleep -Milliseconds 250
            Out-File -FilePath $OutputFolderFilePath -Encoding UTF8 -Append -InputObject $Content -ErrorAction $ErrorActionPreference
        }

    }

    if([string]::IsNullOrWhiteSpace($FontColour)){
        $FontColour = "White"
    }

    if($NoNewLine.IsPresent) {
        Write-Host $Content -ForegroundColor $FontColour -NoNewline
    } else {
        Write-Host $Content -ForegroundColor $FontColour
    }
    

}

#######################################
## FUNCTION 2 - Set-OutputLogFiles
#######################################
# Generate unique log file names
#######################################
Function Set-OutputLogFiles {

    [string]$FileNameDataTime = Get-Date -Format "yy-MM-dd_HHmmss"
            
    # Default to script folder, or user profile folder.
    if([string]::IsNullOrWhiteSpace($script:MyInvocation.MyCommand.Path)){
        $ScriptDir = "."
    } else {
        $ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
    }

    if($OutputFolderPath -eq "FOLDERPATH") {
        # OutputFolderPath param not used
        $OutputFolderPath = $ScriptDir
        $script:OutputFolderFilePath = "$($ScriptDir)\azure-enable-hybrid-use-on-all-vms_$($FileNameDataTime).log"

    } else {
        # OutputFolderPath param has been set, test it is valid
        if(Test-Path($OutputFolderPath)){
            # Specified folder is valid, use it.
            $script:OutputFolderFilePath = "$OutputFolderPath\azure-enable-hybrid-use-on-all-vms_$($FileNameDataTime).log"

        } else {
            # Folder specified is not valid, default to script or user profile folder.
            $OutputFolderPath = $ScriptDir
            $script:OutputFolderFilePath = "$($ScriptDir)\azure-enable-hybrid-use-on-all-vms_$($FileNameDataTime).log"

        }
    }

    #CSV Output File Paths, can be unique depending on boolean flag
    if($CSVUniqueFileNames.IsPresent) {
        $script:OutputFolderFilePathCSV = "$OutputFolderPath\azure-enable-hybrid-use-audit-report_$($FileNameDataTime).csv"
    } else {
        $script:OutputFolderFilePathCSV = "$OutputFolderPath\azure-enable-hybrid-use-audit-report.csv"
    }
}



#######################################
## FUNCTION 3 - Get-AzurePSConnection
#######################################

Function Get-AzurePSConnection {

    if ($SimulateMode) {
        $GridViewTile = "Select the subscription to Simulate Enabling Azure Hybrid Use Benefit"
    } else {
        $GridViewTile = "Select the subscription to Enable Azure Hybrid Use Benefit" 
    }

    # If $SubscriptionName Parameter has not been passed as an argument or edited in the script Params.
    if($SubscriptionName -eq "SUBSCRIPTION NAME") {
        
        Try {

            # Select the first subscription
            $AzureRMContext = (Get-AzureRmSubscription -ErrorAction $ErrorActionPreference | Select-Object -First 1)
                        
            Try {
                Set-AzureRmContext -TenantId $AzureRMContext.TenantID -SubscriptionName $AzureRMContext.Name -ErrorAction $ErrorActionPreference -WarningAction $WarningPreference    
            } Catch [System.Management.Automation.PSInvalidOperationException] {
                Write-Error "Error: $($error[0].Exception)"
                Exit
            }
    
        } Catch {
            
            # If not logged into Azure
            if($error[0].Exception.ToString().Contains("Run Login-AzureRmAccount to login.")) {
                    
                # Login to Azure
                Login-AzureRMAccount -ErrorAction $ErrorActionPreference
                
                # Select the first subscription
                $AzureRMContext = (Get-AzureRmSubscription -ErrorAction $ErrorActionPreference | Select-Object -First 1)
                
                Try {
                    Set-AzureRmContext -TenantId $AzureRMContext.TenantID -SubscriptionName $AzureRMContext.Name -ErrorAction $ErrorActionPreference -WarningAction $WarningPreference    
                } Catch [System.Management.Automation.PSInvalidOperationException] {
                    Write-Error "Error: $($error[0].Exception)"
                    Exit
                }
    
            } else { # Not Logged In, error
    
                Write-Error "Error: $($error[0].Exception)"
                Exit
    
            }
        }
    
    } else { # $SubscriptionName has been specified
    
        # Check if we are already logged into Azure...
        Try {
                
            # Set Azure RM Context to -SubscriptionName, On Error Stop, so we can Catch the Error.
            Set-AzureRmContext -SubscriptionName $SubscriptionName -WarningAction $WarningPreference -ErrorAction $ErrorActionPreference

        } Catch {
            
            # If not logged into Azure
            if($error[0].Exception.ToString().Contains("Run Login-AzureRmAccount to login.")) {
                    
                # Connect to Azure, as no existing connection.
                Out-ToHostAndFile "No Azure PowerShell Session found"
                Out-ToHostAndFile  "`nPrompting for Azure Credentials and Authenticating..."
    
                # Login to Azure Resource Manager (ARM), if this fails, stop script.
                try {
                    Login-AzureRMAccount -SubscriptionName $SubscriptionName -ErrorAction $ErrorActionPreference
                } catch {

                    # Authenticated with Azure, but does not have access to subscription.
                    if($error[0].Exception.ToString().Contains("does not have access to subscription name")) {
        
                        Out-ToHostAndFile "Error: Unable to access Azure Subscription: '$($SubscriptionName)', please check this is the correct name and/or that your account has access.`n" "Red"
                        Out-ToHostAndFile "`nDisplaying GUI to select the correct subscription...."
                        
                        Login-AzureRmAccount -ErrorAction $ErrorActionPreference

                        $AzureRMContext = (Get-AzureRmSubscription -ErrorAction $ErrorActionPreference | Out-GridView `
                        -Title $GridViewTile `
                        -PassThru)
                        
                        Try {
                            Set-AzureRmContext -TenantId $AzureRMContext.TenantID -SubscriptionName $AzureRMContext.Name -ErrorAction $ErrorActionPreference -WarningAction $WarningPreference    
                        } Catch [System.Management.Automation.PSInvalidOperationException] {
                            Out-ToHostAndFile "Error: $($error[0].Exception)" "Red"
                            Exit
                        }
                    }
                }  
                 
            # Already logged into Azure, but Subscription does NOT exist.
            } elseif($error[0].Exception.ToString().Contains("Please provide a valid tenant or a valid subscription.")) {
                
                Out-ToHostAndFile "Error: You are logged into Azure with account: '$((Get-AzureRmContext).Account.id)', but the Subscription: '$($SubscriptionName)' does not exist, or this account does not have access to it.`n" "Red"
                Out-ToHostAndFile "`nDisplaying GUI to select the correct subscription...."
                
                $AzureRMContext = (Get-AzureRmSubscription -ErrorAction $ErrorActionPreference | Out-GridView `
                -Title $GridViewTile `
                -PassThru)
    
                Try {
                    Set-AzureRmContext -TenantId $AzureRMContext.TenantID -SubscriptionName $AzureRMContext.Name -ErrorAction $ErrorActionPreference -WarningAction $WarningPreference    
                } Catch [System.Management.Automation.PSInvalidOperationException] {
                    Out-ToHostAndFile "Error: $($error[0].Exception)" "Red"
                    Exit
                }     
                
            # Already authenticated with Azure, but does not have access to subscription.
            } elseif($error[0].Exception.ToString().Contains("does not have access to subscription name")) {
    
                Out-ToHostAndFile "Error: Unable to access Azure Subscription: '$($SubscriptionName)', please check this is the correct name and/or that account '$((Get-AzureRmContext).Account.id)' has access.`n" "Red"
                Exit
    
            # All other errors.
            } else {
            
                Out-ToHostAndFile "Error: $($error[0].Exception)" "Red"
                # Exit script
                Exit
    
            } # EndIf Checking for $error[0] conditions
    
        } # End Catch
    
    } # EndIf $SubscriptionName has been set
    
    $Script:ActiveSubscriptionName = (Get-AzureRmContext).Subscription.Name
    $Script:ActiveSubscriptionID = (Get-AzureRmContext).Subscription.Id

    # Successfully logged into AzureRM
    Out-ToHostAndFile "SUCCESS: " "Green" -nonewline; `
    Out-ToHostAndFile "Logged into Azure using Account ID: " -NoNewline; `
    Out-ToHostAndFile (Get-AzureRmContext).Account.Id "Green"
    Out-ToHostAndFile " "
    Out-ToHostAndFile "Subscription Name: " -NoNewline; `
    Out-ToHostAndFile $Script:ActiveSubscriptionName "Green"
    Out-ToHostAndFile "Subscription ID: " -NoNewline; `
    Out-ToHostAndFile $Script:ActiveSubscriptionID "Green"
    Out-ToHostAndFile " "
    
} # End of function Login-To-Azure


###############################################
## FUNCTION 4 - Export-ReportDataCSV
###############################################
function Export-ReportDataCSV
{
    param (
        [Parameter(Position=0,Mandatory=$true)]
        $HashtableOfData,

        [Parameter(Position=1,Mandatory=$true)]
        $FullFilePath
    )

	# Create an empty Array to hold Hash Table
	$Data = @()
	$Row = New-Object PSObject
	$HashtableOfData.GetEnumerator() | ForEach-Object {
		# Loop Hash Table and add to PSObject
		$Row | Add-Member NoteProperty -Name $_.Name -Value $_.Value
    }

	# Assign PSObject to Array
	$Data = $Row

	# Export Array to CSV
    try {
        $Data | Export-CSV -Path $FullFilePath -Encoding UTF8 -NoTypeInformation -Append -Force -ErrorAction $ErrorActionPreference
    } catch {
        # On first error, attempt to write again
        $Data | Export-CSV -Path $FullFilePath -Encoding UTF8 -NoTypeInformation -Append -Force -ErrorAction $ErrorActionPreference
    }
}

###############################################
## FUNCTION 5 - Enable-AzureHybridUseBenefit
###############################################
function Enable-AzureHybridUseBenefit {

    # Setup counters for Extension installation results
    [double]$Script:SuccessCount = 0
    [double]$Script:FailedCount = 0
    [double]$Script:AlreadyHUBCount = 0
    [double]$Script:VMNotCompatibleCount = 0

    # If $SubscriptionName Parameter has not been passed as an argument or edited in the script Params.
    if($SubscriptionName -eq "SUBSCRIPTION NAME") {

        # Get all Subscriptions
        [array]$AzureSubscriptions = Get-AzureRmSubscription -ErrorAction $ErrorActionPreference

    } else {
        # Use the subscription that has been selected from the 'Get-AzurePSConnection' function
        [array]$AzureSubscriptions = (Get-AzureRmContext).Subscription
    }

    $SubscriptionCount = 0

    # Loop Subscriptions
    ForEach($AzureSubscription in $AzureSubscriptions) {

        $SubscriptionCount++

        Out-ToHostAndFile "`nProcessing Azure Subscription: " -NoNewLine
        Out-ToHostAndFile "$SubscriptionCount of $($AzureSubscriptions.Count) `n" "Green"

        Out-ToHostAndFile "Subscription Name = " -NoNewLine
        Out-ToHostAndFile """$($AzureSubscription.Name)""`n" "Yellow"

        $Script:ActiveSubscriptionName = $AzureSubscription.Name
        $Script:ActiveSubscriptionID = $AzureSubscription.Id

        if($SimulateMode) {
            # Simulate Mode True
            Out-ToHostAndFile "INFO: " "Yellow" -NoNewLine
            Out-ToHostAndFile "Simulate Mode Enabled" "Green" -NoNewLine
            Out-ToHostAndFile " - No updates will be performed."
            Out-ToHostAndFile " "
            
            $UserConfirmation = Read-Host -Prompt "Do you want to SIMULATE Enabling Azure Hybrid Use Benefits (HUB) on ALL Windows Virtual Machines in the Subscription above? `n`nType 'yes' to confirm...."

        } else {
            # Simulate Mode False 
            Out-ToHostAndFile "INFO: " "Yellow" -NoNewLine
            Out-ToHostAndFile "Simulate Mode DISABLED - Updates will be performed." "Green"
            Out-ToHostAndFile " "
                  
            $UserConfirmation = Read-Host -Prompt "Do you want to Enable Azure Hybrid Use Benefits (HUB) on ALL Windows Virtual Machines in the Subscription above? `n`nType 'yes' to confirm...."

        }

        If($UserConfirmation.ToLower() -ne 'yes')
        {
            Out-ToHostAndFile "`nUser typed ""$($UserConfirmation)"", skipping this Subscription...."
            Out-ToHostAndFile " "
            # use 'Continue' statement to skip this item in the ForEach Loop
            Continue
        } else {
            Out-ToHostAndFile "`nUser typed 'yes' to confirm...."
            Out-ToHostAndFile " "
        }
        
        # Set AzureRMContext as we are in a ForEach Loop
        Out-ToHostAndFile "Set-AzureRmContext " "Yellow" -NoNewLine
        Out-ToHostAndFile "-SubscriptionId " -NoNewLine
        Out-ToHostAndFile "$($AzureSubscription.Id)" "Cyan"

        Set-AzureRmContext -SubscriptionId $AzureSubscription.Id

        # Reset Resource Group Counter for progress bar
        $RGProgress = 0
        
        # Get ALL Resource Groups in this Subscription
        [array]$ResourceGroups = (Get-AzureRmResourceGroup -ErrorAction $ErrorActionPreference).ResourceGroupName

        if($ResourceGroups) {

            # Loop through each Resource Group
            ForEach($ResourceGroup in $ResourceGroups) {

                # Show the Progress bar for Resouce Groups...
                $RGProgress++    
                Write-Progress -Activity "Processing Resource Groups in ""$($AzureSubscription.Name)""..." `
                -Status "Processed: $RGProgress of $($ResourceGroups.count)" `
                -PercentComplete (($RGProgress / $ResourceGroups.Count)*100)
                
                Out-ToHostAndFile "`nProcessing Resouce Group: $ResourceGroup"
                
                # Get ALL virtual machines in the given Resource Group
                [array]$RmVMs = Get-AzureRmVM -ResourceGroupName $ResourceGroup -ErrorAction $ErrorActionPreference -WarningAction $WarningPreference

                if($RmVMs) {
        
                    # Loop through each VM in this Resource Group
                    ForEach($RmVM in $RmVMs) {

                        # Create New Ordered Hash Table to store VM details
                        $VMHUBOutput = [ordered]@{}
                        $VMHUBOutput.Add("Resource Group",$ResourceGroup)
                        $VMHUBOutput.Add("VM Name",$RmVM.Name)
                        $VMHUBOutput.Add("VM Size",$RmVM.HardwareProfile.VmSize)
                        $VMHUBOutput.Add("VM Location",$RmVM.Location)
                        $VMHUBOutput.Add("OS Type",$RmVM.StorageProfile.OsDisk.OsType)

                        # If the VM is a Windows VM
                        if($RmVM.StorageProfile.OsDisk.OsType -eq "Windows") {

                            # If HUB is NOT enabled
                            if(($RmVM.LicenseType -ne "Windows_Server") -and ($RmVM.LicenseType -ne "Windows_Client")) {

                                if($SimulateMode) {
                                    
                                    # $SimulateMode set to $True (default), No Updates will be performed
                                    Out-ToHostAndFile "`tINFO: " "Green" -NoNewLine; `
                                    Out-ToHostAndFile "Would Enable HUB on VM: $($RmVM.Name)"
                                    $VMHUBOutput.Add("HUB Enabled","No")
                                    $VMHUBOutput.Add("Script Action","Script would Enable HUB")
                                    # Increment counter, for reporting only
                                    $Script:SuccessCount++

                                } else {

                                    # $SimulateMode set to $False, updates will be performed
                                    Out-ToHostAndFile "`tUpdating $($RmVM.Name)..."
                                    
                                    $RmVM.LicenseType = "Windows_Server"
                                    
                                    $AzureHUB = (Update-AzureRmVM -ResourceGroupName $ResourceGroup -VM $RmVM -ErrorVariable UpdateVMFailed -ErrorAction SilentlyContinue)
                                    
                                    if($UpdateVMFailed) {
                                        # Failed to enabled HUB, unhandled error
                                        $Script:FailedCount++
                                        Out-ToHostAndFile "`tERROR: " "Red" -NoNewLine
                                        Out-ToHostAndFile "`t$($RmVM.Name) - Failed to set LicenseType..."
                                        Out-ToHostAndFile "`tError: $($UpdateVMFailed.Exception)"
                                        $VMHUBOutput.Add("HUB Enabled","No")
                                        $VMHUBOutput.Add("Script Action","Failed to set LicenseType: $($UpdateVMFailed.Exception)")

                                    } else {

                                        if($AzureHUB.IsSuccessStatusCode -eq $True) {
                                    
                                            # Successfully enabled HUB
                                            $Script:SuccessCount++
                                            Out-ToHostAndFile "`tSUCCESS: " "Green" -NoNewLine; `
                                            Out-ToHostAndFile "$($RmVM.Name) LicenseType set to Enable HUB"
                                            $VMHUBOutput.Add("HUB Enabled","Yes")
                                            $VMHUBOutput.Add("Script Action","HUB Enabled Successfully")
                                        
                                        } elseif($AzureHUB.StatusCode.value__ -eq 409) {
                                        
                                            $Script:VMNotCompatibleCount++
                                            # Marketplace VM Image with additional software, such as SQL Server
                                            # See Notes Section at top of this page for reference on 409 Error:
                                            # https://docs.microsoft.com/en-us/azure/virtual-machines/windows/hybrid-use-benefit-licensing
                                            Out-ToHostAndFile "`tINFO: " "Yellow" -NoNewline
                                            Out-ToHostAndFile "$($RmVM.Name) is NOT compatible with Azure HUB"
                                            $VMHUBOutput.Add("HUB Enabled","No")
                                            $VMHUBOutput.Add("Script Action","Marketplace VM, NOT compatible with Azure HUB")
                                            
                                        } else {

                                            # Failed to enabled HUB, unhandled error
                                            $Script:FailedCount++
                                            Out-ToHostAndFile "`tERROR: " "Red" -NoNewLine
                                            Out-ToHostAndFile "`t$($RmVM.Name) - Failed to set LicenseType..."
                                            Out-ToHostAndFile "`tStatusCode = $AzureHUB.StatusCode ReasonPhrase = $AzureHUB.ReasonPhrase"
                                            $VMHUBOutput.Add("HUB Enabled","No")
                                            $VMHUBOutput.Add("Script Action","Failed to set LicenseType: $($AzureHUB.StatusCode)")

                                        }
                                    }
                                }

                            } else {

                                # HUB LicenseType already enabled
                                $Script:AlreadyHUBCount++
                                Out-ToHostAndFile "`tINFO: " "Yellow" -NoNewline
                                Out-ToHostAndFile "$($RmVM.Name) already has HUB LicenseType Enabled"
                                $VMHUBOutput.Add("HUB Enabled","Yes")
                                $VMHUBOutput.Add("Script Action","HUB LicenseType Already Enabled")
                            }

                        } elseif($RmVM.StorageProfile.OsDisk.OsType -eq "Linux") {
                            
                            # Linux VM
                            $Script:VMNotCompatibleCount++
                            Out-ToHostAndFile "`tINFO: " "Yellow" -NoNewline
                            Out-ToHostAndFile "$($RmVM.Name) is running a Linux OS"
                            $VMHUBOutput.Add("HUB Enabled","No")
                            $VMHUBOutput.Add("Script Action","Linux VM, NOT compatible with Azure HUB")

                        } else {

                            # Non-Windows / Non-Linux VM
                            $Script:VMNotCompatibleCount++
                            Out-ToHostAndFile "`tINFO: " "Yellow" -NoNewline
                            Out-ToHostAndFile "$($RmVM.Name) is NOT running a $($RmVM.StorageProfile.OsDisk.OsType) OS"
                            $VMHUBOutput.Add("HUB Enabled","No")
                            $VMHUBOutput.Add("Script Action","Non-Windows VM, NOT compatible with Azure HUB")
                        }

                        # Add Subscription Name and Subscription ID
                        $VMHUBOutput.Add("Subscription Name",$Script:ActiveSubscriptionName)
                        $VMHUBOutput.Add("Subscription ID",$Script:ActiveSubscriptionID)

                        # Export VM to CSV File
                        Export-ReportDataCSV $VMHUBOutput $script:OutputFolderFilePathCSV 

                    } # ForEach VM

                } else {

                    Out-ToHostAndFile "`n`tINFO: No ARM VMs deployed in this ResourceGroup."

                } # If a VM exist
            } # Foreach ResourceGroup
        } # If ResourceGroups exist 
    } # Foreach Subscriptions

    # Add up all of the counters
    [double]$TotalVMsProcessed = $Script:SuccessCount + $Script:FailedCount + $Script:AlreadyHUBCount `
    + $Script:VMNotCompatibleCount

    # Output Extension Installation Results
    Out-ToHostAndFile " "
    Out-ToHostAndFile "====================================================================="
    Out-ToHostAndFile "`tEnable Azure HUB LicenseType Results`n" "Green"
    if($SimulateMode) { 
        Out-ToHostAndFile "Would have HUB Enabled:`t`t$($Script:SuccessCount)"
    } else {
        Out-ToHostAndFile "Enabled Successfully:`t`t$($Script:SuccessCount)"
    }
    Out-ToHostAndFile "Already Enabled:`t`t$($Script:AlreadyHUBCount)"
    Out-ToHostAndFile "Failed to Enable:`t`t$($Script:FailedCount)"
    Out-ToHostAndFile "Not Compatible with HUB:`t$($Script:VMNotCompatibleCount)`n"
    Out-ToHostAndFile "Total VMs Processed:`t`t$($TotalVMsProcessed)"
    Out-ToHostAndFile "=====================================================================`n`n"

}

#######################################################
# Start PowerShell Script
#######################################################


Set-OutputLogFiles

[string]$DateTimeNow = Get-Date -Format "dd/MM/yyyy - HH:mm:ss"
Out-ToHostAndFile "=====================================================================`n"
Out-ToHostAndFile "$($DateTimeNow) - Enable HUB LicenseType Script Starting...`n"
Out-ToHostAndFile "====================================================================="
Out-ToHostAndFile " "

Get-AzurePSConnection

Enable-AzureHybridUseBenefit

[string]$DateTimeNow = get-date -Format "dd/MM/yyyy - HH:mm:ss"
Out-ToHostAndFile "=====================================================================`n"
Out-ToHostAndFile "$($DateTimeNow) - Enable HUB LicenseType Script Complete`n"
Out-ToHostAndFile "====================================================================="
Out-ToHostAndFile " "