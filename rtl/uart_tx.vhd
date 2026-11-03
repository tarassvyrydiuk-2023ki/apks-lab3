-- =============================================================================
-- uart_tx.vhd -- передавач UART (Tx)
-- -----------------------------------------------------------------------------
-- Лабораторна робота №3, варіант 19 (UART, VHDL).
--
-- Кадр: START (0) | D0 .. D7 (молодший біт першим, LSB first) |
--       [PARITY] | STOP (1). Лінія у стані спокою -- 1.
-- Параметри:
--   CLKS_PER_BIT -- тактів clk на біт (CLK_FREQ / BAUD);
--   PARITY       -- 0: без парності (8N1), 1: парність (even, 8E1),
--                   2: непарність (odd, 8O1).
--
-- Автомат станів: IDLE -> START -> DATA -> [PARITY] -> STOP -> IDLE.
-- Перехід між станами відбувається за імпульсом tick генератора baud.
-- Інтерфейс: імпульс tx_start при tx_busy = 0 запускає передачу байта tx_data;
-- tx_busy = 1 протягом усього кадру; tx_done -- імпульс після стоп-біта.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
  generic (
    CLKS_PER_BIT : positive := 434;
    PARITY       : natural range 0 to 2 := 0
  );
  port (
    clk      : in  std_logic;                      -- системна тактова частота
    rst_n    : in  std_logic;                      -- синхронне скидання (0 = скинути)
    tx_start : in  std_logic;                      -- імпульс: почати передачу
    tx_data  : in  std_logic_vector(7 downto 0);   -- байт для передачі
    txd      : out std_logic;                      -- послідовний вихід TxD
    tx_busy  : out std_logic;                      -- 1 = іде передача кадру
    tx_done  : out std_logic                       -- імпульс: кадр передано
  );
end entity uart_tx;

architecture rtl of uart_tx is

  type state_t is (S_IDLE, S_START, S_DATA, S_PARITY, S_STOP);
  signal state : state_t := S_IDLE;

  signal shreg : std_logic_vector(7 downto 0) := (others => '0'); -- зсувний регістр
  signal bitn  : natural range 0 to 7 := 0;                       -- номер біта даних
  signal par_b : std_logic := '0';                                -- біт парності
  signal txd_r : std_logic := '1';                                -- регістр виходу TxD

  signal clr, tick, mid : std_logic;

  -- XOR-згортка байта: 1, якщо кількість одиниць непарна
  function xor_reduce8 (v : std_logic_vector(7 downto 0)) return std_logic is
    variable r : std_logic := '0';
  begin
    for i in v'range loop
      r := r xor v(i);
    end loop;
    return r;
  end function;

begin

  -- лічильник біта тримається в нулі, поки передавач вільний
  clr <= '1' when state = S_IDLE else '0';

  u_baud : entity work.uart_baud_gen
    generic map (DIV => CLKS_PER_BIT)
    port map (clk => clk, rst_n => rst_n, clr => clr, tick => tick, mid => mid);

  txd     <= txd_r;
  tx_busy <= '0' when state = S_IDLE else '1';

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state   <= S_IDLE;
        txd_r   <= '1';
        shreg   <= (others => '0');
        bitn    <= 0;
        par_b   <= '0';
        tx_done <= '0';
      else
        tx_done <= '0';                       -- tx_done -- одно-тактний імпульс

        case state is

          -- ---- очікування: лінія = 1; завантаження байта за tx_start ----
          when S_IDLE =>
            txd_r <= '1';
            if tx_start = '1' then
              shreg <= tx_data;
              bitn  <= 0;
              if PARITY = 1 then                 -- even: усього одиниць парне
                par_b <= xor_reduce8(tx_data);
              else                               -- odd: усього одиниць непарне
                par_b <= not xor_reduce8(tx_data);
              end if;
              txd_r <= '0';                      -- початок стартового біта
              state <= S_START;
            end if;

          -- ---- стартовий біт (0) триває рівно один бітовий інтервал ----
          when S_START =>
            if tick = '1' then
              txd_r <= shreg(0);                 -- D0
              shreg <= '0' & shreg(7 downto 1);  -- зсув праворуч (LSB first)
              bitn  <= 0;
              state <= S_DATA;
            end if;

          -- ---- 8 бітів даних, молодший першим ----
          when S_DATA =>
            if tick = '1' then
              if bitn = 7 then                   -- всі 8 бітів видано
                if PARITY /= 0 then
                  txd_r <= par_b;
                  state <= S_PARITY;
                else
                  txd_r <= '1';
                  state <= S_STOP;
                end if;
              else
                txd_r <= shreg(0);
                shreg <= '0' & shreg(7 downto 1);
                bitn  <= bitn + 1;
              end if;
            end if;

          -- ---- біт парності (лише якщо PARITY /= 0) ----
          when S_PARITY =>
            if tick = '1' then
              txd_r <= '1';
              state <= S_STOP;
            end if;

          -- ---- стоповий біт (1); після нього можна одразу починати новий кадр ----
          when S_STOP =>
            if tick = '1' then
              tx_done <= '1';
              state   <= S_IDLE;
            end if;

        end case;
      end if;
    end if;
  end process;

end architecture rtl;
