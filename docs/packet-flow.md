# パケットレベルで何が起きているか

macOS 26 Tahoe と YAMAHA RTX830 (Rev.15.02.33) の間で観測した内容です。クライアント側のパケットキャプチャと、ルーター側の IKE デバッグログの両方から確認しています。

---

## 1. 失敗する場合（プロファイルなし）

### クライアント側から見た流れ

```text
[1] Mac  → Router : IKE_SA_INIT 提案（KE = DH group 19 / ECP256）
[2] Router → Mac  : INVALID_KE_PAYLOAD「DH group 14 を使え」
                    ※この応答の Responder SPI = 0 は正常
                      （IKE SA を作らない応答のため）
[3] Mac  → Router : IKE_SA_INIT 再送（KE = DH group 14 / modp2048）
                    ※Initiator SPI は [1] と同一
[4] Router → Mac  : SA・KE・Nonce・NAT-D を含む成功応答
                    ★ Responder SPI = 0000000000000000 のまま ★
→ macOS が応答を破棄し、新しい Initiator SPI で再試行。数回繰り返して切断。
```

macOS 側のログ:

```text
PeerInvalidSyntax
Received no remote SPI on SA_INIT
Failed to parse IKE SA Init retry reply
NEIKEv2ErrorDomain Code=6
```

### ルーター側のデバッグログ

`syslog debug on` と `ipsec ike log message-info payload-info` を有効にすると、ルーター側の処理が確認できます。

```text
［初回の IKE_SA_INIT］
  SA:4/IKE temporarily assigned
  GW:*/SA:4/INIT receive message:
    44f4d0e2ec4e43b7 0000000000000000
  GW:*/SA:4/INIT cannot accept KE payload
  GW:*/SA:4/INIT  INVALID_KE_PAYLOAD data:000e
  GW:*/SA:4/INIT send message:
    44f4d0e2ec4e43b7 0000000000000000   ← IKE SA 未生成のため正常

［同じ SA 枠での再送受信］
  GW:*/SA:4/INIT receive message:
    44f4d0e2ec4e43b7 0000000000000000   ← Initiator SPI は初回と同一
  GW:*/SA:4/INIT  MODP_2048
  GW:*/SA:4/INIT generate SA payload
  GW:*/SA:4/INIT generate KE payload
  GW:*/SA:4/INIT generate Nonce payload
  GW:*/SA:4/INIT send message:
    44f4d0e2ec4e43b7 0000000000000000   ← 成功応答だが Responder SPI がゼロ
  SA:4/IKE established                  ← ルーターは成功と判定している
```

SA・KE・Nonce の生成は完了しており、ルーター側は `established` と判定しています。しかし送信された IKE ヘッダの Responder SPI がゼロのままです。初回のエラー応答時に確保された SA 枠（SA:4）が再送でも引き続き使われているように見えますが、内部処理の詳細まではログからは判別できません。

---

## 2. 成功する場合（プロファイルで DH14 に固定）

```text
0.000s  Mac  → Router : IKE_SA_INIT（最初から DH group 14、提案は 1 本のみ）
0.019s  Router → Mac  : 成功応答（Responder SPI は非ゼロ）
0.066s  IKE_AUTH（UDP 4500 へ移行）
0.138s  ESP 疎通開始
```

再送が発生しないため、ルーターは新しい SA 枠を確保し、正常な Responder SPI を発行します。

---

## 3. Android との対照実験

同じルーターに Android から接続した場合も、初回の KE が MODP_4096 のため、**同じく INVALID_KE_PAYLOAD による再送経路を通ります**。しかし結果が異なりました。

```text
  SA:4/IKE temporarily assigned
  GW:*/SA:4/INIT receive message:
    744846154a99f9e0 0000000000000000   ← Initiator SPI（A）
  （MODP_4096 → INVALID_KE_PAYLOAD）

  SA:5/IKE temporarily assigned          ← 新しい SA 枠が確保される
  GW:*/SA:5/INIT receive message:
    27d4414ed8292c79 0000000000000000   ← Initiator SPI が変わっている（B）
  GW:*/SA:5/INIT send message:
    27d4414ed8292c79 2f926ae1ccdc8302   ← Responder SPI が発行されている
  SA:5/IKE established → 認証成功 → IP Tunnel Up
```

Android は再送時に Initiator SPI を変更しているように見受けられ、その結果ルーター側では新しい SA 枠が確保され、非ゼロの Responder SPI が発行されています。

### 対照表

| | macOS 26 | Android |
|---|---|---|
| 初回 KE のグループ | ECP256（19） | MODP_4096（16） |
| ルーターの応答 | INVALID_KE_PAYLOAD（14を要求） | INVALID_KE_PAYLOAD（14を要求） |
| **再送時の Initiator SPI** | **初回と同一** | **変わっている** |
| ルーター側の SA 枠 | 初回の枠を継続使用 | 新規に確保 |
| 成功応答の Responder SPI | **0000000000000000** | 正常値 |
| 結果 | 失敗 | 成功 |

**再送経路自体は両者共通です。** 観測できた差分は Initiator SPI の取り扱いのみでした。

---

## 4. 仕様上の位置づけ

RFC 7296 3.1 節では、Responder の SPI について次のように規定されていると理解しています。

- IKE 初期交換の最初のメッセージ（cookie を含む再送を含む）では **ゼロであること**
- それ以外のメッセージでは **ゼロであってはならない**

また IKEv2 の解釈指針をまとめた RFC 4718（後に RFC 5996 に統合）では、次の点が説明されています。

- INVALID_KE_PAYLOAD や NO_PROPOSAL_CHOSEN のように IKE SA が作られない応答では、Responder SPI にゼロを返すのが適切
- 上記の「再送」には、**INVALID_KE_PAYLOAD を理由とする再送も含む意図**であった

この理解に基づくと、本件に関わる macOS 側の挙動（同一 Initiator SPI で再送すること、および Responder SPI がゼロの成功応答を受け付けないこと）は、いずれも仕様に沿ったものと考えられます。

---

## 5. 要点

- **DH group 14 そのものは問題ではありません。** 最初から DH14 で交渉すればルーターは正常な SPI を発行します
- 事象が起きるのは **INVALID_KE_PAYLOAD による再送を経た応答**に限られます
- Android のように再送時に Initiator SPI が変わる実装では、この経路を通っても接続できます
- したがって回避策は「**再送を発生させない**」＝クライアント側の提案を最初から DH14 に固定すること

なお RTX830 が IKE で対応する DH グループは modp768 / modp1024 / modp1536 / modp2048 のみで、macOS 26 は DH group 14 未満を廃止しています。**両者の共通項は DH group 14 だけ**であるため、提案を固定すれば再送が発生する余地は構造的にありません。

---

## 6. 自分の環境で確認する方法

### クライアント側（macOS）

```bash
# 使用中のインターフェースを確認
route get default | grep interface

# キャプチャ開始（en2 は環境に合わせて）
sudo tcpdump -i en2 -s 0 -w ~/Desktop/vpn_fail.pcap 'udp port 500 or udp port 4500'
# → VPN 接続を1回試して Ctrl+C
```

Wireshark で開き、`isakmp` でフィルタして各パケットの Responder SPI を確認してください。

### ルーター側（RTX）

```
administrator
syslog debug on
ipsec ike log message-info payload-info
clear log
```

この状態で接続を試し、`show log` で確認します。確認後は必ず戻してください。

```
syslog debug off
save
```

※ `key-info` は指定しないでください（鍵に関する情報がログに出力されます）。
※ デバッグログには IP アドレスや識別子が含まれます。共有する際は必ずマスクしてください。
