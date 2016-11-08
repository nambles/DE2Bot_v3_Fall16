-- This file contains most of the vhdl necessary for an
-- SCOMP peripheral that performs dead reckoning odometry.
--
-- Specifically, it already contains:
--   Necessary input and output ports
--   Hardware and logic to interface with SCOMP's IO bus
--   Two look-up tables with values for SINE and COSINE
--   Two 16x16-bit multiplers
--   A synchronous process in which to update the odometry
--   Some registers to do math with
--   Some math
--
-- It needs:
--   Some additional registers (probably)
--   Additional math

LIBRARY IEEE;
LIBRARY ALTERA_MF;
LIBRARY LPM;

USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_SIGNED.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE ALTERA_MF.ALTERA_MF_COMPONENTS.ALL;
USE LPM.LPM_COMPONENTS.ALL;

ENTITY ODOMETRY IS
	PORT(
		CLOCK    : IN STD_LOGIC; -- determines the update frequency of the odometry
		RESETN   : IN STD_LOGIC; -- resets all internal registers
		IO_WRITE : IN STD_LOGIC; -- signal from SCOMP
		CSX, CSY, CST : IN   STD_LOGIC; -- chip-select for X, Y, and theta position
		ENC_LPOS : IN STD_LOGIC_VECTOR(15 DOWNTO 0); -- incoming wheel encoder position (absolute since reset)
		ENC_RPOS : IN STD_LOGIC_VECTOR(15 DOWNTO 0); -- incoming wheel encoder position (absolute since reset)
		IO_DATA  : INOUT STD_LOGIC_VECTOR(15 DOWNTO 0) -- SCOMP's IO bus lines
	);
END ODOMETRY;


ARCHITECTURE A OF ODOMETRY IS

	SIGNAL READ_REQ : STD_LOGIC; -- read request from SCOMP
	SIGNAL RPOS, LPOS : STD_LOGIC_VECTOR(15 DOWNTO 0); -- internal buffers for the encoder counts
	SIGNAL dU, lastSUM : STD_LOGIC_VECTOR(15 DOWNTO 0); -- register for math
	SIGNAL XPOS, YPOS : STD_LOGIC_VECTOR(31 DOWNTO 0); -- the X & Y positions kept internally
	SIGNAL THETA, SIN_THETA, COS_THETA : STD_LOGIC_VECTOR(15 DOWNTO 0); -- angle, and LUT outputs
	SIGNAL THETA360 : STD_LOGIC_VECTOR(19 DOWNTO 0); -- scaled theta value
	SIGNAL dUxSIN, dUxCOS : STD_LOGIC_VECTOR(31 DOWNTO 0); -- outputs of the mutipliers
	SIGNAL OUTSELECT : STD_LOGIC_VECTOR(2 DOWNTO 0); -- used to select the appropriate output data
	SIGNAL OUTDATA : STD_LOGIC_VECTOR(15 DOWNTO 0); -- register that SCOMP reads
	CONSTANT THETASCALE : STD_LOGIC_VECTOR(9 DOWNTO 0) := STD_LOGIC_VECTOR(TO_UNSIGNED(516,10));
	
BEGIN
	-- ALTSYNCRAM for look-up table (LUT).
	-- This RAM is set up as ROM; there is no way to write 
	-- to it, but it can be loaded with any data from a .MIF file.
	-- A MIF has been created with a table of fixed-point 
	-- SINE values.  See the file itself or supporting 
	-- documentation for more details.  Note that the input 
	-- does NOT have to be in degrees or radians; the division 
	-- of the circle is user-defined.
	-- This memory is synchronous, but here we clock it on the 
	-- falling edge of the clock so that the data changes between
	-- updates to the odometry (which is on the rising edges).
	SIN_LUT : altsyncram
	GENERIC MAP (
		lpm_type => "altsyncram",
		width_a => 16,
		numwords_a => 2048,
		widthad_a => 11,
		init_file => "SIN_table.mif",
		intended_device_family => "Cyclone II",
		lpm_hint => "ENABLE_RUNTIME_MOD=NO",
		operation_mode => "ROM",
		outdata_aclr_a => "NONE",
		outdata_reg_a => "UNREGISTERED",
		power_up_uninitialized => "FALSE"
	)
	PORT MAP (
		clock0 => NOT(CLOCK),
		address_a => THETA(10 DOWNTO 0), -- input is angle
		q_a => SIN_THETA -- output is sin(angle)
	);
	-- another LUT, for COSINE values
	COS_LUT : altsyncram
	GENERIC MAP (
		lpm_type => "altsyncram",
		width_a => 16,
		numwords_a => 2048,
		widthad_a => 11,
		init_file => "COS_table.mif",
		intended_device_family => "Cyclone II",
		lpm_hint => "ENABLE_RUNTIME_MOD=NO",
		operation_mode => "ROM",
		outdata_aclr_a => "NONE",
		outdata_reg_a => "UNREGISTERED",
		power_up_uninitialized => "FALSE"
	)
	PORT MAP (
		clock0 => NOT(CLOCK),
		address_a => THETA(10 DOWNTO 0), -- input is angle
		q_a => COS_THETA -- output is cos(angle)
	);

	-- LPM_MULT for multiplier.
	-- This is an asynchronous device: it multiplies the
	-- inputs together and provides an output after the 
	-- propagation delay of the internal gates.
	MULTIPLIERX: LPM_MULT
	GENERIC MAP(
		lpm_widthA => 16,
		lpm_widthB => 16,
		lpm_widthP => 32,
		lpm_representation => "SIGNED"
	)
	PORT MAP(
		dataA  => dU,
		dataB  => SIN_THETA,
		result => dUxSIN
	);
	-- Another multiplier.
	MULTIPLIERY: LPM_MULT
	GENERIC MAP(
		lpm_widthA => 16,
		lpm_widthB => 16,
		lpm_widthP => 32,
		lpm_representation => "SIGNED"
	)
	PORT MAP(
		dataA  => dU,
		dataB  => COS_THETA,
		result => dUxCOS
	);
	-- Multiplier to scale THETA
	MULTIPLIERT: LPM_MULT
	GENERIC MAP(
		lpm_hint => "INPUT_B_IS_CONSTANT=YES,MAXIMIZE_SPEED=5",
		lpm_representation => "UNSIGNED",
		lpm_type => "LPM_MULT",
		lpm_widtha => 10,
		lpm_widthb => 10,
		lpm_widthp => 20
	)
	PORT MAP(
		dataA  => THETA(10 DOWNTO 1),
		dataB  => THETASCALE,
		result => THETA360
	);
	
	-- LPM tri-state function to drive I/O bus
	IO_BUS: LPM_BUSTRI
	GENERIC MAP (
		lpm_width => 16
	)
	PORT MAP (
		data     => OUTDATA,  -- send this register
		enabledt => READ_REQ, -- when SCOMP requests data
		tridata  => IO_DATA
	);
	
	-- READ_REQ is asserted when SCOMP is requesting ANY data from us
	READ_REQ <= NOT(IO_WRITE) AND (CSX OR CSY OR CST);
	-- OUTSELECT is used to choose the output.
	OUTSELECT <= CSX & CSY & CST;
	
	-- Here we use OUTSELECT to output the appropriate data.
	-- Note that XPOS and YPOS are 32 bits, but the bus is 16 bits,
	-- so a subset must be taken.  It makes sense to ignore the
	-- fractional part of the number, which in this case is 10 bits.
	-- We should then drop another bit because we don't divide dU by two when
	-- it is calculated; however, leaving that extra bit results in units
	-- of 1.05mm, which is the same as the other robot posn/vel units.
	WITH OUTSELECT SELECT OUTDATA <=
		XPOS(26 DOWNTO 11) WHEN "100",
		YPOS(26 DOWNTO 11) WHEN "010",
		("000000"&THETA360(19 DOWNTO 10)) WHEN "001",
		x"0000" WHEN OTHERS;
		
	PROCESS (RESETN, CLOCK)
	BEGIN
		IF RESETN = '0' THEN -- reset all registers
			XPOS <= x"00000000";
			YPOS <= x"00000000";
			THETA <= x"0000";
			RPOS <= x"0000";
			LPOS <= x"0000";
			dU <= x"0000";
			lastSUM <= x"0000";
		ELSIF RISING_EDGE(CLOCK) THEN
			RPOS <= ENC_RPOS;
			LPOS <= ENC_LPOS;
			
			THETA <= STD_LOGIC_VECTOR(SIGNED(RPOS - LPOS) MOD 1428); -- will always be [0,1427]

			-- Add dU*COS(theta) to the previous XPOS, and similar with YPOS
			XPOS <= XPOS + dUxCOS;
			YPOS <= YPOS + dUxSIN;
			
			-- dU is the difference between last sum and current sum.  We don't bother
			-- dividing by two here.  We instead do it when returning the values to SCOMP.
			dU <= (LPOS + RPOS) - lastSUM;
			lastSUM <= (LPOS + RPOS);

		END IF;
	END PROCESS;
	
END A;
