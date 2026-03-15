#!/usr/bin/env bash
# Install all CLI tools needed for Tetris Kubernetes DevSecOps
# Supports: Linux (apt), macOS (brew)

set -e

echo "=== Installing Tetris DevSecOps CLI Tools ==="

# Detect OS
if [[ "$(uname)" == "Linux" ]]; then
  PKG_MGR="apt"
  SUDO="sudo"
elif [[ "$(uname)" == "Darwin" ]]; then
  PKG_MGR="brew"
  SUDO=""
else
  echo "Unsupported OS: $(uname)"
  exit 1
fi

# --- kind: Kubernetes in Docker - local cluster for development ---
install_kind() {
  if command -v kind &>/dev/null; then
    echo "kind already installed: $(kind version)"
    return
  fi
  echo "Installing kind..."
  if [[ "$PKG_MGR" == "brew" ]]; then
    brew install kind
  else
    curl -Lo ./kind "https://kind.sigs.k8s.io/dl/v0.20.0/kind-$(uname)-amd64"
    chmod +x ./kind
    $SUDO mv ./kind /usr/local/bin/kind
  fi
}

# --- kubectl: Kubernetes CLI - interact with clusters ---
install_kubectl() {
  if command -v kubectl &>/dev/null; then
    echo "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    return
  fi
  echo "Installing kubectl..."
  if [[ "$PKG_MGR" == "brew" ]]; then
    brew install kubectl
  else
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    $SUDO mv kubectl /usr/local/bin/
  fi
}

# --- helm: Kubernetes package manager - install charts ---
install_helm() {
  if command -v helm &>/dev/null; then
    echo "helm already installed: $(helm version --short)"
    return
  fi
  echo "Installing helm..."
  if [[ "$PKG_MGR" == "brew" ]]; then
    brew install helm
  else
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
}

# --- argocd CLI: Argo CD client - manage GitOps deployments ---
install_argocd() {
  if command -v argocd &>/dev/null; then
    echo "argocd already installed: $(argocd version --client --short 2>/dev/null || echo 'installed')"
    return
  fi
  echo "Installing argocd CLI..."
  if [[ "$PKG_MGR" == "brew" ]]; then
    brew install argocd
  else
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x argocd-linux-amd64
    $SUDO mv argocd-linux-amd64 /usr/local/bin/argocd
  fi
}

# --- jq: JSON processor - parse API responses and configs ---
install_jq() {
  if command -v jq &>/dev/null; then
    echo "jq already installed: $(jq --version)"
    return
  fi
  echo "Installing jq..."
  if [[ "$PKG_MGR" == "brew" ]]; then
    brew install jq
  else
    $SUDO apt-get update && $SUDO apt-get install -y jq
  fi
}

# --- yq: YAML processor - parse and edit YAML configs ---
install_yq() {
  if command -v yq &>/dev/null; then
    echo "yq already installed: $(yq --version)"
    return
  fi
  echo "Installing yq..."
  if [[ "$PKG_MGR" == "brew" ]]; then
    brew install yq
  else
    YQ_VERSION="v4.35.1"
    curl -sSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -o yq
    chmod +x yq
    $SUDO mv yq /usr/local/bin/
  fi
}

# --- trivy: Container/image vulnerability scanner ---
install_trivy() {
  if command -v trivy &>/dev/null; then
    echo "trivy already installed: $(trivy --version | head -1)"
    return
  fi
  echo "Installing trivy..."
  if [[ "$PKG_MGR" == "brew" ]]; then
    brew install aquasecurity/trivy/trivy
  else
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
  fi
}

# Run all installers
install_kind
install_kubectl
install_helm
install_argocd
install_jq
install_yq
install_trivy

echo ""
echo "=== All tools installed successfully ==="
echo "kind:    $(kind version 2>/dev/null || echo 'N/A')"
echo "kubectl: $(kubectl version --client --short 2>/dev/null || echo 'N/A')"
echo "helm:    $(helm version --short 2>/dev/null || echo 'N/A')"
echo "argocd:  $(argocd version --client --short 2>/dev/null || echo 'N/A')"
echo "jq:      $(jq --version 2>/dev/null || echo 'N/A')"
echo "yq:      $(yq --version 2>/dev/null || echo 'N/A')"
echo "trivy:   $(trivy --version 2>/dev/null | head -1 || echo 'N/A')"
