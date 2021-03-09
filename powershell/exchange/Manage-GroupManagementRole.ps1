# Script for creating a Role that can manage distributions groups but can't create new ones 
#  
################################################################################# 
#  
# The sample scripts are not supported under any Microsoft standard support  
# program or service. The sample scripts are provided AS IS without warranty  
# of any kind. Microsoft further disclaims all implied warranties including, without  
# limitation, any implied warranties of merchantability or of fitness for a particular  
# purpose. The entire risk arising out of the use or performance of the sample scripts  
# and documentation remains with you. In no event shall Microsoft, its authors, or  
# anyone else involved in the creation, production, or delivery of the scripts be liable  
# for any damages whatsoever (including, without limitation, damages for loss of business  
# profits, business interruption, loss of business information, or other pecuniary loss)  
# arising out of the use of or inability to use the sample scripts or documentation,  
# even if Microsoft has been advised of the possibility of such damages 
# 
################################################################################# 
# 
# Written by Matthew Byrd 
# Matbyrd@microsoft.com 
# Last Updated 10.15.09 
 
 
# Parameter to get a different name than default for the new Role 
Param([string]$name="MyDistributionGroupsManagement",[string]$policy="Default Role Assignment Policy",[switch]$creategroup,[switch]$removegroup) 
 
# Help Function 
Function Show-Help { 
 
" 
This script is will create or manage a management role designed to allow users to modify groups that they already own 
but not create or remove any new distribution groups. 
 
Switches: 
-name           Name of the managment role you want to create or modify 
                    Defaults to: `"MyDistributionGroupsManagmenet`" 
                     
-policy         Name of the Role Policy you want to assign the role to 
                    Defaults to: `"Default Role Assignement Policy`" 
                     
-creategroup    Adds or Removes the ability of the Role to Create DLs 
 
-removegroup    Adds or Removes the ability of the Role to Remove DLs 
 
Examples: 
-------------------------------------------- 
This will Use the default names and Policy and will create a role that cannot 
Create or remove groups but can still modify them.  If the role already exists 
It will modify it by removing or adding the abiltity to create and remove groups 
based on the current state. 
 
Manage-GroupManagementRole -CreateGroup -RemoveGroup 
 
" 
 
 
} 
 
 
 
# Function to modify a role by removing or adding Role Entries 
# If no action is passed we assume remove 
# $roleentry should be in the form Role\Roleentry e.g. MyRole\New-DistributionGroup 
Function ModifyRole { 
 Param($roleenty,$action) 
     
    Switch ($action){ 
        Add {Add-ManagementRoleEntry $roleenty -confirm:$false} 
        Remove {Remove-ManagementRoleEntry $roleenty -confirm:$false} 
        Default {Remove-ManagementRoleEntry $roleenty -confirm:$false} 
    } 
} 
 
If (($creategroup -eq $false) -and ($removegroup -eq $false)){ 
    Show-Help 
    exit 
} 
 
 
# Test if we have a role that already has that name 
If (([bool](Get-Managementrole $name -erroraction Silentlycontinue)) -eq $true){ 
    Write-Warning "Found a Role with Name: $name" 
    Write-Warning "Trying to Modify Existing Role" 
} 
Else { 
    # Create the new Management Role 
    Write-Host "Creating Managmenet Role $name" 
    New-ManagementRole -name $name -parent MyDistributionGroups 
} 
 
# Determine if we have the New and Remove Role Entries on the Role Already 
$create = [bool](Get-managementroleentry $name\New-DistributionGroup -erroraction Silentlycontinue) 
$remove = [bool](Get-managementroleentry $name\Remove-DistributionGroup -erroraction Silentlycontinue) 
 
# If we have the switch CreateGroup add or remove the RoleEntry for New-DistributionGroup 
If ($creategroup -eq $true){ 
    If ($create -eq $true){ModifyRole $name\New-DistributionGroup Remove;Write-Host "Removing ability to create distribution Groups from $name"} 
    elseif ($create -eq $false) {ModifyRole $name\New-DistributionGroup Add;Write-Host "Adding ability to create distribution Groups to $name"} 
} 
 
# If we have the switch RemoveGroup add or remove the RoleEntry for New-DistributionGroup 
If ($removegroup -eq $true){ 
    If ($remove -eq $true){ModifyRole $name\Remove-DistributionGroup Remove;Write-Host "Removing ability to create distribution Groups from $name"} 
    elseif ($remove -eq $false) {ModifyRole $name\Remove-DistributionGroup Add;Write-Host "Adding ability to create distribution Groups to $name"} 
} 
 
# Test if we have the assignment for the Role and Policy 
# If we do ... write a warning 
# If not create a new assignment 
If (([bool](get-managementroleassignment $name-$policy -erroraction SilentlyContinue)) -eq $true){ 
    Write-Warning "Found Existing Role Assignment: $name-$policy" 
    Write-Warning "Making no modifications to Role Assignments" 
} 
Else { 
    # Assign the Role to the Role Policy 
    Write-Host "Creating Managmenet Role Assignment $name-$policy" 
    New-ManagementRoleAssignment -name ($name + "-" + $policy) -role $name -policy $policy 
} 
 
