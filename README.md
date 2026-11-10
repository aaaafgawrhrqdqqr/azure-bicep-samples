# azure-bicep-samples

Bicep templates used in the hands-on articles of the blog 「たいやきまんの技術備忘録」 (https://taiyakiman1125.com/).
ブログ「たいやきまんの技術備忘録」の検証記事で使った Bicep テンプレートです。

- 各フォルダーは記事 1 本に対応します。フォルダーの README に、対応する記事、デプロイ手順、作られるリソース、片付けの方法を書きます。
- 検証用のサンプルです。本番に使う前に、設定（SKU、ネットワーク、権限）を必ず見直してください。
- 料金がかかるリソースを含むことがあります。検証が終わったらリソース グループごと削除してください。
- テナント ID、サブスクリプション ID、パスワード、キーなどの秘密情報は含めていません。値はデプロイ時のパラメーターで渡します。

## 改ざんされていないことの確かめ方 / Verifying integrity

このリポジトリでは、次の方法で内容が書き換えられていないことを確かめられるようにしています。

1. **署名付きのコミットとタグ**：すべてのコミットとタグに SSH 署名を付けています。GitHub では「Verified」と表示されます。
2. **書き換えられないタグとリリース**：`v*` のタグは削除・書き換えできない設定（ルールセット）にしています。
3. **SHA-256 ハッシュ**：ブログの記事に、タグ名・コミット SHA・各ファイルの SHA-256 を載せています。

ダウンロードしたファイルのハッシュは、次のコマンドで確かめられます（記事の値と一致すれば、記事を書いた時点と同じ内容です）。

```powershell
Get-FileHash .\<フォルダー>\main.bicep -Algorithm SHA256
```

```bash
sha256sum ./<folder>/main.bicep
```

署名をローカルで確かめる場合は、リポジトリの `allowed_signers` を使います。

```bash
git config gpg.ssh.allowedSignersFile allowed_signers
git verify-commit <コミット SHA>
git verify-tag <タグ名>
```

## License

[MIT](LICENSE)
