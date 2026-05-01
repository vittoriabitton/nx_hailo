#!/usr/bin/env bash
# Starts a named Elixir node for Livebook's Attached Node runtime.
#
# Usage: ./scripts/start_node.sh [node_ip]
#
# The node IP defaults to the ethernet interface (eth0).
# Override by passing an IP as the first argument:
#   ./scripts/start_node.sh 192.168.2.4
#
# Environment variable overrides:
#   NODE_NAME     Full node name (e.g. mynode@192.168.2.4). Defaults to <whoami>@<eth0-ip>.
#   COOKIE        Erlang cookie. Defaults to the node base name (part before @).
#   HAILO_TARGET  Target device: hailo10 (default), hailo8, hailo8l, etc.
#   DOWNLOAD_DIR  Directory for downloaded models. Defaults to <project>/priv.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

NODE_IP="${1:-$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')}"
NODE_NAME="${NODE_NAME:-$(whoami)@${NODE_IP}}"
COOKIE="${COOKIE:-${NODE_NAME%%@*}}"
HAILO_TARGET="${HAILO_TARGET:-hailo10}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${PROJECT_DIR}/priv}"

echo "Project:      ${PROJECT_DIR}"
echo "Node:         ${NODE_NAME}"
echo "Cookie:       ${COOKIE}"
echo "Hailo target: ${HAILO_TARGET}"
echo "Download dir: ${DOWNLOAD_DIR}"
echo ""
echo "Connect Livebook via:"
echo "  Runtime → Attached Node"
echo "  Node:   ${NODE_NAME}"
echo "  Cookie: ${COOKIE}"
echo ""

# Ensure epmd is running (required for Erlang distribution)
epmd -daemon

cd "${PROJECT_DIR}"

exec env \
  HAILO_TARGET="${HAILO_TARGET}" \
  DOWNLOAD_DIR="${DOWNLOAD_DIR}" \
  iex --name "${NODE_NAME}" --cookie "${COOKIE}" -S mix
