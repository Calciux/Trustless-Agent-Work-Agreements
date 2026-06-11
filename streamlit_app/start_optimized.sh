#!/bin/bash
# Optimized mode launcher: auto-approval within Pact boundaries
set -a
source /home/nytch/.hermes/.env 2>/dev/null || true
set +a

cd /home/nytch/Trustless-Agent-Work-Agreements/streamlit_app

# Must be explicitly exported (set -a only affects sourced vars)
export SKIP_CAW=false
export PACT_OPTIMIZED=true

echo "Starting with: SKIP_CAW=$SKIP_CAW PACT_OPTIMIZED=$PACT_OPTIMIZED"
echo "DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY:0:5}..."

exec streamlit run app.py \
  --server.headless true \
  --server.enableCORS false \
  --browser.gatherUsageStats false
