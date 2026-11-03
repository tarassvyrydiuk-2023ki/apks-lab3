#!/usr/bin/env bash
# Запуск симуляції UART (GHDL, VHDL-2008).
#   bash sim/run_sim.sh [параметри generic: -gPARITY=1 -gBAUD=9600 ...] [--vcd=файл]
set -e
cd "$(dirname "$0")/.."
mkdir -p build
ghdl -a --std=08 --workdir=build \
     rtl/uart_baud_gen.vhd rtl/uart_tx.vhd rtl/uart_rx.vhd rtl/uart_top.vhd \
     tb/tb_uart.vhd
ghdl -e --std=08 --workdir=build tb_uart
ghdl -r --std=08 --workdir=build tb_uart "$@"
