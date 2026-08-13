#!/bin/bash
# Publish the router templates as Azure Template Specs.
#
# Template specs give you versioned, RBAC-controlled copies of the templates
# inside your own subscription, so you can deploy them without depending on
# raw.githubusercontent.com being reachable.
#
# Note on scriptUri: a template spec deployment does not expose a template URL,
# so the templates fall back to fetching their setup script from the master
# branch on GitHub. If your VMs cannot reach GitHub, pass scriptUri explicitly
# and point it at a location you control, for example blob storage.
#
# Usage:
#   ./tools/publish-templatespecs.sh <resource-group> <version> [location]
#
# Example:
#   ./tools/publish-templatespecs.sh rg-templatespecs 1.0.0 eastus

set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <resource-group> <version> [location]" >&2
    exit 1
fi

resourceGroup="$1"
version="$2"
location="${3:-eastus}"

repoRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Ensuring resource group $resourceGroup exists in $location"
az group create --name "$resourceGroup" --location "$location" --output none

publish() {
    local specName="$1"
    local templateFile="$2"
    local description="$3"

    echo "Publishing $specName version $version"
    az ts create \
        --resource-group "$resourceGroup" \
        --name "$specName" \
        --version "$version" \
        --location "$location" \
        --template-file "$templateFile" \
        --description "$description" \
        --yes \
        --output none

    az ts show \
        --resource-group "$resourceGroup" \
        --name "$specName" \
        --version "$version" \
        --query id \
        --output tsv
}

publish "linux-router" \
    "$repoRoot/infra/arm/linux-router.json" \
    "Ubuntu VM configured as a router / NVA."

publish "windows-router" \
    "$repoRoot/infra/arm/windows-router.json" \
    "Windows Server VM configured as a router / NVA."

echo
echo "Done. Deploy one with:"
echo "  az deployment group create \\"
echo "    --resource-group <target-rg> \\"
echo "    --template-spec <id printed above> \\"
echo "    --parameters virtualMachineName=nva1 networkMode=NewVnet \\"
echo "                 virtualNetworkName=vnet1 subnetName=nvasubnet \\"
echo "                 adminUsername=azureuser"
