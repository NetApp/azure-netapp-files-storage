# Azure NetApp Files Terraform Templates

This directory contains Terraform templates for deploying Azure NetApp Files solutions. These templates provide Infrastructure as Code (IaC) alternatives to the ARM templates, offering the same functionality with Terraform's declarative syntax.

## Available Templates

### 1. [NFS Volume](./nfs-volume/)
**Basic NetApp Files Setup**
- Virtual network with delegated subnet
- NetApp account and capacity pool
- NFS volume with export policy
- **Use Case**: Simple NFS storage deployment

### 2. [Linux VM with NFS](./linux-vm-with-nfs/)
**Single VM with Mounted Storage**
- Complete virtual network setup
- Linux VM (Ubuntu 18.04-LTS)
- NFS volume automatically mounted
- Network security group configuration
- **Use Case**: Development, testing, single-server applications

### 3. [Multi-Linux VMs with NFS](./multi-linux-vms-with-nfs/)
**Enterprise Multi-VM Solution**
- Multiple Linux VMs (1-10)
- Shared NFS volume across all VMs
- Load balancer for high availability
- Optional public IPs for direct access
- **Use Case**: Clusters, HPC, web application farms

## Prerequisites

### Azure Requirements
- Active Azure subscription
- Contributor or Owner permissions
- Azure NetApp Files enabled in your subscription
- Appropriate regional availability

### Tools Required
- **Terraform**: 1.0+
- **Azure CLI**: For authentication
- **AzureRM Provider**: 3.0+

## Quick Start

1. **Choose your template:**
   ```bash
   cd terraform/nfs-volume/          # Basic NFS volume
   cd terraform/linux-vm-with-nfs/   # Single VM with NFS
   cd terraform/multi-linux-vms-with-nfs/  # Multi-VM solution
   ```

2. **Authenticate with Azure:**
   ```bash
   az login
   ```

3. **Initialize Terraform:**
   ```bash
   terraform init
   ```

4. **Set required variables:**
   ```bash
   # For VM templates, set authentication
   export TF_VAR_admin_username="azureuser"
   export TF_VAR_admin_password="YourSecurePassword123!"
   ```

5. **Deploy:**
   ```bash
   terraform plan
   terraform apply
   ```

## Template Comparison

| Feature | NFS Volume | Linux VM with NFS | Multi-Linux VMs |
|---------|------------|-------------------|-----------------|
| **Complexity** | Basic | Intermediate | Advanced |
| **VMs Created** | 0 | 1 | 1-10 |
| **NFS Volume** | ✅ | ✅ | ✅ |
| **Load Balancer** | ❌ | ❌ | ✅ (if >1 VM) |
| **Public IPs** | ❌ | ✅ | ✅ (optional) |
| **Cloud-init** | ❌ | ✅ | ✅ |
| **Auto-mount** | ❌ | ✅ | ✅ |

## Common Variables

All templates support these common variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `location` | Azure region | `eastus` |
| `project_name` | Project name for tagging | `dev` |
| `netapp_service_level` | Service level | `Standard` |

## Security Features

### Network Security
- Subnet delegation for NetApp Files
- Network security groups with SSH and NFS rules
- Export policies restricting access to VM subnets

### Authentication
- Support for both password and SSH key authentication
- Secure password handling with sensitive variables
- SSH key validation

### Best Practices
- Resource tagging for cost management
- Proper subnet isolation
- Root access disabled on NFS volumes
- Export policies limiting access

## Outputs

Each template provides relevant outputs:

### NFS Volume
- `volume_id`, `volume_ip`, `mount_command`

### Linux VM with NFS
- `vm_id`, `vm_public_ip`, `ssh_command`, `mount_command`

### Multi-Linux VMs
- `vm_ids[]`, `vm_public_ips[]`, `load_balancer_ip`, `ssh_commands[]`

## Customization

### Using terraform.tfvars
Create a `terraform.tfvars` file in any template directory:

```hcl
# Example for multi-VM template
admin_username = "myuser"
admin_password = "MySecurePassword123!"
vm_count = 5
vm_size = "Standard_D4s_v3"
location = "westus2"
project_name = "production"
```

### Environment Variables
Set variables using environment variables:

```bash
export TF_VAR_admin_username="azureuser"
export TF_VAR_location="westus2"
export TF_VAR_project_name="myproject"
```

## Troubleshooting

### Common Issues

1. **Authentication Errors**
   - Ensure Azure CLI is logged in: `az login`
   - Check subscription: `az account show`

2. **NetApp Files Not Available**
   - Verify NetApp Files is enabled in your subscription
   - Check regional availability

3. **VM Creation Fails**
   - Check VM quotas in the region
   - Verify VM size availability

4. **NFS Mount Issues**
   - Ensure VMs can reach NetApp volume IP
   - Check export policy allows VM subnet

### Getting Help

- Check individual template README files for specific guidance
- Review Terraform logs: `terraform plan -detailed-exitcode`
- Check Azure portal for resource status

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

## Contributing

When contributing to these templates:

1. Follow Terraform best practices
2. Include proper variable validation
3. Add comprehensive documentation
4. Test with different variable combinations
5. Ensure security best practices are followed

## License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details. 