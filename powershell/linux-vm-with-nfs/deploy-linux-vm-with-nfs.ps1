#Requires -Version 7.0
#Requires -Modules Az.Compute, Az.Network, Az.NetAppFiles, Az.Resources

<#
.SYNOPSIS
    Deploy a Linux VM with mounted NFS volume

.DESCRIPTION
    This script creates a complete solution with:
    - Virtual network and subnets (VM and NetApp Files)
    - Linux virtual machine (Ubuntu 18.04-LTS)
    - NFS volume automatically mounted to the VM
    - Network security group configuration
    - Public IP for remote access

.PARAMETER ResourceGroupName
    Name of the resource group to create or use

.PARAMETER Location
    Azure region for all resources (default: East US)

.PARAMETER VmName
    Name of the virtual machine

.PARAMETER AdminUsername
    Username for the Virtual Machine

.PARAMETER AdminPassword
    Password for the Virtual Machine (secure string)

.PARAMETER VmSize
    Size of the virtual machine (default: Standard_D2s_v3)

.PARAMETER NetAppVolumeName
    Name of the NetApp volume

.PARAMETER NetAppVolumeSize
    Size of the NetApp volume in GB (default: 100)

.PARAMETER NetAppServiceLevel
    Service level for the NetApp volume (Standard, Premium, Ultra)

.PARAMETER VnetName
    Name of the virtual network

.PARAMETER ProjectName
    Project name for tagging and resource management

.EXAMPLE
    $password = ConvertTo-SecureString "your-secure-password-here" -AsPlainText -Force
    .\deploy-linux-vm-with-nfs.ps1 -ResourceGroupName "rg-myproject-vm" -AdminUsername "azureuser" -AdminPassword $password

.EXAMPLE
    $password = ConvertTo-SecureString "your-secure-password-here" -AsPlainText -Force
    .\deploy-linux-vm-with-nfs.ps1 -ResourceGroupName "rg-prod-vm" -VmName "prod-linux-vm" -AdminUsername "admin" -AdminPassword $password -NetAppVolumeSize 500 -Location "West US 2"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "East US",
    
    [Parameter(Mandatory = $false)]
    [string]$VmName = "linuxVM",
    
    [Parameter(Mandatory = $true)]
    [string]$AdminUsername,
    
    [Parameter(Mandatory = $true)]
    [SecureString]$AdminPassword,
    
    [Parameter(Mandatory = $false)]
    [string]$VmSize = "Standard_D2s_v3",
    
    [Parameter(Mandatory = $false)]
    [string]$NetAppVolumeName = "anf-vol1",
    
    [Parameter(Mandatory = $false)]
    [int]$NetAppVolumeSize = 100,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Standard", "Premium", "Ultra")]
    [string]$NetAppServiceLevel = "Standard",
    
    [Parameter(Mandatory = $false)]
    [string]$VnetName = "vnet",
    
    [Parameter(Mandatory = $false)]
    [string]$ProjectName = "dev"
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Generate unique names
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$netappAccountName = "netapp-$($ProjectName)-$timestamp"
$netappPoolName = "netapppool"
$subnetNameVM = "vmSubnet"
$subnetNameNetApp = "netappSubnet"
$nsgName = "nsg-$VmName"
$pipName = "pip-$VmName"
$nicName = "nic-$VmName"

# Network configuration
$vnetAddressPrefix = "10.0.0.0/16"
$vmSubnetPrefix = "10.0.1.0/24"
$netappSubnetPrefix = "10.0.2.0/24"

# Common tags
$commonTags = @{
    Project = $ProjectName
    CreatedBy = "PowerShell"
    CreatedOn = (Get-Date).ToString("yyyy-MM-dd")
    ANF_PLG = "true"
    ANF_Template_Version = "1.0.0"
    ANF_Deployment_ID = (Get-Date).ToString("yyyyMMdd-HHmmss")
}

Write-Host "Starting Linux VM with NFS deployment..." -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host "VM Name: $VmName" -ForegroundColor Yellow
Write-Host "Location: $Location" -ForegroundColor Yellow
Write-Host "Volume Name: $NetAppVolumeName" -ForegroundColor Yellow
Write-Host "Volume Size: $NetAppVolumeSize GB" -ForegroundColor Yellow

try {
    # Check if logged into Azure
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "Not logged into Azure. Please run Connect-AzAccount first."
        exit 1
    }
    
    Write-Host "Connected to Azure subscription: $($context.Subscription.Name)" -ForegroundColor Green
    
    # Create or get resource group
    Write-Host "Creating/Getting resource group..." -ForegroundColor Cyan
    $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $resourceGroup) {
        $resourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag $commonTags
        Write-Host "Created resource group: $ResourceGroupName" -ForegroundColor Green
    } else {
        Write-Host "Using existing resource group: $ResourceGroupName" -ForegroundColor Green
    }
    
    # Create virtual network
    Write-Host "Creating virtual network..." -ForegroundColor Cyan
    $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $vnet) {
        $vnet = New-AzVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix $vnetAddressPrefix -Tag $commonTags
        Write-Host "Created virtual network: $VnetName" -ForegroundColor Green
    } else {
        Write-Host "Using existing virtual network: $VnetName" -ForegroundColor Green
    }
    
    # Create subnet for VM
    Write-Host "Creating subnet for VM..." -ForegroundColor Cyan
    $vmSubnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetNameVM -VirtualNetwork $vnet -ErrorAction SilentlyContinue
    if (-not $vmSubnet) {
        $vmSubnet = Add-AzVirtualNetworkSubnetConfig -Name $subnetNameVM -VirtualNetwork $vnet -AddressPrefix $vmSubnetPrefix
        $vnet | Set-AzVirtualNetwork
        Write-Host "Created VM subnet: $subnetNameVM" -ForegroundColor Green
    } else {
        Write-Host "Using existing VM subnet: $subnetNameVM" -ForegroundColor Green
    }
    
    # Create subnet for NetApp Files
    Write-Host "Creating subnet for NetApp Files..." -ForegroundColor Cyan
    $netappSubnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetNameNetApp -VirtualNetwork $vnet -ErrorAction SilentlyContinue
    if (-not $netappSubnet) {
        $netappSubnet = Add-AzVirtualNetworkSubnetConfig -Name $subnetNameNetApp -VirtualNetwork $vnet -AddressPrefix $netappSubnetPrefix -ServiceEndpoint "Microsoft.NetApp/volumes"
        $vnet | Set-AzVirtualNetwork
        Write-Host "Created NetApp subnet: $subnetNameNetApp" -ForegroundColor Green
    } else {
        Write-Host "Using existing NetApp subnet: $subnetNameNetApp" -ForegroundColor Green
    }
    
    # Create Network Security Group
    Write-Host "Creating Network Security Group..." -ForegroundColor Cyan
    $nsg = Get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $nsg) {
        $nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $Location -Tag $commonTags
        Write-Host "Created NSG: $nsgName" -ForegroundColor Green
    } else {
        Write-Host "Using existing NSG: $nsgName" -ForegroundColor Green
    }
    
    # Add security rules
    $sshRule = Get-AzNetworkSecurityRuleConfig -Name "SSH" -NetworkSecurityGroup $nsg -ErrorAction SilentlyContinue
    if (-not $sshRule) {
        Add-AzNetworkSecurityRuleConfig -Name "SSH" -NetworkSecurityGroup $nsg -Access Allow -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22
        Write-Host "Added SSH rule to NSG" -ForegroundColor Green
    }
    
    $nfsRule = Get-AzNetworkSecurityRuleConfig -Name "NFS" -NetworkSecurityGroup $nsg -ErrorAction SilentlyContinue
    if (-not $nfsRule) {
        Add-AzNetworkSecurityRuleConfig -Name "NFS" -NetworkSecurityGroup $nsg -Access Allow -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 2049
        Write-Host "Added NFS rule to NSG" -ForegroundColor Green
    }
    
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg
    
    # Create Public IP
    Write-Host "Creating Public IP..." -ForegroundColor Cyan
    $pip = Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $pip) {
        $pip = New-AzPublicIpAddress -Name $pipName -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Dynamic -Sku Basic -Tag $commonTags
        Write-Host "Created Public IP: $pipName" -ForegroundColor Green
    } else {
        Write-Host "Using existing Public IP: $pipName" -ForegroundColor Green
    }
    
    # Create Network Interface
    Write-Host "Creating Network Interface..." -ForegroundColor Cyan
    $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $nic) {
        $nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $vmSubnet.Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id -Tag $commonTags
        Write-Host "Created Network Interface: $nicName" -ForegroundColor Green
    } else {
        Write-Host "Using existing Network Interface: $nicName" -ForegroundColor Green
    }
    
    # Create NetApp account
    Write-Host "Creating NetApp account..." -ForegroundColor Cyan
    $netappAccount = Get-AzNetAppFilesAccount -Name $netappAccountName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $netappAccount) {
        $netappAccount = New-AzNetAppFilesAccount -Name $netappAccountName -ResourceGroupName $ResourceGroupName -Location $Location -Tag $commonTags
        Write-Host "Created NetApp account: $netappAccountName" -ForegroundColor Green
    } else {
        Write-Host "Using existing NetApp account: $netappAccountName" -ForegroundColor Green
    }
    
    # Create capacity pool
    Write-Host "Creating capacity pool..." -ForegroundColor Cyan
    $capacityPool = Get-AzNetAppFilesPool -Name $netappPoolName -ResourceGroupName $ResourceGroupName -AccountName $netappAccountName -ErrorAction SilentlyContinue
    if (-not $capacityPool) {
        $capacityPool = New-AzNetAppFilesPool -Name $netappPoolName -ResourceGroupName $ResourceGroupName -AccountName $netappAccountName -Location $Location -ServiceLevel $NetAppServiceLevel -SizeInBytes 4TB
        Write-Host "Created capacity pool: $netappPoolName" -ForegroundColor Green
    } else {
        Write-Host "Using existing capacity pool: $netappPoolName" -ForegroundColor Green
    }
    
    # Create NFS volume
    Write-Host "Creating NFS volume..." -ForegroundColor Cyan
    $volume = Get-AzNetAppFilesVolume -Name $NetAppVolumeName -ResourceGroupName $ResourceGroupName -AccountName $netappAccountName -PoolName $netappPoolName -ErrorAction SilentlyContinue
    if (-not $volume) {
        # Create export policy
        $exportPolicy = New-AzNetAppFilesVolumeExportPolicy -RuleIndex 1 -AllowedClients "10.0.0.0/16" -UnixReadOnly $false -UnixReadWrite $true -Nfsv3 $true -Nfsv41 $false -Cifs $false -RootAccess $false
        
        # Create volume
        $volume = New-AzNetAppFilesVolume -Name $NetAppVolumeName -ResourceGroupName $ResourceGroupName -AccountName $netappAccountName -PoolName $netappPoolName -Location $Location -SubnetId $netappSubnet.Id -UsageThreshold ($NetAppVolumeSize * 1GB) -ServiceLevel $NetAppServiceLevel -CreationToken $NetAppVolumeName -ProtocolType @("NFSv3") -ExportPolicy $exportPolicy -Tag $commonTags
        Write-Host "Created NFS volume: $NetAppVolumeName" -ForegroundColor Green
    } else {
        Write-Host "Using existing volume: $NetAppVolumeName" -ForegroundColor Green
    }
    
    # Get volume details for cloud-init
    $volumeDetails = Get-AzNetAppFilesVolume -Name $NetAppVolumeName -ResourceGroupName $ResourceGroupName -AccountName $netappAccountName -PoolName $netappPoolName
    $volumeIP = $volumeDetails.MountTargets[0].IpAddress
    
    # Create cloud-init script
    $cloudInitScript = @"
#cloud-config
package_update: true
package_upgrade: true

packages:
  - nfs-common

runcmd:
  # Create mount point
  - mkdir -p /mnt/$NetAppVolumeName
  
  # Mount the NFS volume
  - mount -t nfs -o vers=3 $volumeIP:/$NetAppVolumeName /mnt/$NetAppVolumeName
  
  # Add to fstab for persistent mounting
  - echo "$volumeIP:/$NetAppVolumeName /mnt/$NetAppVolumeName nfs rw,hard,rsize=65536,wsize=65536,vers=3,tcp 0 0" >> /etc/fstab
  
  # Create a test file to verify the mount
  - echo "NFS volume mounted successfully at $(date)" > /mnt/$NetAppVolumeName/mount-test.txt
  
  # Set permissions
  - chmod 755 /mnt/$NetAppVolumeName

final_message: "NFS volume has been mounted successfully"
"@
    
    # Create VM
    Write-Host "Creating Linux VM..." -ForegroundColor Cyan
    $vm = Get-AzVM -Name $VmName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $vm) {
        $vmConfig = New-AzVMConfig -VMName $VmName -VMSize $VmSize -Tags $commonTags
        
        # Set OS profile
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $VmName -Credential (New-Object System.Management.Automation.PSCredential($AdminUsername, $AdminPassword)) -DisablePasswordAuthentication $false
        
        # Set image
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "Canonical" -Offer "UbuntuServer" -Skus "18.04-LTS" -Version "latest"
        
        # Set network interface
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        
        # Set OS disk
        $vmConfig = Set-AzVMOSDisk -VM $vmConfig -CreateOption FromImage -StorageAccountType Standard_LRS
        
        # Set custom data (cloud-init)
        $vmConfig = Set-AzVMCustomData -VM $vmConfig -CustomData $cloudInitScript
        
        # Create VM
        $vm = New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig
        Write-Host "Created Linux VM: $VmName" -ForegroundColor Green
    } else {
        Write-Host "Using existing VM: $VmName" -ForegroundColor Green
    }
    
    # Get VM details
    $vmDetails = Get-AzVM -Name $VmName -ResourceGroupName $ResourceGroupName
    $pipDetails = Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $ResourceGroupName
    
    # Output results
    Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
    Write-Host "VM ID: $($vmDetails.Id)" -ForegroundColor Yellow
    Write-Host "VM Public IP: $($pipDetails.IpAddress)" -ForegroundColor Yellow
    Write-Host "SSH Command: ssh $AdminUsername@$($pipDetails.IpAddress)" -ForegroundColor Yellow
    Write-Host "Volume ID: $($volumeDetails.Id)" -ForegroundColor Yellow
    Write-Host "Volume IP: $volumeIP" -ForegroundColor Yellow
    Write-Host "Mount Command: mkdir -p /mnt/$NetAppVolumeName && mount -t nfs -o vers=3 $volumeIP:/$NetAppVolumeName /mnt/$NetAppVolumeName" -ForegroundColor Yellow
    
    # Create output object
    $output = @{
        VmId = $vmDetails.Id
        VmPublicIP = $pipDetails.IpAddress
        VmPrivateIP = $nic.IpConfigurations[0].PrivateIpAddress
        VolumeId = $volumeDetails.Id
        VolumeIP = $volumeIP
        SshCommand = "ssh $AdminUsername@$($pipDetails.IpAddress)"
        MountCommand = "mkdir -p /mnt/$NetAppVolumeName && mount -t nfs -o vers=3 $volumeIP:/$NetAppVolumeName /mnt/$NetAppVolumeName"
    }
    
    return $output
    
} catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    throw
} 