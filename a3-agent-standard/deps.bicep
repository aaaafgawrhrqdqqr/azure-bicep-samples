// AI 編 A3：Foundry Agent Service の標準セットアップに必要な依存先と VNet
// VNet（エージェント用の委任サブネット、プライベート エンドポイント用サブネット）、
// Cosmos DB for NoSQL（サーバーレス）、AI 検索（Basic）、Storage と、それぞれのプライベート エンドポイントと DNS ゾーンを作る。

@description('リージョン')
param location string = resourceGroup().location

@description('名前の接尾辞（グローバルで一意にするため）')
param suffix string = uniqueString(resourceGroup().id)

@description('Storage BLOB データ共同作成者を付けるプリンシパル（Foundry を作る人）のオブジェクト ID')
param deployerPrincipalId string

@description('プリンシパルの種類')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param deployerPrincipalType string = 'User'

var vnetName = 'vnet-a3'
// ストレージ BLOB データ共同作成者
var blobContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // allow-guid

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.30.0.0/16'
      ]
    }
    subnets: [
      {
        // エージェントの送信用（Microsoft.App/environments に委任、/27 以上。推奨は /24）
        name: 'snet-agent'
        properties: {
          addressPrefix: '10.30.0.0/24'
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: '10.30.1.0/24'
        }
      }
    ]
  }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: 'cosmos-a3-${suffix}'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: 'srch-a3-${suffix}'
  location: location
  sku: {
    name: 'basic'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    disableLocalAuth: true
    publicNetworkAccess: 'enabled'
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'sta3${take(suffix, 16)}'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
  }
}

// 依存先のプライベート エンドポイントと DNS ゾーン
var peDefs = [
  {
    name: 'cosmos'
    id: cosmos.id
    group: 'Sql'
    zone: 'privatelink.documents.azure.com'
  }
  {
    name: 'search'
    id: search.id
    group: 'searchService'
    zone: 'privatelink.search.windows.net'
  }
  {
    name: 'blob'
    id: storage.id
    group: 'blob'
    zone: 'privatelink.blob.${environment().suffixes.storage}'
  }
]

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for p in peDefs: {
  name: p.zone
  location: 'global'
}]

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (p, i) in peDefs: {
  parent: zones[i]
  name: 'link-${vnetName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}]

resource pes 'Microsoft.Network/privateEndpoints@2024-05-01' = [for p in peDefs: {
  name: 'pe-${p.name}-a3'
  location: location
  properties: {
    subnet: {
      id: '${vnet.id}/subnets/snet-pe'
    }
    privateLinkServiceConnections: [
      {
        name: 'pls-${p.name}'
        properties: {
          privateLinkServiceId: p.id
          groupIds: [
            p.group
          ]
        }
      }
    ]
  }
}]

resource peDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = [for (p, i) in peDefs: {
  parent: pes[i]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(p.zone, '.', '-')
        properties: {
          privateDnsZoneId: zones[i].id
        }
      }
    ]
  }
}]

// Foundry を作る人に、Storage BLOB データ共同作成者（公式の前提条件）
resource blobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, deployerPrincipalId, blobContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobContributorRoleId)
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
  }
}

output cosmosName string = cosmos.name
output searchName string = search.name
output storageName string = storage.name
output vnetId string = vnet.id
