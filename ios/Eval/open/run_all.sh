#!/bin/zsh
# usage: run_all.sh NAME HF_REPO:QUANT   (runs every set/mode that matters for the selection)
cd "$(dirname "$0")"
NAME=$1; REPO=$2
if [[ "$NAME" == "gemma3-4b" || "$NAME" == "gemma3-1b" ]]; then echo "skip $NAME (superseded by gemma4)"; exit 0; fi
./serve_model.sh "$REPO" || exit 1
for s in r1 r3 r4; do python3 run_open.py $NAME $s kind; python3 run_open.py $NAME $s full; done
python3 run_open.py $NAME edit4 edit
pkill -f llama-server
