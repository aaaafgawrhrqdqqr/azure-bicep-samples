// AI 編 A5：Azure AI 検索のセキュリティ
// Basic の検索サービスを、ロールベースのアクセス制御だけ（API キー無効）、許可する IP だけのネットワーク、
// システム割り当てマネージド ID で作る。インデクサー用の Storage は、既定で拒否し、
// 信頼された Microsoft サービスの例外だけで検索サービスからの読み取りを許可する。

@description('リージョン（検索サービスと Storage は同じリージョン）')
param location string = resourceGroup().location

@description('検索サービス名（グローバルで一意）')
param searchName string = 'srch-${uniqueString(resourceGroup().id)}'

@description('Storage アカウント名（グローバルで一意、小文字と数字）')
param storageName string = 'st${uniqueString(resourceGroup().id)}'

@description('検索サービスへのアクセスを許可するパブリック IP アドレス')
param allowedIpAddresses array = []

@description('検索インデックス データ閲覧者を割り当てるプリンシパルのオブジェクト ID')
param principalId string

@description('プリンシパルの種類')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'User'

// 組み込みロール定義 ID
var searchIndexDataReaderRoleId = '1407120a-92aa-4202-b7e9-c0e197c71c8f' // allow-guid
var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1' // allow-guid

resource search 'Microsoft.Search/searchServices@2025-05-01' = {
  name: searchName
  location: location
  sku: {
    name: 'basic'
  }
  identity: {
    type: 'SystemAssigned' // インデクサーが Storage に接続するときに使う
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    disableLocalAuth: true // API キーを無効にし、ロールベースのアクセス制御だけにする
    publicNetworkAccess: 'enabled'
    networkRuleSet: {
      ipRules: [for ip in allowedIpAddresses: {
        value: ip
      }]
    }
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices' // 信頼された Microsoft サービスの例外
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storage
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  name: 'docs'
}

resource searchToBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, search.id, storageBlobDataReaderRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
    principalId: search.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource readerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, principalId, searchIndexDataReaderRoleId)
  scope: search
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataReaderRoleId)
    principalId: principalId
    principalType: principalType
  }
}

output searchEndpoint string = 'https://${search.name}.search.windows.net'
output searchName string = search.name
output storageId string = storage.id
