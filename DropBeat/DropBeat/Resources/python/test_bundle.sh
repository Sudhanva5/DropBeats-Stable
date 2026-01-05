#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/backend/api"
"$SCRIPT_DIR/bin/python3" -m uvicorn main:app --host 127.0.0.1 --port 4002 --log-level info
