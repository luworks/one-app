#!/bin/zsh
# usage: serve_model.sh HF_REPO:QUANT   -> starts llama-server on :8089, waits until healthy
pkill -f "llama-server" 2>/dev/null; sleep 1
nohup nice -n 15 llama-server -hf "$1" -c 4096 -ngl 99 -t 4 --jinja --reasoning off --port 8089 --log-disable > "$(dirname "$0")/results/server.log" 2>&1 &
for i in {1..600}; do curl -sf http://127.0.0.1:8089/health >/dev/null && exit 0; sleep 2; done
echo "server did not start"; tail -5 "$(dirname "$0")/results/server.log"; exit 1
