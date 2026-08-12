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

@description('Admin username')
param adminUsername string

@description('Admin password')
@secure()
param adminPassword string

@description('Existing Virtual Nework Name')
param existingVirtualNetworkName string

@description('Name of the Subnet where NVA will reside')
param subnetName string = 'lxnva-subnet'

@description('Specify Subnet Prefix. It can be small as /29')
param subnetPrefix string

@description('Script that will be executed')
param scriptUri string = uri(deployment().properties.templateLink.uri, 'LinuxRouter.sh')

@description('Command to run the script')
param scriptCmd string = 'sh linuxrouter.sh'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Deploy Public IP Address')
param deployPublicIpAdress bool = true

var extensionName = 'CustomScript'
var nicName = '${virtualMachineName}-nic'
var publicIPAddressName = '${virtualMachineName}-PublicIP'

resource default_nsg 'Microsoft.Network/networkSecurityGroups@2020-05-01' = {
  name: 'default-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-Traffic-RFC-1918'
        properties: {
          priority: 300
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '10.0.0.0/8,172.16.0.0/12,192.168.0.0/16'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-11-01' existing = {
  name: existingVirtualNetworkName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2020-05-01' = {
  name: '${subnetName}-vnet'
  parent: virtualNetwork
  properties: {
    addressPrefix: subnetPrefix
    networkSecurityGroup: {
      id: default_nsg.id
    }
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2017-03-30' = {
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
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
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

resource nic 'Microsoft.Network/networkInterfaces@2017-06-01' = {
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
          publicIPAddress: deployPublicIpAdress ? {
            id: publicIpAddress.id
          } : {}
        }
      }
    ]
  }
}

resource publicIpAddress 'Microsoft.Network/publicIPAddresses@2017-06-01' = if (deployPublicIpAdress) {
  name: publicIPAddressName
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
  }
}

resource virtualMachineExtension 'Microsoft.Compute/virtualMachines/extensions@2015-06-15' = {
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
