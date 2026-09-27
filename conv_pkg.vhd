library IEEE;
use IEEE.STD_LOGIC_1164.all;

package conv_pkg is

    ------------------------------------------------------------------
    -- image geometry
    ------------------------------------------------------------------
    constant IMG_W      : integer := 28;
    constant IMG_H      : integer := 28;
    constant IMG_PIXELS : integer := IMG_W * IMG_H;             -- 784
    constant PIX_W      : integer := 8;

    ------------------------------------------------------------------
    -- kernel
    ------------------------------------------------------------------
    constant K_DIM      : integer := 3;
    constant K_TAPS     : integer := K_DIM * K_DIM;             -- 9

    ------------------------------------------------------------------
    -- line buffer: the paper uses K_DIM full rows of IMG_W
    ------------------------------------------------------------------
    constant LB_DEPTH   : integer := K_DIM * IMG_W;             -- 84
    constant WIN_LAT    : integer := LB_DEPTH - 1;              -- 83

    ------------------------------------------------------------------
    -- arithmetic widths
    --   TERM_W : one +/- pixel                    -> 9  bits signed
    --   ACC_W  : sum of K_TAPS terms, +ceil(log2 9) -> 13 bits signed
    ------------------------------------------------------------------
    constant TERM_W     : integer := PIX_W + 1;                 -- 9
    constant ACC_W      : integer := TERM_W + 4;                -- 13
    constant OUT_W      : integer := 16;                        -- sign-extended

    ------------------------------------------------------------------
    -- memories and run length
    ------------------------------------------------------------------
    constant MEM_AW     : integer := 10;                        -- 1024 >= 784

    -- 784 = one output per input pixel, as counted in the paper.
    -- Set to IMG_PIXELS + 25 (809) to also produce the last windows
    -- of the 26x26 feature map. See section 2.4.
    constant RUN_CYCLES : integer := IMG_PIXELS;

    ------------------------------------------------------------------
    -- window
    ------------------------------------------------------------------
    type pix_array is array (0 to K_TAPS - 1)
        of std_logic_vector(PIX_W - 1 downto 0);

    -- How far back in the pixel stream each window tap sits.
    -- win(r*K_DIM + c) is the window element at kernel row r, column c,
    -- and equals the pixel from TAP_OFFSET(r*K_DIM + c) cycles ago.
    --
    --   win(0) win(1) win(2)      83  82  81
    --   win(3) win(4) win(5)  =   55  54  53
    --   win(6) win(7) win(8)      27  26  25
    --
    -- Rows are IMG_W apart, columns are 1 apart: a proper 3x3 window.
    type tap_offsets_t is array (0 to K_TAPS - 1) of integer;

    constant TAP_OFFSET : tap_offsets_t := (
        0 => 3 * IMG_W - 1,  1 => 3 * IMG_W - 2,  2 => 3 * IMG_W - 3,
        3 => 2 * IMG_W - 1,  4 => 2 * IMG_W - 2,  5 => 2 * IMG_W - 3,
        6 => 1 * IMG_W - 1,  7 => 1 * IMG_W - 2,  8 => 1 * IMG_W - 3
    );

end package conv_pkg;