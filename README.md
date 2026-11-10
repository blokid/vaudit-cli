# vaudit-cli

One command to sign in to the Vaudit internal tool APIs (today: the Plane API
at `plane.internal.vaudit.com`). Only a vaudit.com Google account can sign in.

## Install (once)

Mac or Linux, in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/blokid/vaudit-cli/main/install.sh | sh
```

Windows, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/blokid/vaudit-cli/main/install.ps1 | iex
```

The install signs you in at the end: open the link it shows, sign in with
Google, and approve the code.

## Use

| Command | What it does |
|---|---|
| `vaudit login` | Sign in with Google. Once a day; a sign-in lasts 8 hours. |
| `vaudit token` | Print a token for a script, with no browser. |
| `vaudit logout` (or `vaudit signout`) | Forget the sign-in on this computer. |

```sh
curl -H "Authorization: Bearer $(vaudit token)" \
     -H "X-API-Key: $PLANE_API_KEY" \
     https://plane.internal.vaudit.com/api/v1/users/me/
```

`PLANE_API_KEY` is your own Plane access token (Plane, Profile settings,
Personal access tokens). Approve only a sign-in code that you started yourself.

## What the install does

1. Downloads [kubelogin](https://github.com/int128/kubelogin) at a fixed
   version, and stops unless the file matches the SHA-256 in the script.
2. Puts `kubelogin` and `vaudit` in `~/.vaudit/bin` (Windows:
   `%LOCALAPPDATA%\vaudit\bin`) and adds that folder to your PATH. It needs no
   administrator rights.
3. Runs `vaudit login`.

Tokens stay in the Mac Keychain, the Windows Credential Manager, or the Linux
password store. A Linux server with no password store keeps them in a file
that only you can read.

## For maintainers

- Every change to `main` needs a pull request and a code owner's approval.
  Each employee runs these scripts, so a change here reaches every laptop.
- The scripts hold no secret. The Keycloak address and the client id
  `internal-cli` are public.
- New kubelogin version: change `KUBELOGIN_VERSION` and the 4 sums in
  `install.sh`, and `$KubeloginVersion` and the sum in `install.ps1`. Copy each
  sum from the `.sha256` file of that GitHub release. Use a release that is at
  least 2 weeks old. `check-sums.sh` and CI compare them with the release.
- CI installs on Linux (x86 and ARM), Mac, and Windows on every change, and
  checks the pinned sums every Monday.
