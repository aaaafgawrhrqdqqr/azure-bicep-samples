// AI 編 A6：ガードレール
// キー認証を無効にした Foundry リソースとプロジェクト、gpt-5-mini のデプロイに、
// カスタム ガードレール（間接プロンプト インジェクションのブロック、カスタム ブロックリスト）を割り当てる。
// Foundry の外から使う Azure AI Content Safety（F0）も作る。

@description('リージョン')
param location string = resourceGroup().location

@description('Foundry リソース名（カスタム サブドメインにも使う。グローバルで一意）')
param foundryName string = 'fdy-${uniqueString(resourceGroup().id)}'

@description('Content Safety のリソース名（グローバルで一意）')
param contentSafetyName string = 'cs-${uniqueString(resourceGroup().id)}'

@description('プロジェクト名')
param projectName string = 'proj-a6'

@description('ブロックリストに入れる語（完全一致）')
param blockedTerms array = [
  'PROJECT-HAYABUSA'
]

@description('Foundry User と Cognitive Services User を割り当てるプリンシパルのオブジェクト ID')
param principalId string

@description('プリンシパルの種類')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'User'

var foundryUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d' // allow-guid
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908' // allow-guid

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
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
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

resource blocklist 'Microsoft.CognitiveServices/accounts/raiBlocklists@2025-06-01' = {
  parent: foundry
  name: 'bl-internal'
  properties: {
    description: '社外秘のプロジェクト名'
  }
  dependsOn: [
    project // 同じ Foundry リソースへの変更を同時に送ると RequestConflict になるので順番に作る
  ]
}

@batchSize(1)
resource blocklistItems 'Microsoft.CognitiveServices/accounts/raiBlocklists/raiBlocklistItems@2025-06-01' = [for (term, i) in blockedTerms: {
  parent: blocklist
  name: 'item-${i}'
  properties: {
    pattern: term
    isRegex: false
  }
}]

// ガードレール（RAI ポリシー）とモデルのデプロイは、ブロックリストができてから作る（同じテンプレートだと事前検証でブロックリストが見つからない）
module guardrail 'guardrail.bicep' = {
  name: 'guardrail'
  params: {
    foundryName: foundry.name
    blocklistName: blocklist.name
    // 実行時に決まる値を渡し、モジュールの検証をブロックリストの作成後にする
    blocklistDescription: blocklist.properties.description
  }
  dependsOn: [
    blocklistItems
  ]
}

resource contentSafety 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: contentSafetyName
  location: location
  kind: 'ContentSafety'
  sku: {
    name: 'F0'
  }
  properties: {
    customSubDomainName: contentSafetyName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource foundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, principalId, foundryUserRoleId)
  scope: foundry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', foundryUserRoleId)
    principalId: principalId
    principalType: principalType
  }
}

resource csUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(contentSafety.id, principalId, cognitiveServicesUserRoleId)
  scope: contentSafety
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: principalId
    principalType: principalType
  }
}

output foundryEndpoint string = 'https://${foundry.name}.openai.azure.com/openai/v1/'
output contentSafetyEndpoint string = contentSafety.properties.endpoint
