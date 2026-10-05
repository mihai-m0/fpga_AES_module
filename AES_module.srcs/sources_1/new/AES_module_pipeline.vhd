library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity aes_module_pipeline is
    Port ( text_in : in STD_LOGIC_VECTOR (0 to 127);
           key : in STD_LOGIC_VECTOR (0 to 127);
           clk : in STD_LOGIC;
           start:in std_logic;
           encrypted_text : out STD_LOGIC_VECTOR (0 to 127);
           done_out:out std_logic);
end aes_module_pipeline;

architecture Behavioral of aes_module_pipeline is

    type sbox_arr is array(0 to 255) of std_logic_vector(0 to 7);
    function s_box(one_byte:std_logic_vector(0 to 7)) -- one byte as input
    --the sbox has been transformed from a matrix into an array
    return std_logic_vector is
          constant SBOX : sbox_arr := (
        x"63", x"7c", x"77", x"7b", x"f2", x"6b", x"6f", x"c5",
        x"30", x"01", x"67", x"2b", x"fe", x"d7", x"ab", x"76",
        x"ca", x"82", x"c9", x"7d", x"fa", x"59", x"47", x"f0",
        x"ad", x"d4", x"a2", x"af", x"9c", x"a4", x"72", x"c0",
        x"b7", x"fd", x"93", x"26", x"36", x"3f", x"f7", x"cc",
        x"34", x"a5", x"e5", x"f1", x"71", x"d8", x"31", x"15",
        x"04", x"c7", x"23", x"c3", x"18", x"96", x"05", x"9a",
        x"07", x"12", x"80", x"e2", x"eb", x"27", x"b2", x"75",
        x"09", x"83", x"2c", x"1a", x"1b", x"6e", x"5a", x"a0",
        x"52", x"3b", x"d6", x"b3", x"29", x"e3", x"2f", x"84",
        x"53", x"d1", x"00", x"ed", x"20", x"fc", x"b1", x"5b",
        x"6a", x"cb", x"be", x"39", x"4a", x"4c", x"58", x"cf",
        x"d0", x"ef", x"aa", x"fb", x"43", x"4d", x"33", x"85",
        x"45", x"f9", x"02", x"7f", x"50", x"3c", x"9f", x"a8",
        x"51", x"a3", x"40", x"8f", x"92", x"9d", x"38", x"f5",
        x"bc", x"b6", x"da", x"21", x"10", x"ff", x"f3", x"d2",
        x"cd", x"0c", x"13", x"ec", x"5f", x"97", x"44", x"17",
        x"c4", x"a7", x"7e", x"3d", x"64", x"5d", x"19", x"73",
        x"60", x"81", x"4f", x"dc", x"22", x"2a", x"90", x"88",
        x"46", x"ee", x"b8", x"14", x"de", x"5e", x"0b", x"db",
        x"e0", x"32", x"3a", x"0a", x"49", x"06", x"24", x"5c",
        x"c2", x"d3", x"ac", x"62", x"91", x"95", x"e4", x"79",
        x"e7", x"c8", x"37", x"6d", x"8d", x"d5", x"4e", x"a9",
        x"6c", x"56", x"f4", x"ea", x"65", x"7a", x"ae", x"08",
        x"ba", x"78", x"25", x"2e", x"1c", x"a6", x"b4", x"c6",
        x"e8", x"dd", x"74", x"1f", x"4b", x"bd", x"8b", x"8a",
        x"70", x"3e", x"b5", x"66", x"48", x"03", x"f6", x"0e",
        x"61", x"35", x"57", x"b9", x"86", x"c1", x"1d", x"9e",
        x"e1", x"f8", x"98", x"11", x"69", x"d9", x"8e", x"94",
        x"9b", x"1e", x"87", x"e9", x"ce", x"55", x"28", x"df",
        x"8c", x"a1", x"89", x"0d", x"bf", x"e6", x"42", x"68",
        x"41", x"99", x"2d", x"0f", x"b0", x"54", x"bb", x"16"
    );
    
    begin
        return SBOX(to_integer(unsigned(one_byte)));
    end function;

    type round_key is array(0 to 43) of std_logic_vector(0 to 31);
    signal round_keys:round_key:=(others=>(others=>'0'));
    
    type rcj_arr is array(0 to 10) of std_logic_vector(0 to 7);
    
    function g_func(word:std_logic_vector(0 to 31);round:integer:=0)
    return std_logic_vector is
        variable temp_vec:std_logic_vector(0 to 31);
        variable b0:std_logic_vector(0 to 7);
        constant rc_arr:rcj_arr:=(x"00",x"01", x"02", x"04", x"08", x"10",x"20", x"40", x"80", x"1b", x"36");
    begin
        --left shift
        b0:=word(0 to 7);
        temp_vec(0 to 23):=word(8 to 31);
        temp_vec(24 to 31):=b0;
        
        --s box substitution
        temp_vec(0 to 7):=s_box(temp_vec(0 to 7));
        temp_vec(8 to 15):=s_box(temp_vec(8 to 15));
        temp_vec(16 to 23):=s_box(temp_vec(16 to 23));
        temp_vec(24 to 31):=s_box(temp_vec(24 to 31));
       
        --xor with rc
        temp_vec(0 to 7):=temp_vec(0 to 7) xor rc_arr(round);
        return temp_vec;
    end function;
    
    
    
    type row_type is array(0 to 3) of std_logic_vector(0 to 7);
    type byte_matrix is array(0 to 3) of row_type;
    
    function bytes_to_matrix(flat : std_logic_vector(0 to 127))
        return byte_matrix is
        variable m   : byte_matrix;
        variable idx : integer;
    begin
        for col in 0 to 3 loop
            for row in 0 to 3 loop
                idx := (col*4 + row) * 8;
                m(row)(col) := flat(idx to idx+7);
            end loop;
        end loop;
        return m;
    end function;
    
    function matrix_to_bytes(m : byte_matrix) return std_logic_vector is
        variable flat : std_logic_vector(0 to 127);
        variable idx  : integer;
    begin
        for col in 0 to 3 loop
            for row in 0 to 3 loop
                idx := (col*4 + row) * 8;
                flat(idx to idx+7) := m(row)(col);
            end loop;
        end loop;
        return flat;
    end function;
    
    function xtime(b : std_logic_vector(0 to 7)) return std_logic_vector is
        variable shifted : std_logic_vector(0 to 7);
    begin
        shifted := b(1 to 7) & "0";          -- shift left by 1
        if b(0) = '1' then                    -- MSB was 1 overflow, reduce
            shifted := shifted xor x"1b";
        end if;
        return shifted;
    end function;
    
    function mul3(b : std_logic_vector(0 to 7)) return std_logic_vector is
    begin
        return xtime(b) xor b;
    end function;
    
    function mix_columns(c_state : byte_matrix) return byte_matrix is
        variable new_state : byte_matrix;
        variable a, b, c, d : std_logic_vector(0 to 7);
    begin
        for col in 0 to 3 loop
            a := c_state(0)(col);
            b := c_state(1)(col);
            c := c_state(2)(col);
            d := c_state(3)(col);
    
            new_state(0)(col) := xtime(a) xor mul3(b) xor c xor d;
            new_state(1)(col) := a xor xtime(b) xor mul3(c) xor d;
            new_state(2)(col) := a xor b xor xtime(c) xor mul3(d);
            new_state(3)(col) := mul3(a) xor b xor c xor xtime(d);
        end loop;
    
        return new_state;
    end function;
    
    function aes_round(data_in : std_logic_vector(0 to 127);
                       round_key : std_logic_vector(0 to 127);
                       is_last_round : boolean)
        return std_logic_vector is
        variable temp_result : std_logic_vector(0 to 127);
        variable temp_matrix : byte_matrix;
    begin
        temp_result := data_in;
    
        -- SubBytes
        for k in 0 to 15 loop
            temp_result(8*k to 8*k+7) := s_box(temp_result(8*k to 8*k+7));
        end loop;
    
        -- ShiftRows
        temp_matrix := bytes_to_matrix(temp_result);
        temp_matrix(1) := temp_matrix(1)(1 to 3) & temp_matrix(1)(0 to 0);
        temp_matrix(2) := temp_matrix(2)(2 to 3) & temp_matrix(2)(0 to 1);
        temp_matrix(3) := temp_matrix(3)(3 to 3) & temp_matrix(3)(0 to 2);
    
        -- MixColumns (skipped on the final round)
        if not is_last_round then
            temp_matrix := mix_columns(temp_matrix);
        end if;
    
        -- AddRoundKey
        temp_result := matrix_to_bytes(temp_matrix);
        temp_result := temp_result xor round_key;
    
        return temp_result;
    end function;
    
    type pipe_stage is record
        data  : std_logic_vector(0 to 127);
        valid : std_logic;
    end record;

    type pipe_array is array(0 to 10) of pipe_stage;

    signal pipe_reg : pipe_array := (others => (data => (others => '0'), valid => '0'));
    
    -- combinational: what SHOULD go into pipe_reg(0) next cycle
    signal stage0_data  : std_logic_vector(0 to 127);
    signal stage0_valid : std_logic;


begin
    
    --PROCESS WHICH GENERATES THE ROUND KEY MATRIX
    create_roundkeys:process(key)
        variable rk : round_key;
        begin
            rk(0) := key(0 to 31);
            rk(1) := key(32 to 63);
            rk(2) := key(64 to 95);
            rk(3) := key(96 to 127);
    
        for i in 1 to 10 loop
            rk(4*i)   := rk(4*i-4) xor g_func(rk(4*i-1), i);
            rk(4*i+1) := rk(4*i)   xor rk(4*i-3);
            rk(4*i+2) := rk(4*i+1) xor rk(4*i-2);
            rk(4*i+3) := rk(4*i+2) xor rk(4*i-1);
        end loop;
    
        round_keys <= rk;
        
    end process;
    
    stage0_data  <= text_in xor (round_keys(0) & round_keys(1) & round_keys(2) & round_keys(3));
    stage0_valid <= start;
    
    pipeline_proc : process(clk)
        begin
            if rising_edge(clk) then
        
                -- stage 0 loads from outside the pipe
                pipe_reg(0).data  <= stage0_data;
                pipe_reg(0).valid <= stage0_valid;
        
                -- stages 1->10 each pull from the stage behind them
                for n in 1 to 10 loop
                    pipe_reg(n).data  <= aes_round(pipe_reg(n-1).data,
                                                    round_keys(4*n) & round_keys(4*n+1) & round_keys(4*n+2) & round_keys(4*n+3),
                                                    n = 10);
                    pipe_reg(n).valid <= pipe_reg(n-1).valid;
                end loop;

         end if;
    end process;
    
    encrypted_text <= pipe_reg(10).data;
    done_out       <= pipe_reg(10).valid;
end Behavioral;
