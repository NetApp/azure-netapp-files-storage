# NFS Volume PowerShell Script

This PowerShell script creates a basic Azure NetApp Files setup including:
- Virtual network with delegated subnet for NetApp Files
- NetApp account
- Capacity pool
- NFS volume with specified size and service level

## Prerequisites

- PowerShell 7.0+
- Az PowerShell module 8.0+
- Azure NetApp Files enabled in your subscription

## Quick Start

1. **Install required modules:**
   ```powershell
   Install-Module -Name Az -AllowClobber -Force
   ```

2. **Authenticate with Azure:**
   ```powershell
   Connect-AzAccount
   ```

3. **Run the script:**
   ```powershell
   .\deploy-nfs-volume.ps1 -ResourceGroupName "rg-myproject-anf" -VolumeName "my-nfs-volume"
   ```

## Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `ResourceGroupName` | Name of the resource group | None | Yes |
| `Location` | Azure region | `East US` | No |
| `VolumeName` | Name of the NetApp volume | `anf-volume` | No |
| `VolumeSizeGiB` | Size of the NetApp volume in GiB | `100` | No |
| `VnetName` | Name of the virtual network | `anf-vnet` | No |
| `ProjectName` | Project name for tagging | `dev` | No |
| `AllowedClients` | IP range allowed to access NFS volume | `10.0.0.0/24` | No |

## Examples

### Basic Deployment
```powershell
.\deploy-nfs-volume.ps1 -ResourceGroupName "rg-myproject-anf" -VolumeName "my-nfs-volume"
```

### Customized Deployment
```powershell
.\deploy-nfs-volume.ps1 `
    -ResourceGroupName "rg-prod-anf" `
    -VolumeName "prod-storage" `
    -VolumeSizeGiB 500 `
    -Location "West US 2" `
    -ProjectName "production" `
    -AllowedClients "10.1.0.0/24"
```

## Features

### Network Architecture
- Virtual network: `10.0.0.0/16`
- NetApp subnet: `10.0.1.0/24` (delegated)
- Proper subnet delegation for NetApp Files

### Security
- Export policy configured for specified IP ranges
- Root access disabled on NFS volume
- Network isolation with dedicated subnet

### Resource Management
- Automatic resource group creation
- Consistent tagging for cost management
- Unique naming with timestamps

## Outputs

After deployment, the script returns:
- `VolumeId`: The ID of the NetApp volume
- `VolumeIP`: The IP address of the volume mount target
- `MountCommand`: Command to mount the NFS volume
- `FstabEntry`: Entry for /etc/fstab to mount automatically
- `MountInstructions`: Instructions for mounting the volume

## Mounting the Volume

Use the output `MountCommand` to mount the volume on a Linux VM:

```bash
# Example mount command
mkdir -p /mnt/my-nfs-volume && mount -t nfs -o vers=3 10.0.1.4:/my-nfs-volume /mnt/my-nfs-volume
```

## Cleanup

To remove all resources:
```powershell
Remove-AzResourceGroup -Name "your-resource-group-name" -Force
```

## Troubleshooting

### Common Issues

1. **Authentication Error**: Ensure you're logged into Azure with `Connect-AzAccount`

2. **NetApp Files Not Available**: Verify NetApp Files is enabled in your subscription

3. **Resource Creation Fails**: Check if resources already exist with the same names

4. **Permission Errors**: Ensure you have Contributor or Owner permissions on the resource group

### Getting Help

- Check script help: `Get-Help .\deploy-nfs-volume.ps1`
- Review Azure logs: `Get-AzLog`
- Check Azure portal for resource status

## Security Notes

- The script creates a virtual network with proper subnet delegation for NetApp Files
- Export policy is configured to allow specified IP ranges
- Root access is disabled by default for security
- All resources are tagged for better resource management 