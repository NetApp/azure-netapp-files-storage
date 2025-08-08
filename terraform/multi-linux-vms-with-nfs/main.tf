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

# Variables
variable "admin_username" {
  description = "Username for the Virtual Machines"
  type        = string
}

variable "authentication_type" {
  description = "Type of authentication to use on the Virtual Machines"
  type        = string
  default     = "password"
  validation {
    condition     = contains(["password", "sshPublicKey"], var.authentication_type)
    error_message = "Authentication type must be either 'password' or 'sshPublicKey'."
  }
}

variable "admin_password" {
  description = "Password for the Virtual Machines"
  type        = string
  sensitive   = true
  default     = null
}

variable "ssh_public_key" {
  description = "SSH public key for the Virtual Machines"
  type        = string
  default     = null
}

variable "vm_name_prefix" {
  description = "Prefix for the virtual machine names (will be appended with numbers)"
  type        = string
  default     = "azlinuxvms"
}

variable "vm_count" {
  description = "Number of virtual machines to create"
  type        = number
  default     = 3
  validation {
    condition     = var.vm_count >= 1 && var.vm_count <= 10
    error_message = "VM count must be between 1 and 10."
  }
}

variable "vm_size" {
  description = "Size of the virtual machines"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "create_public_ips" {
  description = "Whether to create public IP addresses for VMs"
  type        = bool
  default     = true
}

variable "location" {
  description = "Location for all resources"
  type        = string
  default     = "eastus"
}

variable "netapp_account_name" {
  description = "Name of the NetApp account"
  type        = string
  default     = "azlinux-netapp-account"
}

variable "netapp_pool_name" {
  description = "Name of the NetApp pool"
  type        = string
  default     = "azlinux-netapp-pool"
}

variable "netapp_pool_size_in_tb" {
  description = "Size of the NetApp pool in TB (minimum 4)"
  type        = number
  default     = 4
  validation {
    condition     = var.netapp_pool_size_in_tb >= 4 && var.netapp_pool_size_in_tb <= 500
    error_message = "NetApp pool size must be between 4 and 500 TB."
  }
}

variable "netapp_volume_name" {
  description = "Name of the shared NetApp volume"
  type        = string
  default     = "azlinux-shared-nfs"
}

variable "netapp_volume_size" {
  description = "Size of the NetApp volume in GB (optimized for multiple VMs)"
  type        = number
  default     = 500
}

variable "netapp_service_level" {
  description = "Service level for the NetApp volume"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium", "Ultra"], var.netapp_service_level)
    error_message = "Service level must be Standard, Premium, or Ultra."
  }
}

variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
  default     = "azlinux-vnet"
}

variable "subnet_name_vm" {
  description = "Name of the subnet for the VMs"
  type        = string
  default     = "vmSubnet"
}

variable "subnet_name_netapp" {
  description = "Name of the subnet for NetApp Files"
  type        = string
  default     = "netappSubnet"
}

variable "project_name" {
  description = "Project name for tagging and resource management"
  type        = string
  default     = "dev"
}

# Local values
locals {
  resource_group_name = "rg-${var.project_name}-anf-multi-vm"
  
  common_tags = {
    project    = var.project_name
    created_by = "Terraform"
    created_on = formatdate("YYYY-MM-DD", timestamp())
  }
  
  # Network configuration
  vnet_address_prefix = "10.0.0.0/16"
  vm_subnet_prefix    = "10.0.1.0/24"
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
    purpose = "Multi-VM NetApp Files Infrastructure"
  })
}

# Subnet for VMs
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
      name = "Microsoft.NetApp/volumes"
    }
  }
}

# Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${var.vm_name_prefix}"
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
    nfsv3_enabled     = true
    nfsv41_enabled    = false
    cifs_enabled      = false
    root_access_enabled = false
  }

  tags = merge(local.common_tags, {
    volume_name = var.netapp_volume_name
    created_by  = "ANF-Terraform"
  })
}

# Public IPs (conditional)
resource "azurerm_public_ip" "pip" {
  count               = var.create_public_ips ? var.vm_count : 0
  name                = "pip-${local.vm_names[count.index]}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
  tags                = local.common_tags
}

# Network Interfaces
resource "azurerm_network_interface" "nic" {
  count               = var.vm_count
  name                = "nic-${local.vm_names[count.index]}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
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
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  tags = merge(local.common_tags, {
    vm_index = count.index + 1
  })

  network_interface_ids = [
    azurerm_network_interface.nic[count.index].id
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
    vm_index    = count.index + 1
  }))
}

# Load Balancer (optional - for high availability)
resource "azurerm_lb" "lb" {
  count               = var.vm_count > 1 ? 1 : 0
  name                = "lb-${var.vm_name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  tags                = local.common_tags

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.lb_pip[0].id
  }
}

# Load Balancer Public IP
resource "azurerm_public_ip" "lb_pip" {
  count               = var.vm_count > 1 ? 1 : 0
  name                = "pip-lb-${var.vm_name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
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
  description = "The public IP address of the load balancer"
  value       = var.vm_count > 1 ? azurerm_public_ip.lb_pip[0].ip_address : null
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