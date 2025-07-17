# Private AKS Terraform Template

This Terraform template creates **only a private Azure Kubernetes Service (AKS) cluster** that meets all the requirements outlined in the main README.md. This template assumes you already have the required networking infrastructure in place.

## What This Template Creates

✅ **AKS Cluster Only** - Private cluster with no public endpoints  
✅ **User-Assigned Managed Identity** - For secure Azure service access  

## What You Need to Provide

🔧 **Existing Resource Group** - Where AKS will be deployed  
🔧 **Existing Virtual Network** - With proper address space  
🔧 **Existing Subnet** - With user-defined routing configured  
🔧 **Existing Egress Solution** - Azure Firewall or NVA (NAT Gateway not supported)  
🔧 **Existing Route Table** - Associated with the subnet for egress routing  

## Core Requirements Implementation

1. ✅ **Private API Server Only** - `private_cluster_enabled = true`
2. ✅ **No public outbound IPs** - `outbound_type = "userDefinedRouting"`
3. ✅ **Internal-only service endpoints** - See examples/internal-service.yaml
4. ✅ **Manual routing for egress traffic** - Uses your existing routing infrastructure

## ⚠️ Important Limitation

**NAT Gateway is NOT compatible with AKS using custom VNet/subnet.** You must use one of the following egress solutions:

- ✅ **Azure Firewall** (Recommended)
- ✅ **Network Virtual Appliance (NVA)** 
- ❌ **NAT Gateway** (Not supported with custom VNet)

## Prerequisites

### Required Infrastructure
Before using this template, you must have:

1. **Resource Group** - Existing resource group for deployment
2. **Virtual Network** with appropriate address space
3. **Subnet** for AKS nodes (minimum /24 recommended)
4. **Route Table** with egress route (0.0.0.0/0) pointing to your firewall/NVA
5. **Egress Solution**: One of the following:
   - **Azure Firewall** with appropriate rules
   - **Network Virtual Appliance (NVA)** with forwarding enabled

### Example Network Setup with Azure Firewall
```
VNET (10.0.0.0/16)
├── AKS Subnet (10.0.1.0/24) ← You provide this
├── Azure Firewall Subnet (10.0.2.0/26) ← You provide this
└── Route Table → 0.0.0.0/0 → Azure Firewall IP ← You provide this
```

### Example Network Setup with NVA
```
VNET (10.0.0.0/16)
├── AKS Subnet (10.0.1.0/24) ← You provide this
├── NVA Subnet (10.0.2.0/24) ← You provide this
└── Route Table → 0.0.0.0/0 → NVA Private IP ← You provide this
```

## Variables

### Required Variables
```hcl
resource_group_name = "your-existing-resource-group"
aks_subnet_id = "/subscriptions/.../subnets/your-aks-subnet"
```

### Optional Variables
```hcl
project_name       = "privateaks"
kubernetes_version = "1.29"  # Use supported version (not LTS)
node_count        = 2
node_vm_size      = "Standard_D2s_v3"
outbound_type     = "userDefinedRouting"  # Required for custom VNet
service_cidr      = "10.1.0.0/16"  # Must not overlap with VNet
dns_service_ip    = "10.1.0.10"    # Must be within service_cidr
```

## Deployment Instructions

1. **Check supported Kubernetes versions**:
   ```powershell
   az aks get-versions --location "East US" --output table
   ```

2. **Copy example variables**:
   ```powershell
   copy terraform.tfvars.example terraform.tfvars
   ```

3. **Edit `terraform.tfvars`** with your values:
   ```hcl
   resource_group_name = "my-existing-rg"
   aks_subnet_id = "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/my-network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/aks-subnet"
   kubernetes_version = "1.29"  # Use non-LTS version
   ```

4. **Initialize Terraform**:
   ```powershell
   terraform init
   ```

5. **Validate configuration**:
   ```powershell
   terraform validate
   ```

6. **Plan deployment**:
   ```powershell
   terraform plan
   ```

7. **Apply configuration**:
   ```powershell
   terraform apply
   ```

## Post-Deployment

### Connect to the cluster
```bash
# Get credentials (must be run from a machine with access to the VNet)
az aks get-credentials --resource-group <resource-group> --name <cluster-name>

# Verify connection (must be done from within VNet or connected network)
kubectl get nodes
```

### Deploy internal service
```bash
kubectl apply -f examples/internal-service.yaml
```

## Network Requirements Checklist

Before deploying, ensure your existing infrastructure has:

- [ ] **Resource Group** exists
- [ ] **Subnet** with sufficient IP addresses (/24 minimum for production)
- [ ] **Route Table** associated with the AKS subnet
- [ ] **Egress Route** (0.0.0.0/0) pointing to Azure Firewall or NVA private IP
- [ ] **DNS Resolution** configured for private endpoints
- [ ] **Azure Firewall Rules** (if using Azure Firewall):
  - [ ] Allow DNS (port 53)
  - [ ] Allow HTTPS to Azure services (port 443)
  - [ ] Allow container registry access (mcr.microsoft.com, *.azurecr.io)
  - [ ] Allow OS updates (Ubuntu repositories)
  - [ ] Allow Azure service dependencies

## Troubleshooting

### Common Issues

1. **Kubernetes version not supported**: 
   - Use `az aks get-versions --location <region>` to find supported versions
   - Avoid LTS versions unless using Premium tier

2. **Nodes fail to join**: 
   - Check route table configuration
   - Verify egress solution is working
   - Test connectivity from subnet to internet

3. **Can't pull container images**: 
   - Verify firewall rules for container registries
   - Check DNS resolution for mcr.microsoft.com

4. **DNS resolution issues**: 
   - Ensure DNS works from the AKS subnet
   - Check Azure private DNS zones

5. **Permission errors**: 
   - Verify managed identity has Network Contributor role on subnet

### Validation Commands
```bash
# Check if subnet has route table
az network vnet subnet show --ids YOUR_SUBNET_ID --query routeTable

# Check route table routes
az network route-table route list --resource-group YOUR_RG --route-table-name YOUR_RT

# Test connectivity from a VM in the AKS subnet
nslookup mcr.microsoft.com
curl -I https://mcr.microsoft.com
wget -O /dev/null http://security.ubuntu.com/ubuntu/dists/focal-security/Release
```

## Lessons Learned

🚨 **Critical Limitations:**
- AKS with custom VNet **cannot use NAT Gateway** with `outbound_type = "userDefinedRouting"`
- Must use Azure Firewall or NVA for egress traffic
- LTS Kubernetes versions require Premium tier and special configuration

## Security Benefits

✅ **Zero Public IPs** - No resources have public IP addresses  
✅ **Private API Server** - Kubernetes API only accessible from VNet  
✅ **Controlled Egress** - All outbound traffic goes through your firewall/NVA  
✅ **Internal Load Balancers** - Services use internal IPs only  
✅ **Managed Identity** - Secure authentication without credentials  

## Example Terraform Module Usage

```hcl
module "private_aks" {
  source = "./private-aks"
  
  project_name        = "my-private-aks"
  resource_group_name = "my-existing-rg"
  aks_subnet_id       = data.azurerm_subnet.aks.id
  service_cidr        = "10.1.0.0/16"
  dns_service_ip      = "10.1.0.10"
  kubernetes_version  = "1.29"
  node_count          = 3
  node_vm_size        = "Standard_D4s_v3"
  outbound_type       = "userDefinedRouting"
  
  tags = {
    Environment = "Production"
    Project     = "MyApp"
  }
}
```

## Required Azure Firewall Configuration

If using Azure Firewall, ensure these rules are configured:

### Network Rules
```
# DNS
Protocol: UDP, Port: 53, Destination: *

# NTP (time sync)  
Protocol: UDP, Port: 123, Destination: *

# Azure Services
Protocol: TCP, Port: 443, Destination: AzureCloud
```

### Application Rules
```
# Container Registries
*.azurecr.io, mcr.microsoft.com, *.cdn.mscr.io

# Ubuntu Updates
security.ubuntu.com, archive.ubuntu.com, changelogs.ubuntu.com

# Azure Services
*.azure.com, *.microsoftonline.com, *.windows.net
```