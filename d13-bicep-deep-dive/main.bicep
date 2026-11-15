// D13: Bicep deep dive sample (resource group scope)
targetScope = 'resourceGroup'

@description('Environment name. Only dev or prod is allowed.')
type environmentType = 'dev' | 'prod'

@description('Short prefix for resource names (3-8 lowercase letters or digits).')
@minLength(3)
@maxLength(8)
param prefix string

@description('Environment of this deployment.')
param environment environmentType = 'dev'

@description('Location of all resources.')
param location string = resourceGroup().location

@description('Subnets to create in the virtual network.')
param subnets array = [
  { name: 'snet-app', prefix: '10.20.1.0/24' }
  { name: 'snet-data', prefix: '10.20.2.0/24' }
]

@description('Create a Log Analytics workspace only when true.')
param deployLogs bool = false

var suffix = uniqueString(resourceGroup().id)
var tags = {
  environment: environment
  managedBy: 'bicep'
}

// Local module: virtual network with a loop over subnets
module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    name: 'vnet-${prefix}-${environment}'
    location: location
    addressPrefix: '10.20.0.0/16'
    subnets: subnets
    tags: tags
  }
}

// Public registry module: Azure Verified Modules (AVM) storage account
module storage 'br/public:avm/res/storage/storage-account:0.33.1' = {
  name: 'storage'
  params: {
    name: 'st${prefix}${take(suffix, 8)}'
    location: location
    skuName: environment == 'prod' ? 'Standard_ZRS' : 'Standard_LRS'
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    tags: tags
  }
}

// Conditional resource
resource logs 'Microsoft.OperationalInsights/workspaces@2025-07-01' = if (deployLogs) {
  name: 'log-${prefix}-${environment}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

output vnetId string = network.outputs.id
output subnetNames array = network.outputs.subnetNames
output storageName string = storage.outputs.name
