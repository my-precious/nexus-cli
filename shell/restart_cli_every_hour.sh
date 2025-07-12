#!/bin/bash

# 每小时自动重启 CLI
# 请确保 ./my_cli 是你的 CLI 可执行文件路径

~/nexus-cli/clients/cli/target/release/nexus-network batch-file --file ~/.nexus/nodes.txt \
  --max-concurrent 80 \
  --restart-interval-minutes 40 \
  --restart-grace-period 20