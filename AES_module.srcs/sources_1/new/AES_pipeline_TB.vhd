library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity AES_pipeline_tb is
end AES_pipeline_tb;

architecture sim of AES_pipeline_tb is

    component aes_module_pipeline is
    Port ( text_in : in STD_LOGIC_VECTOR (0 to 127);
           key : in STD_LOGIC_VECTOR (0 to 127);
           clk : in STD_LOGIC;
           start:in std_logic;
           encrypted_text : out STD_LOGIC_VECTOR (0 to 127);
           done_out:out std_logic);
    end component;

    signal text_in : STD_LOGIC_VECTOR(0 to 127);
    signal key : STD_LOGIC_VECTOR(0 to 127);
    signal clk : STD_LOGIC := '0';
    signal start : STD_LOGIC := '0';
    signal encrypted_text : STD_LOGIC_VECTOR(0 to 127);
    signal done_out : STD_LOGIC;

    constant CLK_PERIOD : time := 10 ns;

    -- FIPS-197 test vector goes in first, two dummy blocks follow it through the pipe
    constant BLOCK_0 : STD_LOGIC_VECTOR(0 to 127) := x"00112233445566778899aabbccddeeff";
    constant BLOCK_1 : STD_LOGIC_VECTOR(0 to 127) := x"11112233445566778899aabbccddeeff";
    constant BLOCK_2 : STD_LOGIC_VECTOR(0 to 127) := x"22112233445566778899aabbccddeeff";

    constant EXPECTED_0 : STD_LOGIC_VECTOR(0 to 127) := x"69c4e0d86a7b0430d8cdb78070b4c55a";

begin

    uut : aes_module_pipeline
        port map (
            text_in => text_in,
            key => key,
            clk => clk,
            start => start,
            encrypted_text => encrypted_text,
            done_out => done_out
        );

    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    stim_process : process
    begin
        key <= x"000102030405060708090a0b0c0d0e0f";
        wait for CLK_PERIOD;

        text_in <= BLOCK_0;
        start <= '1';
        wait for CLK_PERIOD;

        text_in <= BLOCK_1;
        wait for CLK_PERIOD;

        text_in <= BLOCK_2;
        wait for CLK_PERIOD;

        start <= '0';
        wait for CLK_PERIOD*20;

        wait;
    end process;

    -- reports the first result as soon as it lands, and checks it against FIPS-197
    check_process : process
    begin
        wait until done_out = '1';
        if encrypted_text = EXPECTED_0 then
            report "BLOCK 0 PASSED";
        else
            report "BLOCK 0 FAILED";
        end if;
        wait;
    end process;

end sim;