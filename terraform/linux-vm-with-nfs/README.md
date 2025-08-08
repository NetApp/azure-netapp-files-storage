# Linux VM with NFS Terraform Template

This Terraform template deploys a complete solution with:
- Virtual network and subnets (VM and NetApp Files)
- Linux virtual machine (Ubuntu 18.04-LTS)
- NFS volume automatically mounted to the VM
- Network security group configuration
- Public IP for remote access

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
| `admin_username` | Username for the VM | `azureuser` | Yes |
| `authentication_type` | Authentication type | `password` | No |
| `admin_password` | Password for the VM | `null` | Yes* |
| `ssh_public_key` | SSH public key | `null` | Yes* |
| `vm_name` | Name of the VM | `linuxVM` | No |
| `vm_size` | VM size | `Standard_D2s_v3` | No |
| `location` | Azure region | `eastus` | No |
| `netapp_volume_name` | NFS volume name | `anf-vol1` | No |
| `netapp_volume_size` | Volume size in GB | `100` | No |
| `netapp_service_level` | Service level | `Standard` | No |
| `project_name` | Project name | `dev` | No |

*Required based on authentication type

## Customization

Create a `terraform.tfvars` file for customization:

```hcl
admin_username = "myuser"
admin_password = "MySecurePassword123!"
vm_name = "my-linux-vm"
vm_size = "Standard_D4s_v3"
location = "westus2"
netapp_volume_name = "my-nfs-volume"
netapp_volume_size = 200
netapp_service_level = "Premium"
project_name = "production"
```

## Features

### Automatic NFS Mounting
The template uses cloud-init to automatically:
- Install NFS client packages
- Mount the NFS volume at `/mnt/{volume_name}`
- Add the mount to `/etc/fstab` for persistence
- Create a test file to verify the mount

### Security
- Network security group with SSH (port 22) and NFS (port 2049) rules
- Subnet delegation for NetApp Files
- Export policy configured for the VM subnet
- Root access disabled on NFS volume

### Network Architecture
- Virtual network: `10.0.0.0/16`
- VM subnet: `10.0.1.0/24`
- NetApp subnet: `10.0.2.0/24` (delegated)

## Outputs

After deployment, Terraform will output:
- `vm_id`: The ID of the Linux VM
- `vm_public_ip`: Public IP address for SSH access
- `vm_private_ip`: Private IP address of the VM
- `volume_id`: The ID of the NetApp volume
- `volume_ip`: The IP address of the volume mount target
- `ssh_command`: SSH command to connect to the VM
- `mount_command`: Command to manually mount the NFS volume

## Connecting to the VM

Use the output `ssh_command` to connect:

```bash
# Example
ssh azureuser@20.124.56.78
```

## Verifying the NFS Mount

Once connected to the VM:

```bash
# Check if the volume is mounted
df -h /mnt/anf-vol1

# List contents
ls -la /mnt/anf-vol1/

# Check the test file
cat /mnt/anf-vol1/mount-test.txt
```

## Cleanup

To destroy the infrastructure:
```bash
terraform destroy
```

## Troubleshooting

### Common Issues

1. **Authentication Error**: Ensure you've set the correct `admin_username` and `admin_password` or `ssh_public_key`

2. **NFS Mount Fails**: Check that the VM can reach the NetApp volume IP and that the export policy allows the VM's subnet

3. **Cloud-init Issues**: Check the cloud-init logs:
   ```bash
   sudo cat /var/log/cloud-init-output.log
   ```

### Security Notes

- Change default passwords after deployment
- Consider using SSH keys instead of passwords
- Review and restrict NSG rules for production use
- Enable Azure Security Center monitoring 