-- TIMER.VHD (a peripheral module for SCOMP)
-- 2003.04.24
--
-- Timer returns a 16 bit counter value with a resolution of the CLOCK period.
-- Writing any value to timer resets to 0x0000, but the timer continues to run.
-- The counter value rolls over to 0x0000 after a clock tick at 0xFFFF.

LIBRARY IEEE;

USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;


ENTITY CTIMER IS
  PORT(CLOCK,
       RESETN,
       CS       : IN  STD_LOGIC;
       IO_DATA  : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
       INT      : OUT STD_LOGIC );
END CTIMER;


ARCHITECTURE a OF CTIMER IS
  SIGNAL COUNT   : STD_LOGIC_VECTOR(15 DOWNTO 0);
  SIGNAL TRIGVAL : STD_LOGIC_VECTOR(15 DOWNTO 0);

  BEGIN
    -- Use value from SCOMP as trigger value
	PROCESS (CS, RESETN)
      BEGIN
        IF RESETN = '0' THEN
          TRIGVAL <= x"0000";
        ELSIF RISING_EDGE(CS) THEN
          TRIGVAL <= IO_DATA;
        END IF;
    END PROCESS;
    
    -- Count up until reaching trigger value, then reset.
    PROCESS (CLOCK, RESETN, CS)
      BEGIN
        IF (RESETN = '0') OR (CS = '1') THEN
          COUNT <= x"0000";
        ELSIF (FALLING_EDGE(CLOCK)) THEN
          IF TRIGVAL = x"0000" THEN
            INT <= '0';
          ELSIF COUNT = TRIGVAL THEN
            COUNT <= x"0001";
            INT <= '1';
          ELSE
            COUNT <= COUNT + 1;
            INT <= '0';
          END IF;
        END IF;
      END PROCESS;
  END a;

