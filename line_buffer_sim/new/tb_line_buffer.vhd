library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

use work.conv_pkg.all;

entity tb_line_buffer is
end entity tb_line_buffer;

architecture sim of tb_line_buffer is

    constant CLK_PERIOD : time := 10 ns;

    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal ce       : std_logic := '0';
    signal clr      : std_logic := '0';
    signal pixel_in : std_logic_vector(PIX_W - 1 downto 0) := (others => '0');
    signal win_out  : pix_array;

    signal errors   : integer := 0;
    signal done     : boolean := false;

    -- the value we feed for pixel index n
    function pix_of (n : integer) return integer is
    begin
        return n mod 256;
    end function pix_of;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done else '0';

    dut : entity work.line_buffer
        port map (
            clk      => clk,
            rst      => rst,
            ce       => ce,
            clr => clr,
            pixel_in => pixel_in,
            win_out  => win_out
        );

    stim : process
        variable err : integer := 0;

        -- Checks the nine taps against the pixels they should hold,
        -- given that pixel index `newest` was the last one shifted in.
        procedure check_window (newest : in integer; tag : in string) is            variable want : integer;
        begin
            for j in 0 to K_TAPS - 1 loop
                if newest - TAP_OFFSET(j) >= 0 then
                    want := pix_of(newest - TAP_OFFSET(j));
                else
                    want := 0;            -- still reset content
                end if;
                if to_integer(unsigned(win_out(j))) /= want then
                    err := err + 1;
                    report "FAIL @" & time'image(now) & " " & tag &
                           " tap " & integer'image(j) &
                           " expected " & integer'image(want) &
                           " got " & integer'image(to_integer(unsigned(win_out(j))))
                        severity error;
                end if;
            end loop;
        end procedure check_window;

        -- shift one pixel in; on return, `newest` has entered the chain
        procedure push (v : in integer) is
        begin
            pixel_in <= std_logic_vector(to_unsigned(v, PIX_W));
            ce       <= '1';
            wait until falling_edge(clk);
        end procedure push;

    begin
        wait until falling_edge(clk);

        ----------------------------------------------------------------
        report "TEST 1: reset clears every stage" severity note;
        ----------------------------------------------------------------
        rst <= '1';
        wait until falling_edge(clk);
        for j in 0 to K_TAPS - 1 loop
            if to_integer(unsigned(win_out(j))) /= 0 then
                err := err + 1;
                report "FAIL: tap " & integer'image(j) & " not cleared"
                    severity error;
            end if;
        end loop;
        rst <= '0';

        ----------------------------------------------------------------
        report "TEST 2: fill the chain and check every tap each cycle"
            severity note;
        ----------------------------------------------------------------
        -- Push 200 pixels. From n = 83 onwards the window is entirely
        -- real data; before that the deeper taps are still reset zeros.
        for n in 0 to 199 loop
            push(pix_of(n));
            check_window(n, "fill n=" & integer'image(n));
        end loop;

        ----------------------------------------------------------------
        report "TEST 3: the window is a genuine 3x3 image neighbourhood"
            severity note;
        ----------------------------------------------------------------
        -- At n = 83 the window must be image rows 0,1,2 columns 0,1,2
        -- of a 28-wide image, i.e. pixels 0,1,2 / 28,29,30 / 56,57,58.
        -- (Already covered by TEST 2, restated here as an explicit check
        --  because it is the property that actually matters.)
        for r in 0 to K_DIM - 1 loop
            for c in 0 to K_DIM - 1 loop
                if TAP_OFFSET(r * K_DIM + c) /= (K_DIM - r) * IMG_W - 1 - c then
                    err := err + 1;
                    report "FAIL: TAP_OFFSET geometry is wrong at r=" &
                           integer'image(r) & " c=" & integer'image(c)
                        severity error;
                end if;
            end loop;
        end loop;

        ----------------------------------------------------------------
        report "TEST 4: clock enable freezes the chain" severity note;
        ----------------------------------------------------------------
        ce       <= '0';
        pixel_in <= x"AA";
        for i in 1 to 5 loop
            wait until falling_edge(clk);
            check_window(199, "frozen");     -- must not have moved
        end loop;
        ce <= '1';

----------------------------------------------------------------
        report "TEST 5: asynchronous reset acts between clock edges"
            severity note;
        ----------------------------------------------------------------
        rst <= '1';
        wait for CLK_PERIOD / 4;
        for j in 0 to K_TAPS - 1 loop
            if to_integer(unsigned(win_out(j))) /= 0 then
                err := err + 1;
                report "FAIL: reset is not asynchronous" severity error;
            end if;
        end loop;
        wait until falling_edge(clk);
        rst <= '0';
        ce  <= '0';

        ----------------------------------------------------------------
        report "TEST 6: synchronous clear empties the chain" severity note;
        ----------------------------------------------------------------
        ce <= '1';
        for n in 0 to 99 loop
            push(pix_of(n));
        end loop;
        clr <= '1';
        wait until falling_edge(clk);
        clr <= '0';
        for j in 0 to K_TAPS - 1 loop
            if to_integer(unsigned(win_out(j))) /= 0 then
                err := err + 1;
                report "FAIL: clr did not empty tap " & integer'image(j)
                    severity error;
            end if;
        end loop;
        ce <= '0';

        ----------------------------------------------------------------
        errors <= err;
        report "tb_line_buffer finished with " & integer'image(err) &
               " error(s)" severity note;
        assert err = 0 report "tb_line_buffer FAILED" severity error;

        done <= true;
        wait;
    end process stim;

end architecture sim;