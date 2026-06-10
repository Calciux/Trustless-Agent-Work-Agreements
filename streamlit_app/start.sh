#!/bin/bash
set -a  # auto-export all sourced variables
source /home/nytch/.hermes/.env 2>/dev/null || true
set +a
cd /home/nytch/Trustless-Agent-Work-Agreements/streamlit_app
export SKIP_CAW=false
exec streamlit run app.py --server.headless true --server.enableCORS false --browser.gatherUsageStats false
