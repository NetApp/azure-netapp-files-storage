# Azure NetApp Files PowerShell Scripts

This directory contains PowerShell scripts for deploying Azure NetApp Files solutions. These scripts provide automated deployment alternatives to the ARM and Terraform templates, offering the same functionality with PowerShell's scripting capabilities.

## Available Scripts

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
- **PowerShell**: 7.0+ (cross-platform)
- **Az PowerShell module**: 8.0+
- **Required modules**: Az.NetAppFiles, Az.Network, Az.Compute, Az.Resources, Az.LoadBalancer

## Quick Start

1. **Install PowerShell modules:**
   ```powershell
   Install-Module -Name Az -AllowClobber -Force
   ```

2. **Authenticate with Azure:**
   ```powershell
   Connect-AzAccount
   ```

3. **Choose your script:**
   ```powershell
   cd powershell/nfs-volume/          # Basic NFS volume
   cd powershell/linux-vm-with-nfs/   # Single VM with NFS
   cd powershell/multi-linux-vms-with-nfs/  # Multi-VM solution
   ```

4. **Run the script:**
   ```powershell
   # For NFS Volume
   .\deploy-nfs-volume.ps1 -ResourceGroupName "rg-myproject-anf" -VolumeName "my-nfs-volume"
   
   # For Linux VM with NFS
   $password = ConvertTo-SecureString "MySecurePassword123!" -AsPlainText -Force
   .\deploy-linux-vm-with-nfs.ps1 -ResourceGroupName "rg-myproject-vm" -AdminUsername "azureuser" -AdminPassword $password
   
   # For Multi-Linux VMs
   $password = ConvertTo-SecureString "MySecurePassword123!" -AsPlainText -Force
   .\deploy-multi-linux-vms-with-nfs.ps1 -ResourceGroupName "rg-mycluster" -AdminUsername "azureuser" -AdminPassword $password -VmCount 3
   ```

## Script Comparison

| Feature | NFS Volume | Linux VM with NFS | Multi-Linux VMs |
|---------|------------|-------------------|-----------------|
| **Complexity** | Basic | Intermediate | Advanced |
| **VMs Created** | 0 | 1 | 1-10 |
| **NFS Volume** | ✅ | ✅ | ✅ |
| **Load Balancer** | ❌ | ❌ | ✅ (if >1 VM) |
| **Public IPs** | ❌ | ✅ | ✅ (optional) |
| **Cloud-init** | ❌ | ✅ | ✅ |
| **Auto-mount** | ❌ | ✅ | ✅ |

## Common Parameters

All scripts support these common parameters:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ResourceGroupName` | Name of the resource group | Required |
| `Location` | Azure region | `East US` |
| `ProjectName` | Project name for tagging | `dev` |
| `NetAppServiceLevel` | Service level | `Standard` |

## Security Features

### Network Security
- Subnet delegation for NetApp Files
- Network security groups with SSH and NFS rules
- Export policies restricting access to VM subnets

### Authentication
- **Required password input** (no hardcoded defaults for security)
- Secure password handling with SecureString parameters
- Proper credential management

### Best Practices
- Resource tagging for cost management
- Proper subnet isolation
- Root access disabled on NFS volumes
- Export policies limiting access

## Outputs

Each script provides relevant outputs:

### NFS Volume
- `VolumeId`, `VolumeIP`, `MountCommand`

### Linux VM with NFS
- `VmId`, `VmPublicIP`, `SshCommand`, `MountCommand`

### Multi-Linux VMs
- `VmIds[]`, `VmPublicIPs[]`, `LoadBalancerIP`, `SshCommands[]`

## Customization

### Using Parameters
```powershell
# Example for multi-VM script
$password = ConvertTo-SecureString "MySecurePassword123!" -AsPlainText -Force
.\deploy-multi-linux-vms-with-nfs.ps1 `
    -ResourceGroupName "rg-prod-cluster" `
    -AdminUsername "admin" `
    -AdminPassword $password `
    -VmCount 5 `
    -NetAppVolumeSize 1000 `
    -Location "West US 2" `
    -ProjectName "production"
```

### Environment Variables
```powershell
# Set environment variables
$env:AZURE_SUBSCRIPTION_ID = "your-subscription-id"
$env:AZURE_TENANT_ID = "your-tenant-id"
```

## Troubleshooting

### Common Issues

1. **Authentication Errors**
   - Ensure you're logged in: `Connect-AzAccount`
   - Check subscription: `Get-AzContext`

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

- Check individual script help: `Get-Help .\script-name.ps1`
- Review PowerShell logs: `Get-AzLog`
- Check Azure portal for resource status

## Cleanup

To remove all resources:
```powershell
# Remove resource group (this removes all resources)
Remove-AzResourceGroup -Name "your-resource-group-name" -Force
```

## Contributing

When contributing to these scripts:

1. Follow PowerShell best practices
2. Include proper parameter validation
3. Add comprehensive help documentation
4. Test with different parameter combinations
5. Ensure security best practices are followed

## License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details. 