library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

use work.conv_pkg.all;

entity tb_conv_unit is
end entity tb_conv_unit;

architecture sim of tb_conv_unit is

    constant CLK_PERIOD : time := 10 ns;

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal win       : pix_array := (others => (others => '0'));
    signal kern      : std_logic_vector(K_TAPS - 1 downto 0) := (others => '0');
    signal valid_in  : std_logic := '0';
    signal result    : std_logic_vector(ACC_W - 1 downto 0);
    signal valid_out : std_logic;


    signal errors    : integer := 0;
    signal done      : boolean := false;

    type int9 is array (0 to K_TAPS - 1) of integer;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done else '0';

    dut : entity work.conv_unit
        port map (
            clk => clk, rst => rst, win => win, kern => kern,
            valid_in => valid_in, result => result, valid_out => valid_out
        );

    stim : process
        variable err : integer := 0;

                function expected (pix : int9;
                           k   : std_logic_vector(K_TAPS - 1 downto 0))
            return integer is
            variable s : integer := 0;
        begin
            for j in 0 to K_TAPS - 1 loop
                if k(j) = '1' then
                    s := s + pix(j);
                else
                    s := s - pix(j);
                end if;
            end loop;
            return s;
        end function expected;

        -- Apply a window and kernel for one cycle. On return, `result`
        -- holds the answer for those inputs.
        procedure apply (pix : in int9;
                         k   : in std_logic_vector(K_TAPS - 1 downto 0);
                         v   : in std_logic) is
        begin
            for j in 0 to K_TAPS - 1 loop
                win(j) <= std_logic_vector(to_unsigned(pix(j), PIX_W));
            end loop;
            kern     <= k;
            valid_in <= v;
            wait until falling_edge(clk);
        end procedure apply;

        procedure check (want : in integer; msg : in string) is
            variable got : integer;
        begin
            got := to_integer(signed(result));
            if got /= want then
                err := err + 1;
                report "FAIL @" & time'image(now) & " : " & msg &
                       " (expected " & integer'image(want) &
                       ", got " & integer'image(got) & ")"
                    severity error;
            end if;
        end procedure check;

        variable p : int9;
        variable k : std_logic_vector(K_TAPS - 1 downto 0);


    begin
        wait until falling_edge(clk);

        ----------------------------------------------------------------
        report "TEST 1: reset" severity note;
        ----------------------------------------------------------------
        rst <= '1';
        wait until falling_edge(clk);
        check(0, "result not cleared by reset");
        if valid_out /= '0' then
            err := err + 1;
            report "FAIL: valid_out set during reset" severity error;
        end if;
        rst <= '0';

        ----------------------------------------------------------------
        report "TEST 2: all +1 kernel is a 3x3 box sum" severity note;
        ----------------------------------------------------------------
        p := (10, 20, 30, 40, 50, 60, 70, 80, 90);
        apply(p, (others => '1'), '1');
        check(450, "box sum");

        ----------------------------------------------------------------
        report "TEST 3: all -1 kernel negates it" severity note;
        ----------------------------------------------------------------
        apply(p, (others => '0'), '1');
        check(-450, "negated box sum");

        ----------------------------------------------------------------
        report "TEST 4: pixels above 127 must stay positive" severity note;
        ----------------------------------------------------------------
        -- This is the signed/unsigned trap. If the pixel were cast to
        -- signed without widening, 255 would become -1 and the answer
        -- would be -9 instead of 2295.
        p := (255, 255, 255, 255, 255, 255, 255, 255, 255);
        apply(p, (others => '1'), '1');
        check(2295, "maximum positive - are pixels being sign-extended?");

        ----------------------------------------------------------------
        report "TEST 5: worst case proves ACC_W is wide enough"
            severity note;
        ----------------------------------------------------------------
        -- +2295 needs 13 bits signed (12 bits only reaches 2047).
        apply(p, (others => '0'), '1');
        check(-2295, "maximum negative");
        report "  range required: -2295 .. +2295, ACC_W = " &
               integer'image(ACC_W) & " covers " &
               integer'image(-(2 ** (ACC_W - 1))) & " .. " &
               integer'image(2 ** (ACC_W - 1) - 1)
            severity note;

        ----------------------------------------------------------------
        report "TEST 6: mixed kernel, and tap ordering" severity note;
        ----------------------------------------------------------------
        -- Distinct powers of two make any tap-ordering error obvious.
        p := (1, 2, 4, 8, 16, 32, 64, 128, 255);
        apply(p, "000010101", '1');   -- kern(0),(2),(4) are '1'
        check(expected(p, "000010101"), "mixed kernel");

        -- walk a single +1 through all nine positions
        -- walk a single +1 through all nine positions
        for j in 0 to K_TAPS - 1 loop
            k    := (others => '0');
            k(j) := '1';
            apply(p, k, '1');
            check(expected(p, k),
                  "single +1 at position " & integer'image(j));
        end loop;
        
        ----------------------------------------------------------------
        report "TEST 7: zero window" severity note;
        ----------------------------------------------------------------
        p := (others => 0);
        apply(p, "101010101", '1');
        check(0, "zero window");

        ----------------------------------------------------------------
        report "TEST 8: valid travels with the data" severity note;
        ----------------------------------------------------------------
        p := (1, 1, 1, 1, 1, 1, 1, 1, 1);
        apply(p, (others => '1'), '0');
        if valid_out /= '0' then
            err := err + 1;
            report "FAIL: valid_out high when valid_in was low"
                severity error;
        end if;
        check(9, "result is still computed when valid is low");
        apply(p, (others => '1'), '1');
        if valid_out /= '1' then
            err := err + 1;
            report "FAIL: valid_out did not follow valid_in" severity error;
        end if;
        valid_in <= '0';

        ----------------------------------------------------------------
        report "TEST 9: the output is registered, not combinational"
            severity note;
        ----------------------------------------------------------------
        p := (5, 5, 5, 5, 5, 5, 5, 5, 5);
        for j in 0 to K_TAPS - 1 loop
            win(j) <= std_logic_vector(to_unsigned(p(j), PIX_W));
        end loop;
        kern <= (others => '1');
        wait for CLK_PERIOD / 4;          -- still before the next rising edge
        check(9, "output changed before a clock edge");
        wait until falling_edge(clk);
        check(45, "output did not update one cycle later");

        ----------------------------------------------------------------
        errors <= err;
        report "tb_conv_unit finished with " & integer'image(err) &
               " error(s)" severity note;
        assert err = 0 report "tb_conv_unit FAILED" severity error;

        done <= true;
        wait;
    end process stim;

end architecture sim;