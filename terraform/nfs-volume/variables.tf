# Variables for NFS Volume Template

variable "volume_name" {
  description = "Name of the NetApp volume"
  type        = string
  default     = "my-nfs-volume"
}

variable "volume_size_gib" {
  description = "Size of the NetApp volume in GiB"
  type        = number
  default     = 100
}

variable "location" {
  description = "Location for all resources"
  type        = string
  default     = "eastus"
}

variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
  default     = "anf-vnet"
}

variable "project_name" {
  description = "Project name for tagging and resource management"
  type        = string
  default     = "dev"
}

variable "allowed_clients" {
  description = "IP address range allowed to access the NFS volume (CIDR format)"
  type        = string
  default     = "10.0.0.0/24"
} 