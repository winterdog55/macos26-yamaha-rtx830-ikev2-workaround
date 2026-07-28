#!/bin/bash
#
# make-profile.sh
#   質問に答えるだけで、インストールできる .mobileconfig を作ります。
#   XML を手で編集する必要はありません。
#
#   使い方:  bash make-profile.sh
#
set -eu

TEMPLATE="$(dirname "$0")/profiles/macos26-ikev2-dh14-template.mobileconfig"
OUTPUT="${HOME}/Desktop/ikev2-vpn.mobileconfig"

if [ ! -f "$TEMPLATE" ]; then
  echo "エラー: テンプレートが見つかりません: $TEMPLATE" >&2
  echo "リポジトリのルートから実行してください。" >&2
  exit 1
fi

echo "============================================"
echo " macOS 26 用 IKEv2 プロファイル作成"
echo "============================================"
echo
echo "4つの質問に答えてください。"
echo

printf "【1】ルーターのアドレス（グローバルIPかDDNSホスト名）: "
read -r REMOTE_ADDRESS
if [ -z "$REMOTE_ADDRESS" ]; then echo "エラー: 入力が空です。" >&2; exit 1; fi

printf "【2】ルーター側の名乗り（不明ならそのままEnterで【1】と同じ値を使います）: "
read -r REMOTE_IDENTIFIER
if [ -z "$REMOTE_IDENTIFIER" ]; then
  REMOTE_IDENTIFIER="$REMOTE_ADDRESS"
  echo "     → 「$REMOTE_ADDRESS」を使います"
fi

printf "【3】自分の名乗り（RTX なら ipsec ike2 remote name のユーザー名）: "
read -r LOCAL_IDENTIFIER
if [ -z "$LOCAL_IDENTIFIER" ]; then echo "エラー: 入力が空です。" >&2; exit 1; fi

echo
echo "【4】事前共有鍵（PSK）"
echo "     ※入力しても画面には表示されません"
echo "     ※空のままEnterを押すと、PSKを書かないファイルを作ります"
echo "       （その場合はインストール後に、システム設定のVPN画面で手動入力してください）"
printf "     PSK: "
stty -echo 2>/dev/null || true
read -r SHARED_SECRET
stty echo 2>/dev/null || true
echo
echo

# XML の特殊文字をエスケープ
xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

E_REMOTE_ADDRESS="$(xml_escape "$REMOTE_ADDRESS")"
E_REMOTE_IDENTIFIER="$(xml_escape "$REMOTE_IDENTIFIER")"
E_LOCAL_IDENTIFIER="$(xml_escape "$LOCAL_IDENTIFIER")"
E_SHARED_SECRET="$(xml_escape "$SHARED_SECRET")"

# 置換（環境変数経由で渡すことで、記号を含む値でも安全に処理）
export E_REMOTE_ADDRESS E_REMOTE_IDENTIFIER E_LOCAL_IDENTIFIER E_SHARED_SECRET
perl -pe '
  s/\@\@ルーターのアドレス\@\@/$ENV{E_REMOTE_ADDRESS}/g;
  s/\@\@ルーター側の名乗り\@\@/$ENV{E_REMOTE_IDENTIFIER}/g;
  s/\@\@自分の名乗り\@\@/$ENV{E_LOCAL_IDENTIFIER}/g;
  s/\@\@事前共有鍵\@\@/$ENV{E_SHARED_SECRET}/g;
' "$TEMPLATE" > "$OUTPUT"

chmod 600 "$OUTPUT"

# 検証
if command -v plutil >/dev/null 2>&1; then
  if ! plutil -lint "$OUTPUT" >/dev/null 2>&1; then
    echo "エラー: 生成したファイルの構文が不正です。入力値を確認してください。" >&2
    exit 1
  fi
  if plutil -extract PayloadContent.0.IKEv2.SharedSecret raw "$OUTPUT" >/dev/null 2>&1; then
    SECRET_STATE="プロファイルに含まれています"
  else
    SECRET_STATE="含まれていません（インストール後に手動入力してください）"
  fi
else
  SECRET_STATE="（検証をスキップしました）"
fi

echo "============================================"
echo " 作成しました: $OUTPUT"
echo "============================================"
echo
echo "  接続先      : $REMOTE_ADDRESS"
echo "  ルーター名乗り: $REMOTE_IDENTIFIER"
echo "  自分の名乗り : $LOCAL_IDENTIFIER"
echo "  事前共有鍵  : $SECRET_STATE"
echo
echo "次の手順:"
echo "  1. 既存の VPN 設定（システム設定 > ネットワーク > VPN）を削除"
echo "  2. デスクトップの ikev2-vpn.mobileconfig をダブルクリック"
echo "  3. システム設定 > 一般 > デバイス管理 からインストール"
echo
echo "※このファイルには事前共有鍵が平文で含まれます。"
echo "  インストール後は削除するか、安全な場所に保管してください。"
