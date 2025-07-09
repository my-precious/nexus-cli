#!/bin/bash

# 每小时自动重启 CLI
# 请确保 ./my_cli 是你的 CLI 可执行文件路径

if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD=gtimeout
else
  TIMEOUT_CMD=timeout
fi

while true; do
  echo "[$(date)] 启动 CLI（1小时后自动重启）..."
  $TIMEOUT_CMD 2400 ~/nexus-cli/clients/cli/target/release/nexus-network batch-file --file ~/.nexus/nodes.txt --max-concurrent 80
  echo "[$(date)] CLI 已重启..."
done 