// AI 編 A1：Microsoft Foundry の構成要素と認証・RBAC
// キー認証を無効にした Foundry リソース、プロジェクト、モデルのデプロイ（gpt-5-mini）と、
// 指定したプリンシパルへの Foundry User ロールの割り当てを作る。
// 記事: https://taiyakiman1125.com/ （AI 編 A1）

@description('リージョン')
param location string = resourceGroup().location

@description('Foundry リソース名（カスタム サブドメインにも使う。グローバルで一意）')
param foundryName string = 'fdy-${uniqueString(resourceGroup().id)}'

@description('プロジェクト名')
param projectName string = 'proj-a1'

@description('デプロイするモデル')
param modelName string = 'gpt-5-mini'

@description('モデルのバージョン')
param modelVersion string = '2025-08-07'

@description('デプロイの容量（グローバル標準では 1 = 1,000 TPM）')
param capacity int = 10

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
    customSubDomainName: foundryName // Entra ID 認証に必要
    allowProjectManagement: true // Foundry のプロジェクトを使う
    disableLocalAuth: true // API キー認証を無効にする（Entra ID だけ）
    publicNetworkAccess: 'Enabled' // 閉域化は A2 で扱う
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

// プロジェクトとモデルのデプロイを同時に作ると、Foundry リソースへの操作が重なって
// RequestConflict（Another operation is in progress on the resource）になったため、順番に作る
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

resource foundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  name: guid(foundry.id, principalId, foundryUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', foundryUserRoleId)
    principalId: principalId
    principalType: principalType
  }
}

output endpoint string = 'https://${foundryName}.openai.azure.com/openai/v1/'
output foundryEndpoint string = foundry.properties.endpoint
output projectName string = project.name
output deploymentName string = deployment.name
