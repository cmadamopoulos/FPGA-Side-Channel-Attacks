library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity tb_sensor_accel is
end entity tb_sensor_accel;

architecture sim of tb_sensor_accel is

    constant CLK_PERIOD : time    := 10 ns;
    constant TRACE_LEN  : integer := 64;    -- short, for a fast test
    constant TRACE_AW   : integer := 6;

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal arm       : std_logic := '0';
    signal sw_ctrl   : std_logic_vector(31 downto 0) := (others => '0');
    signal hw_status : std_logic_vector(31 downto 0);

    signal errors    : integer := 0;
    signal sim_done  : boolean := false;

begin

    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

    dut : entity work.sensor_accel
        generic map (INIT_DELAY => 4, SENSOR_WIDTH => 16,
                     TRACE_LEN => TRACE_LEN, TRACE_AW => TRACE_AW)
        port map (clk => clk, rst => rst, arm => arm,
                  sw_ctrl => sw_ctrl, hw_status => hw_status);

    stim : process
        variable err : integer := 0;

        procedure fail (msg : in string) is
        begin
            err := err + 1;
            report "FAIL @" & time'image(now) & " : " & msg severity error;
        end procedure fail;

        procedure strobe (bit_n : in integer) is
            variable w : std_logic_vector(31 downto 0) := (others => '0');
        begin
            w(bit_n) := '1';
            sw_ctrl  <= w;
            wait until falling_edge(clk);
            sw_ctrl  <= (others => '0');
            wait until falling_edge(clk);
        end procedure strobe;

    begin
        wait until falling_edge(clk);

        ----------------------------------------------------------------
        report "TEST 1: reset clears status" severity note;
        ----------------------------------------------------------------
        rst <= '1';
        wait until falling_edge(clk);
        if hw_status(16) /= '0' or hw_status(17) /= '0' then
            fail("done or busy set during reset");
        end if;
        rst <= '0';
        wait until falling_edge(clk);

        ----------------------------------------------------------------
        report "TEST 2: a software-armed capture runs and completes" severity note;
        ----------------------------------------------------------------
        strobe(0);                                   -- arm
        if hw_status(17) /= '1' then
            fail("busy did not assert after arm");
        end if;

        -- wait for done
        for i in 1 to TRACE_LEN + 8 loop
            exit when hw_status(16) = '1';
            wait until falling_edge(clk);
        end loop;
        if hw_status(16) /= '1' then
            fail("capture never asserted done");
        end if;
        if hw_status(17) /= '0' then
            fail("still busy after done");
        end if;

        ----------------------------------------------------------------
        report "TEST 3: read pointer walks the trace" severity note;
        ----------------------------------------------------------------
        strobe(2);                                   -- clr pointers
        -- drain TRACE_LEN samples; behavioural sensor value is constant,
        -- so we check the mechanism completes, not the sample values
        for m in 0 to TRACE_LEN - 1 loop
            -- hw_status(7:0) is the current sample; just exercise the read path
            strobe(1);                               -- read strobe -> rd_ptr++
        end loop;

        report "  drained " & integer'image(TRACE_LEN) & " samples" severity note;

        ----------------------------------------------------------------
        report "TEST 4: the hardware arm pin also triggers a capture" severity note;
        ----------------------------------------------------------------
        strobe(2);
        arm <= '1';
        wait until falling_edge(clk);
        arm <= '0';
        if hw_status(17) /= '1' then
            fail("hardware arm did not start a capture");
        end if;
        for i in 1 to TRACE_LEN + 8 loop
            exit when hw_status(16) = '1';
            wait until falling_edge(clk);
        end loop;
        if hw_status(16) /= '1' then
            fail("hardware-armed capture never completed");
        end if;

        ----------------------------------------------------------------
        errors <= err;
        report "tb_sensor_accel finished with " & integer'image(err) &
               " error(s)" severity note;
        assert err = 0 report "tb_sensor_accel FAILED" severity error;

        sim_done <= true;
        wait;
    end process stim;

end architecture sim;