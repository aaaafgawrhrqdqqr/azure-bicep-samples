// AI 編 A9：AI の監視とログ
// Foundry のモデル（キー認証は無効）に、診断設定（リソース ログとメトリック → Log Analytics）、
// Application Insights、アクション グループ、メトリック アラート（429 の多発）、
// ログ検索アラート（権限のない呼び出しの 401）を設定する。

@description('リージョン')
param location string = resourceGroup().location

@description('モデルのデプロイ名')
param deploymentName string = 'gpt-5-mini'

@description('モデルの容量（1 で 1 分 1,000 トークン）')
param capacity int = 10

@description('429 のアラートのしきい値（5 分間の件数がこの値を超えたら発生）')
param throttleThreshold int = 5

var suffix = uniqueString(resourceGroup().id)
var ownerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' // allow-guid

// Foundry（キー認証を無効にする）とモデル
resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: 'aif-${suffix}'
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
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
    capacity: capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5-mini'
      version: '2025-08-07'
    }
  }
}

// ログの保存先
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

// トレースの保存先（アプリから OpenTelemetry で送る）
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${suffix}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
  }
}

// 診断設定：すべてのリソース ログとメトリックを Log Analytics（AzureDiagnostics / AzureMetrics）へ
resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-ai'
  scope: foundry
  properties: {
    workspaceId: law.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// 通知先：サブスクリプションの所有者ロールを持つユーザーへのメール
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-ai-owner'
  location: 'global'
  properties: {
    groupShortName: 'agai'
    enabled: true
    armRoleReceivers: [
      {
        name: 'owner'
        roleId: ownerRoleId
        useCommonAlertSchema: true
      }
    ]
  }
}

// メトリック アラート：429（レート制限）が 5 分間でしきい値を超えたら通知
resource throttleAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-ai-429'
  location: 'global'
  properties: {
    description: 'モデルの呼び出しで 429 が多発している'
    severity: 3
    enabled: true
    scopes: [
      foundry.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'throttled'
          criterionType: 'StaticThresholdCriterion'
          metricNamespace: 'Microsoft.CognitiveServices/accounts'
          metricName: 'ModelRequests'
          dimensions: [
            {
              name: 'StatusCode'
              operator: 'Include'
              values: [
                '429'
              ]
            }
          ]
          operator: 'GreaterThan'
          threshold: throttleThreshold
          timeAggregation: 'Total'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ログ検索アラート：Entra ID のトークンはあるが権限のない呼び出し（401）が 1 件でもあれば通知
resource unauthorizedAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'alert-ai-401'
  location: location
  properties: {
    displayName: 'alert-ai-401'
    description: 'Foundry に権限のない呼び出し（401）があった'
    severity: 2
    enabled: true
    scopes: [
      law.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'AzureDiagnostics | where Category == "RequestResponse" and ResultSignature == "401"'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
  dependsOn: [
    diag
  ]
}

output foundryEndpoint string = foundry.properties.endpoint
output workspaceId string = law.properties.customerId
#disable-next-line outputs-should-not-contain-secrets // 接続文字列はトレースの送信先。読み取りの権限は含まない
output appInsightsConnectionString string = appInsights.properties.ConnectionString
