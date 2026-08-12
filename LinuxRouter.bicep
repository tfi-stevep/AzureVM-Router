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
@allowed(['18.04', '22.04'])
param osVersion string = '18.04'

@description('Admin username')
param adminUsername string

@description('Admin password')
@secure()
param adminPassword string

@description('Existing Virtual Nework Name')
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
param deployPublicIpAdress bool = true


var extensionName = 'CustomScript'
var nicName = '${virtualMachineName}-NIC'
var publicIPAddressName = '${virtualMachineName}-PublicIP'
var subnetResourceId = resourceId('Microsoft.Network/virtualNetworks/subnets', existingVirtualNetworkName, existingSubnet)

var osVersionDefinitions = {  
  '18.04': {
    publisher: 'Canonical'
    offer: 'UbuntuServer'
    sku: '18.04-LTS'
    version: 'latest'
  }
  '22.04': {
    publisher: 'Canonical'
    offer: '0001-com-ubuntu-server-jammy'
    sku: '22_04-lts'
    version: 'latest'
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
            id: subnetResourceId
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: deployPublicIpAdress ? publicIpAddress.id : null
          }
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

resource virtualMachineName_extension 'Microsoft.Compute/virtualMachines/extensions@2015-06-15' = {
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
