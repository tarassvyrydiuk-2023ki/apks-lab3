# Лабораторна робота №3 -- UART на VHDL (варіант 19)

Послідовний протокол UART (8N1; опційно парність even/odd), мова VHDL-2008.

| Каталог | Вміст |
|---|---|
| `rtl/` | `uart_baud_gen` (дільник), `uart_tx`, `uart_rx`, `uart_top` |
| `tb/` | самоперевірний тестбенч `tb_uart.vhd` |
| `sim/` | `run_sim.sh`, `run_all.sh`, `mutation.py`, `plot_waves.py` |
| `syn/` | `synth.sh` -- GHDL → Yosys → nextpnr (iCE40-HX8K, ECP5-25F) |
| `docs/` | діаграми FSM (Graphviz) та осцилограми |

```bash
bash sim/run_sim.sh                   # 8N1, 115200, 50 МГц
bash sim/run_sim.sh -gPARITY=1        # 8E1
bash sim/run_all.sh                   # усі конфігурації + мутаційна перевірка
bash syn/synth.sh                     # синтез і часовий аналіз
```
Потрібні: GHDL >= 4.0, Yosys, nextpnr-ice40, nextpnr-ecp5, Python 3 + matplotlib, Graphviz.
