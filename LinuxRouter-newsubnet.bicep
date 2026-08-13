@description('VM size')
param virtualMachineSize string = 'Standard_B2s'

@description('Linux Router Machine Name')
param virtualMachineName string

@description('Select Disk Type: Premium SSD (Premium_LRS), Standard SSD (StandardSSD_LRS), Standard HDD (Standard_LRS)')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param osDiskType string = 'Standard_LRS'

@description('Ubuntu OS Version')
@allowed(['22.04', '24.04'])
param osVersion string = '24.04'

@description('Admin username')
param adminUsername string

@description('Admin password')
@secure()
param adminPassword string

@description('Existing Virtual Network Name')
param existingVirtualNetworkName string

@description('Name of the Subnet where NVA will reside')
param subnetName string = 'lxnva-subnet'

@description('Specify Subnet Prefix. It can be small as /29')
param subnetPrefix string

@description('Script that will be executed')
param scriptUri string = uri(deployment().properties.templateLink.uri, 'linuxrouter.sh')

@description('Command to run the script')
param scriptCmd string = 'sh linuxrouter.sh'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Deploy Public IP Address')
param deployPublicIpAddress bool = true

var extensionName = 'CustomScript'
var nicName = '${virtualMachineName}-NIC'
var publicIPAddressName = '${virtualMachineName}-PublicIP'

var osVersionDefinitions = {
  '22.04': {
    publisher: 'Canonical'
    offer: '0001-com-ubuntu-server-jammy'
    sku: '22_04-lts-gen2'
    version: 'latest'
  }
  '24.04': {
    publisher: 'Canonical'
    offer: 'ubuntu-24_04-lts'
    sku: 'server'
    version: 'latest'
  }
}

resource default_nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'default-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-Traffic-RFC-1918'
        properties: {
          priority: 300
          protocol: '*'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefixes: [
            '10.0.0.0/8'
            '172.16.0.0/12'
            '192.168.0.0/16'
          ]
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: existingVirtualNetworkName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  name: subnetName
  parent: virtualNetwork
  properties: {
    addressPrefix: subnetPrefix
    networkSecurityGroup: {
      id: default_nsg.id
    }
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: virtualMachineName
  location: location
  properties: {
    osProfile: {
      computerName: virtualMachineName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    hardwareProfile: {
      vmSize: virtualMachineSize
    }
    storageProfile: {
      imageReference: osVersionDefinitions[osVersion]
      osDisk: {
        createOption: 'FromImage'
        name: '${virtualMachineName}-OSDisk'
        managedDisk: {
          storageAccountType: osDiskType
        }
      }
      dataDisks: []
    }
    networkProfile: {
      networkInterfaces: [
        {
          properties: {
            primary: true
          }
          id: nic.id
        }
      ]
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  properties: {
    enableIPForwarding: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnet.id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: deployPublicIpAddress ? {
            id: publicIpAddress.id
          } : null
        }
      }
    ]
  }
}

resource publicIpAddress 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployPublicIpAddress) {
  name: publicIPAddressName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource virtualMachineExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  name: extensionName
  parent: virtualMachine
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        scriptUri
      ]
      commandToExecute: scriptCmd
    }
  }
}
