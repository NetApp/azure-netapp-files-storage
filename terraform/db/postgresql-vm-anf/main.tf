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
  resource_group_name     = "rg-${var.project_name}-postgresql-vm-anf"
  resource_group_location = var.location

  common_tags = {
    project             = var.project_name
    created_by          = "Terraform"
    created_on          = formatdate("YYYY-MM-DD", timestamp())
    pg_plg              = "true"
    pg_template_version = "1.0.0"
    pg_deployment_id    = formatdate("YYYYMMDD-hhmmss", timestamp())
  }

  # Network configuration
  vnet_address_prefix  = "10.0.0.0/16"
  vm_subnet_prefix     = "10.0.1.0/24"
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
    purpose = "PostgreSQL VM with ANF Infrastructure"
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
    name                       = "PostgreSQL"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.postgresql_port)
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "NFS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2049"
    source_address_prefix      = local.vm_subnet_prefix
    destination_address_prefix = "*"
  }
}

# Public IP (conditional)
resource "azurerm_public_ip" "pip" {
  count               = var.create_public_ip ? 1 : 0
  name                = "pip-${var.vm_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
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
    public_ip_address_id          = var.create_public_ip ? azurerm_public_ip.pip[0].id : null
  }
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "nsg_association" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# NetApp Account
resource "azurerm_netapp_account" "netapp_account" {
  name                = "${var.netapp_account_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags = merge(local.common_tags, {
    created_by = "PostgreSQL-ANF-Terraform"
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
    rule_index          = 1
    allowed_clients     = [local.vm_subnet_prefix]
    unix_read_only      = false
    unix_read_write     = true
    root_access_enabled = true
  }

  tags = merge(local.common_tags, {
    volume_name = var.netapp_volume_name
    created_by  = "PostgreSQL-ANF-Terraform"
  })
}

# Configure export policy using AzAPI provider for NFSv3 support
resource "azapi_update_resource" "netapp_volume_export_policy" {
  type        = "Microsoft.NetApp/netAppAccounts/capacityPools/volumes@2023-05-01"
  resource_id = azurerm_netapp_volume.netapp_volume.id

  body = jsonencode({
    properties = {
      exportPolicy = {
        rules = [
          {
            ruleIndex           = 1
            allowedClients      = local.vm_subnet_prefix
            unixReadOnly        = false
            unixReadWrite       = true
            rootAccessEnabled   = true
            nfsv3               = true
            nfsv41              = false
            cifs                = false
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
}

# VM Run Command to setup PostgreSQL with ANF
resource "azurerm_virtual_machine_run_command" "setup_postgresql" {
  name               = "setupPostgreSQL"
  location           = local.resource_group_location
  virtual_machine_id = azurerm_linux_virtual_machine.vm.id

  source {
    script = templatefile("${path.module}/setup-postgresql.sh", {
      postgresql_version        = var.postgresql_version
      postgresql_admin_password = var.postgresql_admin_password
      database_name             = var.database_name
      database_user             = var.database_user
      database_password         = var.database_password
      volume_ip                 = azurerm_netapp_volume.netapp_volume.mount_ip_addresses[0]
      volume_name               = var.netapp_volume_name
      postgresql_port           = var.postgresql_port
    })
  }

  depends_on = [
    azurerm_linux_virtual_machine.vm,
    azapi_update_resource.netapp_volume_export_policy
  ]
}

# Outputs
output "vm_id" {
  description = "The ID of the Linux VM"
  value       = azurerm_linux_virtual_machine.vm.id
}

output "vm_public_ip" {
  description = "The public IP address of the VM (if created)"
  value       = var.create_public_ip ? azurerm_public_ip.pip[0].ip_address : "No public IP"
}

output "vm_private_ip" {
  description = "The private IP address of the VM"
  value       = azurerm_network_interface.nic.private_ip_address
}

output "postgresql_connection_string" {
  description = "PostgreSQL connection string"
  value       = "host=${var.create_public_ip ? azurerm_public_ip.pip[0].ip_address : azurerm_network_interface.nic.private_ip_address} port=${var.postgresql_port} dbname=${var.database_name} user=${var.database_user} password=${var.database_password}"
  sensitive   = true
}

output "postgresql_admin_connection_string" {
  description = "PostgreSQL admin connection string"
  value       = "host=${var.create_public_ip ? azurerm_public_ip.pip[0].ip_address : azurerm_network_interface.nic.private_ip_address} port=${var.postgresql_port} dbname=postgres user=postgres password=${var.postgresql_admin_password}"
  sensitive   = true
}

output "psql_command" {
  description = "psql command to connect to PostgreSQL"
  value       = "psql -h ${var.create_public_ip ? azurerm_public_ip.pip[0].ip_address : azurerm_network_interface.nic.private_ip_address} -p ${var.postgresql_port} -U ${var.database_user} -d ${var.database_name}"
  sensitive   = false
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = var.create_public_ip ? "ssh ${var.admin_username}@${azurerm_public_ip.pip[0].ip_address}" : "Use private IP: ${azurerm_network_interface.nic.private_ip_address}"
}

output "volume_id" {
  description = "The ID of the NetApp volume"
  value       = azurerm_netapp_volume.netapp_volume.id
}

output "volume_mount_path" {
  description = "Path where ANF volume is mounted"
  value       = "/mnt/${var.netapp_volume_name}"
}

output "postgresql_data_directory" {
  description = "PostgreSQL data directory on ANF"
  value       = "/mnt/${var.netapp_volume_name}/postgresql-data"
}

