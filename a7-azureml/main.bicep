// AI 編 A7：Azure Machine Learning のセキュリティ
// マネージド VNet（承認された送信のみ）、ID ベースの既定データストア、許可した IP だけのパブリック アクセスで
// ワークスペースを作る。関連する Storage は共有キーを無効、Key Vault は RBAC にする。

@description('リージョン')
param location string = resourceGroup().location

@description('ワークスペース名')
param workspaceName string = 'mlw-${uniqueString(resourceGroup().id)}'

@description('ワークスペースへのアクセスを許可するパブリック IP（CIDR）。空ならパブリック アクセスを無効にする')
param allowedIpRanges array = []

@description('AzureML データ サイエンティストを割り当てるプリンシパルのオブジェクト ID')
param principalId string

@description('プリンシパルの種類')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'User'

var suffix = uniqueString(resourceGroup().id)
var dataScientistRoleId = 'f6c7c914-8db3-469d-8ca1-694a8f32e121' // allow-guid
var blobContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // allow-guid
var filePrivilegedContributorRoleId = '69566ab7-960f-475b-8e7c-b3118f30c6bd' // allow-guid

resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: 'stml${take(suffix, 18)}'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowSharedKeyAccess: false // ID ベースのアクセスだけ
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kvml${take(suffix, 18)}'
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 7
  }
}

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-ml-${suffix}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-ml-${suffix}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

resource workspace 'Microsoft.MachineLearningServices/workspaces@2025-06-01' = {
  name: workspaceName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: workspaceName
    storageAccount: storage.id
    keyVault: keyVault.id
    applicationInsights: appInsights.id
    systemDatastoresAuthMode: 'identity' // 既定のデータストアを ID ベースにする
    publicNetworkAccess: empty(allowedIpRanges) ? 'Disabled' : 'Enabled'
    // ポータルで「選択した IP アドレスから有効」にしたときに入るプロパティ（Bicep の型定義にまだない）
    #disable-next-line BCP037
    networkAcls: {
      defaultAction: 'Deny'
      ipRules: [for ip in allowedIpRanges: {
        value: ip
      }]
    }
    managedNetwork: {
      isolationMode: 'AllowOnlyApprovedOutbound' // 承認された送信だけ（あとから戻せない）
      firewallSku: 'Basic' // FQDN 規則を作ったときだけ使われる
    }
    provisionNetworkNow: true
  }
}

resource dataScientist 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workspace.id, principalId, dataScientistRoleId)
  scope: workspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', dataScientistRoleId)
    principalId: principalId
    principalType: principalType
  }
}

// ID ベースのデータストアを使う利用者には、Storage のデータ ロールも要る
resource userBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, principalId, blobContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobContributorRoleId)
    principalId: principalId
    principalType: principalType
  }
}

resource userFile 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, principalId, filePrivilegedContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', filePrivilegedContributorRoleId)
    principalId: principalId
    principalType: principalType
  }
}

output workspaceName string = workspace.name
output studioUrl string = 'https://ml.azure.com/?wsid=${workspace.id}'
