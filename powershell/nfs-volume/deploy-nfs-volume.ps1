#Requires -Version 7.0
#Requires -Modules Az.NetAppFiles, Az.Network, Az.Resources

<#
.SYNOPSIS
    Deploy a basic Azure NetApp Files NFS volume

.DESCRIPTION
    This script creates a complete Azure NetApp Files setup including:
    - Virtual network with delegated subnet for NetApp Files
    - NetApp account
    - Capacity pool
    - NFS volume with specified size and service level

.PARAMETER ResourceGroupName
    Name of the resource group to create or use

.PARAMETER Location
    Azure region for all resources (default: East US)

.PARAMETER VolumeName
    Name of the NetApp volume

.PARAMETER VolumeSizeGiB
    Size of the NetApp volume in GiB (default: 100)

.PARAMETER VnetName
    Name of the virtual network (default: anf-vnet)

.PARAMETER ProjectName
    Project name for tagging and resource management (default: dev)

.PARAMETER AllowedClients
    IP address range allowed to access the NFS volume in CIDR format (default: 10.0.0.0/24)

.EXAMPLE
    .\deploy-nfs-volume.ps1 -ResourceGroupName "rg-myproject-anf" -VolumeName "my-nfs-volume"

.EXAMPLE
    .\deploy-nfs-volume.ps1 -ResourceGroupName "rg-prod-anf" -VolumeName "prod-storage" -VolumeSizeGiB 500 -Location "West US 2"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "East US",
    
    [Parameter(Mandatory = $false)]
    [string]$VolumeName = "anf-volume",
    
    [Parameter(Mandatory = $false)]
    [int]$VolumeSizeGiB = 100,
    
    [Parameter(Mandatory = $false)]
    [string]$VnetName = "anf-vnet",
    
    [Parameter(Mandatory = $false)]
    [string]$ProjectName = "dev",
    
    [Parameter(Mandatory = $false)]
    [string]$AllowedClients = "10.0.0.0/24"
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Generate unique names
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$netappAccountName = "netapp-$($ProjectName)-$timestamp"
$netappPoolName = "pool1"
$netappSubnetName = "netappSubnet"

# Network configuration
$vnetAddressPrefix = "10.0.0.0/16"
$netappSubnetPrefix = "10.0.1.0/24"

# Common tags
$commonTags = @{
    Project = $ProjectName
    CreatedBy = "PowerShell"
    CreatedOn = (Get-Date).ToString("yyyy-MM-dd")
    ANF_PLG = "true"
    ANF_Template_Version = "1.0.0"
    ANF_Deployment_ID = (Get-Date).ToString("yyyyMMdd-HHmmss")
}

Write-Host "Starting Azure NetApp Files NFS volume deployment..." -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host "Location: $Location" -ForegroundColor Yellow
Write-Host "Volume Name: $VolumeName" -ForegroundColor Yellow
Write-Host "Volume Size: $VolumeSizeGiB GiB" -ForegroundColor Yellow

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
    
    # Create subnet for NetApp Files
    Write-Host "Creating subnet for NetApp Files..." -ForegroundColor Cyan
    $subnet = Get-AzVirtualNetworkSubnetConfig -Name $netappSubnetName -VirtualNetwork $vnet -ErrorAction SilentlyContinue
    if (-not $subnet) {
        $subnet = Add-AzVirtualNetworkSubnetConfig -Name $netappSubnetName -VirtualNetwork $vnet -AddressPrefix $netappSubnetPrefix -ServiceEndpoint "Microsoft.NetApp/volumes"
        $vnet | Set-AzVirtualNetwork
        Write-Host "Created subnet: $netappSubnetName" -ForegroundColor Green
    } else {
        Write-Host "Using existing subnet: $netappSubnetName" -ForegroundColor Green
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
        $capacityPool = New-AzNetAppFilesPool -Name $netappPoolName -ResourceGroupName $ResourceGroupName -AccountName $netappAccountName -Location $Location -ServiceLevel "Standard" -SizeInBytes 4TB
        Write-Host "Created capacity pool: $netappPoolName" -ForegroundColor Green
    } else {
        Write-Host "Using existing capacity pool: $netappPoolName" -ForegroundColor Green
    }
    
    # Create NFS volume
    Write-Host "Creating NFS volume..." -ForegroundColor Cyan
    $volume = Get-AzNetAppFilesVolume -Name $VolumeName -ResourceGroupName $ResourceGroupName -AccountName $netappAccountName -PoolName $netappPoolName -ErrorAction SilentlyContinue
    if (-not $volume) {
        # Create export policy
        $exportPolicy = New-AzNetAppFilesVolumeExportPolicy -RuleIndex 1 -AllowedClients $AllowedClients -UnixReadOnly $false -UnixReadWrite $true -Nfsv3 $true -Nfsv41 $false -Cifs $false -RootAccess $false
        
        # Create volume
        $volume = New-AzNetAppFilesVolume -Name $VolumeName -ResourceGroupName $ResourceGroupName -AccountName $netappAccountName -PoolName $netappPoolName -Location $Location -SubnetId $subnet.Id -UsageThreshold ($VolumeSizeGiB * 1GB) -ServiceLevel "Standard" -CreationToken $VolumeName -ProtocolType @("NFSv3") -ExportPolicy $exportPolicy -Tag $commonTags
        Write-Host "Created NFS volume: $VolumeName" -ForegroundColor Green
    } else {
        Write-Host "Using existing volume: $VolumeName" -ForegroundColor Green
    }
    
    # Get volume details
    $volumeDetails = Get-AzNetAppFilesVolume -Name $VolumeName -ResourceGroupName $ResourceGroupName -AccountName $netappAccountName -PoolName $netappPoolName
    
    # Output results
    Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
    Write-Host "Volume ID: $($volumeDetails.Id)" -ForegroundColor Yellow
    Write-Host "Volume IP: $($volumeDetails.MountTargets[0].IpAddress)" -ForegroundColor Yellow
    Write-Host "Mount Command: mkdir -p /mnt/$VolumeName && mount -t nfs -o vers=3 $($volumeDetails.MountTargets[0].IpAddress):/$VolumeName /mnt/$VolumeName" -ForegroundColor Yellow
    Write-Host "Fstab Entry: $($volumeDetails.MountTargets[0].IpAddress):/$VolumeName /mnt/$VolumeName nfs rw,hard,rsize=65536,wsize=65536,vers=3,tcp 0 0" -ForegroundColor Yellow
    
    # Create output object
    $output = @{
        VolumeId = $volumeDetails.Id
        VolumeIP = $volumeDetails.MountTargets[0].IpAddress
        MountCommand = "mkdir -p /mnt/$VolumeName && mount -t nfs -o vers=3 $($volumeDetails.MountTargets[0].IpAddress):/$VolumeName /mnt/$VolumeName"
        FstabEntry = "$($volumeDetails.MountTargets[0].IpAddress):/$VolumeName /mnt/$VolumeName nfs rw,hard,rsize=65536,wsize=65536,vers=3,tcp 0 0"
        MountInstructions = "Mount command: mount -t nfs -o vers=3 $($volumeDetails.MountTargets[0].IpAddress):/$VolumeName /your/mount/path"
    }
    
    return $output
    
} catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    throw
} 