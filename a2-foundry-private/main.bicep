// AI 編 A2：Microsoft Foundry の閉域化（プライベート エンドポイント）
// パブリック アクセスとキー認証を無効にした Foundry リソース、プロジェクト、モデルのデプロイ、
// VNet、プライベート エンドポイント、3 つのプライベート DNS ゾーンと VNet リンク、Foundry User の割り当てを作る。

@description('リージョン')
param location string = resourceGroup().location

@description('Foundry リソース名（カスタム サブドメインにも使う。グローバルで一意）')
param foundryName string = 'fdy-${uniqueString(resourceGroup().id)}'

@description('プロジェクト名')
param projectName string = 'proj-a2'

@description('デプロイするモデル')
param modelName string = 'gpt-5-mini'

@description('モデルのバージョン')
param modelVersion string = '2025-08-07'

@description('デプロイの容量（グローバル標準では 1 = 1,000 TPM）')
param capacity int = 10

@description('VNet のアドレス空間')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('アプリや VM を置くサブネット')
param appSubnetPrefix string = '10.0.0.0/24'

@description('プライベート エンドポイントを置くサブネット')
param peSubnetPrefix string = '10.0.1.0/24'

@description('Foundry User を割り当てるプリンシパルのオブジェクト ID（ユーザー、グループ、マネージド ID）')
param principalId string

@description('プリンシパルの種類')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'User'

// Foundry User（旧 Azure AI User）の組み込みロール定義 ID
var foundryUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d' // allow-guid

// Foundry のプライベート エンドポイントに必要な 3 つの DNS ゾーン
var dnsZoneNames = [
  'privatelink.services.ai.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.cognitiveservices.azure.com'
]

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-a2'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefix: appSubnetPrefix
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: peSubnetPrefix
        }
      }
    ]
  }
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: foundryName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: foundryName
    allowProjectManagement: true
    disableLocalAuth: true // API キー認証を無効にする
    publicNetworkAccess: 'Disabled' // プライベート エンドポイントだけで受ける
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices' // 信頼されたサービスの例外（ポータルの既定と同じ）
    }
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundry
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// プロジェクトと同時に作ると RequestConflict になるため、順番に作る
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: modelName
  dependsOn: [
    project
  ]
  sku: {
    name: 'GlobalStandard'
    capacity: capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

resource dnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for z in dnsZoneNames: {
  name: z
  location: 'global'
}]

resource dnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (z, i) in dnsZoneNames: {
  parent: dnsZones[i]
  name: 'link-vnet-a2'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}]

resource pe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${foundryName}'
  location: location
  dependsOn: [
    deployment
  ]
  properties: {
    subnet: {
      id: '${vnet.id}/subnets/snet-pe'
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

resource peDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (z, i) in dnsZoneNames: {
      name: replace(z, '.', '-')
      properties: {
        privateDnsZoneId: dnsZones[i].id
      }
    }]
  }
}

resource foundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  name: guid(foundry.id, principalId, foundryUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', foundryUserRoleId)
    principalId: principalId
    principalType: principalType
  }
}

output foundryName string = foundry.name
output privateEndpointName string = pe.name
