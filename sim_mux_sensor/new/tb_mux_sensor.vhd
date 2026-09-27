library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity tb_mux_sensor is
end entity tb_mux_sensor;

architecture sim of tb_mux_sensor is

    constant CLK_PERIOD : time    := 10 ns;
    constant WIDTH      : integer := 16;   -- small, for a quick smoke test

    signal clk      : std_logic := '0';
    signal sensor_o : std_logic_vector(WIDTH - 1 downto 0);
    signal done     : boolean := false;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done else '0';

    -- both sensor clocks tied together, as in the real system
    dut : entity work.mux_sensor
        generic map (INIT_DELAY => 4, SENSOR_WIDTH => WIDTH, SET_NUMBER => 1)
        port map (clk_i => clk, sampling_clk_i => clk, sensor_o => sensor_o);

    stim : process
    begin
        for i in 1 to 20 loop
            wait until falling_edge(clk);
            -- The ONLY thing we can assert behaviourally: the output is
            -- resolved to 0/1, never U or X. Delay behaviour is invisible here.
            for b in sensor_o'range loop
                assert sensor_o(b) = '0' or sensor_o(b) = '1'
                    report "tb_mux_sensor: tap " & integer'image(b) &
                           " is not a defined logic level at " & time'image(now)
                    severity error;
            end loop;
        end loop;

        report "tb_mux_sensor: smoke test complete. " &
               "Delay sensing is NOT verified here - use post-implementation " &
               "timing simulation (section 6.5) or hardware." severity note;

        done <= true;
        wait;
    end process stim;

end architecture sim;