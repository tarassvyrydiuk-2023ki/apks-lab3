-- =============================================================================
-- uart_rx.vhd -- приймач UART (Rx)
-- -----------------------------------------------------------------------------
-- Лабораторна робота №3, варіант 19 (UART, VHDL).
--
-- Алгоритм: вхід RxD синхронізується двома тригерами (захист від
-- метастабільності). Передній фронт 1 -> 0 вказує на початок стартового біта;
-- лічильник baud обнуляється й далі кожен біт зчитується в його СЕРЕДИНІ
-- (імпульс mid). Через пів біта стартовий біт перевіряється ще раз: якщо
-- лінія вже 1 -- це завада, а не старт, і приймач повертається в IDLE.
-- Автомат станів: IDLE -> START -> DATA -> [PARITY] -> STOP -> IDLE.
--
-- Виходи: rx_data + імпульс rx_valid; frame_err = 1, якщо стоп-біт = 0;
-- parity_err = 1, якщо біт парності не збігся (лише при PARITY /= 0).
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
  generic (
    CLKS_PER_BIT : positive := 434;
    PARITY       : natural range 0 to 2 := 0     -- 0 none, 1 even, 2 odd
  );
  port (
    clk        : in  std_logic;                      -- системна тактова частота
    rst_n      : in  std_logic;                      -- синхронне скидання (0 = скинути)
    rxd        : in  std_logic;                      -- послідовний вхід RxD (асинхронний)
    rx_data    : out std_logic_vector(7 downto 0);   -- прийнятий байт
    rx_valid   : out std_logic;                      -- імпульс: rx_data дійсний
    frame_err  : out std_logic;                      -- 1 = стоп-біт не дорівнює 1
    parity_err : out std_logic;                      -- 1 = помилка парності
    rx_busy    : out std_logic                       -- 1 = іде прийом кадру
  );
end entity uart_rx;

architecture rtl of uart_rx is

  type state_t is (S_IDLE, S_START, S_DATA, S_PARITY, S_STOP);
  signal state : state_t := S_IDLE;

  signal sync    : std_logic_vector(1 downto 0) := "11"; -- синхронізатор RxD
  signal rxd_s   : std_logic;                            -- синхронізований RxD
  signal rxd_p   : std_logic := '1';                     -- попереднє значення (пошук фронту)
  signal shreg   : std_logic_vector(7 downto 0) := (others => '0');
  signal bitn    : natural range 0 to 7 := 0;
  signal par_bad : std_logic := '0';

  signal clr, tick, mid : std_logic;

  function xor_reduce8 (v : std_logic_vector(7 downto 0)) return std_logic is
    variable r : std_logic := '0';
  begin
    for i in v'range loop
      r := r xor v(i);
    end loop;
    return r;
  end function;

begin

  rxd_s <= sync(1);
  clr   <= '1' when state = S_IDLE else '0';

  u_baud : entity work.uart_baud_gen
    generic map (DIV => CLKS_PER_BIT)
    port map (clk => clk, rst_n => rst_n, clr => clr, tick => tick, mid => mid);

  rx_busy <= '0' when state = S_IDLE else '1';

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        sync       <= "11";
        rxd_p      <= '1';
        state      <= S_IDLE;
        shreg      <= (others => '0');
        bitn       <= 0;
        rx_data    <= (others => '0');
        rx_valid   <= '0';
        frame_err  <= '0';
        parity_err <= '0';
        par_bad    <= '0';
      else
        sync     <= sync(0) & rxd;
        rxd_p    <= rxd_s;
        rx_valid <= '0';                         -- rx_valid -- одно-тактний імпульс

        case state is

          -- ---- очікування переднього фронту (1 -> 0) стартового біта ----
          when S_IDLE =>
            if rxd_p = '1' and rxd_s = '0' then
              state <= S_START;
            end if;

          -- ---- середина стартового біта: лінія все ще 0? ----
          when S_START =>
            if mid = '1' then
              if rxd_s = '0' then
                bitn  <= 0;
                state <= S_DATA;
              else
                state <= S_IDLE;                 -- завада, не старт
              end if;
            end if;

          -- ---- зчитування бітів даних у середині бітових інтервалів ----
          when S_DATA =>
            if mid = '1' then
              shreg <= rxd_s & shreg(7 downto 1);  -- LSB першим -> зсув праворуч
              if bitn = 7 then
                if PARITY /= 0 then
                  state <= S_PARITY;
                else
                  state <= S_STOP;
                end if;
              else
                bitn <= bitn + 1;
              end if;
            end if;

          -- ---- біт парності ----
          when S_PARITY =>
            if mid = '1' then
              if PARITY = 1 then                 -- even: очікуємо xor(data)
                par_bad <= rxd_s xor xor_reduce8(shreg);
              else                               -- odd: очікуємо not xor(data)
                par_bad <= rxd_s xor (not xor_reduce8(shreg));
              end if;
              state <= S_STOP;
            end if;

          -- ---- стоповий біт: видати байт і одразу чекати наступний старт ----
          when S_STOP =>
            if mid = '1' then
              rx_data    <= shreg;
              rx_valid   <= '1';
              frame_err  <= not rxd_s;           -- стоп-біт має бути 1
              parity_err <= par_bad;
              par_bad    <= '0';
              state      <= S_IDLE;              -- далі шукаємо новий фронт
            end if;

        end case;
      end if;
    end if;
  end process;

end architecture rtl;
