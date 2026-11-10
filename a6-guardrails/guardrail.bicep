// A6：カスタム ガードレール（RAI ポリシー）と、それを割り当てた gpt-5-mini のデプロイ（main.bicep から呼ぶ）

@description('Foundry リソース名')
param foundryName string

@description('ブロックリスト名')
param blocklistName string

@description('ブロックリストの説明（作成の順番を保つために受け取る）')
param blocklistDescription string

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryName
}

// カスタム ガードレール（RAI ポリシー）：既定の DefaultV2 と同じ 4 カテゴリ・脱獄・保護されたマテリアルに、
// 間接プロンプト インジェクション（文書攻撃）とカスタム ブロックリストを足す
resource guardrail 'Microsoft.CognitiveServices/accounts/raiPolicies@2025-06-01' = {
  parent: foundry
  name: 'gr-custom'
  properties: {
    basePolicyName: 'Microsoft.DefaultV2'
    mode: 'Default'
    contentFilters: [
      { name: 'Hate', source: 'Prompt', enabled: true, blocking: true, severityThreshold: 'Medium' }
      { name: 'Hate', source: 'Completion', enabled: true, blocking: true, severityThreshold: 'Medium' }
      { name: 'Sexual', source: 'Prompt', enabled: true, blocking: true, severityThreshold: 'Medium' }
      { name: 'Sexual', source: 'Completion', enabled: true, blocking: true, severityThreshold: 'Medium' }
      { name: 'Selfharm', source: 'Prompt', enabled: true, blocking: true, severityThreshold: 'Medium' }
      { name: 'Selfharm', source: 'Completion', enabled: true, blocking: true, severityThreshold: 'Medium' }
      { name: 'Violence', source: 'Prompt', enabled: true, blocking: true, severityThreshold: 'Medium' }
      { name: 'Violence', source: 'Completion', enabled: true, blocking: true, severityThreshold: 'Medium' }
      { name: 'Jailbreak', source: 'Prompt', enabled: true, blocking: true }
      { name: 'Indirect Attack', source: 'Prompt', enabled: true, blocking: true }
      { name: 'Protected Material Text', source: 'Completion', enabled: true, blocking: true }
      { name: 'Protected Material Code', source: 'Completion', enabled: true, blocking: true }
    ]
    customBlocklists: [
      { blocklistName: blocklistName, source: 'Prompt', blocking: true }
      { blocklistName: blocklistName, source: 'Completion', blocking: true }
    ]
  }
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: 'gpt-5-mini'
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5-mini'
      version: '2025-08-07'
    }
    raiPolicyName: guardrail.name // カスタム ガードレールを割り当てる
  }
}

output guardrailName string = guardrail.name
output blocklistDescription string = blocklistDescription
