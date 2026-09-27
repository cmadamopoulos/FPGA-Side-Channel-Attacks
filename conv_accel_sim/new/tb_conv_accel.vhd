library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

use work.conv_pkg.all;

entity tb_conv_accel is
end entity tb_conv_accel;

architecture sim of tb_conv_accel is

    constant CLK_PERIOD : time := 20 ns;

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal clr       : std_logic := '0';
    signal sw_ctrl   : std_logic_vector(31 downto 0) := (others => '0');
    signal hw_status : std_logic_vector(31 downto 0);

    signal errors    : integer := 0;
    signal sim_done  : boolean := false;

    type img_t is array (0 to IMG_PIXELS - 1) of integer;

    -- Pseudo-random test image. Structured images hide index errors;
    -- this one does not. Section 6 shows how to load a real MNIST digit.
    function make_image return img_t is
        variable im : img_t;
    begin
        for i in 0 to IMG_PIXELS - 1 loop
            im(i) := (i * 97 + 41) mod 256;
        end loop;
        return im;
    end function make_image;

    constant IMAGE : img_t := make_image;

begin

    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

    dut : entity work.conv_accel
        port map (clk => clk, rst => rst,
                  sw_ctrl => sw_ctrl, hw_status => hw_status);

    stim : process
        variable err : integer := 0;

        ----------------------------------------------------------------
        -- reference model: result(m) is the window whose top-left pixel
        -- is index m - WIN_LAT. Pixels before the start of the stream
        -- read as zero, which is what the line buffer's reset gives.
        ----------------------------------------------------------------
        function reference (m : integer;
                            k : std_logic_vector(K_TAPS - 1 downto 0))
            return integer is
            variable s   : integer := 0;
            variable idx : integer;
        begin
            for j in 0 to K_TAPS - 1 loop
                idx := m - TAP_OFFSET(j);
                if idx >= 0 and idx < IMG_PIXELS then
                    if k(j) = '1' then
                        s := s + IMAGE(idx);
                    else
                        s := s - IMAGE(idx);
                    end if;
                end if;
            end loop;
            return s;
        end function reference;

        -- write sw_ctrl with a strobe bit, then clear it
        procedure command (base : in std_logic_vector(31 downto 0);
                           bit_n : in integer) is
            variable w : std_logic_vector(31 downto 0);
        begin
            w         := base;
            w(bit_n)  := '1';
            sw_ctrl   <= w;
            wait until falling_edge(clk);
            w(bit_n)  := '0';
            sw_ctrl   <= w;
            wait until falling_edge(clk);
        end procedure command;
        

        variable base   : std_logic_vector(31 downto 0);
        variable kernel : std_logic_vector(K_TAPS - 1 downto 0);
        variable got    : integer;
        variable want   : integer;
        variable shown  : integer := 0;
        variable sum_v  : integer;

    begin
        wait until falling_edge(clk);

        ----------------------------------------------------------------
        report "TEST 1: reset" severity note;
        ----------------------------------------------------------------
        rst <= '1';
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        if hw_status(16) /= '0' or hw_status(17) /= '0' then
            err := err + 1;
            report "FAIL: done or busy set during reset" severity error;
        end if;
        rst <= '0';
        wait until falling_edge(clk);

        ----------------------------------------------------------------
        -- run the whole flow three times with different kernels
        ----------------------------------------------------------------
        for t in 0 to 2 loop

            case t is
                when 0      => kernel := (others => '1');    -- box sum
                when 1      => kernel := (others => '0');    -- negated box sum
                when others => kernel := "010110101";        -- arbitrary
            end case;

            report "RUN " & integer'image(t) & ": kernel = " &
                   integer'image(to_integer(unsigned(kernel)))
                severity note;

            base              := (others => '0');
            base(16 downto 8) := kernel;

            ------------------------------------------------------------
            -- clear, then load 784 pixels
            ------------------------------------------------------------
            command(base, 20);                                   -- clr

            for i in 0 to IMG_PIXELS - 1 loop
                base(7 downto 0) := std_logic_vector(to_unsigned(IMAGE(i), PIX_W));
                command(base, 17);                               -- write strobe
            end loop;

            if to_integer(unsigned(hw_status(27 downto 18))) /= IMG_PIXELS then
                err := err + 1;
                report "FAIL: write pointer is " &
                       integer'image(to_integer(unsigned(hw_status(27 downto 18)))) &
                       " after loading, expected " & integer'image(IMG_PIXELS)
                    severity error;
            end if;

            ------------------------------------------------------------
            -- run
            ------------------------------------------------------------
            base(7 downto 0) := (others => '0');
            command(base, 19);                                   -- start

            while hw_status(16) = '0' loop
                wait until falling_edge(clk);
            end loop;

            if hw_status(17) /= '0' then
                err := err + 1;
                report "FAIL: busy still set when done asserted" severity error;
            end if;

            ------------------------------------------------------------
            -- read back and compare
            ------------------------------------------------------------
            command(base, 20);                                   -- clr pointers
            shown := 0;

            for m in 0 to RUN_CYCLES - 1 loop
                got  := to_integer(signed(hw_status(15 downto 0)));
                want := reference(m, kernel);

                if got /= want then
                    err := err + 1;
                    if shown < 10 then
                        report "MISMATCH run " & integer'image(t) &
                               " result " & integer'image(m) &
                               ": expected " & integer'image(want) &
                               ", got " & integer'image(got)
                            severity error;
                        shown := shown + 1;
                    end if;
                end if;

                command(base, 18);                               -- read strobe
            end loop;

            report "  run " & integer'image(t) & " compared " &
                   integer'image(RUN_CYCLES) & " results" severity note;
        end loop;

        ----------------------------------------------------------------
        report "TEST 2: a second run without reloading reuses the image"
            severity note;
        ----------------------------------------------------------------
        base              := (others => '0');
        base(16 downto 8) := "111000111";
        command(base, 20);
        command(base, 19);
        while hw_status(16) = '0' loop
            wait until falling_edge(clk);
        end loop;
        command(base, 20);
        for m in 0 to 99 loop        -- spot-check the first hundred
            got  := to_integer(signed(hw_status(15 downto 0)));
            want := reference(m, "111000111");
            if got /= want then
                err := err + 1;
                report "MISMATCH on rerun at result " & integer'image(m)
                    severity error;
            end if;
            command(base, 18);
        end loop;

                ----------------------------------------------------------------
        report "TEST 3: index 83 is the first fully real window"
            severity note;
        ----------------------------------------------------------------
        -- result(83) must equal the convolution of image rows 0,1,2
        -- columns 0,1,2. Computed here from IMAGE directly, without
        -- going through TAP_OFFSET, so it is an independent check.
        sum_v  := 0;
        kernel := (others => '1');
        for r in 0 to K_DIM - 1 loop
            for c in 0 to K_DIM - 1 loop
                sum_v := sum_v + IMAGE(r * IMG_W + c);
            end loop;
        end loop;

        report "  expected result(83) for an all-+1 kernel = " &
               integer'image(sum_v) severity note;

        if sum_v /= reference(WIN_LAT, kernel) then
            err := err + 1;
            report "FAIL: the reference model disagrees with a direct " &
                   "3x3 sum at index 83 - TAP_OFFSET is wrong"
                severity error;
        end if;

        ----------------------------------------------------------------
        errors <= err;
        report "=====================================================" severity note;
        report "tb_conv_accel finished with " & integer'image(err) &
               " error(s)" severity note;
        if err = 0 then
            report "ALL TESTS PASSED" severity note;
        end if;
        report "=====================================================" severity note;

        sim_done <= true;
        wait;
    end process stim;

end architecture sim;