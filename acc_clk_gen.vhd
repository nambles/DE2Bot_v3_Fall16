LIBRARY IEEE;
USE  IEEE.STD_LOGIC_1164.all;
USE  IEEE.STD_LOGIC_ARITH.all;
USE  IEEE.STD_LOGIC_UNSIGNED.all;

-- This is an improved version of the ACC_CLK_GEN provided for Lab 8.

ENTITY ACC_CLK_GEN IS

	PORT
	(
		clock_25Mhz      : IN  STD_LOGIC;
		clock_12500KHz   : OUT STD_LOGIC;
		clock_400KHz     : OUT STD_LOGIC;
		clock_170KHz     : OUT STD_LOGIC;
		clock_10KHz      : OUT STD_LOGIC;
		clock_100Hz      : OUT STD_LOGIC;
		clock_32Hz       : OUT STD_LOGIC;
		clock_10Hz       : OUT STD_LOGIC;
		clock_4Hz        : OUT STD_LOGIC
	);
	
END ACC_CLK_GEN;

ARCHITECTURE a OF ACC_CLK_GEN IS

	SIGNAL count_400Khz     : INTEGER RANGE 0 TO 12500000/400000; 
	SIGNAL count_170Khz     : INTEGER RANGE 0 TO 12500000/170000; 
	SIGNAL count_10Khz      : INTEGER RANGE 0 TO 12500000/10000; 
	SIGNAL count_100hz      : INTEGER RANGE 0 TO 12500000/100;
	SIGNAL count_32hz       : INTEGER RANGE 0 TO 12500000/32; 
	SIGNAL count_10hz       : INTEGER RANGE 0 TO 12500000/10; 
	SIGNAL count_4hz        : INTEGER RANGE 0 TO 12500000/4; 
	
	SIGNAL clock_12500KHz_int : STD_LOGIC; 
	SIGNAL clock_400Khz_int : STD_LOGIC; 
	SIGNAL clock_170Khz_int : STD_LOGIC; 
	SIGNAL clock_10Khz_int  : STD_LOGIC; 
	SIGNAL clock_100hz_int  : STD_LOGIC;
	SIGNAL clock_32hz_int   : STD_LOGIC; 
	SIGNAL clock_10hz_int   : STD_LOGIC; 
	SIGNAL clock_4hz_int    : STD_LOGIC; 
	
BEGIN
	PROCESS 
	BEGIN
	WAIT UNTIL RISING_EDGE(clock_25Mhz);
	
		clock_12500KHz <= clock_12500KHz_int;
		clock_400Khz <= clock_400Khz_int;
		clock_170Khz <= clock_170Khz_int;
		clock_10Khz <= clock_10Khz_int;
		clock_100hz <= clock_100hz_int;
		clock_32hz  <= clock_32hz_int;
		clock_10hz  <= clock_10hz_int;
		clock_4hz  <= clock_4hz_int;

		clock_12500KHz_int <= NOT(clock_12500KHz_int);
	--
		IF count_400Khz < (12500000/400000-1) THEN
			count_400Khz <= count_400Khz + 1;
		ELSE
			count_400Khz <= 0;
			clock_400Khz_int <= NOT(clock_400Khz_int);
		END IF;	
	--
		IF count_170Khz < (12500000/170000-1) THEN
			count_170Khz <= count_170Khz + 1;
		ELSE
			count_170Khz <= 0;
			clock_170Khz_int <= NOT(clock_170Khz_int);
		END IF;	
	--
		IF count_10Khz < (12500000/10000-1) THEN
			count_10Khz <= count_10Khz + 1;
		ELSE
			count_10Khz <= 0;
			clock_10Khz_int <= NOT(clock_10Khz_int);
		END IF;	
	--
		IF count_100hz < (12500000/100-1) THEN
			count_100hz <= count_100hz + 1;
		ELSE
			count_100hz <= 0;
			clock_100hz_int <= NOT(clock_100hz_int);
		END IF;	
	--
		IF count_32hz < (12500000/32-1) THEN
			count_32hz <= count_32hz + 1;
		ELSE
			count_32hz <= 0;
			clock_32hz_int <= NOT(clock_32hz_int);
		END IF;
	--
		IF count_10hz < (12500000/10-1) THEN
			count_10hz <= count_10hz + 1;
		ELSE
			count_10hz <= 0;
			clock_10hz_int <= NOT(clock_10hz_int);
		END IF;
	--
		IF count_4hz < (12500000/4-1) THEN
			count_4hz <= count_4hz + 1;
		ELSE
			count_4hz <= 0;
			clock_4hz_int <= NOT(clock_4hz_int);
		END IF;
	--
		
	END PROCESS;	
END a;

