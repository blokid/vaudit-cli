#!/bin/sh
# Installs the command `vaudit` for the Vaudit internal tool APIs (Mac, Linux).
#
#   curl -fsSL https://raw.githubusercontent.com/blokid/vaudit-cli/main/install.sh | sh
#
# What it does, and nothing else:
#   1. Downloads kubelogin (github.com/int128/kubelogin) at a FIXED version and
#      stops unless the file matches the SHA-256 below.
#   2. Puts kubelogin and the small `vaudit` command in ~/.vaudit/bin, and adds
#      that folder to PATH in your shell startup file. No sudo.
#   3. Runs `vaudit login` once.
#
# It holds no secret: the Keycloak address and the client id are public.
# To move to a new kubelogin version, change KUBELOGIN_VERSION and the 4 sums,
# copied from the .sha256 files of that GitHub release.
set -eu

KUBELOGIN_VERSION=v1.36.4
SHA_darwin_amd64=7927b10c122b55dd4d9632f75d56752bfdc5f7b6ad3104615115c02f5f55e4f0
SHA_darwin_arm64=5aa470d059a9672d732439474678ac05a0de5623ad3af54966b8fe1ac7df4254
SHA_linux_amd64=9e8baeb4905d35a301304af2548324997add512fe94ab20e65993d167212bf85
SHA_linux_arm64=669c2d3bcc6766351ad5a7b03971792b4e7a55117b335a12d9858d43a525d9dc

VAUDIT_HOME=${VAUDIT_HOME:-"$HOME/.vaudit"}
BIN="$VAUDIT_HOME/bin"

fail() { echo "vaudit install: $*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) fail "this script is for Mac and Linux. On Windows use install.ps1." ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) fail "no kubelogin build for $(uname -m)." ;;
esac
case "${os}_${arch}" in
  darwin_amd64) want=$SHA_darwin_amd64 ;;
  darwin_arm64) want=$SHA_darwin_arm64 ;;
  linux_amd64) want=$SHA_linux_amd64 ;;
  linux_arm64) want=$SHA_linux_arm64 ;;
esac

for tool in curl unzip; do
  command -v "$tool" >/dev/null 2>&1 || fail "please install $tool first."
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading kubelogin $KUBELOGIN_VERSION ($os/$arch)..."
curl -fsSL -o "$tmp/kubelogin.zip" \
  "https://github.com/int128/kubelogin/releases/download/$KUBELOGIN_VERSION/kubelogin_${os}_${arch}.zip"

if command -v sha256sum >/dev/null 2>&1; then
  got=$(sha256sum "$tmp/kubelogin.zip" | awk '{print $1}')
else
  got=$(shasum -a 256 "$tmp/kubelogin.zip" | awk '{print $1}')
fi
[ "$got" = "$want" ] || fail "the download does not match the expected SHA-256. Nothing was installed."

unzip -o -q "$tmp/kubelogin.zip" kubelogin -d "$tmp"
mkdir -p "$BIN"
mv "$tmp/kubelogin" "$BIN/kubelogin"
chmod 755 "$BIN/kubelogin"

cat > "$BIN/vaudit" <<'VAUDIT'
#!/bin/sh
# vaudit: Google sign-in for the Vaudit internal tool APIs (Keycloak client
# internal-cli, realm vaudit). Made by the vaudit install script.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# Own cache folder, so `vaudit logout` never touches other kubelogin sign-ins.
cache="$here/../cache"

# The Mac Keychain, or the Linux password store when a desktop session runs.
# A Linux server has no password store, so the tokens go to a 0600 file.
store=keyring
if [ "$(uname -s)" = Linux ] && [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  store=disk
fi

get_token() {
  "$here/kubelogin" get-token \
    --oidc-issuer-url=https://id.internal.vaudit.com/realms/vaudit \
    --oidc-client-id=internal-cli \
    --grant-type=device-code \
    --oidc-extra-scope=email \
    --oidc-extra-scope=offline_access \
    --oidc-use-access-token \
    --token-cache-storage="$store" \
    --token-cache-dir="$cache"
}

case "${1:-}" in
  login)
    get_token >/dev/null
    echo "Signed in for 8 hours."
    ;;
  token)
    get_token | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
    ;;
  logout | signout)
    "$here/kubelogin" clean --token-cache-dir="$cache" >/dev/null 2>&1
    echo "Signed out."
    ;;
  *)
    echo "usage: vaudit login | token | logout (or signout)" >&2
    echo "  login   sign in with Google (once a day)" >&2
    echo "  token   print a token for a script: curl -H \"Authorization: Bearer \$(vaudit token)\" ..." >&2
    echo "  logout  forget the sign-in on this computer (same as: signout)" >&2
    exit 2
    ;;
esac
VAUDIT
chmod 755 "$BIN/vaudit"

# Add ~/.vaudit/bin to PATH once, in the startup file of the user's shell.
if [ "${VAUDIT_NO_RC:-}" != 1 ]; then
  case "${SHELL:-}" in
    */zsh) rc="$HOME/.zshrc" ;;
    */bash) [ "$os" = darwin ] && rc="$HOME/.bash_profile" || rc="$HOME/.bashrc" ;;
    *) rc="$HOME/.profile" ;;
  esac
  line="export PATH=\"$BIN:\$PATH\"  # vaudit"
  grep -qsF "# vaudit" "$rc" || printf '\n%s\n' "$line" >> "$rc"
fi

echo "Installed: $BIN/vaudit"
if [ "${VAUDIT_NO_LOGIN:-}" != 1 ]; then
  echo "Signing in. Open the link below, sign in with Google, and approve the code."
  "$BIN/vaudit" login
fi
echo "Open a new terminal window, then use: vaudit login, vaudit token"
