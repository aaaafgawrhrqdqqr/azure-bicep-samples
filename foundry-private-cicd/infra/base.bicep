// =============================================================================
// base.bicep
// Runner のコンテナー イメージを置く ACR だけを先に作る。
// main.bicep の Container Apps ジョブは、このイメージを参照するため、
// 「ACR を作る → イメージを push する → main.bicep」の順に流す必要がある。
// =============================================================================

@description('リソースを作るリージョン')
param location string = resourceGroup().location

@description('ACR の名前（Azure 全体で一意。英小文字と数字のみ）')
param acrName string = 'acr${uniqueString(resourceGroup().id)}'

// Basic SKU（月 $5 程度）。Runner のイメージを置くだけなので公開エンドポイントのまま。
// Foundry 本体は閉域にするが、ここには秘密情報を含まないイメージしか置かない。
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false // ユーザー名とパスワードでのログインは使わない（Managed Identity で pull する）
  }
}

output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
