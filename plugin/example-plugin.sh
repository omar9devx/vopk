#!/usr/bin/env bash
# Example Plugin Updater

set -euo pipefail

VOPK_PLUGINS_DIR="${VOPK_CONFIG_DIR:-$HOME/.config/vopk}/plugins"
EXAMPLE_PLUGIN_FILE="example-plugin.sh"
BACKUP_DIR="${VOPK_PLUGINS_DIR}/backups"

echo "🔄 Updating vopk Example Plugin..."
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup current plugin
if [[ -f "${VOPK_PLUGINS_DIR}/${EXAMPLE_PLUGIN_FILE}" ]]; then
    backup_file="${BACKUP_DIR}/example-plugin-$(date +%Y%m%d-%H%M%S).sh"
    cp "${VOPK_PLUGINS_DIR}/${EXAMPLE_PLUGIN_FILE}" "$backup_file"
    echo "📋 Backup created: $backup_file"
fi

# Run plugin's self-update
if [[ -f "${VOPK_PLUGINS_DIR}/${EXAMPLE_PLUGIN_FILE}" ]]; then
    # Source the plugin to get update function
    if source "${VOPK_PLUGINS_DIR}/${EXAMPLE_PLUGIN_FILE}" 2>/dev/null; then
        if command -v update_example_plugin >/dev/null 2>&1; then
            update_example_plugin
        else
            echo "❌ Plugin doesn't have update function"
            echo "   Try reinstalling: curl -sSL https://raw.githubusercontent.com/omar9devx/vopk/main/plugins/example-plugin.sh | bash"
        fi
    else
        echo "❌ Failed to load plugin"
    fi
else
    echo "❌ Plugin not found. Installing..."
    curl -sSL https://raw.githubusercontent.com/omar9devx/vopk/main/plugins/example-plugin.sh | bash
fi