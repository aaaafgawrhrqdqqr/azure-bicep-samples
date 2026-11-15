@description('Virtual network name.')
param name string

@description('Location of the virtual network.')
param location string

@description('Address space of the virtual network.')
param addressPrefix string

@description('Subnets (name and prefix).')
param subnets array

@description('Tags.')
param tags object = {}

resource vnet 'Microsoft.Network/virtualNetworks@2025-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ addressPrefix ] }
    subnets: [for s in subnets: {
      name: s.name
      properties: { addressPrefix: s.prefix }
    }]
  }
}

output id string = vnet.id
output subnetNames array = [for (s, i) in subnets: vnet.properties.subnets[i].name]
