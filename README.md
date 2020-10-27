Azure - Enable Hybrid Use Benefit On All VMs in All Subscriptions
=================================================================

            

PowerShell script to automate Enabling Azure Hybrid Use Benefit on All Windows VMs in All Subscriptions. The default mode for the script is 'Simulate Mode', where no changes are made and Log and CSV Export files are generated, this shows 'What changes the
 script would make' if you run it in Update Mode (-SimulateMode $False as script paramerter).


It is your own responsibility to make sure you / your organisation hold the required 'Windows Server with Software Assurance' licences to enable Azure Hybrid Use Benefit. 


 



**Script:**

**    Version:    1.1.0    Created:    20/11/2017    Updated:   16/10/2018**


 
**Update History:
**

**1.1.0** - 16th October 2018 - Updated script to provide better error handling for VMs that are not compatible with Azure HUB.


**1.0.2** - 7th March 2018 - First version published on TechNet Gallery


 


 


** *** *


**Dependencies:**

**AzureRM Module v3.2 or above **


 

**

PowerShell
#Install the Azure Resource Manager modules from the PowerShell Gallery 
Install-Module -Name AzureRM

#Or if already installed, Update the Azure Resource Manager modules from the PowerShell Gallery 
Update-Module -Name AzureRM

**

 **Syntax Examples:**


 

**

PowerShell
**# Simulate  Mode: **
.\azure-enable-hybrid-use-on-all-vms.ps1 

 

**# Update Mode, Process All Subscriptions (*shows a prompt to confirm enabling HUB per subscription*):**
.\azure-enable-hybrid-use-on-all-vms.ps1 -SimulateMode $False

 


**# Update Mode, Single Subscription :**
.\azure-enable-hybrid-use-on-all-vms.ps1 -SimulateMode $False -SubscriptionName 'My Subscription Name'

 


**# Update Mode, Process All Subscriptions, Unique CSV File Names and Specify Export Folder Path:**
.\azure-enable-hybrid-use-on-all-vms.ps1 -SimulateMode $False -CSVUniqueFileNames -OutputFolderPath 'C:\CSVExportFolder'




 


**Additional Information:**

**

**[https://blogs.technet.microsoft.com/ukplatforms/2018/03/07/azure-cost-optimisation-series-enable-hybrid-use-benefit-hub-using-powershell]( https://blogs.technet.microsoft.com/ukplatforms/2018/03/07/azure-cost-optimisation-series-enable-hybrid-use-benefit-hub-using-powershell)**



        
    
TechNet gallery is retiring! This script was migrated from TechNet script center to GitHub by Microsoft Azure Automation product group. All the Script Center fields like Rating, RatingCount and DownloadCount have been carried over to Github as-is for the migrated scripts only. Note : The Script Center fields will not be applicable for the new repositories created in Github & hence those fields will not show up for new Github repositories.
