// AI 編 A8：API Management の AI ゲートウェイ
// Foundry のモデル（キー認証は無効）の前に API Management（Developer）を置き、
// マネージド ID でモデルと Content Safety を呼ぶ。API にはトークンの上限、安全性チェック、
// トークンのメトリック、プロンプトと応答のログを設定する。

@description('リージョン')
param location string = resourceGroup().location

@description('API Management の名前（グローバルで一意）')
param apimName string = 'apim-${uniqueString(resourceGroup().id)}'

@description('API Management の管理者のメール アドレス（システム通知の送信先）')
param publisherEmail string

@description('API Management の組織名')
param publisherName string = 'contoso'

@description('API Management の価格レベル。Developer は SLA なしの評価用')
@allowed([
  'Developer'
  'BasicV2'
  'StandardV2'
])
param apimSku string = 'Developer'

@description('モデルのデプロイ名')
param deploymentName string = 'gpt-5-mini'

@description('サブスクリプション キーごとの 1 分あたりのトークン数の上限')
param tokensPerMinute int = 300

@description('Content Safety の価格レベル。F0 はサブスクリプションに 1 つだけ')
@allowed([
  'F0'
  'S0'
])
param contentSafetySku string = 'F0'

var suffix = uniqueString(resourceGroup().id)
var openAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // allow-guid
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908' // allow-guid

// Foundry（キー認証を無効にする）とモデル
resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: 'aif-${suffix}'
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: 'aif-${suffix}'
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource model 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: deploymentName
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
  }
}

// Content Safety（APIM のマネージド ID で呼ぶ）
resource contentSafety 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: 'cs-${suffix}'
  location: location
  kind: 'ContentSafety'
  sku: {
    name: contentSafetySku
  }
  properties: {
    customSubDomainName: 'cs-${suffix}'
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

// 監視
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${suffix}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${suffix}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
  }
}

// API Management（システム割り当てマネージド ID）
resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  sku: {
    name: apimSku
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// APIM の ID に最小限のロール：モデルは Cognitive Services OpenAI ユーザー、Content Safety は Cognitive Services ユーザー
resource openAiUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, apim.id, openAiUserRoleId)
  scope: foundry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
    principalId: apim.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource csUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(contentSafety.id, apim.id, cognitiveServicesUserRoleId)
  scope: contentSafety
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: apim.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// バックエンド：マネージド ID で認証する
resource foundryBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apim
  name: 'foundry-backend'
  properties: {
    protocol: 'http'
    url: '${foundry.properties.endpoint}openai'
    credentials: {
      #disable-next-line BCP037 // managedIdentity は Bicep の型定義にまだない
      managedIdentity: {
        resource: 'https://cognitiveservices.azure.com'
      }
    }
  }
}

resource csBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apim
  name: 'content-safety-backend'
  properties: {
    protocol: 'http'
    url: 'https://cs-${suffix}.cognitiveservices.azure.com'
    credentials: {
      #disable-next-line BCP037 // managedIdentity は Bicep の型定義にまだない
      managedIdentity: {
        resource: 'https://cognitiveservices.azure.com'
      }
    }
  }
}

// ロガー：トークンのメトリックは Application Insights、ゲートウェイと LLM のログは Azure Monitor
resource aiLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: 'appinsights'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: appInsights.id
    credentials: {
      connectionString: appInsights.properties.ConnectionString
    }
  }
}

resource monitorLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: 'azuremonitor'
  properties: {
    loggerType: 'azureMonitor'
    isBuffered: true
  }
}

resource aiDiag 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    loggerId: aiLogger.id
    alwaysLog: 'allErrors'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    metrics: true
  }
}

resource monitorDiag 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apim
  name: 'azuremonitor'
  properties: {
    loggerId: monitorLogger.id
    alwaysLog: 'allErrors'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    logClientIp: true
  }
}

// API：Azure OpenAI 互換のチャット補完だけを公開する。キーのヘッダー名は api-key
resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'aoai'
  properties: {
    displayName: 'Azure OpenAI (gateway)'
    path: 'aoai/openai'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'subscription-key'
    }
  }
}

resource chatOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: api
  name: 'chat-completions'
  properties: {
    displayName: 'Chat completions'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/chat/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        type: 'string'
        required: true
      }
    ]
  }
}

var policyXml = '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="foundry-backend" />
    <!-- トークンの上限を安全性チェックより前に置く（429 で返す要求では Content Safety を呼ばない） -->
    <llm-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="__TPM__" estimate-prompt-tokens="false" remaining-tokens-header-name="remaining-tokens" tokens-consumed-header-name="consumed-tokens" />
    <llm-emit-token-metric>
      <dimension name="Subscription ID" />
    </llm-emit-token-metric>
    <llm-content-safety backend-id="content-safety-backend" shield-prompt="true">
      <categories output-type="FourSeverityLevels">
        <category name="Hate" threshold="4" />
        <category name="SelfHarm" threshold="4" />
        <category name="Sexual" threshold="4" />
        <category name="Violence" threshold="4" />
      </categories>
    </llm-content-safety>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: replace(policyXml, '__TPM__', string(tokensPerMinute))
  }
  dependsOn: [
    foundryBackend
    csBackend
    aiLogger
  ]
}

// プロンプトと応答のログ（ApiManagementGatewayLlmLog）
resource apiMonitorDiag 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = {
  parent: api
  name: 'azuremonitor'
  properties: {
    loggerId: monitorLogger.id
    alwaysLog: 'allErrors'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    logClientIp: true
    largeLanguageModel: {
      logs: 'enabled'
      requests: {
        messages: 'all'
        maxSizeInBytes: 32768
      }
      responses: {
        messages: 'all'
        maxSizeInBytes: 32768
      }
    }
  }
  dependsOn: [
    monitorDiag
  ]
}

// アプリ用のサブスクリプション（この API だけが対象）
resource teamA 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: 'team-a'
  properties: {
    displayName: 'team-a'
    scope: api.id
    state: 'active'
  }
}

// 診断設定：ゲートウェイのログと LLM のログを Log Analytics（リソース固有のテーブル）へ
resource apimDiagSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-llm'
  scope: apim
  properties: {
    workspaceId: law.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
      {
        category: 'GatewayLlmLogs'
        enabled: true
      }
    ]
  }
}

output gatewayUrl string = apim.properties.gatewayUrl
output apiBase string = '${apim.properties.gatewayUrl}/aoai'
output apimPrincipalId string = apim.identity.principalId
