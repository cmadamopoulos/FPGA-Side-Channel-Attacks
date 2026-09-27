library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity tb_dp_ram is
end entity tb_dp_ram;

architecture sim of tb_dp_ram is

    constant CLK_PERIOD : time := 10 ns;
    constant DW : integer := 16;
    constant AW : integer := 6;          -- small, so the test runs quickly

    signal clk   : std_logic := '0';
    signal we    : std_logic := '0';
    signal waddr : std_logic_vector(AW - 1 downto 0) := (others => '0');
    signal din   : std_logic_vector(DW - 1 downto 0) := (others => '0');
    signal raddr : std_logic_vector(AW - 1 downto 0) := (others => '0');
    signal dout  : std_logic_vector(DW - 1 downto 0);

    signal errors : integer := 0;
    signal done   : boolean := false;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done else '0';

    dut : entity work.dp_ram
        generic map (DATA_W => DW, ADDR_W => AW)
        port map (clk => clk, we => we, waddr => waddr, din => din,
                  raddr => raddr, dout => dout);

    stim : process
        variable err : integer := 0;

        procedure wr (a : in integer; v : in integer) is
        begin
            waddr <= std_logic_vector(to_unsigned(a, AW));
            din   <= std_logic_vector(to_unsigned(v, DW));
            we    <= '1';
            wait until falling_edge(clk);
            we    <= '0';
        end procedure wr;

        procedure rd (a : in integer) is
        begin
            raddr <= std_logic_vector(to_unsigned(a, AW));
            wait until falling_edge(clk);
        end procedure rd;

        procedure check (want : in integer; msg : in string) is
        begin
            if to_integer(unsigned(dout)) /= want then
                err := err + 1;
                report "FAIL @" & time'image(now) & " : " & msg &
                       " (expected " & integer'image(want) &
                       ", got " & integer'image(to_integer(unsigned(dout))) & ")"
                    severity error;
            end if;
        end procedure check;

    begin
        wait until falling_edge(clk);

        ----------------------------------------------------------------
        report "TEST 1: memory powers up zeroed" severity note;
        ----------------------------------------------------------------
        for a in 0 to 2 ** AW - 1 loop
            rd(a);
            check(0, "location " & integer'image(a) & " not zero at power-up");
        end loop;

        ----------------------------------------------------------------
        report "TEST 2: write then read back every location" severity note;
        ----------------------------------------------------------------
        for a in 0 to 2 ** AW - 1 loop
            wr(a, (a * 7 + 3) mod 2 ** DW);
        end loop;
        for a in 0 to 2 ** AW - 1 loop
            rd(a);
            check((a * 7 + 3) mod 2 ** DW,
                  "readback of location " & integer'image(a));
        end loop;

        ----------------------------------------------------------------
        report "TEST 3: read latency is exactly one cycle" severity note;
        ----------------------------------------------------------------
        rd(0);
        check(3, "setup");
        raddr <= std_logic_vector(to_unsigned(5, AW));
        wait for CLK_PERIOD / 4;          -- before the next rising edge
        check(3, "dout changed combinationally - read is not registered");
        wait until falling_edge(clk);
        check((5 * 7 + 3) mod 2 ** DW, "dout did not update after one cycle");

        ----------------------------------------------------------------
        report "TEST 4: writing one address does not disturb another"
            severity note;
        ----------------------------------------------------------------
        wr(10, 16#BEEF#);
        rd(11);
        check((11 * 7 + 3) mod 2 ** DW, "neighbour corrupted by a write");
        rd(10);
        check(16#BEEF#, "written value not stored");

        ----------------------------------------------------------------
        report "TEST 5: independent read and write addresses" severity note;
        ----------------------------------------------------------------
        raddr <= std_logic_vector(to_unsigned(20, AW));
        wr(30, 16#1234#);
        wait until falling_edge(clk);
        check((20 * 7 + 3) mod 2 ** DW,
              "read port disturbed by a write elsewhere");

        ----------------------------------------------------------------
        errors <= err;
        report "tb_dp_ram finished with " & integer'image(err) &
               " error(s)" severity note;
        assert err = 0 report "tb_dp_ram FAILED" severity error;

        done <= true;
        wait;
    end process stim;

end architecture sim;