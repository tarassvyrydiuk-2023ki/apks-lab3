#!/usr/bin/env python3
"""Будує осцилограми у стилі логічного аналізатора з VCD-файлів GHDL.
Запуск: python3 sim/plot_waves.py build/wave.vcd build/wave_par.vcd docs/waves
Стани FSM відновлюються з імпульсів tick / mid (VCD GHDL не містить enum-типів)."""
import sys, os, bisect
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

BG, AX, GR, YL, BL, RD, TX = "#1b1f1d", "#0a0f0c", "#3be07a", "#e8d14a", "#5fb4ff", "#ff6670", "#a8b0aa"
plt.rcParams.update({"font.family": "DejaVu Sans Mono", "font.size": 10})
US = 1e9            # fs -> мкс

# ---------------------------------------------------------------- VCD
def load_vcd(path, want):
    """want: {'ім'я': 'tb_uart.dut.u_tx.tick'} -> {'ім'я': [(t_fs, value), ...]}"""
    ids, scope, out = {}, [], {}
    with open(path) as f:
        for line in f:
            if line.startswith("$scope"):
                scope.append(line.split()[2])
            elif line.startswith("$upscope"):
                scope.pop()
            elif line.startswith("$var"):
                p = line.split()
                full = ".".join(scope) + "." + p[4]
                for k, v in want.items():
                    if full == v:
                        ids.setdefault(p[3], []).append(k)
                        out[k] = []
            elif line.startswith("$enddefinitions"):
                break
        t = 0
        for line in f:
            c = line[0]
            if c == "#":
                t = int(line[1:])
            elif c in "01xzXZ":
                for k in ids.get(line[1:].strip(), []):
                    out[k].append((t, -1 if c in "xzXZ" else int(c)))
            elif c == "b" or c == "B":
                v, i = line[1:].split()
                for k in ids.get(i, []):
                    try:
                        out[k].append((t, int(v, 2)))
                    except ValueError:
                        out[k].append((t, None))
    return out

def val_at(ev, t):
    i = bisect.bisect_right([e[0] for e in ev], t) - 1
    return ev[i][1] if i >= 0 else None

def pulses(ev, t0, t1):
    return [t for t, v in ev if v == 1 and t0 <= t < t1]

def window(ev_test, k, t_end):
    """інтервал [t_k, t_{k+1}) для test_id = k (для останнього тесту -- до кінця симуляції)"""
    ts = [(t, v) for t, v in ev_test]
    a = next(t for t, v in ts if v == k)
    nxt = [t for t, v in ts if t > a and v != k]
    return a, (nxt[0] if nxt else t_end)

# ---------------------------------------------------------------- малювання
class Lanes:
    def __init__(self, ax, t0, t1, labels):
        t0 = max(t0, 0)
        self.ax, self.t0, self.t1 = ax, t0, t1
        self.n = len(labels)
        self.idx = {k: i for i, k in enumerate(labels)}
        ax.set_facecolor(AX)
        ax.set_xlim(0, (t1 - t0) / US)
        ax.set_ylim(-self.n + 0.1, 1.9)
        ax.set_yticks([-i + 0.3 for i in range(self.n)])
        ax.set_yticklabels(labels, color="white")
        ax.tick_params(axis="x", colors=TX)
        ax.tick_params(axis="y", length=0)
        for s in ax.spines.values():
            s.set_color("#2c332f")
        ax.grid(axis="x", color="#2c332f", lw=0.5)
        ax.set_xlabel("час, мкс", color=TX)

    def x(self, t):
        return (t - self.t0) / US

    def _segs(self, ev):
        """[(t_a, t_b, value)] у вікні"""
        pts = [(t, v) for t, v in ev if t < self.t1]
        cur = None
        segs = []
        start = self.t0
        for t, v in pts:
            if t <= self.t0:
                cur = v
                continue
            segs.append((start, t, cur))
            start, cur = t, v
        segs.append((start, self.t1, cur))
        return segs

    def digital(self, name, ev, color=GR):
        i = self.idx[name]
        xs, ys = [], []
        for a, b, v in self._segs(ev):
            y = -i + (0.6 if v == 1 else 0.0 if v == 0 else 0.3)
            xs += [self.x(a), self.x(b)]
            ys += [y, y]
        self.ax.plot(xs, ys, color=color, lw=1.3, drawstyle="default")

    def bus(self, name, segs, fmt=lambda v: "x" if v is None else f"{v:02X}", color=GR, tcolor=YL):
        """segs: [(t_a, t_b, value_or_text)]"""
        i = self.idx[name]
        h, c = 0.6, 0.012 * (self.t1 - self.t0) / US * 0.5
        for a, b, v in segs:
            xa, xb = self.x(max(a, self.t0)), self.x(min(b, self.t1))
            if xb <= xa:
                continue
            cc = min(c, (xb - xa) / 3)
            y0 = -i
            self.ax.plot([xa, xa + cc, xb - cc, xb, xb - cc, xa + cc, xa],
                         [y0 + h / 2, y0 + h, y0 + h, y0 + h / 2, y0, y0, y0 + h / 2], color=color, lw=1.1)
            txt = v if isinstance(v, str) else fmt(v)
            if (xb - xa) > 0.012 * (self.t1 - self.t0) / US * max(1, len(txt)) * 0.5:
                self.ax.text((xa + xb) / 2, y0 + h / 2, txt, color=tcolor, ha="center", va="center", fontsize=9)

    def marks(self, name, times, color=BL):
        i = self.idx[name]
        for t in times:
            if self.t0 <= t < self.t1:
                self.ax.plot([self.x(t)] * 2, [-i, -i + 0.6], color=color, lw=1.6)

    def vline(self, t, label, color):
        if self.t0 <= t <= self.t1:
            self.ax.axvline(self.x(t), color=color, ls="--", lw=1)
            self.ax.text(self.x(t), 1.75, label, color=color, ha="center", va="top", fontweight="bold")

    def span(self, a, b, label, y=1.45, color=YL, fs=8.5):
        a, b = max(a, self.t0), min(b, self.t1)
        if b <= a:
            return
        self.ax.annotate("", xy=(self.x(a), y), xytext=(self.x(b), y),
                         arrowprops=dict(arrowstyle="<->", color=color, lw=1))
        self.ax.text((self.x(a) + self.x(b)) / 2, y + 0.08, label, color=color, ha="center", va="bottom", fontsize=fs)

def new_fig(n_lanes, title, h_per=0.62, w=13.5, extra=1.6):
    fig, ax = plt.subplots(figsize=(w, n_lanes * h_per + extra), facecolor=BG)
    ax.set_title(title, color="white", loc="left", fontsize=12)
    fig.subplots_adjust(left=0.10, right=0.995, top=0.92, bottom=0.12)
    return fig, ax

# ---------------------------------------------------------------- розшифровка
def tx_segments(d, t0, t1, parity):
    """сегменти станів і бітів Tx за tick/busy: повертає (state_segs, bit_segs, frames)"""
    ticks = pulses(d["tx_tick"], t0, t1)
    busy = d["tx_busy"]
    rises = [t for (t, v), (tp, vp) in zip(busy[1:], busy[:-1]) if v == 1 and vp == 0 and t0 <= t < t1]
    ssegs, bsegs, frames = [], [], []
    nb = 10 + (1 if parity else 0)
    for tb in rises:
        fall = next((t for t, v in busy if t > tb and v == 0), t1)
        tk = [t for t in ticks if tb < t <= fall][:nb]
        if len(tk) < nb:
            tk += [t1] * (nb - len(tk))
        names = ["START"] + [f"D{i}" for i in range(8)] + (["PAR"] if parity else []) + ["STOP"]
        edges = [tb] + tk
        for i, nm in enumerate(names):
            bsegs.append((edges[i], edges[i + 1], nm))
        ssegs.append((edges[0], edges[1], "START"))
        ssegs.append((edges[1], edges[9], "DATA"))
        if parity:
            ssegs.append((edges[9], edges[10], "PARITY"))
        ssegs.append((edges[-2], edges[-1], "STOP"))
        frames.append((tb, edges[-1]))
    return ssegs, bsegs, frames

def rx_segments(d, t0, t1, parity):
    mids = pulses(d["rx_mid"], t0, t1)
    busy = d["rx_busy"]
    rises = [t for (t, v), (tp, vp) in zip(busy[1:], busy[:-1]) if v == 1 and vp == 0 and t0 <= t < t1]
    ssegs, frames = [], []
    nb = 10 + (1 if parity else 0)
    for tb in rises:
        fall = next((t for t, v in busy if t > tb and v == 0), t1)
        mm = [t for t in mids if tb < t <= fall][:nb]
        if len(mm) < 2:          # хибний старт: лише START, далі IDLE
            ssegs.append((tb, fall, "START"))
            frames.append((tb, fall, mm))
            continue
        if len(mm) < nb:
            mm += [t1] * (nb - len(mm))
        ssegs.append((tb, mm[0], "START"))
        ssegs.append((mm[0], mm[8], "DATA"))
        if parity:
            ssegs.append((mm[8], mm[9], "PARITY"))
        ssegs.append((mm[-2], mm[-1], "STOP"))
        frames.append((tb, mm[-1], mm))
    return ssegs, frames

def bit_labels(L, line, frames_edges, nbits_names=None):
    for a, b, nm in frames_edges:
        mid = (a + b) // 2
        v = val_at(line, mid)
        txt = f"{nm}\n{v}" if nm.startswith("D") or nm == "PAR" else nm
        L.ax.text(L.x(mid), 1.05, txt if nm.startswith("D") or nm == "PAR" else nm, color=YL, ha="center", va="center", fontsize=7.5)

def hexseg(ev, t0, t1):
    pts = [(t, v) for t, v in ev]
    segs = []
    for i, (t, v) in enumerate(pts):
        te = pts[i + 1][0] if i + 1 < len(pts) else t1
        if te > t0 and t < t1:
            segs.append((t, te, v))
    return segs

def save(fig, outdir, name):
    p = os.path.join(outdir, name)
    fig.savefig(p, dpi=130, facecolor=BG)
    plt.close(fig)
    print("wrote", p)

# ---------------------------------------------------------------- рисунки
NAMES = {
    "test": "tb_uart.test_id", "rst_n": "tb_uart.rst_n", "tx_start": "tb_uart.tx_start", "tx_data": "tb_uart.tx_data[7:0]",
    "tx_busy": "tb_uart.tx_busy", "tx_done": "tb_uart.tx_done", "txd": "tb_uart.txd", "rxd": "tb_uart.rxd",
    "rxd_ext": "tb_uart.rxd_ext", "loopback": "tb_uart.loopback",
    "rx_data": "tb_uart.rx_data[7:0]", "rx_valid": "tb_uart.rx_valid", "rx_busy": "tb_uart.rx_busy",
    "frame_err": "tb_uart.frame_err", "parity_err": "tb_uart.parity_err",
    "tx_tick": "tb_uart.dut.u_tx.tick", "tx_bitn": "tb_uart.dut.u_tx.bitn", "tx_shreg": "tb_uart.dut.u_tx.shreg[7:0]",
    "rx_mid": "tb_uart.dut.u_rx.mid", "rx_bitn": "tb_uart.dut.u_rx.bitn", "rx_shreg": "tb_uart.dut.u_rx.shreg[7:0]",
    "rxd_s": "tb_uart.dut.u_rx.rxd_s",
}

def decode_line(line, a, b, bt, parity):
    """байт із лінії: a -- момент спаду старт-біта"""
    v = 0
    for i in range(8):
        v |= (val_at(line, a + int(bt * (1.5 + i))) or 0) << i
    return v

def run(vcd, vcd_par, outdir):
    os.makedirs(outdir, exist_ok=True)
    d = load_vcd(vcd, NAMES)
    BT = int(8680 * 1e6)                                 # 8680 нс у фс
    END = max(ev[-1][0] for ev in d.values() if ev)
    W = {k: window(d["test"], k, END) for k in (1, 2, 3, 4, 5, 6, 7, 9, 10)}

    # ---- рис. A: T1 -- передача 0x55
    a, b = W[1]
    st = pulses(d["tx_start"], a, b)[0]
    t0, t1 = st - 15 * 10**9, st + 10 * BT + 12 * 10**9
    t1 = min(t1, b)
    labels = ["rst_n", "tx_start", "tx_busy", "state", "bitn", "TxD", "tx_done"]
    fig, ax = new_fig(len(labels), "T1: передача байта 0x55 (8N1, 115200 біт/с): стани FSM передавача й біти кадру")
    L = Lanes(ax, t0, t1, labels)
    L.digital("rst_n", d["rst_n"]); L.digital("tx_start", d["tx_start"]); L.digital("tx_busy", d["tx_busy"])
    ss, bs, fr = tx_segments(d, t0, t1, False)
    L.bus("state", ss, color=GR); L.bus("bitn", hexseg(d["tx_bitn"], t0, t1), fmt=lambda v: str(v))
    L.digital("TxD", d["txd"]); L.digital("tx_done", d["tx_done"])
    bit_labels(L, d["txd"], bs)
    for x in bs:
        L.ax.axvline(L.x(x[0]), color="#2c332f", lw=0.6)
    fa = fr[0][0]
    L.vline(fa, "S", BL); L.vline(fr[0][1], "P", RD)
    L.span(fa, fr[0][1], "кадр: 10 бітів × 8.68 мкс = 86.8 мкс", y=1.5)
    save(fig, outdir, "fig_t1_tx.png")

    # ---- рис. B: T2 -- потік Tx з ігноруванням tx_start під час busy
    a, b = W[2]
    st = pulses(d["tx_start"], a, b)
    t0 = st[0] - 20 * 10**9 + 0
    ss, bs, fr = tx_segments(d, t0, b, False)
    t1 = fr[-1][1] + 30 * 10**9
    t1 = min(t1, b)
    labels = ["tx_start", "tx_data", "tx_busy", "TxD", "tx_done"]
    fig, ax = new_fig(len(labels), "T2: потік байтів 01 80 FF 2D B4; імпульс tx_start (EE) посеред кадру ігнорується", h_per=0.75)
    L = Lanes(ax, t0, t1, labels)
    L.digital("tx_start", d["tx_start"]); L.bus("tx_data", hexseg(d["tx_data"], t0, t1)); L.digital("tx_busy", d["tx_busy"])
    L.digital("TxD", d["txd"]); L.digital("tx_done", d["tx_done"])
    for (fa, fb) in fr:
        val = decode_line(d["txd"], fa, fb, BT, False)
        L.span(fa, fb, f"0x{val:02X}", y=1.4)
        L.ax.axvline(L.x(fa), color=BL, ls=":", lw=0.8)
    ign = [t for t in st if any(fa < t < fb for fa, fb in fr)]
    for t in ign:
        L.ax.annotate("ігнорується", xy=(L.x(t), 0.6 - 1), xytext=(L.x(t) + 12, 0.95 - 1), color=RD, fontsize=9,
                      arrowprops=dict(arrowstyle="->", color=RD))
    save(fig, outdir, "fig_t2_tx_stream.png")

    # ---- рис. C: T3 -- прийом D2
    a, b = W[3]
    ss, fr = rx_segments(d, a, b, False)
    fa, fb, mm = fr[0]
    t0, t1 = fa - 15 * 10**9, fb + BT
    t1 = min(t1, b)
    labels = ["RxD", "rx_busy", "state", "bitn", "sample", "shreg", "rx_valid", "rx_data", "frame_err"]
    fig, ax = new_fig(len(labels), "T3: прийом байта 0xD2: зчитування в середині кожного біта, збирання в зсувному регістрі")
    L = Lanes(ax, t0, t1, labels)
    L.digital("RxD", d["rxd"]); L.digital("rx_busy", d["rx_busy"]); L.bus("state", rx_segments(d, t0, t1, False)[0])
    L.bus("bitn", hexseg(d["rx_bitn"], t0, t1), fmt=lambda v: str(v))
    L.marks("sample", mm, BL)
    L.bus("shreg", hexseg(d["rx_shreg"], t0, t1))
    L.digital("rx_valid", d["rx_valid"]); L.bus("rx_data", hexseg(d["rx_data"], t0, t1)); L.digital("frame_err", d["frame_err"], RD)
    names = ["START"] + [f"D{i}" for i in range(8)] + ["STOP"]
    for i, nm in enumerate(names):
        a1, b1 = fa + i * BT, fa + (i + 1) * BT
        L.ax.axvline(L.x(a1), color="#2c332f", lw=0.6)
        v = val_at(d["rxd"], (a1 + b1) // 2)
        L.ax.text(L.x((a1 + b1) // 2), 1.05, nm if i in (0, 9) else f"{nm}\n={v}", color=YL, ha="center", va="center", fontsize=7.5)
    L.vline(fa, "S", BL); L.vline(mm[-1], "P", RD)
    save(fig, outdir, "fig_t3_rx.png")

    # ---- рис. D: T4 -- потік Rx
    a, b = W[4]
    ss, fr = rx_segments(d, a, b, False)
    t0, t1 = fr[0][0] - 20 * 10**9, fr[-1][1] + BT
    t1 = min(t1, b)
    labels = ["RxD", "rx_busy", "rx_valid", "rx_data", "frame_err"]
    fig, ax = new_fig(len(labels), "T4: прийом потоку 00 FF 1E 87 B4 без пауз між кадрами", h_per=0.75)
    L = Lanes(ax, t0, t1, labels)
    L.digital("RxD", d["rxd"]); L.digital("rx_busy", d["rx_busy"]); L.digital("rx_valid", d["rx_valid"])
    L.bus("rx_data", hexseg(d["rx_data"], t0, t1)); L.digital("frame_err", d["frame_err"], RD)
    for (fa, fb, mm) in fr:
        L.span(fa, fb, f"кадр 0x{decode_line(d['rxd'], fa, fb, BT, False):02X}", y=1.4)
        L.ax.axvline(L.x(fa), color=BL, ls=":", lw=0.8)
    save(fig, outdir, "fig_t4_rx_stream.png")

    # ---- рис. E: T5 -- помилка кадру
    a, b = W[5]
    ss, fr = rx_segments(d, a, b, False)
    t0, t1 = fr[0][0] - 20 * 10**9, fr[1][1] + BT
    t1 = min(t1, b)
    labels = ["RxD", "rx_busy", "state", "rx_valid", "rx_data", "frame_err"]
    fig, ax = new_fig(len(labels), "T5: стоп-біт = 0 → frame_err = 1; наступний правильний кадр приймається, frame_err скидається", h_per=0.75)
    L = Lanes(ax, t0, t1, labels)
    L.digital("RxD", d["rxd"]); L.digital("rx_busy", d["rx_busy"]); L.bus("state", ss)
    L.digital("rx_valid", d["rx_valid"]); L.bus("rx_data", hexseg(d["rx_data"], t0, t1)); L.digital("frame_err", d["frame_err"], RD)
    L.span(fr[0][0], fr[0][1], "кадр C3, стоп-біт = 0", y=1.4, color=RD)
    L.span(fr[1][0], fr[1][1], "кадр 96, стоп-біт = 1", y=1.4)
    L.ax.text(L.x(fr[0][1]), -4 + 0.75, " frame_err = 1", color=RD, fontsize=9, va="bottom")
    save(fig, outdir, "fig_t5_frame_err.png")

    # ---- рис. F: T6 -- хибний старт
    a, b = W[6]
    ss, fr = rx_segments(d, a, b, False)
    t0, t1 = a - 12 * 10**9, fr[1][1] + BT
    t1 = min(t1, b)
    labels = ["RxD", "rx_busy", "state", "rx_valid", "rx_data"]
    fig, ax = new_fig(len(labels), "T6: завада на RxD коротша за півбіта ігнорується; наступний правильний кадр 6B приймається", h_per=0.75)
    L = Lanes(ax, t0, t1, labels)
    L.digital("RxD", d["rxd"]); L.digital("rx_busy", d["rx_busy"]); L.bus("state", ss)
    L.digital("rx_valid", d["rx_valid"]); L.bus("rx_data", hexseg(d["rx_data"], t0, t1))
    L.span(fr[0][0], fr[0][0] + BT // 4, "завада", y=1.4, color=RD)
    L.span(fr[1][0], fr[1][1], "кадр 6B", y=1.4)
    save(fig, outdir, "fig_t6_glitch.png")

    # ---- рис. G: T7 -- відхилення швидкості: +5 % (вірно) і +6 % (frame_err)
    a, b = W[7]
    ss, fr = rx_segments(d, a, b, False)
    fig, axs = plt.subplots(2, 1, figsize=(13.5, 8.2), facecolor=BG)
    fig.subplots_adjust(left=0.10, right=0.995, top=0.94, bottom=0.08, hspace=0.50)
    for ax, (idx, pct) in zip(axs, ((16, 5), (20, 6))):
        fa, fb, mm = fr[idx]
        bt = int(BT * (1 + pct / 100))
        t0, t1 = fa - 15 * 10**9, fa + 10 * bt + BT
        labels = ["RxD", "sample", "rx_valid", "rx_data", "frame_err"]
        ax.set_title(f"T7: передавач повільніший на +{pct} % (біт {8.6806*(1+pct/100):.2f} мкс), кадр 0x55",
                     color="white", loc="left", fontsize=11)
        L = Lanes(ax, t0, t1, labels)
        L.digital("RxD", d["rxd"]); L.marks("sample", mm, BL); L.digital("rx_valid", d["rx_valid"])
        L.digital("frame_err", d["frame_err"], RD)
        val = val_at(d["rx_data"], fb + 10**9); fe = val_at(d["frame_err"], fb + 10**9)
        good = (val == 0x55 and not fe)
        L.bus("rx_data", hexseg(d["rx_data"], t0, t1), color=GR if good else RD)
        for k in range(11):
            L.ax.axvline(L.x(fa + k * bt), color="#2c332f", lw=0.6)
        if pct == 6:
            L.ax.annotate("стоп-біт відправника\nпочинається тут", xy=(L.x(fa + 9 * bt), 0.72),
                          xytext=(L.x(fa + 9 * bt) - 22, 1.1), color=RD, fontsize=9, ha="center", va="center",
                          arrowprops=dict(arrowstyle="->", color=RD))
        verdict = ("прийнято 0x%02X, frame_err = %d: вірно" % (val, fe)) if good else \
                  ("прийнято 0x%02X, frame_err = %d: ПОМИЛКА КАДРУ" % (val, fe))
        L.ax.text(L.x(t1) - 0.5, 1.85, verdict, color=GR if good else RD, ha="right", va="top", fontsize=10, fontweight="bold")
    save(fig, outdir, "fig_t7_baud_tolerance.png")

    # ---- рис. H: T9 -- loopback
    a, b = W[9]
    st = pulses(d["tx_start"], a, b)
    ss, bs, fr = tx_segments(d, a, b, False)
    t0, t1 = st[0] - 20 * 10**9, fr[-1][1] + 40 * 10**9
    t1 = min(t1, b)
    labels = ["tx_start", "tx_data", "tx_done", "TxD = RxD", "rx_valid", "rx_data", "frame_err"]
    fig, ax = new_fig(len(labels), "T9: loopback TxD → RxD: кожен переданий байт приймається без змін", h_per=0.7)
    L = Lanes(ax, t0, t1, labels)
    L.digital("tx_start", d["tx_start"]); L.bus("tx_data", hexseg(d["tx_data"], t0, t1)); L.digital("tx_done", d["tx_done"])
    L.digital("TxD = RxD", d["rxd"]); L.digital("rx_valid", d["rx_valid"]); L.bus("rx_data", hexseg(d["rx_data"], t0, t1))
    L.digital("frame_err", d["frame_err"], RD)
    for (fa, fb) in fr:
        L.span(fa, fb, f"0x{decode_line(d['txd'], fa, fb, BT, False):02X}", y=1.4)
    save(fig, outdir, "fig_t9_loopback.png")

    # ---- рис. I: T10 -- скидання посеред кадру
    a, b = W[10]
    st = pulses(d["tx_start"], a, b)
    t0 = st[0] - 20 * 10**9
    rr = [t for (t, v), (tp, vp) in zip(d["rst_n"][1:], d["rst_n"][:-1]) if v == 0 and vp == 1 and a <= t < b][0]
    ss, bs, fr = tx_segments(d, t0, b, False)
    t1 = fr[-1][1] + 30 * 10**9
    t1 = min(t1, b)
    labels = ["rst_n", "tx_start", "tx_busy", "TxD", "rx_valid", "rx_data"]
    fig, ax = new_fig(len(labels), "T10: скидання посеред кадру 0xC3 → TxD = 1; після скидання кадр 0x2D передається й приймається", h_per=0.75)
    L = Lanes(ax, t0, t1, labels)
    L.digital("rst_n", d["rst_n"]); L.digital("tx_start", d["tx_start"]); L.digital("tx_busy", d["tx_busy"])
    L.digital("TxD", d["txd"]); L.digital("rx_valid", d["rx_valid"]); L.bus("rx_data", hexseg(d["rx_data"], t0, t1))
    L.vline(rr, "RESET", RD)
    L.span(st[0], rr, "кадр C3 перерваний", y=1.4, color=RD)
    L.span(fr[-1][0], fr[-1][1], "кадр 2D", y=1.4)
    save(fig, outdir, "fig_t10_reset.png")

    # ---- рис. J: T8 -- парність (окремий прогін -gPARITY=1)
    if vcd_par:
        p = load_vcd(vcd_par, NAMES)
        a, b = window(p["test"], 8, max(ev[-1][0] for ev in p.values() if ev))
        ss, fr = rx_segments(p, a, b, True)
        t0, t1 = fr[0][0] - 20 * 10**9, fr[1][1] + BT
        t1 = min(t1, b)
        labels = ["RxD", "rx_busy", "state", "sample", "rx_valid", "rx_data", "parity_err"]
        fig, ax = new_fig(len(labels), "T8: 8E1 (парність even): кадр A5 з правильною парністю й кадр B3 з хибною → parity_err = 1", h_per=0.72)
        L = Lanes(ax, t0, t1, labels)
        L.digital("RxD", p["rxd"]); L.digital("rx_busy", p["rx_busy"]); L.bus("state", rx_segments(p, t0, t1, True)[0])
        L.marks("sample", [m for f in fr[:2] for m in f[2]], BL)
        L.digital("rx_valid", p["rx_valid"]); L.bus("rx_data", hexseg(p["rx_data"], t0, t1)); L.digital("parity_err", p["parity_err"], RD)
        for (fa, fb, mm), tx in zip(fr[:2], ("A5, парність вірна", "B3, парність хибна")):
            L.span(fa, fb, "кадр " + tx, y=1.4, color=YL if "вірна" in tx else RD)
            L.ax.axvline(L.x(mm[8] + (mm[9] - mm[8]) // 2 * 0 - BT // 2 if False else mm[8]), color="#2c332f", lw=0.6)
        save(fig, outdir, "fig_t8_parity.png")

if __name__ == "__main__":
    run(sys.argv[1], sys.argv[2] if len(sys.argv) > 3 else None, sys.argv[-1])
