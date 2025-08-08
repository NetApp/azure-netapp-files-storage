#Requires -Version 7.0
#Requires -Modules Az.Compute, Az.Network, Az.NetAppFiles, Az.Resources, Az.LoadBalancer

<#
.SYNOPSIS
    Deploy multiple Linux VMs with shared NFS volume

.DESCRIPTION
    This script creates an enterprise solution with:
    - Multiple Linux virtual machines (1-10 VMs)
    - Shared NFS volume accessible by all VMs
    - Load balancer for high availability (when VM count > 1)
    - Network security group configuration
    - Optional public IPs for direct VM access

.PARAMETER ResourceGroupName
    Name of the resource group to create or use

.PARAMETER Location
    Azure region for all resources (default: East US)

.PARAMETER AdminUsername
    Username for all Virtual Machines

.PARAMETER AdminPassword
    Password for all Virtual Machines (secure string)

.PARAMETER VmNamePrefix
    Prefix for the virtual machine names (will be appended with numbers)

.PARAMETER VmCount
    Number of virtual machines to create (1-10)

.PARAMETER VmSize
    Size of the virtual machines (default: Standard_D2s_v3)

.PARAMETER CreatePublicIPs
    Whether to create public IP addresses for VMs (default: true)

.PARAMETER NetAppVolumeName
    Name of the shared NetApp volume

.PARAMETER NetAppVolumeSize
    Size of the NetApp volume in GB (default: 500)

.PARAMETER NetAppServiceLevel
    Service level for the NetApp volume (Standard, Premium, Ultra)

.PARAMETER VnetName
    Name of the virtual network

.PARAMETER ProjectName
    Project name for tagging and resource management

.EXAMPLE
    $password = ConvertTo-SecureString "MySecurePassword123!" -AsPlainText -Force
    .\deploy-multi-linux-vms-with-nfs.ps1 -ResourceGroupName "rg-mycluster" -AdminUsername "azureuser" -AdminPassword $password -VmCount 3

.EXAMPLE
    $password = ConvertTo-SecureString "MySecurePassword123!" -AsPlainText -Force
    .\deploy-multi-linux-vms-with-nfs.ps1 -ResourceGroupName "rg-prod-cluster" -AdminUsername "admin" -AdminPassword $password -VmCount 5 -NetAppVolumeSize 1000 -Location "West US 2"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "East US",
    
    [Parameter(Mandatory = $true)]
    [string]$AdminUsername,
    
    [Parameter(Mandatory = $true)]
    [SecureString]$AdminPassword,
    
    [Parameter(Mandatory = $false)]
    [string]$VmNamePrefix = "azlinuxvms",
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int]$VmCount = 3,
    
    [Parameter(Mandatory = $false)]
    [string]$VmSize = "Standard_D2s_v3",
    
    [Parameter(Mandatory = $false)]
    [bool]$CreatePublicIPs = $true,
    
    [Parameter(Mandatory = $false)]
    [string]$NetAppVolumeName = "azlinux-shared-nfs",
    
    [Parameter(Mandatory = $false)]
    [int]$NetAppVolumeSize = 500,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Standard", "Premium", "Ultra")]
    [string]$NetAppServiceLevel = "Standard",
    
    [Parameter(Mandatory = $false)]
    [string]$VnetName = "azlinux-vnet",
    
    [Parameter(Mandatory = $false)]
    [string]$ProjectName = "dev"
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Generate unique names
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$netappAccountName = "azlinux-netapp-account-$timestamp"
$netappPoolName = "azlinux-netapp-pool"
$subnetNameVM = "vmSubnet"
$subnetNameNetApp = "netappSubnet"
$nsgName = "nsg-$VmNamePrefix"
$lbName = "lb-$VmNamePrefix"
$lbPipName = "pip-lb-$VmNamePrefix"

# Network configuration
$vnetAddressPrefix = "10.0.0.0/16"
$vmSubnetPrefix = "10.0.1.0/24"
$netappSubnetPrefix = "10.0.2.0/24"

# Common tags
$commonTags = @{
    Project = $ProjectName
    CreatedBy = "PowerShell"
    CreatedOn = (Get-Date).ToString("yyyy-MM-dd")
}

# Generate VM names
$vmNames = @()
for ($i = 1; $i -le $VmCount; $i++) {
    $vmNames += "$VmNamePrefix$i"
}

Write-Host "Starting Multi-Linux VMs with NFS deployment..." -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host "VM Count: $VmCount" -ForegroundColor Yellow
Write-Host "VM Names: $($vmNames -join ', ')" -ForegroundColor Yellow
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
    
    # Create subnet for VMs
    Write-Host "Creating subnet for VMs..." -ForegroundColor Cyan
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
    
    # Create load balancer if multiple VMs
    $loadBalancer = $null
    $lbPip = $null
    if ($VmCount -gt 1) {
        Write-Host "Creating Load Balancer..." -ForegroundColor Cyan
        
        # Create load balancer public IP
        $lbPip = Get-AzPublicIpAddress -Name $lbPipName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not $lbPip) {
            $lbPip = New-AzPublicIpAddress -Name $lbPipName -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Static -Sku Standard -Tag $commonTags
            Write-Host "Created Load Balancer Public IP: $lbPipName" -ForegroundColor Green
        } else {
            Write-Host "Using existing Load Balancer Public IP: $lbPipName" -ForegroundColor Green
        }
        
        # Create load balancer
        $loadBalancer = Get-AzLoadBalancer -Name $lbName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not $loadBalancer) {
            $loadBalancer = New-AzLoadBalancer -Name $lbName -ResourceGroupName $ResourceGroupName -Location $Location -Sku Standard -Tag $commonTags
            Write-Host "Created Load Balancer: $lbName" -ForegroundColor Green
        } else {
            Write-Host "Using existing Load Balancer: $lbName" -ForegroundColor Green
        }
        
        # Add frontend IP configuration
        $frontendIP = Get-AzLoadBalancerFrontendIpConfig -Name "frontend-ip" -LoadBalancer $loadBalancer -ErrorAction SilentlyContinue
        if (-not $frontendIP) {
            $frontendIP = Add-AzLoadBalancerFrontendIpConfig -Name "frontend-ip" -LoadBalancer $loadBalancer -PublicIpAddress $lbPip
            Write-Host "Added frontend IP configuration" -ForegroundColor Green
        }
        
        # Add backend pool
        $backendPool = Get-AzLoadBalancerBackendAddressPool -Name "backend-pool" -LoadBalancer $loadBalancer -ErrorAction SilentlyContinue
        if (-not $backendPool) {
            $backendPool = Add-AzLoadBalancerBackendAddressPool -Name "backend-pool" -LoadBalancer $loadBalancer
            Write-Host "Added backend pool" -ForegroundColor Green
        }
        
        Set-AzLoadBalancer -LoadBalancer $loadBalancer
    }
    
    # Create VMs
    $vms = @()
    $publicIPs = @()
    $networkInterfaces = @()
    
    for ($i = 0; $i -lt $VmCount; $i++) {
        $vmName = $vmNames[$i]
        $pipName = "pip-$vmName"
        $nicName = "nic-$vmName"
        
        Write-Host "Creating VM $($i + 1) of $VmCount: $vmName" -ForegroundColor Cyan
        
        # Create Public IP (if enabled)
        $pip = $null
        if ($CreatePublicIPs) {
            $pip = Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
            if (-not $pip) {
                $pip = New-AzPublicIpAddress -Name $pipName -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Dynamic -Sku Basic -Tag $commonTags
                Write-Host "Created Public IP for $vmName" -ForegroundColor Green
            } else {
                Write-Host "Using existing Public IP for $vmName" -ForegroundColor Green
            }
            $publicIPs += $pip
        }
        
        # Create Network Interface
        $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not $nic) {
            $nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $vmSubnet.Id -NetworkSecurityGroupId $nsg.Id -Tag $commonTags
            if ($pip) {
                $nic.IpConfigurations[0].PublicIpAddress = $pip
            }
            Set-AzNetworkInterface -NetworkInterface $nic
            Write-Host "Created Network Interface for $vmName" -ForegroundColor Green
        } else {
            Write-Host "Using existing Network Interface for $vmName" -ForegroundColor Green
        }
        $networkInterfaces += $nic
        
        # Add to load balancer backend pool if multiple VMs
        if ($loadBalancer -and $backendPool) {
            $nic.IpConfigurations[0].LoadBalancerBackendAddressPools = $backendPool
            Set-AzNetworkInterface -NetworkInterface $nic
            Write-Host "Added $vmName to load balancer backend pool" -ForegroundColor Green
        }
        
        # Create cloud-init script
        $vmIndex = $i + 1
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
  
  # Create VM-specific directory
  - mkdir -p /mnt/$NetAppVolumeName/vm-$vmIndex
  
  # Create a test file to verify the mount
  - echo "VM $vmIndex - NFS volume mounted successfully at $(date)" > /mnt/$NetAppVolumeName/vm-$vmIndex/mount-test.txt
  
  # Set permissions
  - chmod 755 /mnt/$NetAppVolumeName
  - chmod 755 /mnt/$NetAppVolumeName/vm-$vmIndex
  
  # Create a shared directory for collaboration
  - mkdir -p /mnt/$NetAppVolumeName/shared
  - chmod 777 /mnt/$NetAppVolumeName/shared

final_message: "VM $vmIndex - NFS volume has been mounted successfully"
"@
        
        # Create VM
        $vm = Get-AzVM -Name $vmName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not $vm) {
            $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $VmSize -Tags $commonTags
            
            # Set OS profile
            $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $vmName -Credential (New-Object System.Management.Automation.PSCredential($AdminUsername, $AdminPassword)) -DisablePasswordAuthentication $false
            
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
            Write-Host "Created VM: $vmName" -ForegroundColor Green
        } else {
            Write-Host "Using existing VM: $vmName" -ForegroundColor Green
        }
        
        $vms += $vm
    }
    
    # Get final details
    $vmDetails = @()
    $pipDetails = @()
    $nicDetails = @()
    
    for ($i = 0; $i -lt $VmCount; $i++) {
        $vmName = $vmNames[$i]
        $vmDetails += Get-AzVM -Name $vmName -ResourceGroupName $ResourceGroupName
        $nicDetails += Get-AzNetworkInterface -Name "nic-$vmName" -ResourceGroupName $ResourceGroupName
        
        if ($CreatePublicIPs) {
            $pipDetails += Get-AzPublicIpAddress -Name "pip-$vmName" -ResourceGroupName $ResourceGroupName
        }
    }
    
    # Output results
    Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
    Write-Host "VM Count: $VmCount" -ForegroundColor Yellow
    
    for ($i = 0; $i -lt $VmCount; $i++) {
        Write-Host "VM $($i + 1): $($vmNames[$i])" -ForegroundColor Yellow
        Write-Host "  ID: $($vmDetails[$i].Id)" -ForegroundColor Gray
        Write-Host "  Private IP: $($nicDetails[$i].IpConfigurations[0].PrivateIpAddress)" -ForegroundColor Gray
        if ($CreatePublicIPs) {
            Write-Host "  Public IP: $($pipDetails[$i].IpAddress)" -ForegroundColor Gray
            Write-Host "  SSH: ssh $AdminUsername@$($pipDetails[$i].IpAddress)" -ForegroundColor Gray
        }
    }
    
    Write-Host "Volume ID: $($volumeDetails.Id)" -ForegroundColor Yellow
    Write-Host "Volume IP: $volumeIP" -ForegroundColor Yellow
    
    if ($loadBalancer) {
        Write-Host "Load Balancer IP: $($lbPip.IpAddress)" -ForegroundColor Yellow
        Write-Host "Load Balancer SSH: ssh $AdminUsername@$($lbPip.IpAddress)" -ForegroundColor Yellow
    }
    
    Write-Host "Mount Command: mkdir -p /mnt/$NetAppVolumeName && mount -t nfs -o vers=3 $volumeIP:/$NetAppVolumeName /mnt/$NetAppVolumeName" -ForegroundColor Yellow
    
    # Create output object
    $output = @{
        VmIds = $vmDetails.Id
        VmNames = $vmNames
        VmPrivateIPs = $nicDetails.IpConfigurations[0].PrivateIpAddress
        VmPublicIPs = if ($CreatePublicIPs) { $pipDetails.IpAddress } else { @() }
        VolumeId = $volumeDetails.Id
        VolumeIP = $volumeIP
        LoadBalancerIP = if ($loadBalancer) { $lbPip.IpAddress } else { $null }
        SshCommands = if ($CreatePublicIPs) { $pipDetails | ForEach-Object { "ssh $AdminUsername@$($_.IpAddress)" } } else { @() }
        MountCommand = "mkdir -p /mnt/$NetAppVolumeName && mount -t nfs -o vers=3 $volumeIP:/$NetAppVolumeName /mnt/$NetAppVolumeName"
    }
    
    return $output
    
} catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    throw
} 