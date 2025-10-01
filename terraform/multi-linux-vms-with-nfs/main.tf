terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {
}

# Variables are defined in variables.tf

# Local values
locals {
  # Resource group reference (either created or existing)
  resource_group_name     = var.create_resource_group ? azurerm_resource_group.rg[0].name : data.azurerm_resource_group.existing[0].name
  resource_group_location = var.create_resource_group ? azurerm_resource_group.rg[0].location : data.azurerm_resource_group.existing[0].location

  common_tags = {
    project              = var.project_name
    created_by           = "Terraform"
    created_on           = formatdate("YYYY-MM-DD", timestamp())
    anf_plg              = "true"
    anf_template_version = "1.0.0"
    anf_deployment_id    = formatdate("YYYYMMDD-hhmmss", timestamp())
  }

  # Network configuration
  vnet_address_prefix  = "10.0.0.0/16"
  vm_subnet_prefix     = "10.0.1.0/24"
  netapp_subnet_prefix = "10.0.2.0/24"

  # VM names
  vm_names = [for i in range(var.vm_count) : "${var.vm_name_prefix}${i + 1}"]
}

# Random string for unique naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Resource Group (conditional - create or use existing)
resource "azurerm_resource_group" "rg" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Data source for existing resource group
data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  address_space       = [local.vnet_address_prefix]
  tags = merge(local.common_tags, {
    purpose = "Multi-VM NetApp Files Infrastructure"
  })
}

# Subnet for VMs
resource "azurerm_subnet" "vm_subnet" {
  name                 = var.subnet_name_vm
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.vm_subnet_prefix]
}

# Subnet for NetApp Files
resource "azurerm_subnet" "netapp_subnet" {
  name                 = var.subnet_name_netapp
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.netapp_subnet_prefix]

  delegation {
    name = "NetAppDelegation"
    service_delegation {
      name = "Microsoft.Netapp/volumes"
    }
  }
}

# Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${var.vm_name_prefix}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  tags                = local.common_tags

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "NFS"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2049"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# NetApp Account
resource "azurerm_netapp_account" "netapp_account" {
  name                = var.netapp_account_name
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  tags = merge(local.common_tags, {
    created_by = "ANF-Terraform"
  })
}

# NetApp Capacity Pool
resource "azurerm_netapp_pool" "netapp_pool" {
  name                = var.netapp_pool_name
  account_name        = azurerm_netapp_account.netapp_account.name
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  service_level       = var.netapp_service_level
  size_in_tb          = var.netapp_pool_size_in_tb
}

# NetApp Volume
resource "azurerm_netapp_volume" "netapp_volume" {
  name                = var.netapp_volume_name
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  account_name        = azurerm_netapp_account.netapp_account.name
  pool_name           = azurerm_netapp_pool.netapp_pool.name
  volume_path         = var.netapp_volume_name
  service_level       = var.netapp_service_level
  subnet_id           = azurerm_subnet.netapp_subnet.id
  storage_quota_in_gb = var.netapp_volume_size
  protocols           = ["NFSv3"]

  tags = merge(local.common_tags, {
    volume_name = var.netapp_volume_name
    created_by  = "ANF-Terraform"
  })
}

# Configure export policy using AzAPI provider (workaround for AzureRM limitation)
resource "azapi_update_resource" "netapp_volume_export_policy" {
  type        = "Microsoft.NetApp/netAppAccounts/capacityPools/volumes@2023-05-01"
  resource_id = azurerm_netapp_volume.netapp_volume.id

  body = jsonencode({
    properties = {
      exportPolicy = {
        rules = [
          {
            ruleIndex           = 1
            allowedClients      = "0.0.0.0/0"
            unixReadOnly        = false
            unixReadWrite       = true
            cifs                = false
            nfsv3               = true
            nfsv41              = false
            rootAccessEnabled   = true
            kerberos5ReadOnly   = false
            kerberos5ReadWrite  = false
            kerberos5iReadOnly  = false
            kerberos5iReadWrite = false
            kerberos5pReadOnly  = false
            kerberos5pReadWrite = false
          }
        ]
      }
    }
  })

  depends_on = [azurerm_netapp_volume.netapp_volume]
}

# VM Run Command to mount NFS volume (matches ARM template's runCommands)
resource "azurerm_virtual_machine_run_command" "mount_nfs" {
  count              = var.vm_count
  name               = "mountANFVolume"
  location           = local.resource_group_location
  virtual_machine_id = azurerm_linux_virtual_machine.vm[count.index].id

  source {
    script = templatefile("${path.module}/mount-nfs.sh", {
      volume_ip   = azurerm_netapp_volume.netapp_volume.mount_ip_addresses[0]
      volume_name = var.netapp_volume_name
      vm_index    = count.index + 1
    })
  }

  depends_on = [
    azurerm_linux_virtual_machine.vm,
    azapi_update_resource.netapp_volume_export_policy
  ]
}

# Public IPs (conditional)
resource "azurerm_public_ip" "pip" {
  count               = var.create_public_ips ? var.vm_count : 0
  name                = "pip-${local.vm_names[count.index]}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Network Interfaces
resource "azurerm_network_interface" "nic" {
  count               = var.vm_count
  name                = "nic-${local.vm_names[count.index]}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.create_public_ips ? azurerm_public_ip.pip[count.index].id : null
  }
}

# Associate NSG with NICs
resource "azurerm_network_interface_security_group_association" "nsg_association" {
  count                     = var.vm_count
  network_interface_id      = azurerm_network_interface.nic[count.index].id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Linux VMs
resource "azurerm_linux_virtual_machine" "vm" {
  count               = var.vm_count
  name                = local.vm_names[count.index]
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  size                = var.vm_size
  admin_username      = var.admin_username
  tags = merge(local.common_tags, {
    vm_index = count.index + 1
  })

  network_interface_ids = [
    azurerm_network_interface.nic[count.index].id
  ]

  admin_password                  = var.authentication_type == "password" ? var.admin_password : null
  disable_password_authentication = var.authentication_type == "sshPublicKey" ? true : false

  dynamic "admin_ssh_key" {
    for_each = var.authentication_type == "sshPublicKey" ? [1] : []
    content {
      username   = var.admin_username
      public_key = var.ssh_public_key
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Custom data removed - using VM extension for NFS mounting instead
}

# Load Balancer (optional - for high availability) - Internal only
resource "azurerm_lb" "lb" {
  count               = var.vm_count > 1 ? 1 : 0
  name                = "lb-${var.vm_name_prefix}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  sku                 = "Standard"
  tags                = local.common_tags

  frontend_ip_configuration {
    name                          = "frontend-ip"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.vm_subnet.id
  }
}

# Load Balancer Backend Pool
resource "azurerm_lb_backend_address_pool" "backend_pool" {
  count           = var.vm_count > 1 ? 1 : 0
  name            = "backend-pool"
  loadbalancer_id = azurerm_lb.lb[0].id
}

# Associate VMs with Load Balancer Backend Pool
resource "azurerm_network_interface_backend_address_pool_association" "lb_association" {
  count                   = var.vm_count > 1 ? var.vm_count : 0
  network_interface_id    = azurerm_network_interface.nic[count.index].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.backend_pool[0].id
}

# Outputs
output "vm_ids" {
  description = "The IDs of the Linux VMs"
  value       = azurerm_linux_virtual_machine.vm[*].id
}

output "vm_public_ips" {
  description = "The public IP addresses of the VMs"
  value       = var.create_public_ips ? azurerm_public_ip.pip[*].ip_address : []
}

output "vm_private_ips" {
  description = "The private IP addresses of the VMs"
  value       = azurerm_network_interface.nic[*].private_ip_address
}

output "volume_id" {
  description = "The ID of the NetApp volume"
  value       = azurerm_netapp_volume.netapp_volume.id
}

output "volume_ip" {
  description = "The IP address of the volume mount target"
  value       = azurerm_netapp_volume.netapp_volume.mount_ip_addresses[0]
}

output "load_balancer_ip" {
  description = "The private IP address of the load balancer"
  value       = var.vm_count > 1 ? azurerm_lb.lb[0].frontend_ip_configuration[0].private_ip_address : null
}

output "ssh_commands" {
  description = "SSH commands to connect to the VMs"
  value = var.create_public_ips ? [
    for i, ip in azurerm_public_ip.pip : "ssh ${var.admin_username}@${ip.ip_address}"
  ] : []
}

output "mount_command" {
  description = "Command to mount the NFS volume"
  value       = "mkdir -p /mnt/${var.netapp_volume_name} && mount -t nfs -o vers=3 ${azurerm_netapp_volume.netapp_volume.mount_ip_addresses[0]}:/${var.netapp_volume_name} /mnt/${var.netapp_volume_name}"
}
