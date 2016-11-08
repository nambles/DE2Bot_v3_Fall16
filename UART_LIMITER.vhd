LIBRARY IEEE;

USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;


ENTITY UART_LIMITER IS
	PORT(
		CLOCK    : IN  STD_LOGIC;
		RESET    : IN  STD_LOGIC;
		WR_REQ   : IN  STD_LOGIC;
		INHIBIT  : OUT STD_LOGIC
	);
END UART_LIMITER;

ARCHITECTURE a OF UART_LIMITER IS
	signal packet_time : integer range 0 to 2000;
	signal byte_time   : integer range 0 to 14;
	signal byte_count  : integer range 0 to 9;
	signal last_count  : integer range 0 to 9;
	signal running     : std_logic;
	signal inhibit_int : std_logic;
	signal inhibit_bt  : std_logic;
	signal inhibit_bc  : std_logic;
	
	constant limit_ot  : integer := 4900; -- repeat rate of packets
	constant limit_bt  : integer := 2; -- all bytes within this time of eachother
	constant limit_bc  : integer := 33; -- limit of number of bytes
BEGIN

	-- If the byte count or timing is exceeded, the
	-- inhibit signal will precent further bytes from
	-- being sent through the UART.
	inhibit_int <= inhibit_bt OR inhibit_bc;
	process(inhibit_int, running)
	begin
		if running = '0' then
			INHIBIT <= '0';
		elsif rising_edge(inhibit_int) then
			INHIBIT <= '1';
		end if;
	end process;
	
	-- Start tracking information on first write.
	process(RESET, WR_REQ, packet_time)
	begin
		if (RESET='1') or (packet_time > limit_ot) then
			running <= '0';
		elsif rising_edge(WR_REQ) then
			running <= '1';
		end if;
	end process;

	-- Time entire packet.
	-- Once started, this timer will not reset until it reaches the
	-- allowed re-send time.  The other parameters are tracked only
	-- while this timer is running.
	process(CLOCK, RESET, running)
	begin
		if (RESET = '1') or (running='0') then
			packet_time <= 0;
		elsif rising_edge(CLOCK) then
			packet_time <= packet_time+1;
		end if;
	end process;
	
	-- Time each byte.
	-- Each byte must be received within a certain time in order for the
	-- serial module to include them all in the same packet.
	process(RESET, CLOCK, running, WR_REQ)
	begin
		if (RESET = '1') or (running='0') or (WR_REQ='1') then
			byte_time <= 0;
			inhibit_bt <= '0';
		elsif rising_edge(CLOCK) then
			byte_time <= byte_time+1;
			if byte_time >= limit_bt then
				inhibit_bt <= '1';
			end if;
		end if;
	end process;

	
	-- Count the number of bytes written.
	-- Only a certain number of bytes can be sent in order
	-- to keep packet size down.
	process(running, WR_REQ)
	begin
		if running = '0' then
			byte_count <= 0;
			inhibit_bc <= '0';
		elsif falling_edge(WR_REQ) then
			byte_count <= byte_count + 1;
			if byte_count > limit_bc then
				inhibit_bc <= '1';
			end if;
		end if;
	end process;

end architecture;
