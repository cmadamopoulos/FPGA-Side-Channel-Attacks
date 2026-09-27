library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

use work.conv_pkg.all;

entity tb_conv_ctrl is
end entity tb_conv_ctrl;

architecture sim of tb_conv_ctrl is

    constant CLK_PERIOD : time := 10 ns;

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';

    signal wr_pulse     : std_logic := '0';
    signal wr_data      : std_logic_vector(PIX_W - 1 downto 0) := (others => '0');
    signal rd_pulse     : std_logic := '0';
    signal start_pulse  : std_logic := '0';
    signal clr_pulse    : std_logic := '0';

    signal img_we       : std_logic;
    signal img_waddr    : std_logic_vector(MEM_AW - 1 downto 0);
    signal img_wdata    : std_logic_vector(PIX_W - 1 downto 0);
    signal img_raddr    : std_logic_vector(MEM_AW - 1 downto 0);
    signal img_rdata    : std_logic_vector(PIX_W - 1 downto 0) := (others => '0');

    signal out_we       : std_logic;
    signal out_waddr    : std_logic_vector(MEM_AW - 1 downto 0);
    signal out_raddr    : std_logic_vector(MEM_AW - 1 downto 0);

    signal lb_ce        : std_logic;
    signal lb_clr       : std_logic;
    signal lb_pixel     : std_logic_vector(PIX_W - 1 downto 0);

    signal cv_valid_in  : std_logic;
    signal cv_valid_out : std_logic := '0';

    signal busy         : std_logic;
    signal done_s       : std_logic;
    signal wr_ptr_o     : std_logic_vector(MEM_AW - 1 downto 0);

    signal errors       : integer := 0;
    signal sim_done     : boolean := false;

    -- counts out_we pulses and remembers the addresses they used
    signal count_rst   : std_logic := '0';   -- driven by stim only
    signal write_count : integer := 0;       -- driven by out_watch only
    signal addr_ok     : boolean := true;    -- driven by out_watch only

begin

    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

    dut : entity work.conv_ctrl
        port map (
            clk => clk, rst => rst,
            wr_pulse => wr_pulse, wr_data => wr_data,
            rd_pulse => rd_pulse, start_pulse => start_pulse,
            clr_pulse => clr_pulse,
            img_we => img_we, img_waddr => img_waddr, img_wdata => img_wdata,
            img_raddr => img_raddr, img_rdata => img_rdata,
            out_we => out_we, out_waddr => out_waddr, out_raddr => out_raddr,
            lb_ce => lb_ce, lb_pixel => lb_pixel, lb_clr => lb_clr,
            cv_valid_in => cv_valid_in, cv_valid_out => cv_valid_out,
            busy => busy, done => done_s, wr_ptr_o => wr_ptr_o
        );

    ------------------------------------------------------------------
    -- Model of the image RAM's read port: one cycle of latency, and it
    -- returns the address itself as data. That lets us verify that the
    -- right pixel index reaches the line buffer on the right cycle.
    ------------------------------------------------------------------
    img_model : process (clk)
    begin
        if rising_edge(clk) then
            img_rdata <= img_raddr(PIX_W - 1 downto 0);
        end if;
    end process img_model;

    ------------------------------------------------------------------
    -- Model of conv_unit: valid_out is valid_in delayed one cycle
    ------------------------------------------------------------------
    cv_model : process (clk, rst)
    begin
        if rst = '1' then
            cv_valid_out <= '0';
        elsif rising_edge(clk) then
            cv_valid_out <= cv_valid_in;
        end if;
    end process cv_model;

    ------------------------------------------------------------------
    -- Watches every output write and checks the address sequence
    ------------------------------------------------------------------
    out_watch : process (clk)
    begin
        if rising_edge(clk) then
            if count_rst = '1' then
                write_count <= 0;
                addr_ok     <= true;
            elsif out_we = '1' then
                if to_integer(unsigned(out_waddr)) /= write_count then
                    addr_ok <= false;
                end if;
                write_count <= write_count + 1;
            end if;
        end if;
    end process out_watch;

    stim : process
        variable err : integer := 0;

        procedure pulse (signal s : out std_logic) is
        begin
            s <= '1';
            wait until falling_edge(clk);
            s <= '0';
            wait until falling_edge(clk);
        end procedure pulse;

        procedure fail (msg : in string) is
        begin
            err := err + 1;
            report "FAIL @" & time'image(now) & " : " & msg severity error;
        end procedure fail;

    begin
        wait until falling_edge(clk);

        ----------------------------------------------------------------
        report "TEST 1: reset clears the pointers and status" severity note;
        ----------------------------------------------------------------
        rst <= '1';
        wait until falling_edge(clk);
        if busy /= '0' or done_s /= '0' then
            fail("busy or done set during reset");
        end if;
        if to_integer(unsigned(wr_ptr_o)) /= 0 then
            fail("write pointer not cleared");
        end if;
        rst <= '0';

        ----------------------------------------------------------------
        report "TEST 2: the write pointer auto-increments" severity note;
        ----------------------------------------------------------------
        for i in 0 to 9 loop
            wr_data <= std_logic_vector(to_unsigned(i, PIX_W));
            if to_integer(unsigned(wr_ptr_o)) /= i then
                fail("write pointer is " &
                     integer'image(to_integer(unsigned(wr_ptr_o))) &
                     ", expected " & integer'image(i));
            end if;
            pulse(wr_pulse);
        end loop;
        if to_integer(unsigned(wr_ptr_o)) /= 10 then
            fail("write pointer did not reach 10");
        end if;

        ----------------------------------------------------------------
        report "TEST 3: clr resets the pointers" severity note;
        ----------------------------------------------------------------
        pulse(clr_pulse);
        if to_integer(unsigned(wr_ptr_o)) /= 0 then
            fail("clr did not reset the write pointer");
        end if;

        ----------------------------------------------------------------
        report "TEST 4: run schedule" severity note;
        ----------------------------------------------------------------
        count_rst <= '1';
        wait until falling_edge(clk);
        count_rst <= '0';

        start_pulse <= '1';
        wait until falling_edge(clk);
        start_pulse <= '0';

        -- cycle 0 of the run is now in progress
        if busy /= '1' then
            fail("busy did not assert on start");
        end if;
        if cv_valid_in /= '0' then
            fail("cv_valid_in high at run cycle 0 - should start at cycle 2");
        end if;

        wait until falling_edge(clk);        -- run cycle 1
        if cv_valid_in /= '0' then
            fail("cv_valid_in high at run cycle 1 - should start at cycle 2");
        end if;
        if lb_ce /= '1' then
            fail("line buffer not enabled during the run");
        end if;

        wait until falling_edge(clk);        -- run cycle 2
        if cv_valid_in /= '1' then
            fail("cv_valid_in did not assert at run cycle 2");
        end if;
        -- the pixel reaching the line buffer this cycle must be pixel 1,
        -- because the RAM model returns the address and cycle 1 addressed 1
        if to_integer(unsigned(lb_pixel)) /= 1 then
            fail("wrong pixel reaching the line buffer at run cycle 2: got " &
                 integer'image(to_integer(unsigned(lb_pixel))));
        end if;

        ----------------------------------------------------------------
        report "TEST 5: the run completes and writes RUN_CYCLES results"
            severity note;
        ----------------------------------------------------------------
        while done_s = '0' loop
            wait until falling_edge(clk);
        end loop;

        if busy /= '0' then
            fail("busy still set after done");
        end if;
        if write_count /= RUN_CYCLES then
            fail("wrote " & integer'image(write_count) & " results, expected " &
                 integer'image(RUN_CYCLES));
        end if;
        if not addr_ok then
            fail("output addresses were not a contiguous run from 0");
        end if;
        report "  results written: " & integer'image(write_count) severity note;

        ----------------------------------------------------------------
        report "TEST 6: the read pointer auto-increments" severity note;
        ----------------------------------------------------------------
        pulse(clr_pulse);
        for i in 0 to 9 loop
            if to_integer(unsigned(out_raddr)) /= i then
                fail("read address is " &
                     integer'image(to_integer(unsigned(out_raddr))) &
                     ", expected " & integer'image(i));
            end if;
            pulse(rd_pulse);
        end loop;

        ----------------------------------------------------------------
        report "TEST 7: writes are blocked during a run" severity note;
        ----------------------------------------------------------------
        pulse(clr_pulse);
        start_pulse <= '1';
        wait until falling_edge(clk);
        start_pulse <= '0';
        wait until falling_edge(clk);

        wr_data  <= x"5A";
        wr_pulse <= '1';
        wait until falling_edge(clk);
        if img_we /= '0' then
            fail("image write accepted while the accelerator was running");
        end if;
        wr_pulse <= '0';

        while done_s = '0' loop
            wait until falling_edge(clk);
        end loop;

        ----------------------------------------------------------------
        errors <= err;
        report "tb_conv_ctrl finished with " & integer'image(err) &
               " error(s)" severity note;
        assert err = 0 report "tb_conv_ctrl FAILED" severity error;

        sim_done <= true;
        wait;
    end process stim;

end architecture sim;