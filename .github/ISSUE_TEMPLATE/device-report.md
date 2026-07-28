---
name: 動作報告 / Device report
about: 他のルーター・環境での成否を報告する
title: "[Report] <ルーター名> + macOS <バージョン>"
labels: report
---

## 環境 / Environment

- ルーター / Router:
- ファームウェア / Firmware:
- macOS バージョン / Version:
- 認証方式 / Authentication (PSK / certificate):

## 観測した挙動 / Observed behavior

- macOS が最初に提案した DH グループ / Initial DH group proposed:
- ルーターが要求した DH グループ / DH group requested by router:
- 再送後の応答の Responder SPI / Responder SPI in the retry response (zero or not):

## プロファイル適用後の結果 / Result after applying the profile

- [ ] 接続成功 / Connected
- [ ] 接続失敗 / Still failing

失敗した場合、macOS 側のログ（コンソール.app で `NEIKEv2` を検索）を貼ってください。
If it failed, please paste the macOS log lines.

> pcap ファイルそのものは環境を特定できる情報を含むため、添付せず要約のみでお願いします。
> Please summarize rather than attaching raw pcap files.
