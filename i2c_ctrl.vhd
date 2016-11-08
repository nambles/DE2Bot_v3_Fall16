-- Controller for the I2C master.
-- This is mostly a state machine used to control
-- the various muxes and registers used for the I2C
-- device.
-- Author: Kevin Johnson.  Last modified: 18 June 2014

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity i2c_ctrl is

	port(
		resetn          : in  std_logic;
		clk             : in  std_logic;
		IO_DATA         : in  std_logic_vector(15 downto 0);
		wr_rdy          : in  std_logic;
		wr_cmd          : in  std_logic;
		wr_data         : in  std_logic;
		rx_byte         : in  std_logic_vector(7 downto 0);
		i2c_busy        : in  std_logic;
		tx_addr         : out std_logic_vector(7 downto 0);
		tx_byte         : out std_logic_vector(7 downto 0);
		comm_en         : out std_logic;
		rnw             : out std_logic;
		data_out        : out std_logic_vector(15 downto 0);
		busy            : out std_logic
	);
	
end entity;

architecture main of i2c_ctrl is

	-- Build an enumerated type for the state machine
	type state_type is (idle, Tx2, Tx1p, Tx1, Rx2, Rx1p, Rx1);
	
	-- Register used to hold the current state
	signal state   : state_type;
	
	signal go      : std_logic;  -- tells state machine when to leave idle
	signal running : std_logic;  -- flag that communication is in progress
	signal prev_busy : std_logic;  -- previous value of i2c_busy
	signal cmd_in  : std_logic_vector(7 downto 0);
	signal addr_in : std_logic_vector(7 downto 0);
	signal data_in : std_logic_vector(15 downto 0);
	
begin

	-- latches for the cmd/data from SCOMP:
	latch_cmd_data : process (wr_cmd, wr_data, resetn)
	begin
		if (resetn = '0') then
			cmd_in <= x"00";
		elsif rising_edge(wr_cmd) then
			cmd_in <= IO_DATA(15 downto 8);
			addr_in <= IO_DATA(7 downto 0);
		end if;
		if (resetn = '0') then
			data_in <= x"0000";
		elsif rising_edge(wr_data) then
			data_in <= IO_DATA;
		end if;
	end process;

	-- This process handles the START signal, which
	-- is basically a DFF that gets set by wr_rdy, and reset
	-- by a signal from the other state machine.  The other
	-- state machine checks this to determine if it should start,
	-- and resets this once it has started.
	latch_rdy : process (wr_rdy, running, resetn)
	begin
		if (resetn = '0') OR (running = '1') then
			go <= '0';
		elsif rising_edge(wr_rdy) then
			go <= '1';
		end if;
	end process;
	
	busy <= running OR go;
	
	-- The main state machine
	state_machine : process (clk, resetn)
	begin
		if resetn = '0' then
			state <= idle;
			comm_en <= '0';
			running <= '0';

		elsif (rising_edge(clk)) then
			prev_busy <= i2c_busy;  -- used to detect transitions
			case state is
			
				when idle =>
					if go = '1' then -- this is the signal to start
						running <= '1';
						tx_addr <= addr_in;  -- set the I2C controller's address
						data_out(15 downto 0) <= x"0000"; -- clear data
						-- transition to the correct state according to cmd
						if cmd_in(5 downto 4) = "10" then -- two to send
							state <= Tx2;
							tx_byte <= data_in(15 downto 8);
							rnw <= '0';
						elsif cmd_in(5 downto 4) = "01" then -- one to send
							state <= Tx1p;
							tx_byte <= data_in(7 downto 0);
							rnw <= '0';
						elsif cmd_in(1 downto 0) = "10" then -- two to rx
							state <= Rx2;
							rnw <= '1';
						elsif cmd_in(1 downto 0) = "01" then -- one to rx
							state <= Rx1p;
							rnw <= '1';
						else -- invalid command
							state <= idle;
						end if;
					else -- not starting
						state <= idle;
						running <= '0'; -- no longer running
					end if;
						
				
				when Tx2 => 
					comm_en <= '1'; -- safe to start transaction
					if (prev_busy = '0') and (i2c_busy = '1') then -- busy just went high
						tx_byte <= data_in(7 downto 0); -- prepare next byte
					elsif (prev_busy = '1') and (i2c_busy = '0') then -- just went low
						state <= Tx1;
					end if;
					
				when Tx1p =>
					comm_en <= '1'; -- begin communication 
					state <= Tx1;
					
				when Tx1 => 
					if (prev_busy = '0') and (i2c_busy = '1') then -- busy just went high
						rnw <= '1'; -- prepare to read
						if cmd_in(1) = cmd_in(0) then -- probably 00 read, but also handles 11
							comm_en <= '0'; -- end communication
						end if;
					elsif (prev_busy = '1') and (i2c_busy = '0') then -- just went low
						if cmd_in(1 downto 0) = "10" then
							state <= Rx2;
						elsif cmd_in(1 downto 0) = "01" then
							state <= Rx1;
						else
							state <= idle;
						end if;
					end if;
					
				when Rx2 => 
					comm_en <= '1'; -- safe to start transaction
					if (prev_busy = '1') and (i2c_busy = '0') then -- just went low
						state <= Rx1;
						data_out(15 downto 8) <= rx_byte; -- store the rx'd byte
					end if;
				
				when Rx1p =>
					comm_en <= '1'; -- begin communication 
					state <= Rx1;
					
				when Rx1 => 
					if (prev_busy = '0') and (i2c_busy = '1') then -- busy just went high
						comm_en <= '0'; -- end communication
					elsif (prev_busy = '1') and (i2c_busy = '0') then -- just went low
						state <= idle;
						data_out(7 downto 0) <= rx_byte; -- store the rx'd byte
					end if;
					
					
				when others =>
					state <= idle;
					
			end case;
		end if;
	end process;

			
end main;
