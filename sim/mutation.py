#!/usr/bin/env python3
"""Перевірка чутливості тестбенча: вносить навмисні помилки в копії RTL і
запускає симуляцію. Кожен «мутант» має бути виявлений (TEST FAILED)."""
import os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MUTANTS = [
    ("uart_tx: MSB першим (замість LSB)", "uart_tx.vhd",
     "shreg <= tx_data;",
     "shreg <= tx_data(0)&tx_data(1)&tx_data(2)&tx_data(3)&tx_data(4)&tx_data(5)&tx_data(6)&tx_data(7);", []),
    ("uart_top: дільник на 1 такт менший (433 замість 434)", "uart_top.vhd",
     "(CLK_FREQ + BAUD / 2) / BAUD;", "(CLK_FREQ + BAUD / 2) / BAUD - 1;", []),
    ("uart_rx: MSB першим (зсув ліворуч)", "uart_rx.vhd",
     "shreg <= rxd_s & shreg(7 downto 1);", "shreg <= shreg(6 downto 0) & rxd_s;", []),
    ("uart_rx: зчитування на початку біта, а не в середині", "uart_baud_gen.vhd",
     "constant HALF : natural := DIV / 2 - 1;", "constant HALF : natural := 1;", []),
    ("uart_rx: не перевіряється стоп-біт", "uart_rx.vhd",
     "frame_err  <= not rxd_s;", "frame_err  <= '0';", []),
    ("uart_rx: немає повторної перевірки старт-біта", "uart_rx.vhd",
     "if rxd_s = '0' then\n                bitn  <= 0;", "if true then\n                bitn  <= 0;", []),
    ("uart_tx: інвертована парність (even <-> odd)", "uart_tx.vhd",
     "if PARITY = 1 then                 -- even", "if PARITY = 2 then                 -- even", ["-gPARITY=1"]),
    ("uart_tx: tx_start приймається під час передачі", "uart_tx.vhd",
     "when S_DATA =>\n            if tick = '1' then",
     "when S_DATA =>\n            if tx_start = '1' then shreg <= tx_data; end if;\n            if tick = '1' then", []),
]
def run(extra, srcdir):
    files = ["uart_baud_gen", "uart_tx", "uart_rx", "uart_top"]
    wd = os.path.join(srcdir, "b"); os.makedirs(wd, exist_ok=True)
    cmd = ["ghdl", "-a", "--std=08", "--workdir=" + wd] + [f"{srcdir}/{f}.vhd" for f in files] + [ROOT + "/tb/tb_uart.vhd"]
    subprocess.run(cmd, check=True, capture_output=True)
    subprocess.run(["ghdl", "-e", "--std=08", "--workdir=" + wd, "tb_uart"], check=True, capture_output=True)
    r = subprocess.run(["ghdl", "-r", "--std=08", "--workdir=" + wd, "tb_uart"] + extra, capture_output=True, text=True)
    return r.stdout
ok_all = True
for name, fn, old, new, extra in MUTANTS:
    d = tempfile.mkdtemp()
    for f in os.listdir(ROOT + "/rtl"): shutil.copy(f"{ROOT}/rtl/{f}", d)
    s = open(f"{d}/{fn}").read()
    assert old in s, (name, "pattern not found")
    open(f"{d}/{fn}", "w").write(s.replace(old, new, 1))
    out = run(extra, d)
    m = re.search(r"TEST FAILED \((\d+) of (\d+) checks failed\)", out)
    fails = [l.strip() for l in out.splitlines() if "[FAIL]" in l]
    if "TEST PASSED" in out: ok_all = False
    res = f"FAILED {m.group(1)} of {m.group(2)}" if m else ("PASSED (!!!)" if "TEST PASSED" in out else "TIMEOUT/ERR")
    print(f"{name} | {res} | {fails[0] if fails else ''}")
sys.exit(0 if ok_all else 1)
