#!/bin/bash
# Setup Python virtualenv for barrel_embed
#
# This script creates a project-local virtualenv in .venv/ and installs
# the required dependencies for embedding providers.
#
# Usage:
#   ./scripts/setup_python_venv.sh [OPTIONS]
#
# Options:
#   --minimal    Install only sentence-transformers (default)
#   --all        Install all providers (torch, transformers, pillow, fastembed)
#   --provider X Install specific provider (sentence-transformers, fastembed, splade, colbert, clip)
#
# The venv is automatically detected by the embedding providers.

set -e

VENV_DIR=".venv"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_MODE="minimal"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            INSTALL_MODE="all"
            shift
            ;;
        --minimal)
            INSTALL_MODE="minimal"
            shift
            ;;
        --provider)
            INSTALL_MODE="provider"
            PROVIDER="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

cd "$PROJECT_DIR"

# Create venv if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtualenv in $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

# Activate and install dependencies
source "$VENV_DIR/bin/activate"

echo "Installing dependencies..."
pip install --upgrade pip

# Install based on mode
case $INSTALL_MODE in
    minimal)
        echo "Installing minimal dependencies (sentence-transformers)..."
        pip install -e "$PROJECT_DIR/priv[sentence-transformers]"
        ;;
    all)
        echo "Installing all dependencies..."
        pip install -e "$PROJECT_DIR/priv[all]"
        ;;
    provider)
        echo "Installing provider: $PROVIDER..."
        pip install -e "$PROJECT_DIR/priv[$PROVIDER]"
        ;;
esac

# Optional: uvloop for better async performance
pip install uvloop 2>/dev/null || echo "Note: uvloop not available (optional, improves async performance)"

echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="
echo ""
echo "Virtualenv location: $PROJECT_DIR/$VENV_DIR"
echo "Python executable:   $PROJECT_DIR/$VENV_DIR/bin/python"
echo ""
echo "To activate manually:"
echo "  source $VENV_DIR/bin/activate"
echo ""
echo "To test embedding:"
echo "  rebar3 shell"
echo "  {ok, S} = barrel_embed:init(#{embedder => {local, #{}}})."
echo "  barrel_embed:embed(<<\"hello world\">>, S)."
echo ""
