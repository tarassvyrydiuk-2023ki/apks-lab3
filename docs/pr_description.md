## lab2/testbench -- UART (варіант 19, VHDL)

Тестбенч `tb/tb_uart.vhd`: CLK 50 МГц, RESET, незалежний декодер TxD, модель зовнішнього
пристрою для RxD, loopback. Результат: `TEST PASSED (32 checks)` для 8N1 і `(37 checks)` для 8E1/8O1.

Тести: T1 Tx 0x55 · T2 потік Tx · T3 прийом · T4 потік Rx · T5 помилка кадру · T6 хибний старт ·
T7 допуск на відхилення baud · T8 парність · T9 loopback 0..255 · T10 скидання посеред кадру.

Осцилограми: `docs/waves/*.png` (додати скріншоти в цей опис). Діаграми FSM: `docs/fsm/*.png`.

Reviewer: @andrii-s-spitzer-lpnu-ua
