#!/usr/bin/env bash
set -euo pipefail

HEXEL_REPO="${HEXEL_REPO:-Zokker1/hexel-releases}"
HEXEL_VERSION="${HEXEL_VERSION:-latest}"
INSTALL_DIR="${HEXEL_INSTALL_DIR:-$HOME/.local/bin}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)
      shift
      INSTALL_DIR="${1:-}"
      [ -n "$INSTALL_DIR" ] || { echo "Error: --dir requires a path." >&2; exit 2; }
      ;;
    --version)
      shift
      HEXEL_VERSION="${1:-}"
      [ -n "$HEXEL_VERSION" ] || { echo "Error: --version requires a tag (e.g. v0.1.0)." >&2; exit 2; }
      ;;
    -h|--help)
      cat <<'EOF'
Hexel Terminal Agent installer

Usage:
  curl -fsSL https://raw.githubusercontent.com/Zokker1/hexel-releases/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/Zokker1/hexel-releases/main/install.sh | bash -s -- [--dir PATH] [--version TAG]
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

OS_RAW="$(uname -s)"
ARCH_RAW="$(uname -m)"

case "$OS_RAW" in
  Darwin)
    # Detect Apple Silicon even if Terminal runs under Rosetta 2
    if [ "$ARCH_RAW" = "x86_64" ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
      ARCH_RAW="arm64"
    fi
    case "$ARCH_RAW" in
      arm64|aarch64) ASSET="hexel-darwin-arm64.tar.gz" ;;
      x86_64)        ASSET="hexel-darwin-x64.tar.gz" ;;
      *) echo "Unsupported macOS architecture: $ARCH_RAW" >&2; exit 1 ;;
    esac
    ;;
  Linux)
    case "$ARCH_RAW" in
      x86_64|amd64) ASSET="hexel-linux-x64.tar.gz" ;;
      *) echo "Unsupported Linux architecture: $ARCH_RAW" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "Unsupported OS: $OS_RAW. On Windows PowerShell use install.ps1." >&2
    exit 1
    ;;
esac

if [ "$HEXEL_VERSION" = "latest" ]; then
  BASE_URL="https://github.com/$HEXEL_REPO/releases/latest/download"
else
  BASE_URL="https://github.com/$HEXEL_REPO/releases/download/$HEXEL_VERSION"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading $ASSET from $HEXEL_REPO ($HEXEL_VERSION)..."
curl -fL --progress-bar "$BASE_URL/$ASSET" -o "$TMP_DIR/$ASSET"

if curl -fsSL "$BASE_URL/SHA256SUMS.txt" -o "$TMP_DIR/SHA256SUMS.txt"; then
  EXPECTED_HASH="$(awk -v file="$ASSET" '$2 == file || $2 == ("*" file) { print $1; exit }' "$TMP_DIR/SHA256SUMS.txt")"
  if [ -n "$EXPECTED_HASH" ]; then
    if command -v shasum >/dev/null 2>&1; then
      ACTUAL_HASH="$(shasum -a 256 "$TMP_DIR/$ASSET" | awk '{print $1}')"
    elif command -v sha256sum >/dev/null 2>&1; then
      ACTUAL_HASH="$(sha256sum "$TMP_DIR/$ASSET" | awk '{print $1}')"
    else
      ACTUAL_HASH=""
    fi
    if [ -n "$ACTUAL_HASH" ] && [ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]; then
      echo "Checksum mismatch for $ASSET! expected=$EXPECTED_HASH actual=$ACTUAL_HASH" >&2
      exit 1
    fi
  fi
fi

mkdir -p "$INSTALL_DIR"
tar -xzf "$TMP_DIR/$ASSET" -C "$TMP_DIR"
[ -f "$TMP_DIR/hexel" ] || { echo "Error: binary 'hexel' missing in archive." >&2; exit 1; }

TARGET_BIN="$INSTALL_DIR/hexel"
cp "$TMP_DIR/hexel" "$TARGET_BIN"
chmod 755 "$TARGET_BIN"

if [ "$OS_RAW" = "Darwin" ] && command -v xattr >/dev/null 2>&1; then
  xattr -d com.apple.quarantine "$TARGET_BIN" >/dev/null 2>&1 || true
fi

if [ "$INSTALL_DIR" = "$HOME/.local/bin" ]; then
  PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
  for profile in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [ -f "$profile" ] || { [ "$OS_RAW" = "Darwin" ] && [ "$profile" = "$HOME/.zshrc" ]; }; then
      touch "$profile"
      if ! grep -Fq '.local/bin' "$profile"; then
        printf '\n%s\n' "$PATH_LINE" >> "$profile"
        echo "Added ~/.local/bin to PATH in $profile"
      fi
    fi
  done
fi

echo ""
echo "Installed: $TARGET_BIN"
"$TARGET_BIN" --version || true
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo "Open a new Terminal window (or run: source ~/.zshrc) and type 'hexel' in any project folder."
else
  echo "Done. Type 'hexel' in any project folder to start."
fi
