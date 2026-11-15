# d13-bicep-deep-dive

ブログ「たいやきまんの技術備忘録」DevOps 編 13（Bicep の深掘り）で使った Bicep です。

## ファイル

| ファイル | 内容 |
|---|---|
| `main.bicep` | リソース グループのスコープ。ユーザー定義型（`environmentType`）、デコレーター、条件付きリソース、出力 |
| `modules/network.bicep` | 仮想ネットワーク。サブネットを配列からループで作る自作モジュール |
| `main.bicepparam` | 既定のパラメーター（サブネット 2 つ、Log Analytics なし） |
| `main.v2.bicepparam` | 変更後のパラメーター（サブネット 3 つ、Log Analytics あり）。what-if とデプロイ スタックの確認用 |
| `bicepconfig.json` | リンターのルール（使われていないパラメーターと existing リソースをエラー、古い API バージョンを警告） |

## 作られるもの

| リソース | 内容 |
|---|---|
| 仮想ネットワーク | `vnet-<prefix>-<environment>`、10.20.0.0/16、サブネットはパラメーター `subnets` |
| ストレージ アカウント | 公開レジストリの Azure Verified Modules（`br/public:avm/res/storage/storage-account:0.33.1`）。共有キー アクセス無効、パブリック ネットワーク アクセス無効。prod では ZRS、dev では LRS |
| Log Analytics ワークスペース | `deployLogs` が true のときだけ作る（PerGB2018、保持 30 日） |

## 確かめる（Azure CLI）

```bash
az bicep lint --file main.bicep
az group create -n rg-blog-d13-bicep -l japaneast
az deployment group what-if -g rg-blog-d13-bicep --parameters main.bicepparam
```

## デプロイ スタックとして配置する

```bash
az stack group create --name stack-d13 -g rg-blog-d13-bicep \
  --parameters main.bicepparam \
  --action-on-unmanage detachAll --deny-settings-mode denyDelete --yes
```

- `denyDelete` にすると、管理対象のリソースはポータルなどから削除できなくなります（拒否の割り当てが作られます）。
- `main.v2.bicepparam` でスタックを更新したあと `main.bicepparam` に戻すと、Log Analytics は `--action-on-unmanage` の値に応じて、切り離される（`detachAll`）か削除されます（`deleteResources`）。
- パイプラインのサービス プリンシパルなどで拒否設定付きのスタックを更新するには、`Microsoft.Resources/deploymentStacks/manageDenySetting/action` を持つロール（Azure Deployment Stack 所有者など）が要ります。

## 片付け

```bash
az stack group delete --name stack-d13 -g rg-blog-d13-bicep --action-on-unmanage deleteResources --yes
az group delete -n rg-blog-d13-bicep --yes
```
