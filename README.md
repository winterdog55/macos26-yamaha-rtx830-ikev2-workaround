# macOS 26 IKEv2 DH14 Workaround

macOS 26 Tahoe の標準 IKEv2 クライアントが VPN ルーターに接続できなくなる問題への、構成プロファイルによる回避策です。

**動作確認済み：macOS 26 Tahoe × YAMAHA RTX830 (Rev.15.02.33)**

*English summary is at the bottom.*

## こんな症状の人向け

- macOS 26 にしてから IKEv2 VPN が接続できなくなった
- 接続開始から数秒で切断される
- コンソール.app に `Received no remote SPI on SA_INIT` や `Failed to parse IKE SA Init retry reply` が出る
- Android や L2TP/IPsec では同じルーターに接続できる（YAMAHA によれば本事象の対象は iOS 18 以降 / iPadOS 18 以降 / macOS 15 以降）

## 5分で試す

### 方法A：スクリプトで作る（おすすめ・XML を触りません）

リポジトリ全体をダウンロード（右上の Code > Download ZIP）して展開し、ターミナルで:

```bash
cd 展開したフォルダ
bash make-profile.sh
```

4つの質問に答えると、デスクトップに `ikev2-vpn.mobileconfig` ができます。PSK は入力しても画面に表示されず、`&` や `<` などの記号も自動で処理されます。

### 方法B：手で編集する

1. [`profiles/macos26-ikev2-dh14-template.mobileconfig`](./profiles/macos26-ikev2-dh14-template.mobileconfig) をダウンロード
2. テキストエディタで開いて、**`@@` で囲まれた4箇所**を書き換える（エディタで `@` を検索すると全部見つかります）

   | 書き換える場所 | 書く内容 |
   |---|---|
   | `@@ルーターのアドレス@@` | ルーターのグローバル IP か DDNS ホスト名 |
   | `@@ルーター側の名乗り@@` | `ipsec ike local name` があればその値、なければ上と同じ |
   | `@@自分の名乗り@@` | RTX なら `ipsec ike2 remote name` のユーザー名 |
   | `@@事前共有鍵@@` | 事前共有鍵（PSK） |

   > **`@@` で囲まれた部分だけを書き換えてください。**`<key>SharedSecret</key>` のように `<key>` で始まる行は項目の名前です。ここを書き換えると **XML としては壊れないままインストールでき、しかも設定が反映されない**という分かりにくい失敗になります（検証環境で実際に踏みました）。
   >
   > macOS のテキストエディットを使う場合は、開いた直後に「フォーマット > 標準テキストにする」（Cmd+Shift+T）を実行してください。リッチテキストのまま保存するとファイルが壊れます。
   >
   > PSK に `&` `<` `>` `"` `'` が含まれる場合、XML ではそのまま書けません（`&` は `&amp;` など）。面倒なら方法A を使ってください。

3. 書き換えたら、インストール前に検証:

   ```bash
   plutil -lint あなたのファイル.mobileconfig

   # PSK が正しい場所に入っているか（鍵そのものは表示されません）
   plutil -extract PayloadContent.0.IKEv2.SharedSecret raw あなたのファイル.mobileconfig > /dev/null \
     && echo "OK: SharedSecret は正しく設定されています" \
     || echo "NG: SharedSecret が見つかりません（key の行を書き換えていませんか？）"
   ```

### インストール（方法A・B 共通）

1. 既存の VPN 設定（システム設定の GUI で作ったもの）を削除
2. できたファイルをダブルクリック → システム設定 > 一般 > デバイス管理 → インストール
3. VPN 一覧に増えた接続をオンにする

> 正しく編集できていれば、PSK もプロファイルから反映されてそのまま接続できます（検証環境で確認済み）。
>
> **認証で失敗する場合**は、`<key>SharedSecret</key>` の行を誤って書き換えていないか確認してください（上の検証コマンドで判定できます）。修正したら、**システム設定 > 一般 > デバイス管理から古いプロファイルを削除してから**入れ直してください。上書きインストールでは反映されないことがあります。
>
> それでも通らない場合は、システム設定 > ネットワーク > VPN で該当の接続を開き、共有シークレットを**手動で入力**しても接続できます（暗号パラメータの固定はプロファイル側で効いているため）。

うまくいかない場合は [docs/troubleshooting.md](./docs/troubleshooting.md) を参照してください。

## なぜこれで直るのか（要約）

macOS 26 は IKE_SA_INIT の初手で DH グループ19（ECP256）の鍵を送ります。RTX830 は未対応のため `INVALID_KE_PAYLOAD` を返し、macOS は指定された DH グループ14 で再送します。このとき **macOS は初回と同じ Initiator SPI を使います**。

RTX830 (Rev.15.02.33) はこの再送に対し、SA・KE・Nonce を含む成功応答を生成して内部的には `established` と判定しますが、**送信する応答の Responder SPI がゼロのまま**です。macOS 26 はこれを不正として破棄するため、接続に失敗します。

同じルーターに Android から接続した場合も同じ再送経路を通りますが、**Android は再送時に Initiator SPI を変更しているように見受けられ**、ルーター側で新しい SA 枠が確保されるため、正常な Responder SPI が発行されて接続できます。

このプロファイルは提案を **AES-256-CBC / SHA2-256 / DH グループ14** に固定し、**再送自体を発生させない**ことで問題を回避します。DH14 そのものは問題ではなく、最初から DH14 で交渉すればルーターは正常な SPI を発行します。

RFC 7296 3.1 節および RFC 4718 の記述からは、macOS 側の挙動（同一 Initiator SPI での再送、および Responder SPI がゼロの成功応答を受け付けないこと）はいずれも仕様に沿ったものと考えられます。

パケットレベルの詳細 → [docs/packet-flow.md](./docs/packet-flow.md)
調査の経緯を含む解説記事 → 調査の経緯を含む解説記事 → [「Apple側の問題です」と言われたVPN不具合、自分で調べたらルーター側やった話](https://ton-technotes.com/blog/2026-07-29-rtx830-macos26-ikev2-responder-spi-fix/)
## 前提条件

- ルーターが IKEv2 で AES-256-CBC / SHA-256 / DH グループ14 に対応していること
- 事前共有鍵認証のリモートアクセス VPN であること（証明書認証は対象外）
- ルーター側も同じアルゴリズムの組み合わせに揃えておくこと

> **公式サポートについて：** RTX830 の仕様表では、IKEv2/IPsec リモートアクセス（PSK）の対応クライアントは Android / iOS / iPadOS のみと記載されています。macOS は公式の対応クライアントに含まれていないため、本プロファイルで接続できたとしてもメーカー保証のある構成ではありません。業務利用の際はその前提でご判断ください。

## 注意

記入後のファイルには **PSK が平文で含まれます**。共有・保管は慎重に。詳しくは [docs/security-notes.md](./docs/security-notes.md) を参照してください。

**より安全な運用：** PSK を空欄のまま（方法A なら PSK の質問で何も入力せず Enter）インストールし、PSK は後からシステム設定の VPN 画面で手動入力する方法もあります。この場合ファイルに秘密情報が残らないため、複数人に配布する場合はこちらを推奨します。

1台に1つだけインストールする場合は、テンプレートの `PayloadUUID` と `PayloadIdentifier` はそのままで動きます。**同じ Mac に複数のプロファイルを入れる場合**のみ、2箇所ある `PayloadUUID` と `PayloadIdentifier` をそれぞれ固有の値に変更してください。UUID はターミナルで生成できます。

```bash
uuidgen
```

本プロファイルは無保証です。自己責任でご利用ください。

## 動作確認済み環境

| クライアント | ルーター | ファーム | 結果 |
|---|---|---|---|
| macOS 26 Tahoe | YAMAHA RTX830 | Rev.15.02.33 | ✅ 接続成功 |

他の機種での成否report を [Issue](../../issues/new/choose) で歓迎します。成功・失敗どちらも情報として価値があります。

---

## English summary

macOS 26 (Tahoe)'s built-in IKEv2 client starts IKE_SA_INIT with a DH group 19 (ECP256) key exchange. When the gateway doesn't support it, an `INVALID_KE_PAYLOAD` renegotiation follows — and on YAMAHA RTX830 (Rev.15.02.33) the **success response on that retry path carries a zero Responder SPI**, which macOS 26 rejects with `Received no remote SPI on SA_INIT`.

This configuration profile pins the client proposal to **AES-256-CBC / SHA2-256 / DH group 14 (modp2048)** so the renegotiation never happens. Note that DH group 14 itself is fine — the router issues a valid SPI when it is offered from the first request.

**Usage:** download [the template](./profiles/macos26-ikev2-dh14-template.mobileconfig), either run `bash make-profile.sh` (interactive, no XML editing) or replace the four `@@...@@` placeholders manually, remove any GUI-created VPN configuration, then double-click and install via System Settings > General > Device Management.

**Requirements:** the gateway must support AES-256-CBC / SHA-256 / DH group 14 with pre-shared key authentication.

**Note on vendor support:** YAMAHA's RTX830 specification lists Android / iOS / iPadOS as the supported clients for IKEv2/IPsec remote access — macOS is not among them. This workaround may connect successfully, but the resulting configuration is not vendor-supported.

**Warning:** the edited file contains your PSK in plain text. See [docs/security-notes.md](./docs/security-notes.md).

Reports from other routers are welcome via Issues — both successes and failures are useful.

## License

MIT
