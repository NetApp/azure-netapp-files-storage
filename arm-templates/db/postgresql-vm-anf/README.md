# PostgreSQL on VM with ANF ARM Template

This ARM template deploys PostgreSQL on a Linux VM with Azure NetApp Files (ANF) as the data storage backend.

## Overview

This solution deploys:
- Linux virtual machine (Ubuntu 22.04-LTS)
- Azure NetApp Files volume (NFS) for PostgreSQL data storage
- PostgreSQL installed and configured on the VM
- PostgreSQL data directory on the mounted ANF volume
- Network security group with PostgreSQL and SSH access
- Public IP for remote access

## Prerequisites

- Azure subscription with NetApp Files enabled
- Azure CLI or Azure PowerShell for deployment
- PostgreSQL repository access (internet required for VM installation)

## Quick Start

### Deploy using Azure CLI:

```bash
az group create --name rg-postgresql-vm-anf --location eastus

az deployment group create \
  --resource-group rg-postgresql-vm-anf \
  --template-file postgresql-vm-anf-template.json \
  --parameters postgresql-vm-anf-parameters.json
```

### Deploy using Azure Portal:

1. Click "Deploy to Azure" button (if available in main README)
2. Fill in required parameters
3. Review and deploy

## Parameters

See `postgresql-vm-anf-parameters.json` for all available parameters.

### Required Parameters:
- `adminUsername`: VM admin username
- `adminPasswordOrKey`: VM admin password or SSH key
- `postgresqlAdminPassword`: PostgreSQL superuser password
- `databasePassword`: Database user password

### Key Parameters:
- `postgresqlVersion`: PostgreSQL version (14, 15, or 16)
- `databaseName`: Database name
- `databaseUser`: Database user name
- `netAppVolumeSize`: ANF volume size in GB
- `postgresqlPort`: PostgreSQL port (default: 5432)

## What Gets Deployed

1. **Virtual Network** with two subnets:
   - VM subnet (10.0.1.0/24)
   - NetApp subnet (10.0.2.0/24) with delegation

2. **Network Security Group** with rules for:
   - SSH (port 22)
   - PostgreSQL (port 5432)
   - NFS (port 2049)

3. **Public IP** for VM access

4. **Linux VM** (Ubuntu 22.04-LTS) with:
   - PostgreSQL installed via runCommand
   - ANF volume mounted
   - PostgreSQL data directory on ANF

5. **Azure NetApp Files**:
   - NetApp account
   - Capacity pool
   - NFS volume (data storage)

## PostgreSQL Configuration

- **Data Directory:** `/mnt/postgresql-data/postgresql-data` (on ANF)
- **Configuration:** Configured via runCommand
- **Port:** 5432 (configurable)
- **Access:** Configured to listen on all interfaces
- **Authentication:** MD5 password authentication

## Connection Information

After deployment, use the outputs to connect:

```bash
# Get connection info from outputs
az deployment group show \
  --resource-group rg-postgresql-vm-anf \
  --name <deployment-name> \
  --query properties.outputs

# Connect using psql
psql -h <vm_public_ip> -p 5432 -U <database_user> -d <database_name>
```

## Outputs

The template provides:
- `vmPublicIP`: Public IP address
- `vmPrivateIP`: Private IP address
- `sshCommand`: SSH command to connect
- `psqlCommand`: psql command to connect
- `postgresqlConnectionString`: Connection string (sensitive)
- `postgresqlDataDirectory`: Path to PostgreSQL data on ANF
- `netAppVolumeIP`: ANF volume mount IP

## Important Notes

- **Setup Time:** PostgreSQL installation takes 10-15 minutes via runCommand
- **Internet Required:** VM needs internet access for PostgreSQL installation
- **Data Persistence:** All PostgreSQL data is stored on ANF volume
- **Backups:** Implement your own backup strategy
- **Single VM:** This is a single VM setup (not HA)

## Troubleshooting

### Check Deployment Status:
```bash
az deployment group show \
  --resource-group rg-postgresql-vm-anf \
  --name <deployment-name>
```

### View RunCommand Logs:
```bash
ssh azureuser@<vm_public_ip>
sudo cat /var/log/postgresql-setup.log
```

### Check PostgreSQL Status:
```bash
sudo systemctl status postgresql
sudo -u postgres psql -c "SELECT version();"
```

## Cleanup

To delete all resources:
```bash
az group delete --name rg-postgresql-vm-anf --yes --no-wait
```

**Warning:** This will delete the PostgreSQL database and all data on the ANF volume.

