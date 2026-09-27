library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

use work.conv_pkg.all;

entity conv_ctrl is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;

        -- software commands, already edge-detected into single-cycle pulses
        wr_pulse     : in  std_logic;
        wr_data      : in  std_logic_vector(PIX_W - 1 downto 0);
        rd_pulse     : in  std_logic;
        start_pulse  : in  std_logic;
        clr_pulse    : in  std_logic;

        -- image memory
        img_we       : out std_logic;
        img_waddr    : out std_logic_vector(MEM_AW - 1 downto 0);
        img_wdata    : out std_logic_vector(PIX_W - 1 downto 0);
        img_raddr    : out std_logic_vector(MEM_AW - 1 downto 0);
        img_rdata    : in  std_logic_vector(PIX_W - 1 downto 0);

        -- output memory
        out_we       : out std_logic;
        out_waddr    : out std_logic_vector(MEM_AW - 1 downto 0);
        out_raddr    : out std_logic_vector(MEM_AW - 1 downto 0);

        -- line buffer
        lb_ce        : out std_logic;
        lb_clr       : out std_logic;                           -- NEW
        lb_pixel     : out std_logic_vector(PIX_W - 1 downto 0);

        -- convolution unit
        cv_valid_in  : out std_logic;
        cv_valid_out : in  std_logic;

        -- status
        busy         : out std_logic;
        done         : out std_logic;
        wr_ptr_o     : out std_logic_vector(MEM_AW - 1 downto 0)
    );
end entity conv_ctrl;

architecture rtl of conv_ctrl is

    -- last run-counter value: RUN_CYCLES outputs, produced from cycle 3
    constant LAST_CYCLE : integer := RUN_CYCLES + 2;

    signal wr_ptr   : unsigned(MEM_AW - 1 downto 0);
    signal rd_ptr   : unsigned(MEM_AW - 1 downto 0);
    signal out_ptr  : unsigned(MEM_AW - 1 downto 0);
    signal run_cnt  : unsigned(MEM_AW downto 0);    -- one bit spare, holds 786
    signal running  : std_logic;
    signal done_r   : std_logic;
    signal pix_en   : std_logic;
    signal pix_en_d : std_logic;

begin

    ------------------------------------------------------------------
    -- combinational outputs
    ------------------------------------------------------------------

    -- address the image RAM while there are still real pixels to fetch
    pix_en <= '1' when (running = '1' and run_cnt < IMG_PIXELS) else '0';

    img_raddr <= std_logic_vector(run_cnt(MEM_AW - 1 downto 0));
    img_waddr <= std_logic_vector(wr_ptr);
    img_wdata <= wr_data;
    img_we    <= wr_pulse and (not running);      -- loading only while idle

    out_raddr <= std_logic_vector(rd_ptr);
    out_waddr <= std_logic_vector(out_ptr);
    out_we    <= cv_valid_out;

    lb_ce    <= running;
    -- flush during run cycle 0, before the first pixel arrives at cycle 1
    lb_clr <= '1' when (running = '1' and run_cnt = 0) else '0';
    -- pix_en_d, not pix_en: the RAM output arrives one cycle after the
    -- address. Past the end of the image we shift zeros so the tail of
    -- the buffer flushes predictably.
    lb_pixel <= img_rdata when pix_en_d = '1' else (others => '0');

    -- Results 0 .. RUN_CYCLES-1 are produced during run cycles 2 .. RUN_CYCLES+1.
    -- Two cycles of offset: one for the RAM read, one for the line buffer shift.
    cv_valid_in <= '1' when (running = '1'
                             and run_cnt >= 2
                             and run_cnt <= RUN_CYCLES + 1) else '0';

    busy     <= running;
    done     <= done_r;
    wr_ptr_o <= std_logic_vector(wr_ptr);

    ------------------------------------------------------------------
    -- sequencer
    ------------------------------------------------------------------
    process (clk, rst)
    begin
        if rst = '1' then
            wr_ptr   <= (others => '0');
            rd_ptr   <= (others => '0');
            out_ptr  <= (others => '0');
            run_cnt  <= (others => '0');
            running  <= '0';
            done_r   <= '0';
            pix_en_d <= '0';

        elsif rising_edge(clk) then

            pix_en_d <= pix_en;

            if clr_pulse = '1' then
                wr_ptr  <= (others => '0');
                rd_ptr  <= (others => '0');
                out_ptr <= (others => '0');
                done_r  <= '0';
            end if;

            if running = '0' then
                ------------------------------------------------------
                -- idle: software may load pixels and pop results
                ------------------------------------------------------
                if wr_pulse = '1' then
                    wr_ptr <= wr_ptr + 1;
                end if;

                if rd_pulse = '1' then
                    rd_ptr <= rd_ptr + 1;
                end if;

                if start_pulse = '1' then
                    running <= '1';
                    run_cnt <= (others => '0');
                    out_ptr <= (others => '0');
                    done_r  <= '0';
                end if;

            else
                ------------------------------------------------------
                -- running: free-wheel for LAST_CYCLE + 1 cycles
                ------------------------------------------------------
                if run_cnt = LAST_CYCLE then
                    running <= '0';
                    done_r  <= '1';
                else
                    run_cnt <= run_cnt + 1;
                end if;

                if cv_valid_out = '1' then
                    out_ptr <= out_ptr + 1;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;