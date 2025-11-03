# PostgreSQL on VM with ANF Terraform Template

This Terraform template deploys PostgreSQL on a Linux VM with Azure NetApp Files (ANF) as the data storage backend.

## Overview

This solution deploys:
- Linux virtual machine (Ubuntu 22.04-LTS)
- Azure NetApp Files volume (NFS) for PostgreSQL data storage
- PostgreSQL installed and configured on the VM
- PostgreSQL data directory on the mounted ANF volume
- Network security group with PostgreSQL and SSH access
- Optional public IP for remote access

## Prerequisites

- Terraform 1.0+
- Azure CLI for authentication
- AzureRM Provider 3.0+
- AzAPI Provider 1.0+
- Azure NetApp Files enabled in your subscription
- PostgreSQL repository access (internet required for installation)

## Quick Start

1. **Authenticate with Azure:**
   ```bash
   az login
   ```

2. **Initialize Terraform:**
   ```bash
   terraform init
   ```

3. **Set required variables:**
   ```bash
   export TF_VAR_admin_username="azureuser"
   export TF_VAR_admin_password="YourVMAdminPassword123!"
   export TF_VAR_postgresql_admin_password="PostgresAdminPassword123!"
   export TF_VAR_database_password="DatabaseUserPassword123!"
   ```

4. **Review the plan:**
   ```bash
   terraform plan
   ```

5. **Deploy the infrastructure:**
   ```bash
   terraform apply
   ```

## Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `vm_name` | Name of the virtual machine | `postgresql-vm` | No |
| `admin_username` | Username for the VM | `azureuser` | Yes |
| `admin_password` | Password for the VM | None | Yes |
| `authentication_type` | Authentication type (password/sshPublicKey) | `password` | No |
| `ssh_public_key` | SSH public key | `null` | No |
| `vm_size` | VM size | `Standard_D2s_v3` | No |
| `location` | Location for all resources | `eastus` | No |
| `postgresql_version` | PostgreSQL version (14, 15, 16) | `15` | No |
| `postgresql_admin_password` | Password for PostgreSQL superuser | None | Yes |
| `database_name` | Name of the database to create | `mydb` | No |
| `database_user` | Database user name | `appuser` | No |
| `database_password` | Database user password | None | Yes |
| `netapp_volume_size` | ANF volume size in GB | `200` | No |
| `netapp_service_level` | ANF service level | `Standard` | No |
| `create_public_ip` | Create public IP address | `true` | No |
| `postgresql_port` | PostgreSQL port | `5432` | No |
| `project_name` | Project name for tagging | `dev` | No |

## Customization

Create a `terraform.tfvars` file:

```hcl
admin_username           = "azureuser"
admin_password           = "YourVMAdminPassword123!"
postgresql_admin_password = "PostgresAdminPassword123!"
database_password        = "DatabaseUserPassword123!"

postgresql_version = "15"
database_name      = "mydb"
database_user      = "appuser"

vm_size            = "Standard_D2s_v3"
netapp_volume_size = 200

create_public_ip   = true
postgresql_port    = 5432
```

## What Gets Deployed

1. **Virtual Network** with two subnets:
   - VM subnet (10.0.1.0/24)
   - NetApp subnet (10.0.2.0/24) with delegation

2. **Network Security Group** with rules for:
   - SSH (port 22)
   - PostgreSQL (port 5432)
   - NFS (port 2049)

3. **Public IP** (optional, default: enabled)

4. **Linux VM** (Ubuntu 22.04-LTS) with:
   - PostgreSQL installed
   - ANF volume mounted
   - PostgreSQL data directory on ANF

5. **Azure NetApp Files**:
   - NetApp account
   - Capacity pool
   - NFS volume (data storage)

## PostgreSQL Configuration

- **Data Directory:** `/mnt/postgresql-data/postgresql-data` (on ANF)
- **Configuration:** `/mnt/postgresql-data/postgresql-data/postgresql.conf`
- **Port:** 5432 (configurable)
- **Access:** Configured to listen on all interfaces
- **Authentication:** MD5 password authentication

## Connecting to PostgreSQL

Use the output `psql_command` or construct manually:

```bash
psql -h <vm_public_ip> -p 5432 -U appuser -d mydb
```

Or use the connection string from outputs:

```bash
psql "host=<vm_public_ip> port=5432 dbname=mydb user=appuser password=YourPassword"
```

## Outputs

After deployment:
- `vm_id`: VM resource ID
- `vm_public_ip`: Public IP address (if created)
- `vm_private_ip`: Private IP address
- `postgresql_connection_string`: Connection string for database user
- `postgresql_admin_connection_string`: Connection string for postgres user
- `psql_command`: psql command to connect
- `ssh_command`: SSH command to connect to VM
- `volume_id`: ANF volume ID
- `postgresql_data_directory`: Path to PostgreSQL data on ANF

## Important Notes

- **Internet Required:** VM needs internet access to install PostgreSQL from official repository
- **Setup Time:** PostgreSQL installation and configuration takes 5-10 minutes
- **Data Persistence:** All PostgreSQL data is stored on ANF volume
- **Backups:** You must implement your own backup strategy
- **High Availability:** This is a single VM setup. For HA, consider replication or multiple VMs

## Security Considerations

- Change all default passwords
- Restrict NSG rules to specific IP ranges in production
- Consider using private IP only (set `create_public_ip = false`)
- Use SSH keys instead of passwords (`authentication_type = "sshPublicKey"`)
- Implement PostgreSQL SSL/TLS in production

## Troubleshooting

### Check PostgreSQL Status
```bash
ssh azureuser@<vm_public_ip>
sudo systemctl status postgresql
```

### View Setup Logs
```bash
sudo cat /var/log/postgresql-setup.log
```

### Verify ANF Mount
```bash
mount | grep nfs
df -h /mnt/postgresql-data
```

### Connect to PostgreSQL Locally (on VM)
```bash
sudo -u postgres psql
```

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

**Warning:** This will delete the PostgreSQL database and all data on the ANF volume.

