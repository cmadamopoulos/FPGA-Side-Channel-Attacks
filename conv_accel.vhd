library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

use work.conv_pkg.all;

entity conv_accel is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;                        -- active high
        sw_ctrl   : in  std_logic_vector(31 downto 0);    -- from AXI GPIO ch 1
        hw_status : out std_logic_vector(31 downto 0)     -- to   AXI GPIO ch 2
    );
end entity conv_accel;

architecture rtl of conv_accel is

    ------------------------------------------------------------------
    -- sw_ctrl bit map                     hw_status bit map
    --   [7:0]   pixel byte                  [7:0]   sensor trace sample (delay data)
    --   [16:8]  kernel, 9 bits              [8]     sensor capture done
    --   [17]    write strobe                [9]     sensor busy (capturing)
    --   [18]    read strobe (trace)         [10]    convolution done
    --   [19]    start (conv + arm sensor)   [11]    convolution busy
    --   [20]    clear (conv + sensor)       [21:12] image write pointer (load check)
    --                                       [31:22] unused
    --
    -- The convolution still runs and computes on every start; its result
    -- memory is written as before but no longer read out. hw_status now
    -- carries the MUXLeak sensor trace captured DURING that run.
    ------------------------------------------------------------------
    alias sw_pixel  : std_logic_vector(PIX_W - 1 downto 0)  is sw_ctrl(7 downto 0);
    alias sw_kernel : std_logic_vector(K_TAPS - 1 downto 0) is sw_ctrl(16 downto 8);

    signal sw_ctrl_d : std_logic_vector(31 downto 0);

    signal wr_pulse    : std_logic;
    signal rd_pulse    : std_logic;
    signal start_pulse : std_logic;
    signal clr_pulse   : std_logic;

    signal img_we    : std_logic;
    signal img_waddr : std_logic_vector(MEM_AW - 1 downto 0);
    signal img_wdata : std_logic_vector(PIX_W - 1 downto 0);
    signal img_raddr : std_logic_vector(MEM_AW - 1 downto 0);
    signal img_rdata : std_logic_vector(PIX_W - 1 downto 0);

    signal out_we    : std_logic;
    signal out_waddr : std_logic_vector(MEM_AW - 1 downto 0);
    signal out_wdata : std_logic_vector(OUT_W - 1 downto 0);
    signal out_raddr : std_logic_vector(MEM_AW - 1 downto 0);
    signal out_rdata : std_logic_vector(OUT_W - 1 downto 0);

    signal lb_ce     : std_logic;
    signal lb_clr    : std_logic;
    signal lb_pixel  : std_logic_vector(PIX_W - 1 downto 0);
    signal window    : pix_array;

    signal cv_valid_in  : std_logic;
    signal cv_valid_out : std_logic;
    signal cv_result    : std_logic_vector(ACC_W - 1 downto 0);

    signal busy      : std_logic;
    signal done      : std_logic;
    signal wr_ptr_o  : std_logic_vector(MEM_AW - 1 downto 0);

    -- sensor integration
    signal sensor_sw     : std_logic_vector(31 downto 0);
    signal sensor_status : std_logic_vector(31 downto 0);

begin

    ------------------------------------------------------------------
    -- Edge detection. Software sets a control bit, then clears it.
    ------------------------------------------------------------------
    process (clk, rst)
    begin
        if rst = '1' then
            sw_ctrl_d <= (others => '0');
        elsif rising_edge(clk) then
            sw_ctrl_d <= sw_ctrl;
        end if;
    end process;

    wr_pulse    <= sw_ctrl(17) and not sw_ctrl_d(17);
    rd_pulse    <= sw_ctrl(18) and not sw_ctrl_d(18);   -- still advances conv out ptr (unused)
    start_pulse <= sw_ctrl(19) and not sw_ctrl_d(19);
    clr_pulse   <= sw_ctrl(20) and not sw_ctrl_d(20);

    ------------------------------------------------------------------
    -- convolution victim: unchanged, still loads / runs / computes
    ------------------------------------------------------------------
    u_ctrl : entity work.conv_ctrl
        port map (
            clk => clk, rst => rst,
            wr_pulse => wr_pulse, wr_data => sw_pixel,
            rd_pulse => rd_pulse, start_pulse => start_pulse,
            clr_pulse => clr_pulse,
            img_we => img_we, img_waddr => img_waddr, img_wdata => img_wdata,
            img_raddr => img_raddr, img_rdata => img_rdata,
            out_we => out_we, out_waddr => out_waddr, out_raddr => out_raddr,
            lb_ce => lb_ce, lb_clr => lb_clr, lb_pixel => lb_pixel,
            cv_valid_in => cv_valid_in, cv_valid_out => cv_valid_out,
            busy => busy, done => done, wr_ptr_o => wr_ptr_o
        );

    u_img : entity work.dp_ram
        generic map (DATA_W => PIX_W, ADDR_W => MEM_AW)
        port map (
            clk => clk, we => img_we, waddr => img_waddr, din => img_wdata,
            raddr => img_raddr, dout => img_rdata
        );

    u_lb : entity work.line_buffer
        port map (
            clk => clk, rst => rst, clr => lb_clr, ce => lb_ce,
            pixel_in => lb_pixel, win_out => window
        );

    u_conv : entity work.conv_unit
        port map (
            clk => clk, rst => rst, win => window, kern => sw_kernel,
            valid_in => cv_valid_in,
            result => cv_result, valid_out => cv_valid_out
        );

    out_wdata <= std_logic_vector(resize(signed(cv_result), OUT_W));

    u_out : entity work.dp_ram
        generic map (DATA_W => OUT_W, ADDR_W => MEM_AW)
        port map (
            clk => clk, we => out_we, waddr => out_waddr, din => out_wdata,
            raddr => out_raddr, dout => out_rdata
        );

    ------------------------------------------------------------------
    -- side-channel sensor, armed by the same pulse that starts the run
    ------------------------------------------------------------------
    -- sensor_accel's own control bits: [0] arm(sw), [1] read, [2] clear.
    -- Arm is driven from hardware (start_pulse), so bit 0 is held low and
    -- the software read/clear strobes are mapped onto the sensor.
    sensor_sw(0)           <= '0';
    sensor_sw(1)           <= sw_ctrl(18);   -- read strobe drains the trace
    sensor_sw(2)           <= sw_ctrl(20);   -- clear also clears sensor pointers
    sensor_sw(31 downto 3) <= (others => '0');

    u_sensor : entity work.sensor_accel
        generic map (
            INIT_DELAY   => 32,
            SENSOR_WIDTH => 128,
            TRACE_LEN    => 1024,
            TRACE_AW     => 10
        )
        port map (
            clk       => clk,
            rst       => rst,
            arm       => start_pulse,        -- capture begins with each convolution run
            sw_ctrl   => sensor_sw,
            hw_status => sensor_status
        );

    ------------------------------------------------------------------
    -- hw_status now carries the sensor trace, plus enough conv status
    -- to verify the image load and see the run complete.
    ------------------------------------------------------------------
    hw_status(7 downto 0)   <= sensor_status(7 downto 0);    -- delay / Hamming-weight sample
    hw_status(8)            <= sensor_status(16);            -- sensor capture done
    hw_status(9)            <= sensor_status(17);            -- sensor busy
    hw_status(10)           <= done;                          -- convolution done
    hw_status(11)           <= busy;                          -- convolution busy
    hw_status(21 downto 12) <= wr_ptr_o;                     -- image write pointer
    hw_status(31 downto 22) <= (others => '0');

end architecture rtl;