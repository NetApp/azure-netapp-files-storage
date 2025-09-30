terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
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

# Variables are defined in variables.tf

# Local values
locals {
  resource_group_name = "rg-${var.project_name}-anf-vm"
  
  common_tags = {
    project                = var.project_name
    created_by            = "Terraform"
    created_on            = formatdate("YYYY-MM-DD", timestamp())
    anf_plg               = "true"
    anf_template_version  = "1.0.0"
    anf_deployment_id     = formatdate("YYYYMMDD-hhmmss", timestamp())
  }
  
  # Network configuration
  vnet_address_prefix = "10.0.0.0/16"
  vm_subnet_prefix    = "10.0.1.0/24"
  netapp_subnet_prefix = "10.0.2.0/24"
}

# Random string for unique naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = [local.vnet_address_prefix]
  tags = merge(local.common_tags, {
    purpose = "NetApp Files and VM Infrastructure"
  })
}

# Subnet for VM
resource "azurerm_subnet" "vm_subnet" {
  name                 = var.subnet_name_vm
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.vm_subnet_prefix]
}

# Subnet for NetApp Files
resource "azurerm_subnet" "netapp_subnet" {
  name                 = var.subnet_name_netapp
  resource_group_name  = azurerm_resource_group.rg.name
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
  name                = "nsg-${var.vm_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
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

# Public IP
resource "azurerm_public_ip" "pip" {
  name                = "pip-${var.vm_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
  tags                = local.common_tags
}

# Network Interface
resource "azurerm_network_interface" "nic" {
  name                = "nic-${var.vm_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "nsg_association" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# NetApp Account
resource "azurerm_netapp_account" "netapp_account" {
  name                = var.netapp_account_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags = merge(local.common_tags, {
    created_by = "ANF-Terraform"
  })
}

# NetApp Capacity Pool
resource "azurerm_netapp_pool" "netapp_pool" {
  name                = var.netapp_pool_name
  account_name        = azurerm_netapp_account.netapp_account.name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_level       = var.netapp_service_level
  size_in_tb          = var.netapp_pool_size_in_tb
}

# NetApp Volume
resource "azurerm_netapp_volume" "netapp_volume" {
  name                = var.netapp_volume_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  account_name        = azurerm_netapp_account.netapp_account.name
  pool_name           = azurerm_netapp_pool.netapp_pool.name
  volume_path         = var.netapp_volume_name
  service_level       = var.netapp_service_level
  subnet_id           = azurerm_subnet.netapp_subnet.id
  storage_quota_in_gb = var.netapp_volume_size
  protocols           = ["NFSv3"]

  export_policy_rule {
    rule_index        = 1
    allowed_clients   = ["10.0.0.0/16"]
    unix_read_only    = false
    unix_read_write   = true
    root_access_enabled = false
  }

  tags = merge(local.common_tags, {
    volume_name = var.netapp_volume_name
    created_by  = "ANF-Terraform"
  })
}

# Linux VM
resource "azurerm_linux_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  tags                = local.common_tags

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  admin_password = var.authentication_type == "password" ? var.admin_password : null
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
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yml", {
    volume_ip   = azurerm_netapp_volume.netapp_volume.mount_ip_addresses[0]
    volume_name = var.netapp_volume_name
  }))
}

# Outputs
output "vm_id" {
  description = "The ID of the Linux VM"
  value       = azurerm_linux_virtual_machine.vm.id
}

output "vm_public_ip" {
  description = "The public IP address of the VM"
  value       = azurerm_public_ip.pip.ip_address
}

output "vm_private_ip" {
  description = "The private IP address of the VM"
  value       = azurerm_network_interface.nic.private_ip_address
}

output "volume_id" {
  description = "The ID of the NetApp volume"
  value       = azurerm_netapp_volume.netapp_volume.id
}

output "volume_ip" {
  description = "The IP address of the volume mount target"
  value       = azurerm_netapp_volume.netapp_volume.mount_ip_addresses[0]
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}

output "mount_command" {
  description = "Command to mount the NFS volume"
  value       = "mkdir -p /mnt/${var.netapp_volume_name} && mount -t nfs -o vers=3 ${azurerm_netapp_volume.netapp_volume.mount_ip_addresses[0]}:/${var.netapp_volume_name} /mnt/${var.netapp_volume_name}"
} 