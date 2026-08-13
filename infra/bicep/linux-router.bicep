@description('Linux Router Machine Name')
param virtualMachineName string

@description('VM size')
param virtualMachineSize string = 'Standard_B2s'

@description('Ubuntu OS Version')
@allowed(['22.04', '24.04'])
param osVersion string = '24.04'

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

@description('How the router is attached to the network. ExistingSubnet: join a virtual network and subnet that already exist. NewSubnet: join an existing virtual network and create a new subnet in it. NewVnet: create a new virtual network and subnet.')
@allowed([
  'ExistingSubnet'
  'NewSubnet'
  'NewVnet'
])
param networkMode string = 'ExistingSubnet'

@description('Virtual network name. Must already exist for ExistingSubnet and NewSubnet; created for NewVnet.')
param virtualNetworkName string

@description('Address space for the virtual network. Only used when networkMode is NewVnet.')
param virtualNetworkAddressPrefix string = '10.100.0.0/16'

@description('Subnet name. Must already exist for ExistingSubnet; created for NewSubnet and NewVnet.')
param subnetName string

@description('CIDR for the subnet to create, can be as small as /29. Only used when networkMode is NewSubnet or NewVnet.')
param subnetAddressPrefix string = '10.100.0.0/24'

@description('Deploy Public IP Address')
param deployPublicIpAddress bool = true

@description('Source address prefix allowed to reach the VM on TCP 22, for example 203.0.113.4/32. Standard SKU public IPs deny inbound traffic by default, so leave this empty only if you do not need SSH from the internet. Use Internet to allow any source (not recommended).')
param allowSshFromAddressPrefix string = ''

@description('Script that will be executed. Defaults to the script alongside this template when deployed from a URL, and to the master branch on GitHub when deployed from a local file or a template spec.')
param scriptUri string = uri(deployment().properties.?templateLink.?uri ?? 'https://raw.githubusercontent.com/dmauser/AzureVM-Router/master/infra/arm/linux-router.json', '../../scripts/linux/linuxrouter.sh')

@description('Command to run the script')
param scriptCmd string = 'sh linuxrouter.sh'

@description('Azure region for all resources.')
param location string = resourceGroup().location

var extensionName = 'CustomScript'
var nicName = '${virtualMachineName}-NIC'
var nsgName = '${virtualMachineName}-NSG'
var publicIPAddressName = '${virtualMachineName}-PublicIP'

var createVirtualNetwork = networkMode == 'NewVnet'
var createSubnet = networkMode != 'ExistingSubnet'

// When the template creates the subnet it owns the subnet NSG. When joining a
// subnet that already exists, the NSG goes on the NIC instead so that any NSG
// already associated with that subnet is left untouched.
var attachNsgToSubnet = createSubnet
var attachNsgToNic = !createSubnet && !empty(allowSshFromAddressPrefix)
var deployNetworkSecurityGroup = attachNsgToSubnet || attachNsgToNic

var subnetResourceId = resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, subnetName)

var sshSecurityRules = empty(allowSshFromAddressPrefix) ? [] : [
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
]

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

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' = if (deployNetworkSecurityGroup) {
  name: nsgName
  location: location
  properties: {
    securityRules: concat(sshSecurityRules, [
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
    ])
  }
}

resource newVirtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = if (createVirtualNetwork) {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
}

resource targetVirtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: virtualNetworkName
}

resource addedSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (networkMode == 'NewSubnet') {
  parent: targetVirtualNetwork
  name: subnetName
  properties: {
    addressPrefix: subnetAddressPrefix
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
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

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  properties: {
    enableIPForwarding: true
    networkSecurityGroup: attachNsgToNic ? {
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
  dependsOn: [
    newVirtualNetwork
    addedSubnet
  ]
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

resource virtualMachineExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
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

@description('Private IP address of the router, use this as the next hop in a route table.')
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress

@description('Public IP address of the router, empty when deployPublicIpAddress is false.')
output publicIpAddress string = publicIpAddress.?properties.ipAddress ?? ''

@description('Resource ID of the subnet the router is attached to.')
output subnetId string = subnetResourceId
