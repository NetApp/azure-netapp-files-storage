# Multi-Linux VMs with NFS Terraform Template

This Terraform template deploys an enterprise solution with:
- Multiple Linux virtual machines (1-10 VMs)
- Shared NFS volume accessible by all VMs
- Load balancer for high availability (when VM count > 1)
- Network security group configuration
- Optional public IPs for direct VM access

## Prerequisites

- Terraform 1.0+
- Azure CLI for authentication
- AzureRM Provider 3.0+
- Azure NetApp Files enabled in your subscription

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
   # For password authentication
   export TF_VAR_admin_username="azureuser"
   export TF_VAR_admin_password="YourSecurePassword123!"
   
   # OR for SSH key authentication
   export TF_VAR_admin_username="azureuser"
   export TF_VAR_authentication_type="sshPublicKey"
   export TF_VAR_ssh_public_key="ssh-rsa AAAA..."
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
| `admin_username` | Username for all VMs | `azureuser` | Yes |
| `authentication_type` | Authentication type | `password` | No |
| `admin_password` | Password for all VMs | `null` | Yes* |
| `ssh_public_key` | SSH public key | `null` | Yes* |
| `vm_name_prefix` | VM name prefix | `azlinuxvms` | No |
| `vm_count` | Number of VMs (1-10) | `3` | No |
| `vm_size` | VM size | `Standard_D2s_v3` | No |
| `create_public_ips` | Create public IPs | `true` | No |
| `location` | Azure region | `eastus` | No |
| `netapp_volume_name` | Shared NFS volume name | `azlinux-shared-nfs` | No |
| `netapp_volume_size` | Volume size in GB | `500` | No |
| `netapp_service_level` | Service level | `Standard` | No |
| `project_name` | Project name | `dev` | No |

*Required based on authentication type

## Customization

Create a `terraform.tfvars` file for customization:

```hcl
admin_username = "myuser"
admin_password = "MySecurePassword123!"
vm_name_prefix = "mycluster"
vm_count = 5
vm_size = "Standard_D4s_v3"
create_public_ips = true
location = "westus2"
netapp_volume_name = "shared-storage"
netapp_volume_size = 1000
netapp_service_level = "Premium"
project_name = "production"
```

## Features

### Shared NFS Storage
- Single NFS volume shared across all VMs
- Each VM gets its own directory: `/mnt/{volume_name}/vm-{index}`
- Shared directory for collaboration: `/mnt/{volume_name}/shared`
- Automatic mounting via cloud-init

### High Availability
- Load balancer automatically created when VM count > 1
- Standard SKU load balancer with static public IP
- Backend pool includes all VMs
- Health checks and traffic distribution

### Network Architecture
- Virtual network: `10.0.0.0/16`
- VM subnet: `10.0.1.0/24`
- NetApp subnet: `10.0.2.0/24` (delegated)
- Network security group with SSH and NFS rules

### VM Naming Convention
VMs are named using the pattern: `{vm_name_prefix}{number}`
- Example: `azlinuxvms1`, `azlinuxvms2`, `azlinuxvms3`

## Outputs

After deployment, Terraform will output:
- `vm_ids`: Array of VM IDs
- `vm_public_ips`: Array of public IP addresses (if enabled)
- `vm_private_ips`: Array of private IP addresses
- `volume_id`: The ID of the shared NetApp volume
- `volume_ip`: The IP address of the volume mount target
- `load_balancer_ip`: Load balancer public IP (if VM count > 1)
- `ssh_commands`: Array of SSH commands for each VM
- `mount_command`: Command to manually mount the NFS volume

## Connecting to VMs

### Direct Access (if public IPs enabled)
```bash
# SSH to specific VM
ssh azureuser@20.124.56.78

# Or use the output commands
terraform output ssh_commands
```

### Through Load Balancer (if VM count > 1)
```bash
# SSH through load balancer
ssh azureuser@<load_balancer_ip>
```

## Verifying the Shared Storage

Once connected to any VM:

```bash
# Check if the volume is mounted
df -h /mnt/azlinux-shared-nfs

# List all VM directories
ls -la /mnt/azlinux-shared-nfs/

# Check your VM's directory
ls -la /mnt/azlinux-shared-nfs/vm-1/

# Access shared directory
ls -la /mnt/azlinux-shared-nfs/shared/
```

## Use Cases

### Development/Testing
- Multiple developers working on shared codebase
- Shared configuration files and data
- Easy collaboration and file sharing

### High-Performance Computing
- Shared input/output data
- Distributed processing with shared results
- Cluster file system for HPC workloads

### Web Application Clusters
- Shared application files
- Common configuration and assets
- Session data and logs

## Cleanup

To destroy the infrastructure:
```bash
terraform destroy
```

## Troubleshooting

### Common Issues

1. **VM Creation Fails**: Check VM quotas and available capacity in the region

2. **NFS Mount Issues**: Verify all VMs can reach the NetApp volume IP

3. **Load Balancer Health**: Check if VMs are healthy in the backend pool

4. **Cloud-init Problems**: Check logs on individual VMs:
   ```bash
   sudo cat /var/log/cloud-init-output.log
   ```

### Performance Optimization

1. **Volume Size**: Increase `netapp_volume_size` for more storage
2. **Service Level**: Use `Premium` or `Ultra` for better performance
3. **VM Size**: Choose larger VMs for compute-intensive workloads
4. **Network**: Ensure VMs and NetApp volume are in the same region

### Security Notes

- Use SSH keys instead of passwords for production
- Restrict NSG rules to specific IP ranges
- Enable Azure Security Center monitoring
- Consider Azure Bastion for secure access
- Implement proper backup strategies for shared data 