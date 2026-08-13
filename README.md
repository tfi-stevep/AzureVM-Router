# Deploying Azure VM as Router

Deploy Azure VM (Linux or Windows) with IP forwarder enabled to be used as Router. All deployments in this document assumes you have already and existing Virtual Network (VNET) and Subnet.

## Deploy Linux VM as Router (IPv4 and IPv6) + NAT to Internet

This template deploys a Linux Router (Ubuntu 24.04 LTS by default, 22.04 LTS selectable via the `osVersion` parameter) to an existing Virtual Network (VNET)/Subnet using a Single NIC + IP Forwarding Enabled. The ARM templates (`LinuxRouter.json`, `LinuxRouter-newsubnet.json`) are generated from the Bicep sources (`LinuxRouter.bicep`, `LinuxRouter-newsubnet.bicep`).

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fdmauser%2FAzureVM-Router%2Fmaster%2FLinuxRouter.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fdmauser%2FAzureVM-Router%2Fmaster%2FLinuxRouter.json)

### Network security defaults

The templates deploy a **Standard SKU** public IP (the previously used Basic SKU was retired by Azure in September 2025). Standard public IPs are *secure by default*, which changes the out-of-the-box connectivity compared to older versions of these templates:

- **Inbound traffic from the Internet is blocked** unless a Network Security Group (NSG) explicitly allows it. To enable SSH from the Internet, set the **`allowSshFromAddressPrefix`** parameter to your trusted source — for example `203.0.113.4/32` for a single address, or a CIDR range for an office network. Both templates then create an NSG with a rule allowing TCP 22 from that prefix. Leaving the parameter empty (the default) keeps the previous behaviour: `LinuxRouter.json` creates no NSG, and `LinuxRouter-newsubnet.json` creates one that only allows inbound traffic from RFC 1918 private ranges. In that case, manage the VM from inside your network or via Azure Bastion. Setting the value to `Internet` or `*` allows SSH from anywhere and is not recommended.
- **Outbound traffic to the Internet is allowed.** NSGs permit outbound traffic by default, and the attached public IP provides an *explicit* outbound method (SNAT), so the setup script can install packages during provisioning. This also keeps the templates working after Azure's retirement of *default outbound access* for new deployments.
- **If you disable the public IP** (`deployPublicIpAddress=false`), make sure the subnet has another explicit outbound method — e.g. a NAT Gateway, an Azure Firewall / NVA route, or Load Balancer outbound rules. On virtual networks without default outbound access (the default for newly created VNets), the VM otherwise has no Internet access and the setup script cannot install its packages.

## Deploy Windows VM as Router (IPv4 and IPv6)

This template deploys a Windows (Server 2019 Core - Small Disk) Router to an existing Virtual Network (VNET)/Subnet using a Single NIC + IP Forwarding Enabled.

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fdmauser%2FAzureVM-Router%2Fmaster%2FWinRouter.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fdmauser%2FAzureVM-Router%2Fmaster%2FWinRouter.json)

## Roadmap

- Add VMSS option for both Linux and Windows deployments
- Add Accelerated Networking option
