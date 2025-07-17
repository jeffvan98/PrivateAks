# Reference existing resource group
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Create user-assigned managed identity for AKS
resource "azurerm_user_assigned_identity" "aks" {
  name                = "${var.project_name}-aks-identity"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  tags = var.tags
}

# Assign Network Contributor role to the managed identity on the subnet
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = var.aks_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# Create Private AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.project_name}-aks"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  dns_prefix          = "${var.project_name}-aks"
  kubernetes_version  = var.kubernetes_version

  # Private cluster configuration - Core Requirement #1
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = false

  # Network profile configuration - Core Requirements #2, #3, #4
  network_profile {
    network_plugin     = "azure"                # Required for userDefinedRouting
    load_balancer_sku  = "standard"
    outbound_type      = var.outbound_type      # Configurable: userDefinedRouting, managedNATGateway, or loadBalancer
    service_cidr       = var.service_cidr
    dns_service_ip     = var.dns_service_ip
  }

  # Use user-assigned managed identity
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  default_node_pool {
    name           = "default"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = var.aks_subnet_id
    
    # Ensure no public IPs for nodes
    enable_node_public_ip = false
  }

  tags = var.tags

  depends_on = [
    azurerm_role_assignment.aks_network_contributor
  ]
}
