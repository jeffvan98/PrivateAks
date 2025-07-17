# Private Azure Kuberntes Service 

For organizations that require strict isolation and prohibit the use of any public IP addresses, deploying Azure Kubernetes Service (AKS) requires careful configuration.  Below is a technical breakdown of how to deploy a fully private AKS cluster - no public ingress or egress - using Bicep or Terraform, along with the required routing configuration.

## Prerequisites:

This configuration assumes you have an existing virtual network (VNET) with appropriate subnets and either Azure Firewall or other egress solution (Network Virtual Appliance; or NVA) already deployed if internet access is required.

**⚠️ Important:** Azure NAT Gateway is **NOT compatible** with AKS clusters deployed into custom VNets when using `userDefinedRouting` outbound type.

## Core requirements for a fully private AKS

1. Private API Server Only
2. No public outbound IPs
3. Internal-only service endpoints
4. Manual routing for egress traffic

## Implementation Guide

The following sections walk through each configuration step required to achieve these requirements.

###	1. AKS control plane configuration
    
The API server is the Kubernetes control plane component that handles all API requests.  By default, AKS creates a public endpoint for the API server, which violates the no-public-IP requirement.  Enabling private cluster mode moves the API server behind a private IP address within your VNET, ensuring all kubectl commands and cluster management traffic stays internal.

Bicep
```	Bicep
apiServerAccessProfile: {
    enablePrivateCluster: true
    enablePrivateClusterPublicFQDN: false // optional: disables public DNS entry
}
```

Terraform
``` Terraform
api_server_access_profile {
    private_cluster_enabled = true
    private_cluster_public_fqdn_enabled = false
}
```

This restricts Kubernetes API access to within your VNET only.
    
###	2. Outbound egress configuration
    
Even with a private API server, AKS nodes still need internet access for essential operations like pulling container images, downloading OS updates, and communicating with Azure services.  By default, AKS creates a public load balancer with a public IP for this outbound traffic.  The userDefinedRouting configuration removes this default behavior, requiring you to explicitly provide an egress path through your own networking infrastructure.
    
**Note:** The userDefinedRouting outbound type requires Azure CNI networking (networkPlugin: 'azure'). This configuration is not compatible with Kubenet networking.

**⚠️ Critical Limitation:** When using a custom VNet/subnet with AKS, Azure NAT Gateway cannot be used with `userDefinedRouting`. You must use Azure Firewall or a Network Virtual Appliance (NVA).

Bicep
``` Bicep
networkProfile: {
    networkPlugin: 'azure'
    loadBalancerSku: 'standard'
    outboundType: 'userDefinedRouting'
    }
    ```

Terraform
``` Terraform
network_profile {
    network_plugin = "azure"
    load_balancer_sku = "standard"
    outbound_type = "userDefinedRouting"
}
```

When userDefinedRouting is set, AKS does not configure any outbound route or SNAT.  You must provide your own Azure Firewall or NVA for internet access.  If your cluster truly needs no internet access (air-gapped scenario), you'll need to configure private endpoints for container registries, Azure services, and handle OS updates through internal repositories.
    
###	3. User Defined Routes (UDRs)
    
With userDefinedRouting enabled, you're responsible for directing the cluster's outbound traffic through Azure Firewall or NVA for controlled egress with filtering and logging capabilities.

**Supported egress solutions for AKS with custom VNet:**

- ✅ **Azure Firewall** - Requires UDR with route table pointing to firewall private IP
- ✅ **Network Virtual Appliance (NVA)** - Requires UDR with route table pointing to NVA private IP  
- ❌ **Azure NAT Gateway** - Not supported with custom VNet and userDefinedRouting

You must apply a route table to the AKS subnet with a route pointing to your firewall or NVA:

``` json
{
    "routes": [
    {
        "name": "egress-route",
        "addressPrefix": "0.0.0.0/0",
        "nextHopType": "VirtualAppliance",
        "nextHopIpAddress": "<private IP of Azure Firewall or NVA>"
    }]
}
```

Apply the route table to the subnet used by the AKS node pool.

**Example Network Architecture:**
```
VNET (10.0.0.0/16)
├── AKS Subnet (10.0.1.0/24) 
│   └── Route Table → 0.0.0.0/0 → Firewall IP
├── Azure Firewall Subnet (10.0.2.0/26)
│   └── Azure Firewall with public IP
└── Other subnets...
```
    
###	4. Application service exposure
    
Kubernetes Services of type LoadBalancer normally create Azure Load Balancers with public IP addresses.  To maintain the no-public IP requirement, you need to explicitly configure these services to use internal load balancers instead.  This ensures application traffic stays within your private network boundaries.

To avoid public IP allocation for Kubernetes Services of type LoadBalancer, use the 'service.beta.kubernetes.io/azure-load-balancer-internal: "true"' annotation:

Example Service:

``` YAML	
apiVersion: v1
kind: Service
metadata:
  name: internal-service
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: myapp
```				
    
This ensures Azure creates an internal load balancer only.
    
###	5. DNS setup
    
Private clusters require DNS resolution for the Kubernetes API server's private FQDN.  AKS handles this automatically by creating a Private DNS Zone, but you need to ensure this zone is properly linked to any VNETs where users or applications need to access the cluster.

AKS automatically creates a Private DNS Zone (privatelink.<region>.azmk8s.io) unless you bring your own.  This is required for internal resolution of the control plane FQDN.  If you manage DNS yourself, ensure the private zone is linked to the VNET where access is needed.
    
###	6. Identity and permissions
    
Private clusters require additional Azure RBAC permissions beyond standard AKS deployments. If you're using the default system-assigned managed identity, AKS automatically grants the necessary permissions for private DNS zone management and network operations.

However, if you're providing your own user-assigned managed identity or service principal, you'll need to ensure it has the following permissions:

- Private DNS Zone Contributor role on the private DNS zone
- Network Contributor role on the VNET/subnet

## Required Azure Firewall Configuration

When using Azure Firewall as your egress solution, ensure these rules are configured:

### Network Rules
- **DNS**: Protocol UDP, Port 53, Destination: *
- **NTP**: Protocol UDP, Port 123, Destination: *  
- **Azure Services**: Protocol TCP, Port 443, Destination: AzureCloud

### Application Rules
- **Container Registries**: *.azurecr.io, mcr.microsoft.com, *.cdn.mscr.io
- **Ubuntu Updates**: security.ubuntu.com, archive.ubuntu.com, changelogs.ubuntu.com
- **Azure Services**: *.azure.com, *.microsoftonline.com, *.windows.net

## Lessons Learned

🚨 **Critical Incompatibilities:**
- **NAT Gateway with Custom VNet**: Azure NAT Gateway cannot be used with AKS deployed into custom VNets when using `userDefinedRouting`
- **Route Table Requirements**: UDR routes with next hop type "Internet" are not allowed; must use "VirtualAppliance" pointing to firewall/NVA
- **LTS Versions**: Kubernetes LTS versions require Premium tier and special configuration

## Troubleshooting Tips

If nodes fail to start or can't pull container images, verify your egress routing is configured correctly.  AKS nodes require internet access for container registry pulls and OS updates unless you've configured private endpoints for all required services.

Common issues:
1. **Route table misconfiguration** - Ensure 0.0.0.0/0 route points to firewall/NVA private IP
2. **Firewall rules missing** - Verify all required outbound rules are configured
3. **DNS resolution failures** - Check private DNS zone linkage
4. **Kubernetes version issues** - Use supported non-LTS versions

## Final Checklist

- [ ] Private cluster enabled (enablePrivateCluster: true)
- [ ] Public FQDN disabled (enablePrivateClusterPublicFQDN: false)
- [ ] Azure CNI networking configured (networkPlugin: 'azure')
- [ ] Outbound type set to userDefinedRouting
- [ ] Azure Firewall or NVA configured for egress (**NOT NAT Gateway**)
- [ ] Route table applied to AKS subnet with 0.0.0.0/0 → firewall/NVA private IP
- [ ] Internal load balancers only (via annotation)
- [ ] No public IPs on node pool, load balancer, or outbound paths
- [ ] Proper identity permissions configured
- [ ] Firewall rules configured for container registries and Azure services

## References

- [Create a private Azure Kubernetes Service (AKS) Cluster](https://learn.microsoft.com/en-us/azure/aks/private-clusters?tabs=advanced-networking%2Cazure-portal)
- [Private-aks-cluster (github)](https://github.com/Azure-Samples/private-aks-cluster/)
- [Microsoft.ContainerService managedClusters - documentation](https://learn.microsoft.com/en-us/azure/templates/microsoft.containerservice/managedclusters?pivots=deployment-language-bicep)
- [Terraform - azurerm_kubernetes_cluster](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster)
- [Terraform Sample](https://github.com/hashicorp/terraform-provider-azurerm/tree/main/examples/kubernetes/private-api-server)
- [AKS Outbound Type Documentation](https://learn.microsoft.com/en-us/azure/aks/egress-outboundtype)