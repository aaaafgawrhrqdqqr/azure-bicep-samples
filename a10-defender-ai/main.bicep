// AI 編 A10：Defender for Cloud の AI 脅威保護
// サブスクリプションの Defender プラン「AI サービス」をオンにし、
// 検証用の Foundry（キー認証は無効）とモデルをリソース グループに作る。
// サブスクリプションのスコープでデプロイする（az deployment sub create）。
targetScope = 'subscription'

@description('リージョン')
param location string = 'japaneast'

@description('検証用のリソース グループ名')
param resourceGroupName string = 'rg-a10-bicep'

@description('アラートに、疑わしいプロンプトの一部（証拠）を載せるか')
param promptEvidence bool = true

@description('AI モデルのセキュリティ（Azure Machine Learning のモデルのスキャン、プレビュー）を有効にするか')
param modelScanner bool = true

// Defender プラン「AI サービス」。サブスクリプション全体に効く
resource aiPlan 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'AI'
  properties: {
    pricingTier: 'Standard'
    extensions: [
      {
        name: 'AIPromptEvidence'
        isEnabled: promptEvidence ? 'True' : 'False'
      }
      {
        name: 'AIModelScanner'
        isEnabled: modelScanner ? 'True' : 'False'
      }
    ]
  }
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

module foundry 'foundry.bicep' = {
  name: 'foundry'
  scope: rg
  params: {
    location: location
  }
}

output foundryEndpoint string = foundry.outputs.endpoint
output planTier string = aiPlan.properties.pricingTier
