#!/bin/zsh
cd "$(dirname "$0")"
for m in gpt-6-luna gpt-6-astra gpt-6-sol gpt-6.1-sol gpt-5.6-luna gpt-5.6-terra gpt-5.4-nano; do
  for s in r3 r4; do python3 run_openai.py $m $s kind; python3 run_openai.py $m $s full; done
  python3 run_openai.py $m edit4 edit
done
echo OPENAI_DONE
