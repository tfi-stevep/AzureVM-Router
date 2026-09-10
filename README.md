<h1 align="center">Azure VM as Router</h1>

<p align="center">
  Deploy an Azure VM (Linux or Windows) with IP forwarding enabled, to be used as a router / Network Virtual Appliance (NVA).
</p>

<p align="center">
  <a href="https://github.com/tfi-stevep/AzureVM-Router/actions/workflows/validate-templates.yml"><img alt="Validate templates" src="https://github.com/tfi-stevep/AzureVM-Router/actions/workflows/validate-templates.yml/badge.svg"></a>
  <img alt="Bicep" src="https://img.shields.io/badge/IaC-Bicep-blue">
  <img alt="Ubuntu" src="https://img.shields.io/badge/Ubuntu-24.04%20%7C%2022.04-E95420?logo=ubuntu&logoColor=white">
  <img alt="Windows Server" src="https://img.shields.io/badge/Windows%20Server-2025%20%7C%202022%20%7C%202019-0078D4?logo=windows&logoColor=white">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green"></a>
</p>

---

## Table of contents

- [Overview](#overview)
- [Quick start](#quick-start)
- [Repository structure](#repository-structure)
- [Network modes](#network-modes)
- [Linux router](#linux-router)
  - [Parameters](#linux-parameters)
- [Windows router](#windows-router)
  - [Parameters](#windows-parameters)
- [Network security defaults](#network-security-defaults)
- [Using the router](#using-the-router)
- [Deploying from the command line](#deploying-from-the-command-line)
- [Publishing as a template spec](#publishing-as-a-template-spec)
- [Setup scripts](#setup-scripts)
- [Lab deployment scripts](#lab-deployment-scripts)
- [Working with the templates](#working-with-the-templates)
- [Recent improvements](#recent-improvements)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

These templates build a single-NIC virtual machine with **IP forwarding enabled** on both the Azure NIC and inside the guest OS, so it can route traffic on behalf of other subnets. A Custom Script Extension applies the in-guest configuration at provisioning time.

| | Linux router | Windows router |
|---|---|---|
| Operating system | Ubuntu 24.04 LTS (default) or 22.04 LTS | Windows Server 2025 / 2022 / 2019, Server Core, small disk, Gen 2 |
| IPv4 + IPv6 forwarding | Yes | Yes |
| NAT / SNAT to the internet | Yes (`iptables` masquerade, persisted) | No |
| ICMP echo reply enabled | Yes | Yes (Windows Firewall rule enabled by the script) |
| Trusted Launch | No | Yes (Secure Boot + vTPM) |
| Default size | `Standard_B2s` | `Standard_B2s` |

> [!NOTE]
> The ARM JSON under `infra/arm/` is **generated** from the Bicep sources under `infra/bicep/`. Edit the Bicep, then rebuild — never hand-edit the JSON. CI enforces this.

---

## Quick start

Pick a template and deploy straight to the portal. Each one can join an existing subnet, add a subnet to an existing VNET, or build the VNET from scratch — see [Network modes](#network-modes).

| Template | Use when | Deploy | Visualize |
|---|---|---|---|
| **Linux router** | You want an Ubuntu router with forwarding and SNAT | [![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/valid-computer-name/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftfi-stevep%2FAzureVM-Router%2Fvalid-computer-name%2Finfra%2Farm%2Flinux-router.json) | [![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/valid-computer-name/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Ftfi-stevep%2FAzureVM-Router%2Fvalid-computer-name%2Finfra%2Farm%2Flinux-router.json) |
| **Windows router** | You want a Windows Server router | [![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/valid-computer-name/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftfi-stevep%2FAzureVM-Router%2Fvalid-computer-name%2Finfra%2Farm%2Fwindows-router.json) | [![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/valid-computer-name/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Ftfi-stevep%2FAzureVM-Router%2Fvalid-computer-name%2Finfra%2Farm%2Fwindows-router.json) |

> [!IMPORTANT]
> Set **`allowSshFromAddressPrefix`** (Linux) or **`allowRdpFromAddressPrefix`** (Windows) to your own public IP, e.g. `203.0.113.4/32`. Standard SKU public IPs block **all** inbound traffic unless an NSG allows it. See [Network security defaults](#network-security-defaults).

---

## Repository structure

```
.
├── .github/workflows/    CI: Bicep build + lint, ARM drift check, shell syntax / CRLF check
├── infra/
│   ├── bicep/            Template sources — edit these
│   └── arm/              Generated ARM JSON — deploy these, never hand-edit
├── scripts/
│   ├── linux/            Custom Script Extension payloads (.sh) and cloud-init
│   └── windows/          Custom Script Extension payload (.ps1)
├── labs/
│   ├── *.azcli           End-to-end Azure CLI lab builds
│   └── conf/             Large BGP route lists used for scale testing
├── tools/                Helper scripts for publishing template specs
├── docs/                 Supporting notes
└── README.md
```

---

## Network modes

Both templates take a **`networkMode`** parameter that decides how the router attaches to the network, so a single template covers every starting point.

| `networkMode` | Virtual network | Subnet | NSG placement |
|---|---|---|---|
| `ExistingSubnet` *(default)* | Must already exist | Must already exist | On the **NIC**, so an NSG already attached to that subnet is never overwritten |
| `NewSubnet` | Must already exist | **Created** using `subnetAddressPrefix` | On the **new subnet** |
| `NewVnet` | **Created** using `virtualNetworkAddressPrefix` | **Created** using `subnetAddressPrefix` | On the **new subnet** |

The parameters that apply to each mode:

| Parameter | `ExistingSubnet` | `NewSubnet` | `NewVnet` |
|---|---|---|---|
| `virtualNetworkName` | Name of the existing VNET | Name of the existing VNET | Name of the VNET to create |
| `virtualNetworkAddressPrefix` | Ignored | Ignored | Address space of the new VNET |
| `subnetName` | Name of the existing subnet | Name of the subnet to create | Name of the subnet to create |
| `subnetAddressPrefix` | Ignored | CIDR of the new subnet | CIDR of the new subnet |

> [!NOTE]
> In the two subnet-creating modes the NSG is always created, because the template owns the new subnet. In `ExistingSubnet` mode the NSG is only created when you set `allowSshFromAddressPrefix` / `allowRdpFromAddressPrefix`, so a deployment into an existing subnet never attaches an unexpected NSG.

Every deployment returns the values you need for a route table:

| Output | Description |
|---|---|
| `privateIpAddress` | Private IP of the router — use this as the UDR next hop |
| `publicIpAddress` | Public IP, empty when `deployPublicIpAddress` is `false` |
| `subnetId` | Resource ID of the subnet the router joined |

---

## Linux router

Deploys an Ubuntu router with a single NIC and IP forwarding enabled. The setup script enables IPv4 and IPv6 forwarding, disables ICMP redirects, configures `iptables` SNAT (masquerade) to the internet for private-range sources, and persists all of it across reboots with `netfilter-persistent`.

<a id="linux-parameters"></a>

### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `virtualMachineName` | string | *(required)* | Name of the router VM. |
| `adminUsername` | string | *(required)* | Local admin user name. |
| `adminPassword` | secure string | *(required)* | Local admin password. |
| `networkMode` | string | `ExistingSubnet` | `ExistingSubnet`, `NewSubnet` or `NewVnet` — see [Network modes](#network-modes). |
| `virtualNetworkName` | string | *(required)* | VNET to join, or to create in `NewVnet` mode. |
| `virtualNetworkAddressPrefix` | string | `10.100.0.0/16` | Address space for the new VNET. `NewVnet` only. |
| `subnetName` | string | *(required)* | Subnet to join, or to create in `NewSubnet` / `NewVnet` mode. |
| `subnetAddressPrefix` | string | `10.100.0.0/24` | CIDR for the new subnet, can be as small as /29. `NewSubnet` / `NewVnet` only. |
| `osVersion` | string | `24.04` | Ubuntu LTS version — `24.04` or `22.04`. |
| `virtualMachineSize` | string | `Standard_B2s` | VM size. |
| `osDiskType` | string | `Standard_LRS` | `Premium_LRS`, `StandardSSD_LRS` or `Standard_LRS`. |
| `deployPublicIpAddress` | bool | `true` | Create a Standard SKU static public IP. |
| `allowSshFromAddressPrefix` | string | `''` | Source prefix allowed inbound on TCP 22. Empty means no SSH rule. |
| `scriptUri` | string | resolved from the template's own URL | Setup script to run. |
| `scriptCmd` | string | `sh linuxrouter.sh` | Command used to run the script. |
| `location` | string | resource group location | Azure region. |

---

## Windows router

Deploys a **Windows Server Core, small disk, Generation 2** router with Trusted Launch (Secure Boot + vTPM) enabled. The setup script enables IPv4 and IPv6 forwarding on all interfaces and enables the inbound ICMPv4/ICMPv6 echo request firewall rules, which Windows blocks by default.

> [!NOTE]
> The Windows router forwards traffic but does **not** perform NAT. If you need SNAT to the internet, use the Linux router or add Routing and Remote Access / NAT separately.

<a id="windows-parameters"></a>

### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `virtualMachineName` | string | *(required)* | Name of the router VM. |
| `adminUsername` | string | *(required)* | Local admin user name. |
| `adminPassword` | secure string | *(required)* | Local admin password. |
| `networkMode` | string | `ExistingSubnet` | `ExistingSubnet`, `NewSubnet` or `NewVnet` — see [Network modes](#network-modes). |
| `virtualNetworkName` | string | *(required)* | VNET to join, or to create in `NewVnet` mode. |
| `virtualNetworkAddressPrefix` | string | `10.100.0.0/16` | Address space for the new VNET. `NewVnet` only. |
| `subnetName` | string | *(required)* | Subnet to join, or to create in `NewSubnet` / `NewVnet` mode. |
| `subnetAddressPrefix` | string | `10.100.0.0/24` | CIDR for the new subnet, can be as small as /29. `NewSubnet` / `NewVnet` only. |
| `osVersion` | string | `2025` | Windows Server version — `2025`, `2022` or `2019`. |
| `virtualMachineSize` | string | `Standard_B2s` | VM size. |
| `osDiskType` | string | `Standard_LRS` | `Premium_LRS`, `StandardSSD_LRS` or `Standard_LRS`. |
| `deployPublicIpAddress` | bool | `true` | Create a Standard SKU static public IP. |
| `allowRdpFromAddressPrefix` | string | `''` | Source prefix allowed inbound on TCP 3389. Empty means no RDP rule. |
| `scriptUri` | string | resolved from the template's own URL | Setup script to run. |
| `scriptCmd` | string | `powershell.exe -ExecutionPolicy Unrestricted -File winrouter.ps1` | Command used to run the script. |
| `location` | string | resource group location | Azure region. |

---

## Network security defaults

The templates deploy a **Standard SKU** public IP, because the Basic SKU was retired by Azure in September 2025. Standard public IPs are *secure by default*, which changes the out-of-the-box behaviour compared to older versions of these templates:

- **Inbound internet traffic is blocked** unless an NSG explicitly allows it. Set `allowSshFromAddressPrefix` / `allowRdpFromAddressPrefix` to a trusted source — `203.0.113.4/32` for a single address, or a CIDR range for an office network. The template then creates an NSG with the matching management rule (priority 200) plus an RFC 1918 allow rule (priority 300) so forwarded traffic keeps flowing under the new default-deny. Leaving the parameter empty keeps the previous behaviour and means you manage the VM from inside your network or through Azure Bastion. Setting it to `Internet` or `*` allows access from anywhere and is **not recommended**.
- **Outbound internet traffic is allowed.** NSGs permit outbound by default, and the attached public IP provides an *explicit* outbound method (SNAT), so the setup script can install packages during provisioning. This also keeps the templates working after Azure's retirement of default outbound access for new deployments.
- **If you set `deployPublicIpAddress=false`**, make sure the subnet has another explicit outbound method — a NAT Gateway, a route through Azure Firewall or another NVA, or Load Balancer outbound rules. Without one, the VM has no internet access on a modern VNET and the setup script cannot install its packages.

---

## Using the router

Deploying the VM does not by itself send any traffic through it. To route traffic:

1. Create a **route table** and add a user-defined route, for example `0.0.0.0/0` with next hop type **Virtual appliance** and the router's **private** IP as the next hop address.
2. Associate the route table with the source subnets whose traffic should traverse the router.
3. Make sure the router's NSG allows the traffic you intend to forward — the templates add an RFC 1918 allow rule for exactly this reason.

> [!TIP]
> Do **not** associate the route table with the router's own subnet using a default route pointing at itself; that creates a routing loop.

---

## Deploying from the command line

Deploy the generated ARM template directly from GitHub. Joining an existing subnet:

```bash
az group create -n rg-nva -l eastus

az deployment group create \
  -g rg-nva \
  --template-uri https://raw.githubusercontent.com/tfi-stevep/AzureVM-Router/valid-computer-name/infra/arm/linux-router.json \
  --parameters \
      virtualMachineName=nva1 \
      adminUsername=azureuser \
      adminPassword='<your-password>' \
      networkMode=ExistingSubnet \
      virtualNetworkName=vnet1 \
      subnetName=nva-subnet \
      allowSshFromAddressPrefix="$(curl -s ifconfig.me)/32"
```

Building the VNET and subnet from scratch:

```bash
az deployment group create \
  -g rg-nva \
  --template-uri https://raw.githubusercontent.com/tfi-stevep/AzureVM-Router/valid-computer-name/infra/arm/linux-router.json \
  --parameters \
      virtualMachineName=nva1 \
      adminUsername=azureuser \
      adminPassword='<your-password>' \
      networkMode=NewVnet \
      virtualNetworkName=vnet-nva \
      virtualNetworkAddressPrefix=10.100.0.0/16 \
      subnetName=lxnva-subnet \
      subnetAddressPrefix=10.100.0.0/24 \
      allowSshFromAddressPrefix="$(curl -s ifconfig.me)/32"
```

Use `networkMode=NewSubnet` to add the subnet to a VNET that already exists.

> [!WARNING]
> `scriptUri` defaults to a path resolved **relative to the template's own URL**, so it automatically follows the branch or fork you deploy from. That resolution relies on `deployment().properties.templateLink`, which is not populated when you deploy a local file with `--template-file` or from a template spec. In those cases the default falls back to the `master` branch on GitHub. Pass the script location explicitly to pin it elsewhere:
>
> ```bash
> --parameters scriptUri=https://raw.githubusercontent.com/tfi-stevep/AzureVM-Router/valid-computer-name/scripts/linux/linuxrouter.sh
> ```

---

## Publishing as a template spec

[Template specs](https://learn.microsoft.com/azure/azure-resource-manager/templates/template-specs) let you store a versioned template in your own subscription and share it through Azure RBAC, so consumers deploy it without needing access to this repository. `tools/publish-templatespecs.sh` publishes both routers:

```bash
./tools/publish-templatespecs.sh rg-templatespecs 1.0.0 eastus
```

Then deploy from the spec:

```bash
az deployment group create \
  -g rg-nva \
  --template-spec "$(az ts show -g rg-templatespecs -n linux-router --version 1.0.0 --query id -o tsv)" \
  --parameters \
      virtualMachineName=nva1 \
      adminUsername=azureuser \
      adminPassword='<your-password>' \
      networkMode=NewVnet \
      virtualNetworkName=vnet-nva \
      subnetName=lxnva-subnet \
      allowSshFromAddressPrefix="$(curl -s ifconfig.me)/32"
```

> [!NOTE]
> A template spec deployment does not expose the original template URL, so `scriptUri` falls back to the `master` branch of this repository. Pass `scriptUri` explicitly if you host the setup scripts somewhere else.

---

## Setup scripts

Custom Script Extension payloads under `scripts/`.

| Script | Purpose |
|---|---|
| `linux/linuxrouter.sh` | **Default.** IPv4/IPv6 forwarding, no ICMP redirects, `iptables` SNAT to the internet, persisted with `netfilter-persistent`. |
| `linux/linuxrouterv2.sh` | Same as above, using `/etc/sysctl.d/` drop-ins instead of editing `/etc/sysctl.conf`. |
| `linux/linuxrouteronly.sh` | Minimal — enables forwarding only, no NAT and no packages installed. |
| `linux/linuxrouterbgp.sh` | Router plus **Quagga** BGP, peering with two route server / peer IPs. |
| `linux/linuxrouterbgpnh.sh` | Quagga BGP with an explicit **next-hop** override for advertised routes. |
| `linux/linuxrouterbgpfrr.sh` | Router plus **FRRouting** BGP. |
| `linux/linuxrouterbgpfrr2.sh` | FRRouting variant used for the second NVA in dual-NVA labs. |
| `linux/linuxrouterbgpfrr2nh.sh` | FRRouting second-NVA variant with a next-hop override. |
| `linux/cloud-init.txt` | cloud-init alternative to the Custom Script Extension. |
| `windows/winrouter.ps1` | Enables forwarding on all interfaces and allows inbound ICMP echo. |

> [!NOTE]
> Every script that installs packages first runs `cloud-init status --wait`. Without it the extension can race cloud-init while it is still switching the VM to the regional Azure apt mirror, which leaves the on-disk package indexes pointing at the superseded mirror and makes installs fail with `Unable to locate package`.

---

## Lab deployment scripts

End-to-end environment builds under `labs/`, intended to be run interactively line by line.

| Script | Builds |
|---|---|
| `deploylinuxnva.azcli` | A VNET with a Linux NVA plus spoke/test VMs and UDRs to validate routing through it. |
| `deploylinuxnvabgp.azcli` | A Linux NVA running BGP, peered with an Azure Route Server. |
| `deploylinuxnvabgpnp.azcli` | The BGP lab with a custom next-hop, plus network test tooling on the test VMs. |
| `conf/*-bgproutes.txt` | Pre-generated route lists (999 to 10240 prefixes) for BGP scale testing. |

---

## Working with the templates

Rebuild the ARM JSON after changing any Bicep file:

```bash
az bicep build --file infra/bicep/linux-router.bicep   --outfile infra/arm/linux-router.json
az bicep build --file infra/bicep/windows-router.bicep --outfile infra/arm/windows-router.json
```

CI runs `bicep lint`, rebuilds every template and fails if `infra/arm/` differs from the committed output. It also checks the shell scripts for syntax errors and rejects CRLF line endings, which break the shebang when the Custom Script Extension runs a script on Linux.

---

## Recent improvements

The templates and scripts were modernised after several Azure platform retirements broke the original versions.

| Area | What changed |
|---|---|
| **Infrastructure as code** | Templates converted to **Bicep**; the ARM JSON is now generated output, kept in sync by CI. |
| **Operating systems** | Ubuntu 18.04 and the retired `UbuntuLTS` / `ubuntults` CLI aliases replaced with **Ubuntu 24.04 LTS** (default) and 22.04 LTS. Windows moved from Server 2019 to **Server 2025** Core / small disk / Gen 2, with Trusted Launch. |
| **Public IP** | Basic SKU (retired September 2025) replaced with **Standard SKU, static allocation** across all templates and lab scripts. |
| **Network security** | Added `allowSshFromAddressPrefix` / `allowRdpFromAddressPrefix` so the templates can create the NSG that Standard SKU public IPs now require, together with an RFC 1918 rule so forwarded traffic still flows. Lab scripts that previously created no NSG now create one. |
| **Provisioning reliability** | Fixed a latent **cloud-init race** that intermittently failed package installation with `Unable to locate package netfilter-persistent`. All package-installing scripts now wait for cloud-init to finish first. |
| **Repository layout** | Reorganised into `infra/`, `scripts/`, `labs/`, `tools/` and `docs/`, with consistent file naming. |
| **Consolidated network modes** | The separate "existing subnet" and "new subnet" templates were merged into one template per OS. A `networkMode` parameter now selects **`ExistingSubnet`**, **`NewSubnet`** or **`NewVnet`**, and the capability was extended to Windows, which previously only supported an existing subnet. Templates now also emit `privateIpAddress`, `publicIpAddress` and `subnetId` outputs. |
| **Template specs** | Added `tools/publish-templatespecs.sh` and made `scriptUri` resolve safely when `deployment().properties.templateLink` is unavailable, so the templates work identically from a URL, a local file or a template spec. |
| **Quality gates** | Added GitHub Actions validation and a `.gitattributes` that pins shell scripts to LF. |
| **Documentation** | Rewrote this README with parameter references, network mode guidance, security guidance and coverage of every script in the repository. |

All templates and the affected lab scripts were verified by deploying them to Azure and confirming NSG placement, inbound reachability, extension success, in-guest forwarding and NAT state, end-to-end egress through the NVA, and persistence across a reboot.

---

## Roadmap

### Add a VMSS option for both Linux and Windows deployments

Replace the single-VM deployment with a **Virtual Machine Scale Set in Flexible orchestration mode** so the router tier can scale out and survive the loss of an instance.

- Place the scale set behind an **internal Standard Load Balancer** with an **HA Ports** rule, so all protocols and ports are distributed, and a health probe that removes unhealthy instances from rotation.
- Point user-defined routes at the **load balancer's frontend IP** instead of a single VM's private IP, so the next hop stays valid as instances come and go.
- Spread instances across **availability zones** for zone resilience, and apply the existing setup scripts through the scale set's extension profile so every new instance is configured identically.
- Design consideration: stateful features such as `iptables` SNAT require **flow symmetry**, so return traffic must reach the same instance that handled the outbound flow. The NAT-to-internet scenario therefore needs per-instance outbound addressing or a NAT Gateway on the subnet rather than per-instance masquerade. Pure forwarding and BGP scenarios do not have this constraint.

### Add an Accelerated Networking option

Expose an `acceleratedNetworking` parameter that sets `enableAcceleratedNetworking` on the NIC. Accelerated Networking gives the VM **SR-IOV**, bypassing the host virtual switch to deliver substantially lower latency and jitter, far higher packets-per-second, and lower CPU utilisation per gigabit — all of which are the main throughput limits for a software NVA.

- Requires a **supported VM size**. The current `Standard_B2s` default is a burstable size and does **not** support Accelerated Networking, so enabling it also means moving to a size such as `Standard_D2s_v5` or larger.
- Should ship with clear guidance mapping expected throughput to VM size, since the NIC setting alone does not lift the size's own bandwidth cap.
- Plan to validate the flag against every supported OS image, since enabling it on an unsupported size or image causes the deployment to fail rather than silently degrade.

---

## Contributing

Issues and pull requests are welcome. When changing a template, edit the Bicep under `infra/bicep/`, rebuild the ARM JSON, and commit both — CI will fail if they drift apart.

## License

Released under the [MIT License](LICENSE).
