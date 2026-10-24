#!/usr/bin/env bash
# One-time setup: installs the tools this project needs inside Ubuntu (WSL)
# and reuses your Windows AWS + git settings.
#   bash scripts/setup-wsl.sh
# It asks for your Ubuntu password once (sudo = "run as administrator").
set -euo pipefail

TF_VERSION=1.16.5
KUBECTL_VERSION=v1.36.1

step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }

step "1/6 Base packages"
sudo apt-get update -qq
sudo apt-get install -y -qq unzip curl gnupg ca-certificates jq >/dev/null

step "2/6 AWS CLI v2"
if ! command -v aws >/dev/null; then
  tmp=$(mktemp -d)
  curl -sSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o "$tmp/awscliv2.zip"
  unzip -q "$tmp/awscliv2.zip" -d "$tmp"
  sudo "$tmp/aws/install"
  rm -rf "$tmp"
fi
aws --version

step "3/6 Terraform $TF_VERSION"
if ! command -v terraform >/dev/null; then
  curl -sSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip" -o /tmp/terraform.zip
  sudo unzip -o -q /tmp/terraform.zip terraform -d /usr/local/bin
  rm /tmp/terraform.zip
fi
terraform version | head -1

step "4/6 kubectl $KUBECTL_VERSION"
if ! command -v kubectl >/dev/null; then
  curl -sSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /tmp/kubectl
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm /tmp/kubectl
fi
kubectl version --client | head -1

step "5/6 GitHub CLI"
if ! command -v gh >/dev/null; then
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg status=none
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq gh >/dev/null
fi
gh --version | head -1

step "6/6 Reusing your Windows settings"
WIN_HOME=$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")
if [ ! -d ~/.aws ] && [ -d "$WIN_HOME/.aws" ]; then
  cp -r "$WIN_HOME/.aws" ~/.aws
  chmod 700 ~/.aws && chmod 600 ~/.aws/credentials ~/.aws/config
  echo "Copied AWS login from Windows."
fi
aws sts get-caller-identity --query Arn --output text

if [ -z "$(git config --global user.name || true)" ]; then
  git config --global user.name "$(git.exe config --global user.name | tr -d '\r')"
  git config --global user.email "$(git.exe config --global user.email | tr -d '\r')"
fi
git config --global core.autocrlf input

if ! gh auth status >/dev/null 2>&1; then
  echo "Log in to GitHub (a browser window / code will appear):"
  gh auth login --hostname github.com --git-protocol https --web
fi
gh auth setup-git
gh auth status

printf '\n\033[32mSetup complete. Next: bash scripts/aws-up.sh\033[0m\n'
