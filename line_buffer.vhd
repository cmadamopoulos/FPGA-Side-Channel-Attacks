library IEEE;
use IEEE.STD_LOGIC_1164.all;

use work.conv_pkg.all;

entity line_buffer is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        clr      : in  std_logic;                               -- NEW
        ce       : in  std_logic;
        pixel_in : in  std_logic_vector(PIX_W - 1 downto 0);
        win_out  : out pix_array
    );
end entity line_buffer;

architecture rtl of line_buffer is
    type chain_t is array (0 to LB_DEPTH - 1)
        of std_logic_vector(PIX_W - 1 downto 0);
    signal chain : chain_t;
begin

    ------------------------------------------------------------------
    -- One long shift register. chain(i) holds the pixel from i cycles
    -- ago, so chain(0..27) is row 0, chain(28..55) row 1, chain(56..83)
    -- row 2 - exactly the paper's arrangement, where the rightmost word
    -- of each row feeds the next row from the left and the rightmost
    -- word of the last row is discarded.
    ------------------------------------------------------------------
    process (clk, rst)
    begin
        if rst = '1' then
            chain <= (others => (others => '0'));
        elsif rising_edge(clk) then
            if clr = '1' then
                -- synchronous flush, so every run starts from a known state
                chain <= (others => (others => '0'));
            elsif ce = '1' then
                chain(0) <= pixel_in;
                for i in 1 to LB_DEPTH - 1 loop
                    chain(i) <= chain(i - 1);
                end loop;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Nine taps: the rightmost three words of each of the three rows
    ------------------------------------------------------------------
    gen_taps : for j in 0 to K_TAPS - 1 generate
        win_out(j) <= chain(TAP_OFFSET(j));
    end generate gen_taps;

end architecture rtl;