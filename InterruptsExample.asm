; InterruptsExample.asm
; Created by Kevin Johnson
; (no copyright applied; edit freely, no attribution necessary)
; This program does basic initialization of the DE2Bot
; and provides an example of SCOMP's interrupt system.

; Section labels are for clarity only.


;***************************************************************
;* Jump Table
;***************************************************************
; When an interrupt occurs, execution is redirected to one of
; these addresses (depending on the interrupt source), which
; need to either contain RETI (return from interrupt) if not
; used, or a JUMP instruction to the desired interrupt service
; routine (ISR).  The first location is the reset vector, and
; should be a JUMP instruction to the beginning of your normal
; code.
ORG        &H000       ; Jump table is located in mem 0-4
	JUMP   Init        ; Reset vector
	JUMP   Sonar_ISR   ; Sonar interrupt
	JUMP   CTimer_ISR  ; Timer interrupt
	RETI               ; UART interrupt (unused here)
	JUMP   Stall_ISR   ; Motor stall interrupt
;***************************************************************
;* Initialization
;***************************************************************
Init:
	; Always a good idea to make sure the robot
	; stops in the event of a reset.
	LOAD   Zero
	OUT    LVELCMD     ; Stop motors
	OUT    RVELCMD
	OUT    SONAREN     ; Disable sonar (optional)
	
	CALL   SetupI2C    ; Configure the I2C to read the battery voltage
	CALL   BattCheck   ; Get battery voltage (and end if too low).
	OUT    LCD         ; Display batt voltage on LCD

WaitForSafety:         ; Wait for safety switch to be toggled
	IN     XIO         ; XIO contains SAFETY signal
	AND    Mask4       ; SAFETY signal is bit 4
	JPOS   WaitForUser ; If ready, jump to wait for PB3
	IN     TIMER       ; We'll use the timer value to
	AND    Mask1       ;  blink LED17 as a reminder to toggle SW17
	SHIFT  8           ; Shift over to LED17
	OUT    XLEDS       ; LED17 blinks at 2.5Hz (10Hz/4)
	JUMP   WaitForSafety
	
WaitForUser:           ; Wait for user to press PB3
	IN     TIMER       ; We'll blink the LEDs above PB3
	AND    Mask1
	SHIFT  5           ; Both LEDG6 and LEDG7
	STORE  Temp        ; (overkill, but looks nice)
	SHIFT  1
	OR     Temp
	OUT    XLEDS
	IN     XIO         ; XIO contains KEYs
	AND    Mask2       ; KEY3 mask (KEY0 is reset and can't be read)
	JPOS   WaitForUser ; not ready (KEYs are active-low, hence JPOS)
	LOAD   Zero
	OUT    XLEDS       ; clear LEDs once ready to continue

;***************************************************************
;* Main code
;***************************************************************
Main: ; "Real" program starts here.
	OUT    RESETPOS    ; reset odometry in case wheels moved after programming	

; This code (as a whole) will use Sonar0 and Sonar5 to turn
; the robot away from whichever sonar detects an object within 1ft.
; As long as a sonar remains triggered, the robot will keep turning
; away from it, effectively making it end up facing away from the
; last thing it 'saw'.
Config:
	LOAD   Zero
	STORE  DesTheta    ; reset the variables
	STORE  TCount
	STORE  SonCount
	
	LOADI  &B100001
	OUT    SONAREN     ; turn on sonars 0 and 5
	LOADI  254
	OUT    SONALARM    ; set alarm distance to 254mm
	
	LOADI  5
	OUT    CTIMER      ; configure timer for 0.01*5=0.05s interrupts
	
	SEI    &B1011      ; enable the desired interrupts
	
InfLoop:
	; everything will be handled by interrupts, so the main
	; code just displays some values that are updated by
	; the ISRs.
	LOAD   TCount      ; The timer ISR increments this at 20Hz
	OUT    SSEG1
	LOAD   SonCount    ; The sonar ISR increments this each warning
	OUT    SSEG2
	JUMP   InfLoop


;***************************************************************
;* Interrupt Service Routines
;***************************************************************
CTimer_ISR:  ; Timer interrupt
; The timer interrupt will be used to turn the robot,
; correcting for turn rate, etc., at 20Hz.
	LOAD   TCount
	ADDI   1
	STORE  TCount
	
	IN     THETA       ; get current angle
	STORE  NowTheta    ; save for later use
	SUB    DesTheta    ; subtract desired angle
	CALL   Mod360      ; remove negative numbers
	ADDI   -180        ; test which semicircle error is in
	JPOS   NeedLeft    ; >180 means need left turn
	JUMP   NeedRight   ; otherwise, need right turn
NeedLeft:
	LOAD   DesTheta
	SUB    NowTheta    ; get the turn error
	CALL   Mod360      ; fix errors around 0
	SUB    DeadZone
	JNEG   NoTurn      ; stop moving if close
	ADD    DeadZone
	ADDI   -100        ; check if >100
	JNEG   TurnLeft
	LOAD   Zero        ; remove excess
TurnLeft:
	ADDI   100         ; replace the 100 from before
	SHIFT  2           ; multiply by 4
	OUT    RVELCMD     ; set right wheel forward
	XOR    NegOne
	ADDI   1           ; negate number
	OUT    LVELCMD     ; set left wheel backwards
	RETI               ; exit ISR
NeedRight:
	LOAD   NowTheta
	SUB    DesTheta    ; get the turn error
	CALL   Mod360      ; fix errors around 0
	SUB    DeadZone
	JNEG   NoTurn      ; stop moving if close
	ADD    DeadZone
	ADDI   -100        ; check if >100
	JNEG   TurnRight
	LOAD   Zero        ; remove excess
TurnRight:
	ADDI   100         ; replace the 100 from before
	SHIFT  2           ; multiply by 4
	OUT    LVELCMD     ; set left wheel forward
	XOR    NegOne
	ADDI   1           ; negate number
	OUT    RVELCMD     ; set left wheel backwards
	RETI               ; exit ISR
NoTurn:
	LOAD   Zero
	OUT    LVELCMD
	OUT    RVELCMD
	RETI
	
	NowTheta: DW 0
	DeadZone: DW 3
	TCount: DW 0

Sonar_ISR:   ; Sonar interrupt
; The sonar interrupt will update the "desired heading"
; variable according to which sonar caused the interrupt.
	LOAD   SonCount
	ADDI   1
	STORE  SonCount
	IN     SONALARM    ; get the alarm register
	AND    Mask05      ; keep only bits 0 and 5
	STORE  Temp
	JZERO  NoChange    ; nothing set, no turn
	XOR    Mask05      ; check for BOTH bits set
	JZERO  NoChange    ;  in which case, don't turn
	LOAD   Temp
	AND    Mask0       ; check for left sonar
	JPOS   SetLeft
	JUMP   SetRight    ; only remaining possibility is right
	Mask05: DW &B100001
NoChange:
	RETI               ; don't need to turn; just exit ISR
SetLeft:
	IN     THETA       ; get current angle
	SUB    TDist       ; set turn distance
	CALL   Mod360      ; calculate mod 360
	STORE  DesTheta    ; set the desired angle
	RETI               ; exit ISR
SetRight:
	IN     THETA       ; get current angle
	ADD    TDist       ; set turn distance
	CALL   Mod360      ; calculate mod 360
	STORE  DesTheta    ; set the desired angle
	RETI               ; exit ISR
	SonCount: DW 0
Stall_ISR:   ; Motor stall interrupt
	RETI
	TDist: DW 100

DesTheta: DW 0
	
;***************************************************************
;* Subroutines
;***************************************************************

; Subroutine to wait (block) for 1 second
Wait1:
	OUT    TIMER
Wloop:
	IN     TIMER
	OUT    XLEDS       ; User-feedback that a pause is occurring.
	ADDI   -10         ; 1 second in 10Hz.
	JNEG   Wloop
	RETURN

; Subroutine to wait the number of counts currently in AC
WaitAC:
	STORE  WaitTime
	OUT    Timer
WACLoop:
	IN     Timer
	OUT    XLEDS       ; User-feedback that a pause is occurring.
	SUB    WaitTime
	JNEG   WACLoop
	RETURN
	WaitTime: DW 0     ; "local" variable.

; Converts an angle to [0,359]
Mod360:
	JNEG   M360N       ; loop exit condition
	ADDI   -360        ; start removing 360 at a time
	JUMP   Mod360      ; keep going until negative
M360N:
	ADDI   360         ; get back to positive
	JNEG   M360N       ; (keep adding 360 until non-negative)
	RETURN
	
; This subroutine will get the battery voltage,
; and stop program execution if it is too low.
; SetupI2C must be executed prior to this.
BattCheck:
	CALL   GetBattLvl
	JZERO  BattCheck   ; A/D hasn't had time to initialize
	SUB    MinBatt
	JNEG   DeadBatt
	ADD    MinBatt     ; get original value back
	RETURN
; If the battery is too low, we want to make
; sure that the user realizes it...
DeadBatt:
	LOAD   Four
	OUT    BEEP        ; start beep sound
	CALL   GetBattLvl  ; get the battery level
	OUT    SSEG1       ; display it everywhere
	OUT    SSEG2
	OUT    LCD
	LOAD   Zero
	ADDI   -1          ; 0xFFFF
	OUT    LEDS        ; all LEDs on
	OUT    XLEDS
	CALL   Wait1       ; 1 second
	Load   Zero
	OUT    BEEP        ; stop beeping
	LOAD   Zero
	OUT    LEDS        ; LEDs off
	OUT    XLEDS
	CALL   Wait1       ; 1 second
	JUMP   DeadBatt    ; repeat forever
	
; Subroutine to read the A/D (battery voltage)
; Assumes that SetupI2C has been run
GetBattLvl:
	LOAD   I2CRCmd     ; 0x0190 (write 0B, read 1B, addr 0x90)
	OUT    I2C_CMD     ; to I2C_CMD
	OUT    I2C_RDY     ; start the communication
	CALL   BlockI2C    ; wait for it to finish
	IN     I2C_DATA    ; get the returned data
	RETURN

; Subroutine to configure the I2C for reading batt voltage
; Only needs to be done once after each reset.
SetupI2C:
	CALL   BlockI2C    ; wait for idle
	LOAD   I2CWCmd     ; 0x1190 (write 1B, read 1B, addr 0x90)
	OUT    I2C_CMD     ; to I2C_CMD register
	LOAD   Zero        ; 0x0000 (A/D port 0, no increment)
	OUT    I2C_DATA    ; to I2C_DATA register
	OUT    I2C_RDY     ; start the communication
	CALL   BlockI2C    ; wait for it to finish
	RETURN
	
; Subroutine to block until I2C device is idle
BlockI2C:
	LOAD   Zero
	STORE  Temp        ; Used to check for timeout
BI2CL:
	LOAD   Temp
	ADDI   1           ; this will result in ~0.1s timeout
	STORE  Temp
	JZERO  I2CError    ; Timeout occurred; error
	IN     I2C_RDY     ; Read busy signal
	JPOS   BI2CL       ; If not 0, try again
	RETURN             ; Else return
I2CError:
	LOAD   Zero
	ADDI   &H12C       ; "I2C"
	OUT    SSEG1
	OUT    SSEG2       ; display error message
	JUMP   I2CError


;***************************************************************
;* Variables
;***************************************************************
Temp:     DW 0 ; "Temp" is not a great name, but can be useful

;***************************************************************
;* Constants
;* (though there is nothing stopping you from writing to these)
;***************************************************************
NegOne:   DW -1
Zero:     DW 0
One:      DW 1
Two:      DW 2
Three:    DW 3
Four:     DW 4
Five:     DW 5
Six:      DW 6
Seven:    DW 7
Eight:    DW 8
Nine:     DW 9
Ten:      DW 10

; Some bit masks.
; Masks of multiple bits can be constructed by ORing these
; 1-bit masks together.
Mask0:    DW &B00000001
Mask1:    DW &B00000010
Mask2:    DW &B00000100
Mask3:    DW &B00001000
Mask4:    DW &B00010000
Mask5:    DW &B00100000
Mask6:    DW &B01000000
Mask7:    DW &B10000000
LowByte:  DW &HFF      ; binary 00000000 1111111
LowNibl:  DW &HF       ; 0000 0000 0000 1111

; some useful movement values
OneMeter: DW 961       ; ~1m in 1.05mm units
HalfMeter: DW 481      ; ~0.5m in 1.05mm units
TwoFeet:  DW 586       ; ~2ft in 1.05mm units
Deg90:    DW 90        ; 90 degrees in odometry units
Deg180:   DW 180       ; 180
Deg270:   DW 270       ; 270
Deg360:   DW 360       ; can never actually happen; for math only
FSlow:    DW 100       ; 100 is about the lowest velocity value that will move
RSlow:    DW -100
FMid:     DW 350       ; 350 is a medium speed
RMid:     DW -350
FFast:    DW 500       ; 500 is almost max speed (511 is max)
RFast:    DW -500

MinBatt:  DW 130       ; 13.0V - minimum safe battery voltage
I2CWCmd:  DW &H1190    ; write one i2c byte, read one byte, addr 0x90
I2CRCmd:  DW &H0190    ; write nothing, read one byte, addr 0x90

;***************************************************************
;* IO address space map
;***************************************************************
SWITCHES: EQU &H00  ; slide switches
LEDS:     EQU &H01  ; red LEDs
TIMER:    EQU &H02  ; timer, usually running at 10 Hz
XIO:      EQU &H03  ; pushbuttons and some misc. inputs
SSEG1:    EQU &H04  ; seven-segment display (4-digits only)
SSEG2:    EQU &H05  ; seven-segment display (4-digits only)
LCD:      EQU &H06  ; primitive 4-digit LCD display
XLEDS:    EQU &H07  ; Green LEDs (and Red LED16+17)
BEEP:     EQU &H0A  ; Control the beep
CTIMER:   EQU &H0C  ; Configurable timer for interrupts
LPOS:     EQU &H80  ; left wheel encoder position (read only)
LVEL:     EQU &H82  ; current left wheel velocity (read only)
LVELCMD:  EQU &H83  ; left wheel velocity command (write only)
RPOS:     EQU &H88  ; same values for right wheel...
RVEL:     EQU &H8A  ; ...
RVELCMD:  EQU &H8B  ; ...
I2C_CMD:  EQU &H90  ; I2C module's CMD register,
I2C_DATA: EQU &H91  ; ... DATA register,
I2C_RDY:  EQU &H92  ; ... and BUSY register
UART_DAT: EQU &H98  ; UART data
UART_RDY: EQU &H98  ; UART status
SONAR:    EQU &HA0  ; base address for more than 16 registers....
DIST0:    EQU &HA8  ; the eight sonar distance readings
DIST1:    EQU &HA9  ; ...
DIST2:    EQU &HAA  ; ...
DIST3:    EQU &HAB  ; ...
DIST4:    EQU &HAC  ; ...
DIST5:    EQU &HAD  ; ...
DIST6:    EQU &HAE  ; ...
DIST7:    EQU &HAF  ; ...
SONALARM: EQU &HB0  ; Write alarm distance; read alarm register
SONARINT: EQU &HB1  ; Write mask for sonar interrupts
SONAREN:  EQU &HB2  ; register to control which sonars are enabled
XPOS:     EQU &HC0  ; Current X-position (read only)
YPOS:     EQU &HC1  ; Y-position
THETA:    EQU &HC2  ; Current rotational position of robot (0-359)
RESETPOS: EQU &HC3  ; write anything here to reset odometry to 0
