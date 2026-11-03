-- =============================================================================
-- tb_uart.vhd -- самоперевірний тестбенч UART (VHDL-2008)
-- -----------------------------------------------------------------------------
-- Лабораторна робота №3, варіант 19 (UART, VHDL).
--
-- Середовище:
--   * генератор clk (50 МГц) і скидання rst_n;
--   * DUT uart_top (generic BAUD, PARITY, CLK_FREQ);
--   * незалежний декодер лінії TxD (процеси mon_decode, mon_width): перевіряє
--     біти кадру та точність бітових інтервалів на рівні сигналів, а не
--     внутрішніх регістрів DUT;
--   * процедура send_frame -- модель ІНШОГО пристрою, що передає кадри на RxD
--     (в т.ч. зіпсовані: стоп-біт 0, хибна парність, відхилена швидкість);
--   * процес rx_collect -- журнал байтів, прийнятих DUT;
--   * режим loopback: TxD -> RxD (перевірка всіх 256 значень байта).
--
-- Тести:
--   T1  передача 0x55: біти кадру, всі бітові інтервали = 1/BAUD
--   T2  потік байтів Tx (несиметричні за бітами); tx_start під час tx_busy ігнорується
--   T3  прийом одного байта
--   T4  прийом потоку байтів без пауз
--   T5  помилка кадру (стоп-біт = 0) і відновлення
--   T6  хибний старт (завада коротша за півбіта) ігнорується
--   T7  допуск приймача на відхилення швидкості передавача
--   T8  парність: правильна і хибна (лише при PARITY /= 0)
--   T9  loopback: всі байти 0..LOOP_N-1
--   T10 скидання посеред кадру і робота після нього
--
-- Запуск: ghdl -a --std=08 rtl/*.vhd tb/tb_uart.vhd && ghdl -r --std=08 tb_uart
--         додаткові параметри: -gPARITY=1 -gBAUD=9600 --vcd=wave.vcd
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_uart is
  generic (
    CLK_FREQ : positive := 50_000_000;
    BAUD     : positive := 115_200;
    PARITY   : natural range 0 to 2 := 0;
    LOOP_N   : positive := 256
  );
end entity tb_uart;

architecture sim of tb_uart is

  -- ---------------- часові константи ----------------
  constant CLK_PERIOD : time     := 1 sec / CLK_FREQ;                  -- 20 нс
  constant BIT_CLKS   : positive := (CLK_FREQ + BAUD / 2) / BAUD;       -- 434
  constant BIT_T      : time     := CLK_PERIOD * BIT_CLKS;               -- 8680 нс
  constant BIT_EXT    : time     := 1 sec / BAUD;                        -- ідеальний біт 8680.56 нс
  constant NBITS      : positive := 10 + boolean'pos(PARITY /= 0);
  constant FRAME_T    : time     := BIT_T * NBITS;

  -- ---------------- сигнали ----------------
  signal clk      : std_logic := '0';
  signal rst_n    : std_logic := '0';
  signal tx_start : std_logic := '0';
  signal tx_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_busy, tx_done, txd : std_logic;
  signal rxd_ext  : std_logic := '1';           -- лінія від іншого пристрою
  signal loopback : std_logic := '0';           -- 1: RxD = TxD
  signal rxd      : std_logic;
  signal rx_data  : std_logic_vector(7 downto 0);
  signal rx_valid, rx_busy, frame_err, parity_err : std_logic;
  signal test_id  : integer := 0;               -- номер тесту (для осцилограм)

  -- журнал декодера TxD
  type byte_arr_t is array (0 to 1023) of std_logic_vector(7 downto 0);
  signal mon_data    : byte_arr_t;
  signal mon_stop_ok : std_logic_vector(0 to 1023) := (others => '0');
  signal mon_par_ok  : std_logic_vector(0 to 1023) := (others => '1');
  signal mon_cnt     : natural := 0;
  signal mon_max_dev : time := 0 ns;            -- найбільше відхилення бітового інтервалу
  signal mon_pulses  : natural := 0;            -- скільки інтервалів виміряно

  -- журнал приймача
  signal rx_log : byte_arr_t;
  signal rx_fe  : std_logic_vector(0 to 1023) := (others => '0');
  signal rx_pe  : std_logic_vector(0 to 1023) := (others => '0');
  signal rx_cnt : natural := 0;

  -- ---------------- допоміжні функції ----------------
  function xor8 (v : std_logic_vector(7 downto 0)) return std_logic is
    variable r : std_logic := '0';
  begin
    for i in v'range loop r := r xor v(i); end loop;
    return r;
  end function;

  -- очікуваний біт парності: mode 1 = even, 2 = odd
  function par_bit (d : std_logic_vector(7 downto 0); mode : natural) return std_logic is
  begin
    if mode = 1 then return xor8(d); else return not xor8(d); end if;
  end function;

  function tstr (t : time) return string is
  begin
    return to_string(real(t / 1 ns) / 1000.0, "%9.2f");
  end function;

  procedure say (constant s : in string) is
    variable l : line;
  begin
    write(l, s);
    writeline(output, l);
  end procedure;

begin

  -- ---------------- тактування, шина, DUT ----------------
  clk  <= not clk after CLK_PERIOD / 2;
  rxd  <= txd when loopback = '1' else rxd_ext;

  dut : entity work.uart_top
    generic map (CLK_FREQ => CLK_FREQ, BAUD => BAUD, PARITY => PARITY)
    port map (clk => clk, rst_n => rst_n,
              tx_start => tx_start, tx_data => tx_data,
              tx_busy => tx_busy, tx_done => tx_done, txd => txd,
              rxd => rxd, rx_data => rx_data, rx_valid => rx_valid,
              rx_busy => rx_busy, frame_err => frame_err, parity_err => parity_err);

  -- ---------------- декодер TxD: біти кадру ----------------
  mon_decode : process
    variable b    : std_logic_vector(7 downto 0);
    variable pbit : std_logic := '0';
    variable k    : natural := 0;
    variable sok  : std_logic;
    variable pok  : std_logic;
  begin
    wait until falling_edge(txd);               -- початок стартового біта
    wait for BIT_T / 2;                         -- середина старт-біта
    if txd = '0' then
      for i in 0 to 7 loop
        wait for BIT_T;
        b(i) := txd;
      end loop;
      pok := '1';
      if PARITY /= 0 then
        wait for BIT_T;
        pbit := txd;
        if pbit /= par_bit(b, PARITY) then pok := '0'; end if;
      end if;
      wait for BIT_T;                           -- середина стоп-біта
      sok := '1' when txd = '1' else '0';
      mon_data(k)    <= b;
      mon_stop_ok(k) <= sok;
      mon_par_ok(k)  <= pok;
      k := k + 1;
      mon_cnt <= k;
      say("[MON] " & tstr(now) & " us  TxD byte 0x" & to_hstring(b) &
          "  stop=" & std_logic'image(sok)(2 to 2));
    end if;
  end process;

  -- ---------------- декодер TxD: точність бітових інтервалів ----------------
  -- Усі інтервали між фронтами всередині кадру мають бути кратні BIT_T.
  mon_width : process (txd)
    variable t_start : time := - 1 sec;
    variable t_last  : time := 0 ns;
    variable w, dev, mx : time := 0 ns;
    variable n  : integer;
    variable np : natural := 0;
  begin
    if txd'event then
      if txd = '0' and (now - t_start) >= FRAME_T - 1 ns then
        t_start := now;                         -- перший фронт нового кадру
      elsif (now - t_start) < FRAME_T - 1 ns then
        w   := now - t_last;
        n   := (w + BIT_T / 2) / BIT_T;
        dev := abs (w - n * BIT_T);
        if dev > mx then mx := dev; end if;
        np := np + 1;
        mon_max_dev <= mx;
        mon_pulses  <= np;
      end if;
      t_last := now;
    end if;
  end process;

  -- ---------------- журнал прийнятих байтів ----------------
  rx_collect : process (clk)
  begin
    if rising_edge(clk) then
      if rx_valid = '1' then
        rx_log(rx_cnt) <= rx_data;
        rx_fe(rx_cnt)  <= frame_err;
        rx_pe(rx_cnt)  <= parity_err;
        rx_cnt         <= rx_cnt + 1;
      end if;
    end if;
  end process;

  -- ---------------- основний сценарій ----------------
  main : process
    variable n_checks, n_errors : natural := 0;
    variable base, base2 : natural;
    variable t_cmd, t_dn : time;
    variable ok, ok_p, ok_n : boolean;
    variable first_fail : integer;
    variable bad : natural;

    procedure check (constant cond : in boolean; constant msg : in string) is
    begin
      n_checks := n_checks + 1;
      if cond then
        say(" [PASS] " & msg);
      else
        n_errors := n_errors + 1;
        say(" [FAIL] " & msg);
      end if;
    end procedure;

    -- запуск передачі байта DUT (імпульс tx_start довжиною 1 такт)
    procedure start_tx (constant d : in std_logic_vector(7 downto 0)) is
    begin
      wait until falling_edge(clk);
      tx_data  <= d;
      tx_start <= '1';
      wait until falling_edge(clk);
      tx_start <= '0';
    end procedure;

    -- передача байта і очікування кінця кадру
    procedure send_tx (constant d : in std_logic_vector(7 downto 0)) is
    begin
      start_tx(d);
      wait until tx_done = '1';
      wait until falling_edge(clk);
    end procedure;

    -- інший пристрій передає кадр на RxD; bt -- довжина біта
    procedure send_frame (constant d : in std_logic_vector(7 downto 0);
                          constant bt : in time;
                          constant bad_stop : in boolean := false;
                          constant bad_par  : in boolean := false) is
      variable p : std_logic;
    begin
      rxd_ext <= '0';
      wait for bt;                                -- START
      for i in 0 to 7 loop
        rxd_ext <= d(i);
        wait for bt;                              -- D0..D7, LSB first
      end loop;
      if PARITY /= 0 then
        p := par_bit(d, PARITY);
        if bad_par then p := not p; end if;
        rxd_ext <= p;
        wait for bt;                              -- PARITY
      end if;
      if bad_stop then rxd_ext <= '0'; else rxd_ext <= '1'; end if;
      wait for bt;                                -- STOP
      rxd_ext <= '1';
    end procedure;

    -- кадр зі зміненою швидкістю + перевірка, що байт прийнято правильно
    procedure rx_try (constant d : in std_logic_vector(7 downto 0);
                      constant scale : in real; variable good : out boolean) is
      variable b0 : natural;
    begin
      b0 := rx_cnt;
      send_frame(d, BIT_EXT * scale);
      wait for 3 * BIT_T;
      good := (rx_cnt = b0 + 1) and rx_log(b0) = d and rx_fe(b0) = '0' and rx_pe(b0) = '0';
    end procedure;

  begin
    say("==== UART testbench: CLK = " & integer'image(CLK_FREQ) & " Hz, BAUD = " &
        integer'image(BAUD) & ", PARITY = " & integer'image(PARITY) &
        ", " & integer'image(BIT_CLKS) & " clk/bit ====");
    rst_n <= '0';
    wait for 10 * CLK_PERIOD;
    wait until falling_edge(clk);
    rst_n <= '1';
    wait for 10 * CLK_PERIOD;
    check(txd = '1' and tx_busy = '0' and rx_busy = '0',
          "after reset: TxD idle = 1, tx_busy = 0, rx_busy = 0");

    -- ================= T1: передача 0x55 =================
    test_id <= 1;
    say("-- T1: transmit 0x55 (alternating bits, every bit interval = 1/BAUD)");
    base  := mon_cnt;
    t_cmd := now;
    start_tx(x"55");
    wait until tx_done = '1';
    t_dn := now;
    wait for 2 * CLK_PERIOD;
    check(tx_busy = '0' and txd = '1', "T1 after frame: tx_busy = 0, TxD = 1");
    check(mon_cnt = base + 1 and mon_data(base) = x"55", "T1 TxD bits decode to 0x55 (LSB first)");
    check(mon_stop_ok(base) = '1', "T1 stop bit = 1");
    check(mon_par_ok(base) = '1', "T1 parity bit correct (or absent)");
    check(mon_max_dev < 1 ns, "T1 every bit interval = " & integer'image(BIT_CLKS) & " clk (deviation < 1 ns)");
    check((t_dn - t_cmd) >= FRAME_T and (t_dn - t_cmd) <= FRAME_T + 4 * CLK_PERIOD,
          "T1 frame time = " & integer'image(NBITS) & " bits");
    say("   frame time = " & tstr(t_dn - t_cmd) & " us, bit = " & tstr(BIT_T) & " us, " &
        "pulses measured: " & integer'image(mon_pulses));

    -- ================= T2: потік байтів, ігнорування start під час busy =================
    test_id <= 2;
    say("-- T2: stream 01 80 FF 2D B4, tx_start during busy must be ignored");
    base := mon_cnt;
    send_tx(x"01");
    send_tx(x"80");
    send_tx(x"FF");
    -- байт 3C із «зайвим» tx_start у середині кадру
    start_tx(x"2D");
    wait for 4 * BIT_T + BIT_T / 3;
    check(tx_busy = '1', "T2 tx_busy = 1 in the middle of a frame");
    start_tx(x"EE");                              -- має бути проігноровано
    wait until tx_done = '1';
    wait until falling_edge(clk);
    send_tx(x"B4");
    check(mon_cnt = base + 5, "T2 exactly 5 frames on the line (start during busy ignored)");
    check(mon_data(base) = x"01" and mon_data(base + 1) = x"80" and mon_data(base + 2) = x"FF" and
          mon_data(base + 3) = x"2D" and mon_data(base + 4) = x"B4", "T2 bytes on the line: 01 80 FF 2D B4");
    check(mon_stop_ok(base to base + 4) = "11111", "T2 stop bits of all frames = 1");
    check(mon_par_ok(base to base + 4) = "11111", "T2 parity of all frames correct (or absent)");
    check(mon_max_dev < 1 ns, "T2 bit intervals still exact");

    -- ================= T3: прийом одного байта =================
    test_id <= 3;
    say("-- T3: receive 0xD2 from another device");
    base := rx_cnt;
    send_frame(x"D2", BIT_EXT);
    wait for 2 * CLK_PERIOD;
    check(rx_cnt = base + 1, "T3 one byte received (rx_valid pulse)");
    check(rx_log(base) = x"D2", "T3 rx_data = D2");
    check(rx_fe(base) = '0' and rx_pe(base) = '0', "T3 no frame / parity error");
    wait for 2 * BIT_T;

    -- ================= T4: прийом потоку без пауз =================
    test_id <= 4;
    say("-- T4: receive back-to-back 00 FF 1E 87 B4");
    base := rx_cnt;
    send_frame(x"00", BIT_EXT);
    send_frame(x"FF", BIT_EXT);
    send_frame(x"1E", BIT_EXT);
    send_frame(x"87", BIT_EXT);
    send_frame(x"B4", BIT_EXT);
    wait for 2 * CLK_PERIOD;
    check(rx_cnt = base + 5, "T4 5 bytes received without gaps");
    check(rx_log(base) = x"00" and rx_log(base + 1) = x"FF" and rx_log(base + 2) = x"1E" and
          rx_log(base + 3) = x"87" and rx_log(base + 4) = x"B4", "T4 rx_data = 00 FF 1E 87 B4");
    check(rx_fe(base to base + 4) = "00000", "T4 no framing errors");
    wait for 2 * BIT_T;

    -- ================= T5: помилка кадру =================
    test_id <= 5;
    say("-- T5: framing error (stop bit = 0), then a good frame");
    base := rx_cnt;
    send_frame(x"C3", BIT_EXT, bad_stop => true);
    wait for 3 * BIT_T;
    check(rx_cnt = base + 1 and rx_fe(base) = '1', "T5 frame_err = 1 when stop bit = 0");
    send_frame(x"96", BIT_EXT);
    wait for 2 * CLK_PERIOD;
    check(rx_cnt = base + 2 and rx_log(base + 1) = x"96" and rx_fe(base + 1) = '0',
          "T5 next good frame received (96), frame_err cleared");
    wait for 2 * BIT_T;

    -- ================= T6: хибний старт =================
    test_id <= 6;
    say("-- T6: glitch on RxD shorter than half a bit");
    base := rx_cnt;
    rxd_ext <= '0';
    wait for BIT_T / 4;
    rxd_ext <= '1';
    wait for 2 * BIT_T;
    check(rx_cnt = base, "T6 glitch produced no byte");
    check(rx_busy = '0', "T6 receiver returned to IDLE (rx_busy = 0)");
    send_frame(x"6B", BIT_EXT);
    wait for 2 * CLK_PERIOD;
    check(rx_cnt = base + 1 and rx_log(base) = x"6B", "T6 good frame after glitch received (6B)");
    wait for 2 * BIT_T;

    -- ================= T7: допуск на відхилення швидкості =================
    test_id <= 7;
    say("-- T7: receiver tolerance to baud-rate deviation of the sender");
    first_fail := 0;
    ok_p := true;
    ok_n := true;
    for pct in 1 to 10 loop
      ok := true;
      rx_try(x"55", 1.0 + real(pct) / 100.0, ok_p);
      if not ok_p then ok := false; end if;
      rx_try(x"AA", 1.0 + real(pct) / 100.0, ok_p);
      if not ok_p then ok := false; end if;
      rx_try(x"55", 1.0 - real(pct) / 100.0, ok_n);
      if not ok_n then ok := false; end if;
      rx_try(x"AA", 1.0 - real(pct) / 100.0, ok_n);
      if not ok_n then ok := false; end if;
      if ok then
        say("   +/-" & integer'image(pct) & " %: received correctly");
      else
        say("   +/-" & integer'image(pct) & " %: ERRORS");
        if first_fail = 0 then first_fail := pct; end if;
      end if;
      if pct = 3 then check(ok, "T7 sender +/-3 % off nominal baud: all frames correct"); end if;
    end loop;
    if first_fail = 0 then
      say("   tolerance >= 10 %");
    else
      say("   first failing deviation: +/-" & integer'image(first_fail) & " %");
    end if;
    check(first_fail >= 4 or first_fail = 0, "T7 tolerance is at least +/-3 %");
    wait for 2 * BIT_T;

    -- ================= T8: парність =================
    test_id <= 8;
    if PARITY /= 0 then
      say("-- T8: parity (mode " & integer'image(PARITY) & ")");
      base := rx_cnt;
      send_frame(x"A5", BIT_EXT);
      send_frame(x"B3", BIT_EXT, bad_par => true);
      send_frame(x"01", BIT_EXT);
      wait for 2 * CLK_PERIOD;
      check(rx_cnt = base + 3, "T8 3 frames received");
      check(rx_pe(base) = '0' and rx_log(base) = x"A5", "T8 correct parity: parity_err = 0");
      check(rx_pe(base + 1) = '1' and rx_fe(base + 1) = '0', "T8 wrong parity: parity_err = 1, frame_err = 0");
      check(rx_pe(base + 2) = '0' and rx_log(base + 2) = x"01", "T8 parity_err cleared on next good frame");
      wait for 2 * BIT_T;
      -- Tx-сторона: біт парності на лінії
      base := mon_cnt;
      send_tx(x"B3");
      send_tx(x"01");
      check(mon_par_ok(base to base + 1) = "11", "T8 TxD parity bit matches data (monitor)");
    else
      say("-- T8: parity disabled (PARITY = 0), skipped");
    end if;

    -- ================= T9: loopback =================
    test_id <= 9;
    say("-- T9: loopback TxD -> RxD, bytes 0.." & integer'image(LOOP_N - 1));
    loopback <= '1';
    base := rx_cnt;
    base2 := mon_cnt;
    for i in 0 to LOOP_N - 1 loop
      send_tx(std_logic_vector(to_unsigned(i mod 256, 8)));
    end loop;
    wait for 2 * CLK_PERIOD;
    bad := 0;
    for i in 0 to LOOP_N - 1 loop
      if rx_log(base + i) /= std_logic_vector(to_unsigned(i mod 256, 8)) or
         rx_fe(base + i) = '1' or rx_pe(base + i) = '1' then
        bad := bad + 1;
      end if;
    end loop;
    check(rx_cnt = base + LOOP_N, "T9 received " & integer'image(LOOP_N) & " bytes");
    check(bad = 0, "T9 every byte received equals the byte sent, no errors");
    check(mon_cnt = base2 + LOOP_N, "T9 monitor saw the same number of frames");
    loopback <= '0';
    wait for 2 * BIT_T;

    -- ================= T10: скидання посеред кадру =================
    test_id <= 10;
    say("-- T10: reset in the middle of a frame");
    start_tx(x"C3");
    wait for 3 * BIT_T + BIT_T / 3;
    check(tx_busy = '1', "T10 frame is in progress");
    wait until falling_edge(clk);
    rst_n <= '0';
    wait for 3 * CLK_PERIOD;
    check(txd = '1' and tx_busy = '0', "T10 reset: TxD = 1, tx_busy = 0");
    rst_n <= '1';
    wait for 3 * BIT_T;
    loopback <= '1';
    base := rx_cnt;
    send_tx(x"2D");
    wait for 2 * CLK_PERIOD;
    check(rx_cnt = base + 1 and rx_log(base) = x"2D", "T10 after reset: byte 2D sent and received correctly");
    loopback <= '0';
    wait for 2 * BIT_T;

    -- ================= підсумок =================
    say("==== bus: TxD " & integer'image(mon_cnt) & " frames, RxD " & integer'image(rx_cnt) & " frames ====");
    if n_errors = 0 then
      say("==== TEST PASSED (" & integer'image(n_checks) & " checks) ====");
    else
      say("==== TEST FAILED (" & integer'image(n_errors) & " of " & integer'image(n_checks) & " checks failed) ====");
    end if;
    finish;
  end process;

  -- сторожовий таймер
  watchdog : process
  begin
    wait for 300 ms;
    say("==== TEST FAILED (timeout) ====");
    finish;
  end process;

end architecture sim;
