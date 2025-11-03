#Requires -Version 7.0
#Requires -Modules Az.Compute, Az.Network, Az.NetAppFiles, Az.Resources

<#
.SYNOPSIS
    Deploy PostgreSQL on Linux VM with Azure NetApp Files storage

.DESCRIPTION
    This script creates a complete solution with:
    - Virtual network and subnets (VM and NetApp Files)
    - Linux virtual machine (Ubuntu 22.04-LTS)
    - Azure NetApp Files volume (NFS) for PostgreSQL data
    - PostgreSQL installed and configured on the VM
    - PostgreSQL data directory on the mounted ANF volume
    - Network security group with PostgreSQL and SSH access

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

.PARAMETER PostgreSQLVersion
    PostgreSQL version to install (14, 15, or 16)

.PARAMETER PostgreSQLAdminPassword
    Password for PostgreSQL superuser (secure string)

.PARAMETER DatabaseName
    Name of the database to create

.PARAMETER DatabaseUser
    Database user name

.PARAMETER DatabasePassword
    Database user password (secure string)

.PARAMETER PostgreSQLPort
    PostgreSQL port (default: 5432)

.PARAMETER NetAppAccountName
    Name of the NetApp account

.PARAMETER NetAppPoolName
    Name of the NetApp pool

.PARAMETER NetAppPoolSizeInTB
    Size of the NetApp pool in TB (default: 4)

.PARAMETER NetAppVolumeName
    Name of the NetApp volume

.PARAMETER NetAppVolumeSize
    Size of the NetApp volume in GB (default: 200)

.PARAMETER NetAppServiceLevel
    Service level for the NetApp volume (Standard, Premium, Ultra)

.PARAMETER CreatePublicIP
    Whether to create a public IP address (default: true)

.PARAMETER VnetName
    Name of the virtual network

.PARAMETER ProjectName
    Project name for tagging and resource management

.EXAMPLE
    $vmPassword = ConvertTo-SecureString "YourVMAdminPassword123!" -AsPlainText -Force
    $pgPassword = ConvertTo-SecureString "PostgresAdminPassword123!" -AsPlainText -Force
    $dbPassword = ConvertTo-SecureString "DatabaseUserPassword123!" -AsPlainText -Force
    
    .\deploy-postgresql-vm-anf.ps1 `
        -ResourceGroupName "rg-postgresql-vm-anf" `
        -AdminUsername "azureuser" `
        -AdminPassword $vmPassword `
        -PostgreSQLAdminPassword $pgPassword `
        -DatabasePassword $dbPassword
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "East US",
    
    [Parameter(Mandatory = $false)]
    [string]$VmName = "postgresql-vm",
    
    [Parameter(Mandatory = $true)]
    [string]$AdminUsername,
    
    [Parameter(Mandatory = $true)]
    [SecureString]$AdminPassword,
    
    [Parameter(Mandatory = $false)]
    [string]$VmSize = "Standard_D2s_v3",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("14", "15", "16")]
    [string]$PostgreSQLVersion = "15",
    
    [Parameter(Mandatory = $true)]
    [SecureString]$PostgreSQLAdminPassword,
    
    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "mydb",
    
    [Parameter(Mandatory = $false)]
    [string]$DatabaseUser = "appuser",
    
    [Parameter(Mandatory = $true)]
    [SecureString]$DatabasePassword,
    
    [Parameter(Mandatory = $false)]
    [int]$PostgreSQLPort = 5432,
    
    [Parameter(Mandatory = $false)]
    [string]$NetAppAccountName = "postgresql-netapp-account",
    
    [Parameter(Mandatory = $false)]
    [string]$NetAppPoolName = "postgresql-pool",
    
    [Parameter(Mandatory = $false)]
    [int]$NetAppPoolSizeInTB = 4,
    
    [Parameter(Mandatory = $false)]
    [string]$NetAppVolumeName = "postgresql-data",
    
    [Parameter(Mandatory = $false)]
    [int]$NetAppVolumeSize = 200,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Standard", "Premium", "Ultra")]
    [string]$NetAppServiceLevel = "Standard",
    
    [Parameter(Mandatory = $false)]
    [bool]$CreatePublicIP = $true,
    
    [Parameter(Mandatory = $false)]
    [string]$VnetName = "postgresql-vnet",
    
    [Parameter(Mandatory = $false)]
    [string]$ProjectName = "dev"
)

# Set error action preference
$ErrorActionPreference = "Stop"

try {
    # Convert secure strings to plain text for script substitution
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword)
    $adminPasswordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PostgreSQLAdminPassword)
    $pgAdminPasswordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DatabasePassword)
    $dbPasswordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

    # Generate unique names with timestamp
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $netappAccountNameFinal = "$NetAppAccountName-$timestamp"
    
    # Common tags
    $commonTags = @{
        project             = $ProjectName
        created_by          = "PostgreSQL-ANF-PowerShell"
        created_on          = (Get-Date -Format "yyyy-MM-dd")
        pg_plg              = "true"
        pg_template_version = "1.0.0"
        pg_deployment_id    = $timestamp
    }

    # Network configuration
    $vnetAddressPrefix = "10.0.0.0/16"
    $vmSubnetPrefix = "10.0.1.0/24"
    $netappSubnetPrefix = "10.0.2.0/24"
    $vmSubnetName = "vmSubnet"
    $netappSubnetName = "netappSubnet"

    # Resource names
    $nsgName = "nsg-$VmName"
    $pipName = "pip-$VmName"
    $nicName = "nic-$VmName"

    # Check Azure connection
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Please connect to Azure first using Connect-AzAccount" -ForegroundColor Red
        exit 1
    }

    Write-Host "Deploying PostgreSQL VM with ANF..." -ForegroundColor Cyan
    Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Yellow
    Write-Host "Location: $Location" -ForegroundColor Yellow
    Write-Host "VM Name: $VmName" -ForegroundColor Yellow

    # Create or get resource group
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

    # Create VM subnet
    $vmSubnet = Get-AzVirtualNetworkSubnetConfig -Name $vmSubnetName -VirtualNetwork $vnet -ErrorAction SilentlyContinue
    if (-not $vmSubnet) {
        $vmSubnet = Add-AzVirtualNetworkSubnetConfig -Name $vmSubnetName -VirtualNetwork $vnet -AddressPrefix $vmSubnetPrefix
        $vnet | Set-AzVirtualNetwork | Out-Null
        Write-Host "Created VM subnet: $vmSubnetName" -ForegroundColor Green
    } else {
        Write-Host "Using existing VM subnet: $vmSubnetName" -ForegroundColor Green
    }

    # Create NetApp subnet with delegation
    $netappSubnet = Get-AzVirtualNetworkSubnetConfig -Name $netappSubnetName -VirtualNetwork $vnet -ErrorAction SilentlyContinue
    if (-not $netappSubnet) {
        $delegation = New-AzDelegation -Name "NetAppDelegation" -ServiceName "Microsoft.Netapp/volumes"
        $netappSubnet = Add-AzVirtualNetworkSubnetConfig -Name $netappSubnetName -VirtualNetwork $vnet -AddressPrefix $netappSubnetPrefix -Delegation $delegation
        $vnet | Set-AzVirtualNetwork | Out-Null
        Write-Host "Created NetApp subnet: $netappSubnetName" -ForegroundColor Green
    } else {
        Write-Host "Using existing NetApp subnet: $netappSubnetName" -ForegroundColor Green
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
    $rules = @(
        @{Name = "SSH"; Priority = 1001; Port = 22},
        @{Name = "PostgreSQL"; Priority = 1002; Port = $PostgreSQLPort},
        @{Name = "NFS"; Priority = 1003; Port = 2049; SourcePrefix = $vmSubnetPrefix}
    )

    foreach ($rule in $rules) {
        $existingRule = Get-AzNetworkSecurityRuleConfig -Name $rule.Name -NetworkSecurityGroup $nsg -ErrorAction SilentlyContinue
        if (-not $existingRule) {
            $sourcePrefix = if ($rule.SourcePrefix) { $rule.SourcePrefix } else { "*" }
            Add-AzNetworkSecurityRuleConfig `
                -Name $rule.Name `
                -NetworkSecurityGroup $nsg `
                -Access Allow `
                -Protocol Tcp `
                -Direction Inbound `
                -Priority $rule.Priority `
                -SourceAddressPrefix $sourcePrefix `
                -SourcePortRange * `
                -DestinationAddressPrefix * `
                -DestinationPortRange $rule.Port | Out-Null
            Write-Host "Added $($rule.Name) rule to NSG" -ForegroundColor Green
        }
    }
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg | Out-Null

    # Create Public IP (optional)
    $pip = $null
    if ($CreatePublicIP) {
        Write-Host "Creating public IP..." -ForegroundColor Cyan
        $pip = Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not $pip) {
            $pip = New-AzPublicIpAddress -Name $pipName -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Static -Sku Standard -Tag $commonTags
            Write-Host "Created public IP: $pipName" -ForegroundColor Green
        } else {
            Write-Host "Using existing public IP: $pipName" -ForegroundColor Green
        }
    }

    # Create Network Interface
    Write-Host "Creating network interface..." -ForegroundColor Cyan
    $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $nic) {
        $ipConfig = New-AzNetworkInterfaceIpConfig -Name "ipconfig1" -Subnet $vmSubnet -PrivateIpAddressAllocation Dynamic
        if ($pip) {
            $ipConfig = New-AzNetworkInterfaceIpConfig -Name "ipconfig1" -Subnet $vmSubnet -PublicIpAddress $pip -PrivateIpAddressAllocation Dynamic
        }
        $nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName -Location $Location -IpConfiguration $ipConfig -NetworkSecurityGroup $nsg -Tag $commonTags
        Write-Host "Created network interface: $nicName" -ForegroundColor Green
    } else {
        Write-Host "Using existing network interface: $nicName" -ForegroundColor Green
    }

    # Create NetApp account
    Write-Host "Creating NetApp account..." -ForegroundColor Cyan
    $netappAccount = Get-AzNetAppFilesAccount -Name $netappAccountNameFinal -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $netappAccount) {
        $netappAccount = New-AzNetAppFilesAccount -Name $netappAccountNameFinal -ResourceGroupName $ResourceGroupName -Location $Location -Tag $commonTags
        Write-Host "Created NetApp account: $netappAccountNameFinal" -ForegroundColor Green
    } else {
        Write-Host "Using existing NetApp account: $netappAccountNameFinal" -ForegroundColor Green
    }

    # Create capacity pool
    Write-Host "Creating capacity pool..." -ForegroundColor Cyan
    $capacityPool = Get-AzNetAppFilesPool -Name $NetAppPoolName -ResourceGroupName $ResourceGroupName -AccountName $netappAccountNameFinal -ErrorAction SilentlyContinue
    if (-not $capacityPool) {
        $poolSizeBytes = [long]$NetAppPoolSizeInTB * 1TB
        $capacityPool = New-AzNetAppFilesPool -Name $NetAppPoolName -ResourceGroupName $ResourceGroupName -AccountName $netappAccountNameFinal -Location $Location -ServiceLevel $NetAppServiceLevel -SizeInBytes $poolSizeBytes
        Write-Host "Created capacity pool: $NetAppPoolName" -ForegroundColor Green
    } else {
        Write-Host "Using existing capacity pool: $NetAppPoolName" -ForegroundColor Green
    }

    # Create NFS volume
    Write-Host "Creating NFS volume..." -ForegroundColor Cyan
    $volume = Get-AzNetAppFilesVolume -Name $NetAppVolumeName -ResourceGroupName $ResourceGroupName -AccountName $netappAccountNameFinal -PoolName $NetAppPoolName -ErrorAction SilentlyContinue
    if (-not $volume) {
        $exportPolicy = New-AzNetAppFilesVolumeExportPolicy -RuleIndex 1 -AllowedClients $vmSubnetPrefix -UnixReadOnly $false -UnixReadWrite $true -Nfsv3 $true -Nfsv41 $false -Cifs $false -RootAccess $true
        $volumeSizeBytes = [long]$NetAppVolumeSize * 1GB
        $volume = New-AzNetAppFilesVolume `
            -Name $NetAppVolumeName `
            -ResourceGroupName $ResourceGroupName `
            -AccountName $netappAccountNameFinal `
            -PoolName $NetAppPoolName `
            -Location $Location `
            -SubnetId $netappSubnet.Id `
            -UsageThreshold $volumeSizeBytes `
            -ServiceLevel $NetAppServiceLevel `
            -CreationToken $NetAppVolumeName `
            -ProtocolType @("NFSv3") `
            -ExportPolicy $exportPolicy `
            -Tag $commonTags
        Write-Host "Created NFS volume: $NetAppVolumeName" -ForegroundColor Green
    } else {
        Write-Host "Using existing volume: $NetAppVolumeName" -ForegroundColor Green
    }

    # Get volume details
    $volumeDetails = Get-AzNetAppFilesVolume -Name $NetAppVolumeName -ResourceGroupName $ResourceGroupName -AccountName $netappAccountNameFinal -PoolName $NetAppPoolName
    $volumeIP = $volumeDetails.MountTargets[0].IpAddress

    Write-Host "Waiting for NetApp volume to be fully provisioned..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60

    # Create VM
    Write-Host "Creating Linux VM..." -ForegroundColor Cyan
    $vm = Get-AzVM -Name $VmName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $vm) {
        $vmConfig = New-AzVMConfig -VMName $VmName -VMSize $VmSize -Tags $commonTags
        
        $credential = New-Object System.Management.Automation.PSCredential($AdminUsername, $AdminPassword)
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $VmName -Credential $credential -DisablePasswordAuthentication $false
        
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-jammy" -Skus "22_04-lts-gen2" -Version "latest"
        
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        
        $vmConfig = Set-AzVMOSDisk -VM $vmConfig -CreateOption FromImage -StorageAccountType Premium_LRS
        
        $vm = New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig
        Write-Host "Created Linux VM: $VmName" -ForegroundColor Green
    } else {
        Write-Host "Using existing VM: $VmName" -ForegroundColor Green
    }

    # Wait for VM to be ready
    Write-Host "Waiting for VM to be fully provisioned..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60

    # Read and prepare PostgreSQL setup script
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $scriptPath = Join-Path $scriptDir "..\..\terraform\db\postgresql-vm-anf\setup-postgresql.sh"
    $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
    
    if ((Test-Path $scriptPath)) {
        Write-Host "Reading PostgreSQL setup script from: $scriptPath" -ForegroundColor Gray
        $setupScriptContent = Get-Content $scriptPath -Raw
        # Replace template variables
        $setupScript = $setupScriptContent `
            -replace '\$\{postgresql_version\}', $PostgreSQLVersion `
            -replace '\$\{postgresql_admin_password\}', $pgAdminPasswordPlain `
            -replace '\$\{database_name\}', $DatabaseName `
            -replace '\$\{database_user\}', $DatabaseUser `
            -replace '\$\{database_password\}', $dbPasswordPlain `
            -replace '\$\{volume_ip\}', $volumeIP `
            -replace '\$\{volume_name\}', $NetAppVolumeName `
            -replace '\$\{postgresql_port\}', $PostgreSQLPort
    } else {
        Write-Host "Warning: Setup script not found at $scriptPath. Using embedded script." -ForegroundColor Yellow
        # Embedded full script with variable substitution
        $setupScript = @"
#!/bin/bash

set -e

exec > /var/log/postgresql-setup.log 2>&1
echo "Starting PostgreSQL setup script at $(date)"

POSTGRESQL_VERSION="$PostgreSQLVersion"
POSTGRESQL_ADMIN_PASSWORD="$pgAdminPasswordPlain"
DATABASE_NAME="$DatabaseName"
DATABASE_USER="$DatabaseUser"
DATABASE_PASSWORD="$dbPasswordPlain"
NETAPP_IP="$volumeIP"
NETAPP_PATH=/$NetAppVolumeName
MOUNT_PATH=/mnt/$NetAppVolumeName
POSTGRESQL_DATA_DIR=/mnt/$NetAppVolumeName/postgresql-data
POSTGRESQL_PORT=$PostgreSQLPort

echo "PostgreSQL Version: $POSTGRESQL_VERSION"
echo "NetApp IP: $NETAPP_IP"
echo "NetApp Path: $NETAPP_PATH"
echo "Mount Path: $MOUNT_PATH"
echo "PostgreSQL Data Directory: $POSTGRESQL_DATA_DIR"

apt-get update -q
apt-get install -y nfs-common

mkdir -p `$MOUNT_PATH

RETRIES=30
count=0
while [ `$count -lt `$RETRIES ]; do
    if ping -c 1 `$NETAPP_IP &> /dev/null; then
        echo "NetApp endpoint is reachable"
        break
    fi
    count=`$((count+1))
    echo "Waiting for NetApp endpoint... Attempt `$count of `$RETRIES"
    sleep 10
done

if [ `$count -eq `$RETRIES ]; then
    echo "ERROR: Could not reach NetApp endpoint after `$RETRIES attempts"
    exit 1
fi

mount -t nfs -o rw,hard,rsize=262144,wsize=262144,vers=3,tcp `$NETAPP_IP:`$NETAPP_PATH `$MOUNT_PATH

if ! mount | grep -q "`$MOUNT_PATH"; then
    echo "ERROR: ANF volume mount failed"
    exit 1
fi

echo "ANF volume mounted successfully"

grep -v "`$MOUNT_PATH" /etc/fstab > /etc/fstab.new || true
mv /etc/fstab.new /etc/fstab
echo "`$NETAPP_IP:`$NETAPP_PATH `$MOUNT_PATH nfs rw,hard,rsize=262144,wsize=262144,vers=3,tcp 0 0" >> /etc/fstab

echo "Installing PostgreSQL `$POSTGRESQL_VERSION..."
export DEBIAN_FRONTEND=noninteractive

apt-get install -y wget ca-certificates
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ `$(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
apt-get update -q

apt-get install -y postgresql-`$POSTGRESQL_VERSION postgresql-contrib-`$POSTGRESQL_VERSION

systemctl stop postgresql

mkdir -p `$POSTGRESQL_DATA_DIR
chown postgres:postgres `$POSTGRESQL_DATA_DIR
chmod 700 `$POSTGRESQL_DATA_DIR

if [ ! -f "`$POSTGRESQL_DATA_DIR/PG_VERSION" ]; then
    echo "Initializing PostgreSQL data directory on ANF..."
    sudo -u postgres /usr/lib/postgresql/`$POSTGRESQL_VERSION/bin/initdb -D `$POSTGRESQL_DATA_DIR -E UTF8 --locale=en_US.UTF-8
fi

POSTGRESQL_CONF="`$POSTGRESQL_DATA_DIR/postgresql.conf"
POSTGRESQL_PG_HBA="`$POSTGRESQL_DATA_DIR/pg_hba.conf"

sed -i "s|#data_directory =.*|data_directory = '`$POSTGRESQL_DATA_DIR'|" `$POSTGRESQL_CONF || echo "data_directory = '`$POSTGRESQL_DATA_DIR'" >> `$POSTGRESQL_CONF
sed -i "s|#listen_addresses =.*|listen_addresses = '*'|" `$POSTGRESQL_CONF || echo "listen_addresses = '*'" >> `$POSTGRESQL_CONF
sed -i "s|#port =.*|port = `$POSTGRESQL_PORT|" `$POSTGRESQL_CONF || echo "port = `$POSTGRESQL_PORT" >> `$POSTGRESQL_CONF
sed -i "s|#logging_collector =.*|logging_collector = on|" `$POSTGRESQL_CONF || echo "logging_collector = on" >> `$POSTGRESQL_CONF

if ! grep -q "host    all             all" `$POSTGRESQL_PG_HBA; then
    echo "host    all             all             0.0.0.0/0               md5" >> `$POSTGRESQL_PG_HBA
fi

SYSTEMD_OVERRIDE="/etc/systemd/system/postgresql.service.d/override.conf"
mkdir -p /etc/systemd/system/postgresql.service.d
cat > `$SYSTEMD_OVERRIDE <<EOF
[Service]
Environment=PGDATA=`$POSTGRESQL_DATA_DIR
ExecStart=
ExecStart=/usr/lib/postgresql/`$POSTGRESQL_VERSION/bin/postgres -D `$POSTGRESQL_DATA_DIR -c config_file=`$POSTGRESQL_CONF
EOF

systemctl daemon-reload

sudo -u postgres psql -c "ALTER USER postgres PASSWORD '`$POSTGRESQL_ADMIN_PASSWORD';" || true

systemctl start postgresql
systemctl enable postgresql

sleep 5
RETRIES=30
count=0
while [ `$count -lt `$RETRIES ]; do
    if sudo -u postgres psql -c "SELECT 1;" > /dev/null 2>&1; then
        echo "PostgreSQL is ready"
        break
    fi
    count=`$((count+1))
    echo "Waiting for PostgreSQL... Attempt `$count of `$RETRIES"
    sleep 5
done

if [ `$count -eq `$RETRIES ]; then
    echo "ERROR: PostgreSQL did not start properly"
    exit 1
fi

sudo -u postgres psql -c "CREATE DATABASE `$DATABASE_NAME;" || echo "Database may already exist"
sudo -u postgres psql -c "CREATE USER `$DATABASE_USER WITH PASSWORD '`$DATABASE_PASSWORD';" || echo "User may already exist"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE `$DATABASE_NAME TO `$DATABASE_USER;"
sudo -u postgres psql -d `$DATABASE_NAME -c "GRANT ALL ON SCHEMA public TO `$DATABASE_USER;"
sudo -u postgres psql -d `$DATABASE_NAME -c "CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, message TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);" || true

echo "PostgreSQL setup completed successfully at $(date)"
"@
    }

    # Execute PostgreSQL setup script using VM Run Command
    Write-Host "Installing and configuring PostgreSQL (this will take 10-15 minutes)..." -ForegroundColor Cyan
    try {
        # Convert script string to array of lines for Invoke-AzVMRunCommand
        $scriptLines = $setupScript -split "`n"
        
        # Invoke-AzVMRunCommand for Linux VMs
        # Note: Parameter might be -Script or -ScriptString depending on Az.Compute module version
        $runCommandParams = @{
            ResourceGroupName = $ResourceGroupName
            VMName            = $VmName
            CommandId         = "RunShellScript"
        }
        
        # Try -ScriptString first (newer versions), fall back to -Script
        $cmdletExists = Get-Command Invoke-AzVMRunCommand -ErrorAction SilentlyContinue
        if ($cmdletExists) {
            $params = Get-Command Invoke-AzVMRunCommand -ErrorAction SilentlyContinue | 
                      Select-Object -ExpandProperty Parameters
            
            if ($params.ContainsKey('ScriptString')) {
                $runCommandParams['ScriptString'] = $setupScript
            } elseif ($params.ContainsKey('Script')) {
                $runCommandParams['Script'] = $setupScript
            } else {
                # Try Script parameter (array of strings)
                $runCommandParams['Script'] = $scriptLines
            }
            
            $runCommandResult = Invoke-AzVMRunCommand @runCommandParams
            
            if ($runCommandResult.Value -and $runCommandResult.Value[0].Message) {
                $output = $runCommandResult.Value[0].Message
                if ($output -like "*ERROR*" -or $output -like "*error*") {
                    Write-Host "Warning: PostgreSQL setup may have encountered issues. Check logs on VM." -ForegroundColor Yellow
                    Write-Host "Output: $output" -ForegroundColor Yellow
                } else {
                    Write-Host "PostgreSQL setup completed successfully" -ForegroundColor Green
                    Write-Host "Setup output: $output" -ForegroundColor Gray
                }
            } else {
                Write-Host "PostgreSQL setup command executed. Check VM logs for details." -ForegroundColor Yellow
            }
        } else {
            throw "Invoke-AzVMRunCommand cmdlet not found. Ensure Az.Compute module is installed."
        }
    } catch {
        Write-Host "Warning: VM Run Command execution failed. You may need to run the setup script manually via SSH." -ForegroundColor Yellow
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
        # Get VM IP for manual instructions
        $vmDetailsTemp = Get-AzVM -Name $VmName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        $vmNicTemp = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        $vmPublicIPTemp = if ($pip -and $vmNicTemp) { 
            (Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue).IpAddress 
        } else { 
            "VM_IP_ADDRESS" 
        }
        Write-Host "`nTo run manually, SSH to the VM and execute the setup script:" -ForegroundColor Cyan
        Write-Host "  ssh $AdminUsername@$vmPublicIPTemp" -ForegroundColor Yellow
        Write-Host "  # Then copy and run the setup script on the VM" -ForegroundColor Yellow
    }

    # Get final details
    $vmDetails = Get-AzVM -Name $VmName -ResourceGroupName $ResourceGroupName
    $vmNic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName
    $vmPrivateIP = $vmNic.IpConfigurations[0].PrivateIpAddress
    $vmPublicIP = if ($pip) { (Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $ResourceGroupName).IpAddress } else { "N/A" }

    # Output results
    Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
    Write-Host "VM ID: $($vmDetails.Id)" -ForegroundColor Yellow
    Write-Host "VM Public IP: $vmPublicIP" -ForegroundColor Yellow
    Write-Host "VM Private IP: $vmPrivateIP" -ForegroundColor Yellow
    Write-Host "PostgreSQL Port: $PostgreSQLPort" -ForegroundColor Yellow
    Write-Host "Database: $DatabaseName" -ForegroundColor Yellow
    Write-Host "Database User: $DatabaseUser" -ForegroundColor Yellow
    
    if ($vmPublicIP -ne "N/A") {
        Write-Host "`nConnection Commands:" -ForegroundColor Cyan
        Write-Host "SSH: ssh $AdminUsername@$vmPublicIP" -ForegroundColor Yellow
        Write-Host "PostgreSQL: psql -h $vmPublicIP -p $PostgreSQLPort -U $DatabaseUser -d $DatabaseName" -ForegroundColor Yellow
    }
    
    Write-Host "`nVolume Details:" -ForegroundColor Cyan
    Write-Host "Volume ID: $($volumeDetails.Id)" -ForegroundColor Yellow
    Write-Host "Volume IP: $volumeIP" -ForegroundColor Yellow
    Write-Host "PostgreSQL Data Directory: /mnt/$NetAppVolumeName/postgresql-data" -ForegroundColor Yellow

    # Create output object
    $output = @{
        VmId                    = $vmDetails.Id
        VmPublicIP             = $vmPublicIP
        VmPrivateIP            = $vmPrivateIP
        VolumeId               = $volumeDetails.Id
        VolumeIP               = $volumeIP
        PostgreSQLPort         = $PostgreSQLPort
        DatabaseName           = $DatabaseName
        DatabaseUser           = $DatabaseUser
        PostgreSQLDataDirectory = "/mnt/$NetAppVolumeName/postgresql-data"
    }

    return $output

} catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    throw
}

