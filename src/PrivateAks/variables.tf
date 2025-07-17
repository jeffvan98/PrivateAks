variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "privateaks"
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default = {
    Environment = "Development"
    Project     = "PrivateAks"
  }
}

# Required existing infrastructure variables
variable "resource_group_name" {
  description = "The name of the existing resource group where AKS will be deployed"
  type        = string
}

variable "aks_subnet_id" {
  description = "The resource ID of the existing subnet where AKS nodes will be deployed"
  type        = string
}

# Egress configuration
variable "outbound_type" {
  description = "The outbound routing method. Use 'userDefinedRouting' for Azure Firewall/NVA with UDRs (required when using custom VNet), 'managedNATGateway' for Azure NAT Gateway (only works with AKS-managed VNet), or 'loadBalancer' for standard load balancer (not recommended for private clusters)"
  type        = string
  default     = "userDefinedRouting"
  
  validation {
    condition = contains(["userDefinedRouting", "managedNATGateway", "loadBalancer"], var.outbound_type)
    error_message = "Outbound type must be one of: userDefinedRouting, managedNATGateway, loadBalancer. Note: managedNATGateway cannot be used with custom VNet/subnet."
  }
}

variable "service_cidr" {
  description = "CIDR block for Kubernetes services (must not overlap with VNet or subnet ranges)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for the Kubernetes DNS service (must be within service_cidr range)"
  type        = string
  default     = "10.1.0.10"
}

# AKS configuration variables
variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "node_count" {
  description = "Initial number of nodes in the node pool"
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "Size of the VMs in the node pool"
  type        = string
  default     = "Standard_D2s_v3"
}
