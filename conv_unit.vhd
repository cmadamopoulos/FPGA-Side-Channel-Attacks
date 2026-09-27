library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

use work.conv_pkg.all;

entity conv_unit is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        win       : in  pix_array;                               -- 9 x 8-bit unsigned
        kern      : in  std_logic_vector(K_TAPS - 1 downto 0);   -- 1 = +1, 0 = -1
        valid_in  : in  std_logic;
        result    : out std_logic_vector(ACC_W - 1 downto 0);    -- 13-bit signed
        valid_out : out std_logic
    );
end entity conv_unit;

architecture rtl of conv_unit is

    type acc_array is array (natural range <>) of signed(ACC_W - 1 downto 0);

    signal term : acc_array(0 to K_TAPS - 1);
    signal lvl1 : acc_array(0 to 4);
    signal lvl2 : acc_array(0 to 2);
    signal lvl3 : acc_array(0 to 1);
    signal lvl4 : signed(ACC_W - 1 downto 0);

begin

    ------------------------------------------------------------------
    -- Sign selection. A binary kernel needs no multiplier: each pixel
    -- is either added or subtracted.
    --
    -- '0' & win(j) widens the unsigned 8-bit pixel to 9 bits before it
    -- is reinterpreted as signed, so 255 stays +255 instead of becoming
    -- -1. Getting this wrong is the classic signed/unsigned bug and it
    -- only shows up on pixels above 127.
    ------------------------------------------------------------------
    gen_terms : for j in 0 to K_TAPS - 1 generate
        term(j) <=  resize(signed('0' & win(j)), ACC_W) when kern(j) = '1'
               else -resize(signed('0' & win(j)), ACC_W);
    end generate gen_terms;

    ------------------------------------------------------------------
    -- Balanced combinational adder tree, four levels deep for 9 terms.
    -- Written out explicitly rather than as an accumulate loop so the
    -- structure - and therefore the critical path - is visible.
    ------------------------------------------------------------------
    lvl1(0) <= term(0) + term(1);
    lvl1(1) <= term(2) + term(3);
    lvl1(2) <= term(4) + term(5);
    lvl1(3) <= term(6) + term(7);
    lvl1(4) <= term(8);

    lvl2(0) <= lvl1(0) + lvl1(1);
    lvl2(1) <= lvl1(2) + lvl1(3);
    lvl2(2) <= lvl1(4);

    lvl3(0) <= lvl2(0) + lvl2(1);
    lvl3(1) <= lvl2(2);

    lvl4    <= lvl3(0) + lvl3(1);

    ------------------------------------------------------------------
    -- Output register. valid travels with the data through the same
    -- register, so the two can never drift apart.
    ------------------------------------------------------------------
    process (clk, rst)
    begin
        if rst = '1' then
            result    <= (others => '0');
            valid_out <= '0';
        elsif rising_edge(clk) then
            result    <= std_logic_vector(lvl4);
            valid_out <= valid_in;
        end if;
    end process;

end architecture rtl;