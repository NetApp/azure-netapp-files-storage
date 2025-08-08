# Azure NetApp Files Storage Templates

A collection of Infrastructure as Code templates for deploying Azure NetApp Files solutions using ARM Templates, Terraform, and PowerShell.

## Repository Structure

```
azure-netapp-files-storage/
├── arm-templates/
│   ├── nfs-volume/
│   ├── linux-vm-with-nfs/
│   └── multi-linux-vms-with-nfs/
├── terraform/
│   ├── nfs-volume/
│   ├── linux-vm-with-nfs/
│   └── multi-linux-vms-with-nfs/
├── powershell/
│   ├── nfs-volume/
│   ├── linux-vm-with-nfs/
│   └── multi-linux-vms-with-nfs/
├── docs/
│   ├── architecture-diagrams/
│   ├── deployment-guides/
│   └── troubleshooting/
└── examples/
    ├── parameter-files/
    └── sample-configurations/
```

## Available Templates

| Template | ARM Templates | Terraform | PowerShell |
|----------|---------------|-----------|------------|
| NFS Volume | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| Linux VM with NFS | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| Multi Linux VMs with NFS | :white_check_mark: | :white_check_mark: | :white_check_mark: |

## Coming Soon

- workload templates

## Prerequisites

### Azure Requirements

- Active Azure subscription
- Contributor or Owner permissions on target resource group
- Azure NetApp Files enabled in your subscription
- Appropriate regional availability for Azure NetApp Files

### Tools Required

**For ARM Templates:**
- Azure CLI 2.30.0+ or Azure PowerShell 6.0+
- Visual Studio Code with Azure Resource Manager Tools extension (recommended)

**For Terraform:**
- Terraform 1.0+
- Azure CLI for authentication
- AzureRM Provider 3.0+

**For PowerShell:**
- PowerShell 7.0+ (cross-platform)
- Az PowerShell module 8.0+

## Deployment Options

### Option 1: Deploy with GitHub Actions (Recommended)
[![Deploy with GitHub Actions](https://img.shields.io/badge/Deploy%20with-GitHub%20Actions-2ea44f)](../../actions/workflows/deploy.yml)

1. **Fork/Clone this repository**
2. **Set up Azure service principal credentials:**
   ```bash
   az ad sp create-for-rbac --name "GitHubActions" --role Contributor --scope /subscriptions/YOUR-SUBSCRIPTION-ID --sdk-auth
   ```
3. **Add the JSON output as a GitHub secret named `AZURE_CREDENTIALS`**
4. **Go to Actions tab and run the "Deploy ANF & VM Infrastructure" workflow**

### Option 2: Deploy to Azure

Choose your deployment scenario and click the button to deploy directly to Azure Portal:

#### 📁 Basic NFS Volume
Deploy only Azure NetApp Files infrastructure (account, pool, volume)

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FNetApp%2Fazure-netapp-files-storage%2Fmain%2Farm-templates%2Fnfs-volume%2Fnetapp-volume-template.json?target=_blank" target="_blank">
<img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure"/>
</a>

**Includes:** NetApp Account, Capacity Pool, NFS Volume, Virtual Network with delegated subnet

#### 🖥️ Single Linux VM with NFS
Deploy Linux VM with mounted NFS volume and network configuration

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FNetApp%2Fazure-netapp-files-storage%2Fmain%2Farm-templates%2Flinux-vm-with-nfs%2Flinux-vm-anf-nfs-template.json?target=_blank" target="_blank">
<img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure"/>
</a>

**Includes:** Ubuntu 18.04-LTS VM, Mounted NFS volume, Network Security Group, Public IP for SSH access

#### 🏢 Multiple Linux VMs with NFS
Deploy multiple VMs with shared NFS storage and load balancing

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FNetApp%2Fazure-netapp-files-storage%2Fmain%2Farm-templates%2Fmulti-linux-vms-with-nfs%2Fazlinux-multi-vm-anf-template.json?target=_blank" target="_blank">
<img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure"/>
</a>

**Includes:** Multiple Ubuntu VMs (configurable count), Shared NFS volume across all VMs, Load Balancer for high availability, Network Security Groups

**💡 How it works:**
1. **Click any "Deploy to Azure" button above**
2. **Sign in with your Azure credentials**
3. **Fill in the required parameters**
4. **Click "Review + Create" to deploy**

### Option 3: Manual Deployment

1. **Clone this repository:**
   ```bash
   git clone https://github.com/NetApp/azure-netapp-files-storage.git
   cd azure-netapp-files-storage
   ```

2. **Choose your preferred tool:**
   ```bash
   cd arm-templates/     # for ARM Templates
   cd terraform/        # for Terraform
   cd powershell/       # for PowerShell
   ```

3. **Start with the basic NFS volume:**
   ```bash
   cd nfs-volume/
   ```

4. **Follow the README** in each template folder for specific deployment instructions.

## Template Descriptions

### NFS Volume
Creates a basic Azure NetApp Files setup including:
- NetApp account
- Capacity pool
- NFS volume with specified size and service level

### Linux VM with NFS
Deploys a complete solution with:
- Virtual network and subnet
- Linux virtual machine
- NFS volume mounted to the VM
- Network security group configuration

### Multi Linux VMs with NFS
Enterprise scenario including:
- Multiple Linux virtual machines
- Shared NFS volumes across VMs
- Load balancing configuration
- High availability setup

## Security Best Practices

> [!WARNING]
> Never commit secrets to the repository

- Use Azure Key Vault for storing sensitive data
- Keep environment-specific parameter files separate and secure
- Implement proper network security groups and subnet delegation
- Use managed identities and RBAC for access control
- Enable encryption in transit and at rest
- Use environment variables for passwords (e.g., `ADMIN_PASSWORD`)
- Replace placeholder passwords with secure values before deployment


## Documentation

- [Deployment Guides](docs/deployment-guides/) - Step-by-step deployment instructions
- [Architecture Diagrams](docs/architecture-diagrams/) - Visual solution designs
- [Troubleshooting](docs/troubleshooting/) - Common issues and solutions
- [Azure NetApp Files Official Documentation](https://docs.microsoft.com/azure/azure-netapp-files/)

## Support

- **Issues**: Report problems or request features using GitHub Issues
- **Questions**: Ask questions in GitHub Discussions
- **Documentation**: Check the docs/ folder for detailed guides

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Maintained by:** Prabu Arjunan  
**Last Updated:** 8/8/25
