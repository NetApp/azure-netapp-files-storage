# NFS Volume Terraform Template

This Terraform template creates a basic Azure NetApp Files setup including:
- Virtual network with delegated subnet for NetApp Files
- NetApp account
- Capacity pool
- NFS volume with specified size and service level

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

3. **Review the plan:**
   ```bash
   terraform plan
   ```

4. **Deploy the infrastructure:**
   ```bash
   terraform apply
   ```

## Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `volume_name` | Name of the NetApp volume | `my-nfs-volume` | No |
| `volume_size_gib` | Size of the NetApp volume in GiB | `100` | No |
| `location` | Location for all resources | `eastus` | No |
| `vnet_name` | Name of the virtual network | `anf-vnet` | No |
| `project_name` | Project name for tagging | `dev` | No |
| `allowed_clients` | IP range allowed to access NFS volume | `10.0.0.0/24` | No |

## Customization

To customize the deployment, create a `terraform.tfvars` file:

```hcl
volume_name = "my-custom-volume"
volume_size_gib = 200
location = "westus2"
project_name = "production"
allowed_clients = "10.1.0.0/24"
```

## Outputs

After deployment, Terraform will output:
- `volume_id`: The ID of the NetApp volume
- `volume_ip`: The IP address of the volume mount target
- `mount_command`: Command to mount the NFS volume
- `fstab_entry`: Entry for /etc/fstab to mount automatically
- `mount_instructions`: Instructions for mounting the volume

## Mounting the Volume

Use the output `mount_command` to mount the volume on a Linux VM:

```bash
# Example mount command
mkdir -p /mnt/my-nfs-volume && mount -t nfs -o vers=3 10.0.1.4:/my-nfs-volume /mnt/my-nfs-volume
```

## Cleanup

To destroy the infrastructure:
```bash
terraform destroy
```

## Security Notes

- The template creates a virtual network with proper subnet delegation for NetApp Files
- Export policy is configured to allow specified IP ranges
- Root access is disabled by default for security
- All resources are tagged for better resource management 