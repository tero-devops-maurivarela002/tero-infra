#!/usr/bin/env bash
# Instala Terraform ${TF_VERSION} en el runner del CI verificando el checksum
# oficial de HashiCorp (misma idea que Trivy en tero-app: versión fija + SHA256).
set -euo pipefail
: "${TF_VERSION:?Falta TF_VERSION}"

base="https://releases.hashicorp.com/terraform/${TF_VERSION}"
file="terraform_${TF_VERSION}_linux_amd64.zip"
dir="$(mktemp -d)"
cd "$dir"
curl --proto '=https' --tlsv1.2 -sSfL -o "$file" "$base/$file"
curl --proto '=https' --tlsv1.2 -sSfL -o SHA256SUMS "$base/terraform_${TF_VERSION}_SHA256SUMS"
grep " ${file}\$" SHA256SUMS | sha256sum -c -
unzip -q "$file" terraform
mkdir -p "$HOME/.local/bin"
mv terraform "$HOME/.local/bin/terraform"
echo "$HOME/.local/bin" >> "${GITHUB_PATH:-/dev/null}"
"$HOME/.local/bin/terraform" version
