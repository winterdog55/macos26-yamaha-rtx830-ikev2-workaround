# Changelog

## [1.0.0] - 2026-07-28
### Added
- 初版公開: `macos26-ikev2-dh14-template.mobileconfig`
- macOS 26 Tahoe + YAMAHA RTX830 (Rev.15.02.33) で接続成功を確認（PSK をプロファイルに記入した状態で、手動入力なしで接続できることも確認）
- パケット解析とルーター側デバッグログによる原因の記録（docs/packet-flow.md）
- Android クライアントとの対照実験の記録
- トラブルシューティングと診断チャート（docs/troubleshooting.md）
- セキュリティ上の注意（docs/security-notes.md）
- 対話形式でプロファイルを生成する `make-profile.sh`（XML 編集不要、XML 特殊文字を自動エスケープ）
