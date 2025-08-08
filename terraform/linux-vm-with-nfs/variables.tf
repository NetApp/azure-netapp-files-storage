# Variables for Linux VM with NFS Template

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "linuxVM"
}

variable "admin_username" {
  description = "Username for the Virtual Machine"
  type        = string
  default     = "azureuser"
}

variable "authentication_type" {
  description = "Type of authentication to use on the Virtual Machine"
  type        = string
  default     = "password"
  validation {
    condition     = contains(["password", "sshPublicKey"], var.authentication_type)
    error_message = "Authentication type must be either 'password' or 'sshPublicKey'."
  }
}

variable "admin_password" {
  description = "Password for the Virtual Machine"
  type        = string
  sensitive   = true
  default     = null
}

variable "ssh_public_key" {
  description = "SSH public key for the Virtual Machine"
  type        = string
  default     = null
}

variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "location" {
  description = "Location for all resources"
  type        = string
  default     = "eastus"
}

variable "netapp_account_name" {
  description = "Name of the NetApp account"
  type        = string
  default     = "netappaccount"
}

variable "netapp_pool_name" {
  description = "Name of the NetApp pool"
  type        = string
  default     = "netapppool"
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
  description = "Name of the NetApp volume"
  type        = string
  default     = "anf-vol1"
}

variable "netapp_volume_size" {
  description = "Size of the NetApp volume in GB"
  type        = number
  default     = 100
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
  default     = "vnet"
}

variable "subnet_name_vm" {
  description = "Name of the subnet for the VM"
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