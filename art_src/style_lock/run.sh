#!/usr/bin/env bash
cd "$(dirname "$0")"
PY=/c/Users/Admin/AppData/Local/Programs/Python/Python312/python.exe
while IFS='|' read -r name prompt; do
  for i in 1 2; do
    [ -f "${name}_$i.png" ] && continue
    $PY -I ~/.claude/skills/qwen-image/gen_image.py --prompt "$prompt" --out "$PWD/${name}_$i.png" --size 1344x768 || echo "FAILED $name $i"
  done
done < prompts.txt
echo ALLDONE
