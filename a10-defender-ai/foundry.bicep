// 検証用の Foundry（キー認証は無効）と gpt-5-mini
param location string

@description('モデルの容量（1 で 1 分 1,000 トークン）')
param capacity int = 20

var suffix = uniqueString(resourceGroup().id)

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: 'aif-${suffix}'
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: 'aif-${suffix}'
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource model 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: 'gpt-5-mini'
  sku: {
    name: 'GlobalStandard'
    capacity: capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5-mini'
      version: '2025-08-07'
    }
  }
}

output endpoint string = foundry.properties.endpoint
