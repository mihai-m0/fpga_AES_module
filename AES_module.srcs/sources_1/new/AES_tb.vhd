library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity aes_module_tb is
end aes_module_tb;

architecture sim of aes_module_tb is

    component aes_module
        Port ( text_in : in STD_LOGIC_VECTOR (0 to 127);
               key : in STD_LOGIC_VECTOR (0 to 127);
               clk : in STD_LOGIC;
               start : in STD_LOGIC;
               encrypted_text : out STD_LOGIC_VECTOR (0 to 127));
    end component;

    signal text_in : STD_LOGIC_VECTOR(0 to 127);
    signal key : STD_LOGIC_VECTOR(0 to 127);
    signal clk : STD_LOGIC := '0';
    signal start : STD_LOGIC := '0';
    signal encrypted_text : STD_LOGIC_VECTOR(0 to 127);

    constant CLK_PERIOD : time := 10 ns;

    constant EXPECTED_CIPHERTEXT : STD_LOGIC_VECTOR(0 to 127) := x"69c4e0d86a7b0430d8cdb78070b4c55a";

begin

    uut : aes_module
        port map (
            text_in => text_in,
            key => key,
            clk => clk,
            start => start,
            encrypted_text => encrypted_text
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
        text_in <= x"00112233445566778899aabbccddeeff";
        key <= x"000102030405060708090a0b0c0d0e0f";
        start <= '0';

        wait for CLK_PERIOD;

        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait for CLK_PERIOD*12;

        if encrypted_text = EXPECTED_CIPHERTEXT then
            report "TEST PASSED";
        else
            report "TEST FAILED";
        end if;

        wait;
    end process;

end sim;