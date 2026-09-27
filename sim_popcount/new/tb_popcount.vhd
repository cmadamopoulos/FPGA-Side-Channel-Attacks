library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity tb_popcount is
end entity tb_popcount;

architecture sim of tb_popcount is

    constant CLK_PERIOD : time    := 10 ns;
    constant WIDTH      : integer := 128;

    signal clk  : std_logic := '0';
    signal rst  : std_logic := '1';
    signal d    : std_logic_vector(WIDTH - 1 downto 0) := (others => '0');
    signal hw   : std_logic_vector(7 downto 0);

    signal errors : integer := 0;
    signal done   : boolean := false;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done else '0';

    dut : entity work.popcount
        generic map (WIDTH => WIDTH)
        port map (clk => clk, rst => rst, d => d, hw => hw);

    stim : process
        variable err : integer := 0;

        -- drive a vector, wait one cycle for the registered output, check it.
        -- The parameter is constrained (not a bare std_logic_vector) so that
        -- calls can pass (others => '0'): an aggregate needs a bounded target.
        procedure check (v : in std_logic_vector(WIDTH - 1 downto 0); want : in integer; msg : in string) is
        begin
            d <= v;
            wait until falling_edge(clk);   -- output registered on the rising edge just passed
            if to_integer(unsigned(hw)) /= want then
                err := err + 1;
                report "FAIL @" & time'image(now) & " : " & msg &
                       " (expected " & integer'image(want) &
                       ", got " & integer'image(to_integer(unsigned(hw))) & ")"
                    severity error;
            end if;
        end procedure check;

        variable v : std_logic_vector(WIDTH - 1 downto 0);
        variable n : integer;
    begin
        wait until falling_edge(clk);
        rst <= '0';

        check((others => '0'), 0,     "all zeros");
        check((others => '1'), WIDTH, "all ones");

        -- exactly one bit
        v := (others => '0'); v(0)  := '1'; check(v, 1, "single bit low");
        v := (others => '0'); v(64) := '1'; check(v, 1, "single bit mid");
        v := (others => '0'); v(WIDTH - 1) := '1'; check(v, 1, "single bit high");

        -- a known thermometer code: bottom 50 bits set
        v := (others => '0');
        for i in 0 to 49 loop v(i) := '1'; end loop;
        check(v, 50, "thermometer of 50");

        -- pseudo-random vectors against an independently counted reference
        for t in 0 to 49 loop
            n := 0;
            for i in 0 to WIDTH - 1 loop
                if ((i * 2749 + t * 179) mod 7) = 0 then
                    v(i) := '1'; n := n + 1;
                else
                    v(i) := '0';
                end if;
            end loop;
            check(v, n, "random vector " & integer'image(t));
        end loop;

        errors <= err;
        report "tb_popcount finished with " & integer'image(err) & " error(s)" severity note;
        assert err = 0 report "tb_popcount FAILED" severity error;

        done <= true;
        wait;
    end process stim;

end architecture sim;