#!/bin/zsh
# Models that Apple's coreai-models registry can export (Qwen3, Gemma 3n) — run after run_matrix.sh
cd "$(dirname "$0")"
./run_all.sh qwen3-0.6b unsloth/Qwen3-0.6B-GGUF:Q4_K_M
./run_all.sh qwen3-4b   unsloth/Qwen3-4B-GGUF:Q4_K_M
./run_all.sh gemma3n-e2b unsloth/gemma-3n-E2B-it-GGUF:Q4_K_M
echo MATRIX2_DONE
