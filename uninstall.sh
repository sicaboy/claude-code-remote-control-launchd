#!/bin/bash
# Thin wrapper: ./uninstall.sh [--keep-logs]
exec "$(cd "$(dirname "$0")" && pwd)/install.sh" uninstall "$@"
