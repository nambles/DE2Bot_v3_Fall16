LIBRARY IEEE;
LIBRARY ALTERA_MF;
LIBRARY LPM;

USE ALTERA_MF.ALTERA_MF_COMPONENTS.ALL;
USE LPM.LPM_COMPONENTS.ALL;

USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;


ENTITY DAC_BEEP IS
	PORT(
		RESETN    : IN  STD_LOGIC;
		FSEL   : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
		DURATION    : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
		CS : IN STD_LOGIC;
		CLK_32Hz : IN STD_LOGIC;
		DAC_WCLK : IN STD_LOGIC;
		DAC_BCLK : IN STD_LOGIC;
		DAC_DAT : OUT STD_LOGIC
	);
END DAC_BEEP;

ARCHITECTURE a OF DAC_BEEP IS
	signal timer : std_logic_vector(15 downto 0);
	signal phase : std_logic_vector(15 downto 0);
	signal step : std_logic_vector(7 downto 0);
	signal sounddata : std_logic_vector(15 downto 0);
	
	BEGIN
	
	-- ROM to hold the waveform
	SOUND_LUT : altsyncram
	GENERIC MAP (
		lpm_type => "altsyncram",
		width_a => 16,
		numwords_a => 512,
		widthad_a => 9,
		init_file => "SOUND.mif",
		intended_device_family => "Cyclone II",
		lpm_hint => "ENABLE_RUNTIME_MOD=NO",
		operation_mode => "ROM",
		outdata_aclr_a => "NONE",
		outdata_reg_a => "UNREGISTERED",
		power_up_uninitialized => "FALSE"
	)
	PORT MAP (
		clock0 => NOT(DAC_WCLK),
		address_a => phase(10 DOWNTO 2), -- input is angle
		q_a => sounddata -- output is amplitude
	);

	-- shift register to serialize the data to the DAC
	DAC_SHIFT : lpm_shiftreg
	GENERIC MAP (
		lpm_direction => "LEFT",
		lpm_type => "LPM_SHIFTREG",
		lpm_width => 32
	)
	PORT MAP (
		load => DAC_WCLK,
		clock => NOT(DAC_BCLK),
		data => sounddata & sounddata,
		shiftout => DAC_DAT
	);

	-- process to perform DDS
	PROCESS(RESETN, CS) BEGIN
		IF RESETN = '0' THEN
			phase <= x"0000";
		ELSIF RISING_EDGE(DAC_WCLK) THEN
			IF step = x"00" THEN
				phase <= x"0000";
			ELSE
				phase <= phase + step; -- increment the phase
			END IF;
		END IF;
	END PROCESS;
	
	-- process to catch data from SCOMP and run the timer
	PROCESS(RESETN, CS, CLK_32Hz) BEGIN
		IF RESETN = '0' THEN
			timer <= x"0000";
			step <= x"00";
		ELSIF CS = '1' THEN
			timer <= ("000000"&DURATION&"00")-1; -- -1 so that 0 is infinite
			step <= FSEL;
		ELSIF RISING_EDGE(CLK_32Hz) THEN
			IF timer /= x"FFFF" THEN
				timer <= timer - 1;
				IF timer = x"0000" THEN
					step <= x"00";
				END IF;
			END IF;
		END IF;
	END PROCESS;

			
END a;






