terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
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
  netapp_account_name = "netapp-${random_string.suffix.result}"
  netapp_pool_name    = "pool1"
  netapp_subnet_name  = "netappSubnet"
  vnet_address_prefix = "10.0.0.0/16"
  netapp_subnet_prefix = "10.0.1.0/24"
  
  common_tags = {
    project                = var.project_name
    created_by            = "Terraform"
    created_on            = formatdate("YYYY-MM-DD", timestamp())
    anf_plg               = "true"
    anf_template_version  = "1.0.0"
    anf_deployment_id     = formatdate("YYYYMMDD-hhmmss", timestamp())
  }
}

# Random string for unique naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.project_name}-anf"
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
    purpose = "NetApp Files Infrastructure"
  })
}

# Subnet for NetApp Files
resource "azurerm_subnet" "netapp_subnet" {
  name                 = local.netapp_subnet_name
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

# NetApp Account
resource "azurerm_netapp_account" "netapp_account" {
  name                = local.netapp_account_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags = merge(local.common_tags, {
    created_by = "ANF-Terraform"
  })
}

# NetApp Capacity Pool
resource "azurerm_netapp_pool" "netapp_pool" {
  name                = local.netapp_pool_name
  account_name        = azurerm_netapp_account.netapp_account.name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_level       = "Standard"
  size_in_tb          = 4
}

# NetApp Volume
resource "azurerm_netapp_volume" "netapp_volume" {
  name                = var.volume_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  account_name        = azurerm_netapp_account.netapp_account.name
  pool_name           = azurerm_netapp_pool.netapp_pool.name
  volume_path         = var.volume_name
  service_level       = "Standard"
  subnet_id           = azurerm_subnet.netapp_subnet.id
  storage_quota_in_gb = var.volume_size_gib
  protocols           = ["NFSv3"]

  export_policy_rule {
    rule_index        = 1
    allowed_clients   = [var.allowed_clients]
    unix_read_only    = false
    unix_read_write   = true
    root_access_enabled = false
  }

  tags = merge(local.common_tags, {
    volume_name = var.volume_name
    created_by  = "ANF-Terraform"
  })
}

# Outputs
output "volume_id" {
  description = "The ID of the NetApp volume"
  value       = azurerm_netapp_volume.netapp_volume.id
}

output "volume_ip" {
  description = "The IP address of the volume mount target"
  value       = azurerm_netapp_volume.netapp_volume.mount_ip_addresses[0]
}

output "mount_command" {
  description = "Command to mount the NFS volume"
  value       = "mkdir -p /mnt/${var.volume_name} && mount -t nfs -o vers=3 ${azurerm_netapp_volume.netapp_volume.mount_ip_addresses[0]}:/${var.volume_name} /mnt/${var.volume_name}"
}

output "fstab_entry" {
  description = "Entry for /etc/fstab to mount the volume automatically"
  value       = "${azurerm_netapp_volume.netapp_volume.mount_ip_addresses[0]}:/${var.volume_name} /mnt/${var.volume_name} nfs rw,hard,rsize=65536,wsize=65536,vers=3,tcp 0 0"
}

output "mount_instructions" {
  description = "Instructions for mounting the NFS volume"
  value       = "Mount command: mount -t nfs -o vers=3 ${azurerm_netapp_volume.netapp_volume.mount_ip_addresses[0]}:/${var.volume_name} /your/mount/path"
} 