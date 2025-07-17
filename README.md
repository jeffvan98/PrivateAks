# Private Azure Kubernetes Service (AKS) Deployment

This repository contains Terraform templates for deploying a fully private Azure Kubernetes Service (AKS) cluster with no public IP addresses and controlled egress routing.

## 🔒 Key Features

- **Private API Server** - No public endpoint access
- **Zero Public IPs** - Complete network isolation  
- **User Defined Routing** - Controlled egress through Azure Firewall or NVA
- **Internal Load Balancers** - Services use private IPs only

## 📁 Repository Structure

```
├── src/PrivateAks/          # Terraform templates
│   ├── main.tf              # AKS cluster configuration
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Output values
│   └── README.md            # Detailed implementation guide
└── docs/                    # Documentation
    └── README.md            # Architecture and requirements
```

## 🚀 Quick Start

For detailed deployment instructions and requirements, see:

**📖 [Implementation Guide](src/PrivateAks/README.md)** - Terraform deployment instructions

**📋 [Architecture Guide](docs/README.md)** - Requirements and network design

## ⚠️ Important Note

This template requires existing Azure networking infrastructure (VNet, subnets, Azure Firewall/NVA, and route tables). NAT Gateway is not compatible with AKS using custom VNet configurations.