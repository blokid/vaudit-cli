#!/bin/sh
# Checks that the kubelogin version and SHA-256 sums written in install.sh and
# install.ps1 match the .sha256 files of that kubelogin release on GitHub.
# CI runs it on every change. A mismatch fails the check.
set -eu

version=$(sed -n 's/^KUBELOGIN_VERSION=//p' install.sh)
ps_version=$(sed -n "s/^\$KubeloginVersion = '\(.*\)'/\1/p" install.ps1)
[ "$version" = "$ps_version" ] || { echo "install.sh has $version, install.ps1 has $ps_version"; exit 1; }

bad=0
check() {
  asset=$1 pinned=$2
  official=$(curl -fsSL "https://github.com/int128/kubelogin/releases/download/$version/kubelogin_$asset.zip.sha256" | awk '{print $1}')
  if [ "$official" = "$pinned" ]; then
    echo "ok        $asset"
  else
    echo "MISMATCH  $asset: pinned $pinned, release $official"
    bad=1
  fi
}

for asset in darwin_amd64 darwin_arm64 linux_amd64 linux_arm64; do
  check "$asset" "$(sed -n "s/^SHA_$asset=//p" install.sh)"
done
check windows_amd64 "$(sed -n "s/^\$Sha256 = '\([0-9a-f]*\)'.*/\1/p" install.ps1)"

exit $bad
