// AI 編 A3：Foundry Agent Service の標準セットアップ（自分の Cosmos DB・Storage・AI 検索）と VNet インジェクション
// deps.bicep で依存先と VNet を作り、Foundry（パブリック アクセスとキー認証を無効、エージェントの送信を委任サブネットへ）、
// プライベート エンドポイント、プロジェクト、プロジェクト レベルの接続、ロールの割り当て、機能ホスト、モデルのデプロイを作る。
// ※接続はプロジェクトのレベルにだけ作る（リソース レベルの接続は、将来のプロジェクトにも効くため）。

@description('リージョン')
param location string = resourceGroup().location

@description('Foundry リソース名（カスタム サブドメインにも使う。グローバルで一意）')
param foundryName string = 'fdy-${uniqueString(resourceGroup().id)}'

@description('プロジェクト名')
param projectName string = 'proj-a3'

@description('デプロイするモデル（エージェントに対応したもの）')
param modelName string = 'gpt-5-mini'

@description('モデルのバージョン')
param modelVersion string = '2025-08-07'

@description('Foundry を作る人（とエージェントを使う人）のオブジェクト ID')
param principalId string

@description('プリンシパルの種類')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'User'

// 組み込みロールの定義 ID
var roles = {
  foundryUser: '53ca6127-db72-4b80-b1b0-d745d6d5456d' // allow-guid
  cosmosOperator: '230815da-be43-4aae-9cb4-875f7bd000aa' // allow-guid
  blobContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // allow-guid
  blobOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // allow-guid
  searchIndexContributor: '8ebe5a00-799e-43f5-93ac-243d3dce84a7' // allow-guid
  searchServiceContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0' // allow-guid
}
// Cosmos DB の組み込みデータ ロール（Cosmos DB Built-in Data Contributor）
var cosmosDataContributor = '00000000-0000-0000-0000-000000000002' // allow-guid

var foundryDnsZones = [
  'privatelink.services.ai.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.cognitiveservices.azure.com'
]

// 依存先と VNet（Cosmos DB・AI 検索・Storage とそのプライベート エンドポイント）
module deps 'deps.bicep' = {
  name: 'deps'
  params: {
    location: location
    deployerPrincipalId: principalId
    deployerPrincipalType: principalType
  }
}

// 依存先の名前は deps.bicep と同じ規則（デプロイの開始時に決まる値にするため）
// ※依存先のプロパティ（エンドポイントなど）は参照しない。作られる前に評価されて ResourceNotFound になった
var suffix = uniqueString(resourceGroup().id)
// VNet の ID も、デプロイの開始時に決まる形で組み立てる（モジュールの出力は事前検証で評価できない）
var vnetId = resourceId('Microsoft.Network/virtualNetworks', 'vnet-a3')

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: 'cosmos-a3-${suffix}'
}
resource search 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: 'srch-a3-${suffix}'
}
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: 'sta3${take(suffix, 16)}'
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: foundryName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  dependsOn: [
    deps
  ]
  properties: {
    customSubDomainName: foundryName
    allowProjectManagement: true
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    // エージェントの送信を委任サブネットに入れる（作成時に決める。あとから追加できない）
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: '${vnetId}/subnets/snet-agent'
        useMicrosoftManagedNetwork: false
      }
    ]
  }
}

// Foundry のプライベート エンドポイントと 3 つの DNS ゾーン
resource fZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for z in foundryDnsZones: {
  name: z
  location: 'global'
}]

resource fLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (z, i) in foundryDnsZones: {
  parent: fZones[i]
  name: 'link-vnet-a3'
  location: 'global'
  dependsOn: [
    deps
  ]
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}]

resource fPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${foundryName}'
  location: location
  properties: {
    subnet: {
      id: '${vnetId}/subnets/snet-pe'
    }
    privateLinkServiceConnections: [
      {
        name: 'pls-${foundryName}'
        properties: {
          privateLinkServiceId: foundry.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

resource fPeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: fPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (z, i) in foundryDnsZones: {
      name: replace(z, '.', '-')
      properties: {
        privateDnsZoneId: fZones[i].id
      }
    }]
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: foundry
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
  dependsOn: [
    fPeDns
  ]
}

// プロジェクト レベルの接続（Entra ID 認証）
resource connCosmos 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: 'cosmos'
  properties: {
    category: 'CosmosDb'
    target: 'https://${cosmos.name}.documents.azure.com:443/'
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmos.id
      location: location
    }
  }
}

resource connStorage 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: 'storage'
  properties: {
    category: 'AzureStorageAccount'
    target: 'https://${storage.name}.blob.${environment().suffixes.storage}/'
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: storage.id
      location: location
    }
  }
}

resource connSearch 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: 'aisearch'
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${search.name}.search.windows.net'
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: search.id
      location: location
    }
  }
}

// プロジェクトのマネージド ID に、依存先のロール（機能ホストの前に必要なもの）
resource raCosmosOperator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cosmos
  name: guid(cosmos.id, project.id, roles.cosmosOperator)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cosmosOperator)
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource raBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, project.id, roles.blobContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.blobContributor)
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource raSearchIndex 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(search.id, project.id, roles.searchIndexContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexContributor)
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource raSearchService 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(search.id, project.id, roles.searchServiceContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchServiceContributor)
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// 機能ホスト（エージェントの会話・ファイル・ベクター ストアの保存先を指定する）
resource capHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: project
  name: 'caphost'
  properties: {
    #disable-next-line BCP037 // 型定義にまだないが、ポータルで作った機能ホストにも入っている値
    capabilityHostKind: 'Agents'
    threadStorageConnections: [
      connCosmos.name
    ]
    storageConnections: [
      connStorage.name
    ]
    vectorStoreConnections: [
      connSearch.name
    ]
  }
  dependsOn: [
    raCosmosOperator
    raBlobContributor
    raSearchIndex
    raSearchService
  ]
}

// 機能ホストのあとに付けるデータ ロール
resource cosmosData 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = {
  parent: cosmos
  name: guid(cosmos.id, project.id, cosmosDataContributor)
  properties: {
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/${cosmosDataContributor}'
    principalId: project.identity.principalId
    scope: cosmos.id
  }
  dependsOn: [
    capHost
  ]
}

resource raBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, project.id, roles.blobOwner)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.blobOwner)
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    capHost
  ]
}

// モデルのデプロイ（プロジェクトと同時に作ると RequestConflict になるため、機能ホストのあと）
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: foundry
  name: modelName
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
  dependsOn: [
    capHost
  ]
}

// エージェントを使う人に Foundry User
resource raFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  name: guid(foundry.id, principalId, roles.foundryUser)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.foundryUser)
    principalId: principalId
    principalType: principalType
  }
}

output foundryName string = foundry.name
output projectName string = project.name
