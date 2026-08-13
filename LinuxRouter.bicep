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

@description('Type Existing Subnet Name')
param existingSubnet string

@description('Script that will be executed')
param scriptUri string = uri(deployment().properties.templateLink.uri, 'linuxrouter.sh')

@description('Command to run the script')
param scriptCmd string = 'sh linuxrouter.sh'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Deploy Public IP Address')
param deployPublicIpAddress bool = true

@description('Source address prefix allowed to reach the VM on TCP 22, for example 203.0.113.4/32. Standard SKU public IPs deny inbound traffic by default, so leave this empty only if you do not need SSH from the internet. Use Internet to allow any source (not recommended).')
param allowSshFromAddressPrefix string = ''

var extensionName = 'CustomScript'
var nicName = '${virtualMachineName}-NIC'
var nsgName = '${virtualMachineName}-NSG'
var publicIPAddressName = '${virtualMachineName}-PublicIP'
var subnetResourceId = resourceId('Microsoft.Network/virtualNetworks/subnets', existingVirtualNetworkName, existingSubnet)
var deployNetworkSecurityGroup = !empty(allowSshFromAddressPrefix)

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

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' = if (deployNetworkSecurityGroup) {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-Inbound'
        properties: {
          priority: 200
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowSshFromAddressPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
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

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  properties: {
    enableIPForwarding: true
    networkSecurityGroup: deployNetworkSecurityGroup ? {
      id: networkSecurityGroup.id
    } : null
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetResourceId
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

resource virtualMachineName_extension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: virtualMachine
  name: extensionName
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
