library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity popcount is
    generic (
        WIDTH : integer := 128
    );
    port (
        clk : in  std_logic;
        rst : in  std_logic;
        d   : in  std_logic_vector(WIDTH - 1 downto 0);
        hw  : out std_logic_vector(7 downto 0)      -- 0 .. 128 fits in 8 bits
    );
end entity popcount;

architecture rtl of popcount is
begin

    ------------------------------------------------------------------
    -- Registered Hamming weight. The loop is unrolled at elaboration
    -- into an adder tree, exactly like conv_unit's, and synthesis
    -- balances it. One register stage so it is never on a long
    -- combinational path from the sensor into the capture RAM.
    ------------------------------------------------------------------
    process (clk, rst)
        variable acc : integer range 0 to WIDTH;
    begin
        if rst = '1' then
            hw <= (others => '0');
        elsif rising_edge(clk) then
            acc := 0;
            for i in d'range loop
                if d(i) = '1' then
                    acc := acc + 1;
                end if;
            end loop;
            hw <= std_logic_vector(to_unsigned(acc, hw'length));
        end if;
    end process;

end architecture rtl;