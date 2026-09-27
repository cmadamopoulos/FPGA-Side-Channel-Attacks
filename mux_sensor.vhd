library IEEE;
use IEEE.STD_LOGIC_1164.all;

library UNISIM;
use UNISIM.vcomponents.all;

entity mux_sensor is
    generic (
        INIT_DELAY   : integer := 32;    -- pass-through stages before the taps
        SENSOR_WIDTH : integer := 128;   -- number of sampled taps
        SET_NUMBER   : integer := 1      -- names the U_SET group, for multi-sensor builds
    );
    port (
        clk_i          : in  std_logic;                              -- edge propagates through the chain
        sampling_clk_i : in  std_logic;                              -- constant-phase sample clock
        sensor_o       : out std_logic_vector(SENSOR_WIDTH - 1 downto 0)
    );
end entity mux_sensor;

architecture behavioral of mux_sensor is

    component MUXF7
        port (O : out std_ulogic; I0 : in std_ulogic; I1 : in std_ulogic; S : in std_ulogic);
    end component;

    constant CHAIN_LEN : integer := INIT_DELAY + SENSOR_WIDTH;

    signal chain    : std_logic_vector(CHAIN_LEN - 1 downto 0);
    signal sample_s : std_logic_vector(SENSOR_WIDTH - 1 downto 0) := (others => '0');

    ------------------------------------------------------------------
    -- Optimisation barriers. Without these the synthesizer collapses a
    -- MUXF7 with constant data inputs into a buffer, and the "delay
    -- line" evaporates. Retain the full attribute set from the artifact
    -- you started from; the ones below are the load-bearing minimum.
    ------------------------------------------------------------------
    attribute dont_touch : string;
    attribute dont_touch of chain    : signal is "true";
    attribute dont_touch of sample_s : signal is "true";

    attribute keep : string;
    attribute keep of chain    : signal is "true";
    attribute keep of sample_s : signal is "true";

    attribute s : string;                       -- SAVE: keep the net, block trimming
    attribute s of chain    : signal is "true";
    attribute s of sample_s : signal is "true";

    -- CLOCK_SIGNAL no: tell the tools clk_i deliberately runs through logic,
    -- so they do not try to promote it onto a clock network.
    attribute clock_signal : string;
    attribute clock_signal of chain : signal is "no";

begin

    ------------------------------------------------------------------
    -- One ripple chain of MUXF7. Stage 0's select is the incoming edge;
    -- every later stage's select is the previous stage's output. I0/I1
    -- are constant 0/1, so each stage reproduces its select after one
    -- MUX propagation delay: the edge walks down the chain.
    ------------------------------------------------------------------
    stage0 : MUXF7 port map (O => chain(0), I0 => '0', I1 => '1', S => clk_i);

    gen_chain : for k in 1 to CHAIN_LEN - 1 generate
        stagek : MUXF7 port map (O => chain(k), I0 => '0', I1 => '1', S => chain(k - 1));
    end generate gen_chain;

    ------------------------------------------------------------------
    -- Sample the last SENSOR_WIDTH stages. The first INIT_DELAY stages
    -- are the head start that positions the transition inside this window.
    ------------------------------------------------------------------
    gen_fd : for j in 0 to SENSOR_WIDTH - 1 generate
        fdj : FD port map (Q => sample_s(j), C => sampling_clk_i, D => chain(INIT_DELAY + j));
    end generate gen_fd;

    sensor_o <= sample_s;

end architecture behavioral;