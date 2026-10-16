#!/bin/zsh
cd "$(dirname "$0")"
./run_all.sh qwen3.5-2b   unsloth/Qwen3.5-2B-GGUF:Q4_K_M
./run_all.sh qwen3.5-0.8b unsloth/Qwen3.5-0.8B-GGUF:Q4_K_M
./run_all.sh qwen3.5-4b   unsloth/Qwen3.5-4B-GGUF:Q4_K_M
./run_all.sh gemma4-e2b   unsloth/gemma-4-E2B-it-GGUF:Q4_K_M
./run_all.sh gemma4-e4b   unsloth/gemma-4-E4B-it-GGUF:Q4_K_M
./run_all.sh qwen3-1.7b   unsloth/Qwen3-1.7B-GGUF:Q4_K_M
./run_all.sh gemma3-4b    unsloth/gemma-3-4b-it-GGUF:Q4_K_M
./run_all.sh gemma3-1b    ggml-org/gemma-3-1b-it-GGUF
./run_all.sh qwen3.5-9b   unsloth/Qwen3.5-9B-GGUF:Q4_K_M
echo MATRIX_DONE
