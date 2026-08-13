@description('VM size')
param virtualMachineSize string = 'Standard_B2s'

@description('Windows Router Machine Name')
param virtualMachineName string

@description('Select Disk Type: Premium SSD (Premium_LRS), Standard SSD (StandardSSD_LRS), Standard HDD (Standard_LRS)')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param osDiskType string = 'Standard_LRS'

@description('Windows Server version. All options are Server Core, small disk, Generation 2 images.')
@allowed(['2019', '2022', '2025'])
param osVersion string = '2025'

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
param scriptUri string = uri(deployment().properties.templateLink.uri, '../../scripts/windows/winrouter.ps1')

@description('Command to run the script')
param scriptCmd string = 'powershell.exe -ExecutionPolicy Unrestricted -File winrouter.ps1'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Deploy Public IP Address')
param deployPublicIpAddress bool = true

@description('Source address prefix allowed to reach the VM on TCP 3389, for example 203.0.113.4/32. Standard SKU public IPs deny inbound traffic by default, so leave this empty only if you do not need RDP from the internet. Use Internet to allow any source (not recommended).')
param allowRdpFromAddressPrefix string = ''

var extensionName = 'CustomScript'
var nicName = '${virtualMachineName}-NIC'
var nsgName = '${virtualMachineName}-NSG'
var publicIPAddressName = '${virtualMachineName}-PublicIP'
var subnetResourceId = resourceId('Microsoft.Network/virtualNetworks/subnets', existingVirtualNetworkName, existingSubnet)
var deployNetworkSecurityGroup = !empty(allowRdpFromAddressPrefix)

var osVersionDefinitions = {
  '2019': {
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2019-datacenter-core-smalldisk-g2'
    version: 'latest'
  }
  '2022': {
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-core-smalldisk-g2'
    version: 'latest'
  }
  '2025': {
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2025-datacenter-core-smalldisk-g2'
    version: 'latest'
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' = if (deployNetworkSecurityGroup) {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-Inbound'
        properties: {
          priority: 200
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowRdpFromAddressPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
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
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
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

resource virtualMachineExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: virtualMachine
  name: extensionName
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        scriptUri
      ]
      commandToExecute: scriptCmd
    }
  }
}
