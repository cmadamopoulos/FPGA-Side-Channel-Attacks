library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity sensor_accel is
    generic (
        INIT_DELAY   : integer := 32;
        SENSOR_WIDTH : integer := 128;
        TRACE_LEN    : integer := 1024;   -- samples per trace
        TRACE_AW     : integer := 10      -- ceil(log2(TRACE_LEN))
    );
    port (
        clk       : in  std_logic;                        -- FCLK_CLK0
        rst       : in  std_logic;                        -- active high
        arm       : in  std_logic;                        -- 1-cycle pulse: start a capture
        sw_ctrl   : in  std_logic_vector(31 downto 0);    -- from AXI GPIO ch1
        hw_status : out std_logic_vector(31 downto 0)     -- to   AXI GPIO ch2
    );
end entity sensor_accel;

architecture rtl of sensor_accel is

    ------------------------------------------------------------------
    -- sw_ctrl bit map                     hw_status bit map
    --   [0]  arm strobe (software)          [7:0]   trace sample (Hamming weight)
    --   [1]  read strobe                     [16]    capture done
    --   [2]  clear pointers                  [17]    busy (capturing)
    --                                        [27:18] write pointer (debug)
    ------------------------------------------------------------------
    signal sw_ctrl_d  : std_logic_vector(31 downto 0);
    signal rd_pulse   : std_logic;
    signal clr_pulse  : std_logic;
    signal arm_sw     : std_logic;
    signal arm_any    : std_logic;

    signal sensor_bits : std_logic_vector(SENSOR_WIDTH - 1 downto 0);
    signal hw_sample   : std_logic_vector(7 downto 0);

    signal wr_ptr   : unsigned(TRACE_AW - 1 downto 0);
    signal rd_ptr   : unsigned(TRACE_AW - 1 downto 0);
    signal running  : std_logic;
    signal done_r   : std_logic;
    signal tr_we    : std_logic;
    signal tr_rdata : std_logic_vector(7 downto 0);

begin

    ------------------------------------------------------------------
    -- edge detection on the software control bits (same as conv_accel)
    ------------------------------------------------------------------
    process (clk, rst)
    begin
        if rst = '1' then
            sw_ctrl_d <= (others => '0');
        elsif rising_edge(clk) then
            sw_ctrl_d <= sw_ctrl;
        end if;
    end process;

    arm_sw    <= sw_ctrl(0) and not sw_ctrl_d(0);
    rd_pulse  <= sw_ctrl(1) and not sw_ctrl_d(1);
    clr_pulse <= sw_ctrl(2) and not sw_ctrl_d(2);

    -- A capture can be launched by software (for standalone testing) OR by the
    -- hardware `arm` pin wired from conv_accel's start, so a trace lines up
    -- exactly with a convolution run.
    arm_any <= arm_sw or arm;

    ------------------------------------------------------------------
    u_sensor : entity work.mux_sensor
        generic map (INIT_DELAY => INIT_DELAY, SENSOR_WIDTH => SENSOR_WIDTH, SET_NUMBER => 1)
        port map (clk_i => clk, sampling_clk_i => clk, sensor_o => sensor_bits);

    u_pop : entity work.popcount
        generic map (WIDTH => SENSOR_WIDTH)
        port map (clk => clk, rst => rst, d => sensor_bits, hw => hw_sample);

    -- trace memory: one dp_ram, 8-bit samples, TRACE_LEN deep
    tr_we <= running;
    u_tr : entity work.dp_ram
        generic map (DATA_W => 8, ADDR_W => TRACE_AW)
        port map (
            clk   => clk,
            we    => tr_we,
            waddr => std_logic_vector(wr_ptr),
            din   => hw_sample,
            raddr => std_logic_vector(rd_ptr),
            dout  => tr_rdata
        );

    ------------------------------------------------------------------
    -- capture sequencer: on arm, record TRACE_LEN consecutive samples
    ------------------------------------------------------------------
    process (clk, rst)
    begin
        if rst = '1' then
            wr_ptr  <= (others => '0');
            rd_ptr  <= (others => '0');
            running <= '0';
            done_r  <= '0';
        elsif rising_edge(clk) then

            if clr_pulse = '1' then
                rd_ptr <= (others => '0');
                done_r <= '0';
            end if;

            if running = '0' then
                if rd_pulse = '1' then
                    rd_ptr <= rd_ptr + 1;
                end if;
                if arm_any = '1' then
                    running <= '1';
                    wr_ptr  <= (others => '0');
                    done_r  <= '0';
                end if;
            else
                if wr_ptr = TRACE_LEN - 1 then
                    running <= '0';
                    done_r  <= '1';
                else
                    wr_ptr <= wr_ptr + 1;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    hw_status(7 downto 0)   <= tr_rdata;
    hw_status(15 downto 8)  <= (others => '0');
    hw_status(16)           <= done_r;
    hw_status(17)           <= running;
    hw_status(27 downto 18) <= std_logic_vector(resize(wr_ptr, 10));
    hw_status(31 downto 28) <= (others => '0');

end architecture rtl;