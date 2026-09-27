library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity dp_ram is
    generic (
        DATA_W : integer := 8;
        ADDR_W : integer := 10
    );
    port (
        clk   : in  std_logic;
        we    : in  std_logic;
        waddr : in  std_logic_vector(ADDR_W - 1 downto 0);
        din   : in  std_logic_vector(DATA_W - 1 downto 0);
        raddr : in  std_logic_vector(ADDR_W - 1 downto 0);
        dout  : out std_logic_vector(DATA_W - 1 downto 0)
    );
end entity dp_ram;

architecture rtl of dp_ram is
    type mem_t is array (0 to 2 ** ADDR_W - 1)
        of std_logic_vector(DATA_W - 1 downto 0);
    signal mem : mem_t := (others => (others => '0'));
begin

    ------------------------------------------------------------------
    -- Simple dual port: one write port, one read port, one clock.
    -- No reset anywhere, which is what lets this infer block RAM.
    ------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                mem(to_integer(unsigned(waddr))) <= din;
            end if;
            dout <= mem(to_integer(unsigned(raddr)));
        end if;
    end process;

end architecture rtl;