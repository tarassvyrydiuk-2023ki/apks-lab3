-- =============================================================================
-- uart_top.vhd -- верхній рівень UART (передавач + приймач)
-- -----------------------------------------------------------------------------
-- Лабораторна робота №3, варіант 19 (UART, VHDL).
--
-- Поєднує uart_tx і uart_rx зі спільними параметрами. Швидкість обміну
-- задається двома generic: CLK_FREQ (частота clk, Гц) та BAUD (біт/с);
-- кількість тактів на біт CLKS_PER_BIT = round(CLK_FREQ / BAUD).
-- За замовчуванням: 50 МГц, 115200 біт/с, 8N1 -> 434 такти на біт
-- (похибка швидкості 0.006 %).
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_top is
  generic (
    CLK_FREQ : positive := 50_000_000;    -- частота clk, Гц
    BAUD     : positive := 115_200;       -- швидкість, біт/с
    PARITY   : natural range 0 to 2 := 0  -- 0 none (8N1), 1 even, 2 odd
  );
  port (
    clk        : in  std_logic;
    rst_n      : in  std_logic;
    -- ---- передавач ----
    tx_start   : in  std_logic;                      -- імпульс: почати передачу
    tx_data    : in  std_logic_vector(7 downto 0);   -- байт для передачі
    tx_busy    : out std_logic;                      -- 1 = кадр передається
    tx_done    : out std_logic;                      -- імпульс: кадр передано
    txd        : out std_logic;                      -- послідовний вихід
    -- ---- приймач ----
    rxd        : in  std_logic;                      -- послідовний вхід
    rx_data    : out std_logic_vector(7 downto 0);   -- прийнятий байт
    rx_valid   : out std_logic;                      -- імпульс: байт прийнято
    rx_busy    : out std_logic;                      -- 1 = кадр приймається
    frame_err  : out std_logic;                      -- помилка стоп-біта
    parity_err : out std_logic                       -- помилка парності
  );
end entity uart_top;

architecture rtl of uart_top is
  constant CLKS_PER_BIT : positive := (CLK_FREQ + BAUD / 2) / BAUD;
begin

  u_tx : entity work.uart_tx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT, PARITY => PARITY)
    port map (clk => clk, rst_n => rst_n, tx_start => tx_start, tx_data => tx_data,
              txd => txd, tx_busy => tx_busy, tx_done => tx_done);

  u_rx : entity work.uart_rx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT, PARITY => PARITY)
    port map (clk => clk, rst_n => rst_n, rxd => rxd, rx_data => rx_data,
              rx_valid => rx_valid, frame_err => frame_err,
              parity_err => parity_err, rx_busy => rx_busy);

end architecture rtl;
