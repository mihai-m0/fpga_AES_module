library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity aes_uart_top is
    Port ( clk : in STD_LOGIC;
           uart_rx_pin : in STD_LOGIC;
           uart_tx_pin : out STD_LOGIC );
end aes_uart_top;

architecture Behavioral of aes_uart_top is

    component receiver
        generic(tick_limit : integer := 10417);
        port(clk : in std_logic; din : in std_logic;
             valid : out std_logic; dout : out std_logic_vector(7 downto 0));
    end component;

    component transmitter
        generic(tick_limit : integer := 10417);
        port(clk : in std_logic; data_request : in std_logic; din : in std_logic_vector(7 downto 0);
             dout : out std_logic; working : out std_logic; done : out std_logic);
    end component;

    component aes_module_pipeline
        Port ( text_in : in STD_LOGIC_VECTOR (0 to 127);
               key : in STD_LOGIC_VECTOR (0 to 127);
               clk : in STD_LOGIC;
               start : in STD_LOGIC;
               encrypted_text : out STD_LOGIC_VECTOR (0 to 127);
               done_out : out STD_LOGIC);
    end component;

    signal rx_valid : std_logic;
    signal rx_byte   : std_logic_vector(7 downto 0);

    signal key_reg      : std_logic_vector(0 to 127) := (others => '0');
    signal text_in_reg  : std_logic_vector(0 to 127) := (others => '0');
    signal receiving_key: std_logic := '1';
    signal byte_count   : integer range 0 to 15 := 0;
    signal start_pulse  : std_logic := '0';

    signal encrypted_text : std_logic_vector(0 to 127);
    signal done_out       : std_logic;

    type tx_states is (tx_idle, tx_load, tx_wait_done);
    signal tx_state   : tx_states := tx_idle;
    signal tx_buffer  : std_logic_vector(0 to 127);
    signal tx_index   : integer range 0 to 15 := 0;
    signal tx_byte    : std_logic_vector(7 downto 0);
    signal tx_request : std_logic := '0';
    signal tx_working, tx_done : std_logic;

begin

    uart_rx_inst : receiver
        generic map (tick_limit => 10417)
        port map (clk => clk, din => uart_rx_pin, valid => rx_valid, dout => rx_byte);

    uart_tx_inst : transmitter
        generic map (tick_limit => 10417)
        port map (clk => clk, data_request => tx_request, din => tx_byte,
                   dout => uart_tx_pin, working => tx_working, done => tx_done);

    aes_inst : aes_module_pipeline
        port map (text_in => text_in_reg, key => key_reg, clk => clk,
                   start => start_pulse, encrypted_text => encrypted_text, done_out => done_out);

    rx_assembler : process(clk)
    begin
        if rising_edge(clk) then
            start_pulse <= '0';

            if rx_valid = '1' then
                if receiving_key = '1' then
                    key_reg(byte_count*8 to byte_count*8+7) <= rx_byte;
                    if byte_count = 15 then
                        byte_count <= 0;
                        receiving_key <= '0';
                    else
                        byte_count <= byte_count + 1;
                    end if;
                else
                    text_in_reg(byte_count*8 to byte_count*8+7) <= rx_byte;
                    if byte_count = 15 then
                        byte_count <= 0;
                        start_pulse <= '1';
                    else
                        byte_count <= byte_count + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    tx_assembler : process(clk)
    begin
        if rising_edge(clk) then
            tx_request <= '0';

            case tx_state is
                when tx_idle =>
                    if done_out = '1' then
                        tx_buffer <= encrypted_text;
                        tx_index  <= 0;
                        tx_state  <= tx_load;
                    end if;

                when tx_load =>
                    tx_byte    <= tx_buffer(tx_index*8 to tx_index*8+7);
                    tx_request <= '1';
                    tx_state   <= tx_wait_done;

                when tx_wait_done =>
                    if tx_done = '1' then
                        if tx_index = 15 then
                            tx_state <= tx_idle;
                        else
                            tx_index <= tx_index + 1;
                            tx_state <= tx_load;
                        end if;
                    end if;
            end case;
        end if;
    end process;

end Behavioral;
