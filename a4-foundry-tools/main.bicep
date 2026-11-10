// AI 編 A4：Foundry Tools 共通のセキュリティ
// Document Intelligence（既定は無料レベル F0）を、キー認証の無効化、ネットワーク制限（許可する IP だけ）、
// データ損失防止（解析に渡せる URL のドメインを制限）を設定して作り、
// 指定したプリンシパルに Cognitive Services User ロールを割り当てる。

@description('リージョン')
param location string = resourceGroup().location

@description('リソース名（カスタム サブドメインにも使う。グローバルで一意）')
param accountName string = 'di-${uniqueString(resourceGroup().id)}'

@description('価格レベル（F0 はサブスクリプションごとに数の制限がある）')
@allowed([
  'F0'
  'S0'
])
param skuName string = 'F0'

@description('アクセスを許可するパブリック IP アドレス（空なら、どこからも呼べない）')
param allowedIpAddresses array = []

@description('解析に渡す URL で許可するドメイン（データ損失防止）')
param allowedFqdnList array = [
  'raw.githubusercontent.com'
]

@description('Cognitive Services User を割り当てるプリンシパルのオブジェクト ID')
param principalId string

@description('プリンシパルの種類')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'User'

// Cognitive Services User の組み込みロール定義 ID
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908' // allow-guid

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: accountName
  location: location
  kind: 'FormRecognizer'
  sku: {
    name: skuName
  }
  properties: {
    customSubDomainName: accountName // Entra ID 認証に必要
    disableLocalAuth: true // API キー認証を無効にする（Entra ID だけ）
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: []
      ipRules: [for ip in allowedIpAddresses: {
        value: ip
      }]
    }
    restrictOutboundNetworkAccess: true // データ損失防止
    allowedFqdnList: allowedFqdnList
  }
}

resource userRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(account.id, principalId, cognitiveServicesUserRoleId)
  scope: account
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: principalId
    principalType: principalType
  }
}

output endpoint string = account.properties.endpoint
output accountName string = account.name
