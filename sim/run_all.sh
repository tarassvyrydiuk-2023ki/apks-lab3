#!/usr/bin/env bash
# Усі конфігурації: 8N1, 8E1, 8O1, 9600 бод, 921600 бод; потім мутаційна перевірка.
set -e
cd "$(dirname "$0")/.."
for cfg in "" "-gPARITY=1" "-gPARITY=2" "-gBAUD=9600 -gLOOP_N=16" "-gBAUD=921600 -gLOOP_N=64"; do
  echo "### $cfg"; bash sim/run_sim.sh $cfg | grep -E "FAIL|PASSED|FAILED"
done
python3 sim/mutation.py
