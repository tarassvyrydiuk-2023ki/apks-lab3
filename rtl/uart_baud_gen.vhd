-- =============================================================================
-- uart_baud_gen.vhd -- дільник тактової частоти (генератор baud-імпульсів)
-- -----------------------------------------------------------------------------
-- Лабораторна робота №3, варіант 19 (UART, VHDL).
--
-- Лічильник рахує такти clk від 0 до DIV-1, де DIV = CLK_FREQ / BAUD
-- (кількість тактів clk на один біт UART). Формує два одно-тактні імпульси:
--   tick -- кінець бітового інтервалу (лічильник = DIV-1);
--   mid  -- середина бітового інтервалу (лічильник = DIV/2-1), момент, коли
--           приймач зчитує лінію RxD (найдалі від фронтів, тому найстійкіше).
-- Вхід clr = '1' утримує лічильник у нулі: так приймач прив'язує відлік до
-- переднього фронту стартового біта, а передавач -- до моменту запуску.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_baud_gen is
  generic (
    DIV : positive := 434               -- тактів clk на один біт
  );
  port (
    clk   : in  std_logic;              -- системна тактова частота
    rst_n : in  std_logic;              -- синхронне скидання, активний рівень 0
    clr   : in  std_logic;              -- 1 = обнулити та зупинити лічильник
    tick  : out std_logic;              -- імпульс: кінець біта
    mid   : out std_logic               -- імпульс: середина біта
  );
end entity uart_baud_gen;

architecture rtl of uart_baud_gen is
  constant HALF : natural := DIV / 2 - 1;      -- відлік середини біта
  signal cnt    : natural range 0 to DIV - 1 := 0;
begin

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' or clr = '1' then
        cnt <= 0;
      elsif cnt = DIV - 1 then
        cnt <= 0;
      else
        cnt <= cnt + 1;
      end if;
    end if;
  end process;

  -- вихідні імпульси -- комбінаційні порівняння; при clr = '1' заблоковані
  tick <= '1' when (cnt = DIV - 1 and clr = '0') else '0';
  mid  <= '1' when (cnt = HALF    and clr = '0') else '0';

end architecture rtl;
