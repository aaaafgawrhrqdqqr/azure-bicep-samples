// =============================================================================
// main.bicep
// 入口を閉じた Foundry と、VNet 内の Self-hosted runner（Container Apps ジョブ）を作る。
//
//   VNet
//   ├─ snet-aca（Container Apps 環境。Microsoft.App/environments に委任）
//   │    └─ GitHub Actions の Self-hosted runner ジョブ（使い捨て、自動スケール）
//   └─ snet-pe（Private Endpoint 用）
//        └─ Foundry の Private Endpoint（公開アクセスは無効）
// =============================================================================

@description('リソースを作るリージョン')
param location string = resourceGroup().location

@description('リソース名に付ける接頭辞')
param prefix string = 'fdy'

@description('base.bicep で作った ACR の名前')
param acrName string

@description('Runner のコンテナー イメージ（例: acrxxxx.azurecr.io/gh-runner:abcdef123456）')
param runnerImage string

@description('GitHub のリポジトリ所有者（ユーザー名または Organization 名）')
param githubOwner string

@description('GitHub のリポジトリ名')
param githubRepo string

@description('Runner の登録と KEDA のスケール判定に使う GitHub のトークン（fine-grained PAT）')
@secure()
param githubPat string

@description('Runner に付けるラベル。ワークフローの runs-on と合わせる')
param runnerLabel string = 'foundry-private'

@description('モデルのデプロイ名とモデル名')
param modelName string = 'gpt-5-mini'

@description('モデルのバージョン')
param modelVersion string = '2025-08-07'

@description('モデルのデプロイの種類。GlobalStandard は使った分だけの従量課金')
param modelSkuName string = 'GlobalStandard'

@description('モデルの容量（GlobalStandard では 1 = 1,000 トークン／分）')
param modelCapacity int = 10

@description('Foundry ポータルを自分の PC から見るために一時的に許可するグローバル IP（例: ["203.0.113.10"]）。空なら公開アクセスを完全に無効にする')
param allowedIpAddresses array = []

@description('VNet のアドレス空間')
param vnetAddressPrefix string = '10.20.0.0/16'

@description('Container Apps 環境のサブネット（ワークロード プロファイル環境は /27 以上）')
param acaSubnetPrefix string = '10.20.0.0/27'

@description('Private Endpoint 用のサブネット')
param peSubnetPrefix string = '10.20.1.0/27'

var suffix = uniqueString(resourceGroup().id)
var foundryName = '${prefix}-aif-${suffix}'
var projectName = 'proj-agents'
var projectEndpoint = 'https://${foundryName}.services.ai.azure.com/api/projects/${projectName}'

// 組み込みロールの ID（名前が変わっても ID は変わらない）
var roleIds = {
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull の組み込みロール ID allow-guid
  foundryUser: '53ca6127-db72-4b80-b1b0-d745d6d5456d' // Foundry User（旧名: Azure AI User） allow-guid
}

// Foundry の Private Endpoint に必要な Private DNS ゾーン（3 つ）
var dnsZoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
]

// -----------------------------------------------------------------------------
// ログ（Runner ジョブのトラブルシュート用。少量なのでほぼ無料）
// -----------------------------------------------------------------------------
resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-log-${suffix}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// -----------------------------------------------------------------------------
// ネットワーク
// -----------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${prefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-aca'
        properties: {
          addressPrefix: acaSubnetPrefix
          delegations: [
            {
              name: 'aca'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: peSubnetPrefix
        }
      }
    ]
  }
}

var acaSubnetId = '${vnet.id}/subnets/snet-aca'
var peSubnetId = '${vnet.id}/subnets/snet-pe'

resource dnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [
  for zone in dnsZoneNames: {
    name: zone
    location: 'global'
  }
]

// VNet 内（Runner）から Foundry の名前を引くと、Private Endpoint の IP が返るようにする
resource dnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [
  for (zone, i) in dnsZoneNames: {
    parent: dnsZones[i]
    name: 'link-${vnet.name}'
    location: 'global'
    properties: {
      virtualNetwork: {
        id: vnet.id
      }
      registrationEnabled: false
    }
  }
]

// -----------------------------------------------------------------------------
// Foundry（リソース、プロジェクト、モデルのデプロイ）
// -----------------------------------------------------------------------------
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
    customSubDomainName: foundryName // エンドポイントの名前（<name>.services.ai.azure.com）
    allowProjectManagement: true // Foundry のプロジェクトを作れるようにする
    disableLocalAuth: true // API キーを使わせない（Entra ID 認証のみ）
    // 許可 IP が空なら完全に無効。指定したときだけ、その IP からのアクセスを許可する
    publicNetworkAccess: empty(allowedIpAddresses) ? 'Disabled' : 'Enabled'
    networkAcls: {
      defaultAction: 'Deny'
      ipRules: [
        for ip in allowedIpAddresses: {
          value: ip
        }
      ]
      virtualNetworkRules: []
    }
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundry
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Agents (CI/CD)'
    description: 'GitHub Actions からエージェントをデプロイするプロジェクト'
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: modelName // エージェント定義の model にはこの「デプロイ名」を書く
  sku: {
    name: modelSkuName
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
  dependsOn: [
    project // 同じアカウントへの更新が同時に走って衝突しないよう、順番にする
  ]
}

resource foundryPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${foundry.name}'
  location: location
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'foundry'
        properties: {
          privateLinkServiceId: foundry.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

resource foundryPeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: foundryPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      for (zone, i) in dnsZoneNames: {
        name: replace(zone, '.', '-')
        properties: {
          privateDnsZoneId: dnsZones[i].id
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Runner 用の Managed Identity と権限
//   - ACR からイメージを pull する（AcrPull）
//   - Foundry のプロジェクトでエージェントを作成・実行する（Foundry User）
// GitHub 側に Foundry の資格情報を一切置かない。VNet 内の Runner だけが Foundry を操作できる。
// -----------------------------------------------------------------------------
resource runnerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${prefix}-id-runner'
  location: location
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, runnerIdentity.id, roleIds.acrPull)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.acrPull)
    principalId: runnerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource foundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(project.id, runnerIdentity.id, roleIds.foundryUser)
  scope: project
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.foundryUser)
    principalId: runnerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// -----------------------------------------------------------------------------
// Container Apps 環境（VNet 統合）と Runner ジョブ
// -----------------------------------------------------------------------------
resource acaEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${prefix}-cae'
  location: location
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: acaSubnetId
      internal: true // 外部からの受信口を作らない（Runner は外向き通信しかしない）
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption' // 動いた時間だけ課金
      }
    ]
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logs.properties.customerId
        sharedKey: logs.listKeys().primarySharedKey
      }
    }
  }
}

resource runnerJob 'Microsoft.App/jobs@2024-03-01' = {
  name: '${prefix}-job-gh-runner'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runnerIdentity.id}': {}
    }
  }
  properties: {
    environmentId: acaEnv.id
    workloadProfileName: 'Consumption'
    configuration: {
      triggerType: 'Event' // GitHub にジョブが溜まったときだけ起動する
      replicaTimeout: 1800 // 1 ジョブの最大実行時間（秒）
      replicaRetryLimit: 0
      eventTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
        scale: {
          minExecutions: 0 // 待機中は 0 台 = 0 円
          maxExecutions: 5
          pollingInterval: 30 // 30 秒ごとに GitHub のキューを確認する
          rules: [
            {
              name: 'github-runner'
              type: 'github-runner' // KEDA の GitHub Runner スケーラー
              metadata: {
                githubAPIURL: 'https://api.github.com'
                owner: githubOwner
                runnerScope: 'repo'
                repos: githubRepo
                labels: runnerLabel // このラベルを要求するジョブだけを数える
                targetWorkflowQueueLength: '1'
              }
              auth: [
                {
                  secretRef: 'github-pat'
                  triggerParameter: 'personalAccessToken'
                }
              ]
            }
          ]
        }
      }
      secrets: [
        {
          name: 'github-pat'
          value: githubPat
        }
      ]
      registries: [
        {
          server: acr.properties.loginServer
          identity: runnerIdentity.id // Managed Identity で pull（パスワード不要）
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'runner'
          image: runnerImage
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            {
              name: 'GITHUB_PAT'
              secretRef: 'github-pat'
            }
            {
              name: 'GH_URL'
              value: 'https://github.com/${githubOwner}/${githubRepo}'
            }
            {
              name: 'REGISTRATION_TOKEN_API_URL'
              value: 'https://api.github.com/repos/${githubOwner}/${githubRepo}/actions/runners/registration-token'
            }
            {
              name: 'RUNNER_LABELS'
              value: runnerLabel
            }
            {
              // DefaultAzureCredential が、この Managed Identity を使うようにする
              name: 'AZURE_CLIENT_ID'
              value: runnerIdentity.properties.clientId
            }
            {
              // エージェントのデプロイ先。ワークフローの各ステップからそのまま使える
              name: 'FOUNDRY_PROJECT_ENDPOINT'
              value: projectEndpoint
            }
          ]
        }
      ]
    }
  }
  // Foundry 側の準備（モデル、権限、Private Endpoint と DNS）が全部終わってから Runner を作る。
  // 先に Runner ができると、待っていたエージェントのジョブが準備前に動いて失敗するため。
  dependsOn: [
    acrPull
    foundryUser
    modelDeployment
    foundryPeDns
    dnsLinks
  ]
}

// -----------------------------------------------------------------------------
// 出力
// -----------------------------------------------------------------------------
@description('エージェントのデプロイ先（Runner には環境変数で自動的に渡している）')
output projectEndpoint string = projectEndpoint

output foundryName string = foundry.name
output modelDeploymentName string = modelDeployment.name
output runnerJobName string = runnerJob.name
