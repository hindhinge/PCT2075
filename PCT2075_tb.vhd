--Rados³aw Sawicki
--253153
--PCT2075 testbench
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
 
ENTITY PCT2075_tb IS
END PCT2075_tb;
 
ARCHITECTURE behavior OF PCT2075_tb IS 
 
    COMPONENT PCT2075
    PORT(
			SDA: INOUT std_logic;
         TEMP : IN  std_logic_vector(15 downto 0);
         SCL : IN std_logic;
         A0 : IN  std_logic;
         A1 : IN  std_logic;
         A2 : IN  std_logic;
         OS : OUT  std_logic
        );
    END COMPONENT;
    

   signal temp : std_logic_vector(15 downto 0) := (others => '0');
   signal a0 : std_logic := '0';
   signal a1 : std_logic := '0';
   signal a2 : std_logic := '0';
	
	signal sda: std_logic;
   signal scl : std_logic;
	
   signal os : std_logic;
 
   constant clk_period : time := 10 ns;
 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   uut: PCT2075 PORT MAP (
			 SDA => sda,
          TEMP => temp,
          SCL => scl,
          A0 => a0,
          A1 => a1,
          A2 => a2,
          OS => os
        );

   -- Clock process definitions
   scl_process :process
   begin
		scl<= '1';
		wait for clk_period/2;
		scl <= '0';
		wait for clk_period/2;
   end process;
 

   stim_proc: process
   begin
		----------CONFIG ON STARTUP---------
		temp <= "1010100101010100";
		a0<='0';
		a1<='1';
		a2<='0';
		----------WRITE TO REGISTER---------
		SDA <='1'; --idle
		wait for clk_period/4;
		SDA <='0'; --start 
		wait for clk_period/3;
		SDA <= '1'; --addr6
		wait for clk_period;
		SDA <= '0'; --addr5
		wait for clk_period;
		SDA <= '0'; --addr4
		wait for clk_period;
		SDA <= '1'; --addr3
		wait for clk_period;
		SDA <= '0';--addr2
		wait for clk_period;
		SDA <= '1';--addr1
		wait for clk_period;
		SDA <= '0';--addr0
		wait for clk_period;
		SDA <= '0';--write
		wait for clk_period;
		SDA <= '1';--acks
		wait for clk_period;
		SDA <= '0';--pointer 7
		wait for clk_period;
		SDA <= '0';--pointer 6
		wait for clk_period;
		SDA <= '0';--pointer 5
		wait for clk_period;
		SDA <= '0';--pointer 4
		wait for clk_period;
		SDA <= '0';--pointer 3
		wait for clk_period;
		SDA <= '0';--pointer 2
		wait for clk_period;
		SDA <= '1';--pointer 1
		wait for clk_period;
		SDA <= '1';--pointer 0
		wait for clk_period;
		SDA <= '1';
		wait for clk_period; --acks
		SDA <='1';
		wait for clk_period/10;
		SDA <='0'; --config 7
		wait for clk_period/10;
		SDA <= not SDA;        ------------------------tutaj dziej¹ siê chocki klocki bo je¿eli chcemy zapisaæ coœ do rejestru po ACK nie mo¿e byæ repeated start
		wait for clk_period/10;		------------------------chwilowe dwie inwersje zapewniaj¹ zmianê sgna³u przy SCL = 0 i automat wie ¿e zapisujemy a nie odczytujemy.
		SDA <= not SDA;
		wait for clk_period/10;
		wait for clk_period/5;
		wait for clk_period/5;
		wait for clk_period/5;
		SDA <= '1'; --config 6
		wait for clk_period;
		SDA <= '0'; --config 5
		wait for clk_period;
		SDA <= '0'; --config 4
		wait for clk_period;
		SDA <= '1'; --config 3
		wait for clk_period;
		SDA <= '0'; --config 2
		wait for clk_period;
		SDA <= '1'; --config 1
		wait for clk_period;
		SDA <= '0'; --config 0
		wait for clk_period*2; -- acks
		SDA <='1'; --config 7
		wait for clk_period;
		SDA <='0'; --config 6
		wait for clk_period;
		SDA <='1'; --config 5
		wait for clk_period;
		SDA <='0'; --config 4
		wait for clk_period;
		SDA <='1'; --config 3
		wait for clk_period;
		SDA <='0'; --config 2
		wait for clk_period;
		SDA <='1'; --config 1
		wait for clk_period;
		SDA <='0'; --config 0
		wait for clk_period*2; --acks
		wait for clk_period/2;
		SDA <='1';
		wait for clk_period;
		-------------------------READ TEMPERATURE-----------------
		SDA <='0'; --start 
		wait for clk_period/3;
		SDA <= '1'; --addr6
		wait for clk_period;
		SDA <= '0'; --addr5
		wait for clk_period;
		SDA <= '0'; --addr4
		wait for clk_period;
		SDA <= '1'; --addr3
		wait for clk_period;
		SDA <= '0';--addr2
		wait for clk_period;
		SDA <= '1';--addr1
		wait for clk_period;
		SDA <= '0';--addr0
		wait for clk_period;
		SDA <= '0';--write
		wait for clk_period;
		SDA <= '1';--acks
		wait for clk_period;
		SDA <= '0';--pointer 7
		wait for clk_period;
		SDA <= '0';--pointer 6
		wait for clk_period;
		SDA <= '0';--pointer 5
		wait for clk_period;
		SDA <= '0';--pointer 4
		wait for clk_period;
		SDA <= '0';--pointer 3
		wait for clk_period;
		SDA <= '0';--pointer 2
		wait for clk_period;
		SDA <= '1';--pointer 1
		wait for clk_period;
		SDA <= '1';--pointer 0
		wait for clk_period;
		SDA <= '1';
		wait for clk_period; --acks
		wait for clk_period;
		SDA <= '0'; --restart
      wait for clk_period/2;
		SDA <= '1'; -- addr6
		wait for clk_period;
		SDA <= '0'; --addr5
		wait for clk_period;
		SDA <= '0'; --addr4
		wait for clk_period;
		SDA <= '1'; --addr3
		wait for clk_period;
		SDA <= '0';--addr2
		wait for clk_period;
		SDA <= '1';--addr1
		wait for clk_period;
		SDA <= '0';--addr0
		wait for clk_period;
		SDA <= '1';--read
		wait for clk_period;
		SDA <= 'Z';
		wait for clk_period; --acks
		wait for clk_period*8; --send8 msb
		SDA <= '0'; --ackm
		wait for clk_period;
		SDA <= 'Z';
		wait for clk_period*8; --send8 lsb
		SDA <= '0';
		wait for clk_period; --noack master
		SDA <= '0';
		wait for clk_period/2; --stop
		SDA <= '1';
		wait for clk_period;
		assert false severity failure;
   end process stim_proc;

END behavior;
