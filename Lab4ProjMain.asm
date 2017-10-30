/******************************************************************************
* EE244 Lab 4
* Creates sinewave display on the Freedom Board's IO Shield LED array
* incorporating a user-inputted frequency.
* Brian Willis, 3/07/17
******************************************************************************/
                .syntax unified        /* define syntax */
                .cpu cortex-m4
                .fpu fpv4-sp-d16

                .globl main

/******************************** Addresses ********************************/
.equ SIM_SCGC5, 0x40048038				/* clock */

/* port C */
.equ GPIOC_PDIR, 0x400FF090				/* data in/out */
.equ PORTC_GPCLR, 0x4004B080			/* global pin assignment (GPIO) */
.equ GPIOC_PDDR, 0x400FF094				/* input vs. output  */

/* port D */
.equ GPIOD_PDOR, 0x400FF0C0
.equ PORTD_GPCLR, 0x4004C080
.equ GPIOD_PDDR, 0x400FF0D4

/* port B */
.equ GPIOB_PDOR, 0x400FF040
.equ PORTB_GPCLR, 0x4004A080
.equ PORTB_GPCHR, 0x4004A084
.equ GPIOB_PDDR, 0x400FF054


/******************************** Constants ********************************/
.equ CLOCK_DATA, 0x00001C00				/* clock on for ports B, C, D */

.equ PIN_ASS_C, 0x03FC0103				/* assign as GPIO */
.equ IO_DATA_SWITCH, 0x00000000			/* set as inputs */

.equ PIN_ASS_D, 0x1C0100
.equ IO_DATA_LED_D, 0x1C

.equ PIN_ASS_B_LOW, 0x30100
.equ PIN_ASS_B_HIGH, 0xD0100
.equ IO_DATA_LED_B, 0xD0003

/***************************** Useful Equates *****************************/
.equ ALL_BITS_SET, 0xFFFFFFFF
.equ SWITCHES_OFF, 0xFF					/* value SwArrayRead will return if all switches are off */

.equ LED_0_CHECK, 0x2000				/* values sine table value must be less than to turn on specific LED */
.equ LED_1_CHECK, 0x4000
.equ LED_2_CHECK, 0x6000
.equ LED_3_CHECK, 0x8000
.equ LED_4_CHECK, 0xA000
.equ LED_5_CHECK, 0xC000
.equ LED_6_CHECK, 0xE000

.equ LED_0, 0x1B						/* value to load into LED port to light LED */
.equ LED_1, 0x17
.equ LED_2, 0xF
.equ LED_3, 0xFFFFE
.equ LED_4, 0xFFFFD
.equ LED_5, 0xEFFFF
.equ LED_6, 0xBFFFF
.equ LED_7, 0x7FFFF

.equ ASCII_0, 0x30
.equ ASCII_1, 0x31
.equ ASCII_9, 0x39
.equ ASCII_DASH, 0x2D
.equ ASCII_DOT, 0x2E
.equ ASCII_Q, 0x71

.equ STRING_LEN, 3

.equ CLOCK_FREQ, 120

                .section .text
main:
				bl IOShieldInit					/* Initializes LED and Switch GPIO Ports */
                bl BIOOpen             			/* Initializes serial port */

				ldr R0, =GPIOD_PDOR				/* LEDs off */
				ldr R1, =ALL_BITS_SET
				str R1, [R0]
				ldr R0, =GPIOB_PDOR
				ldr R1, =ALL_BITS_SET
				str R1, [R0]

loop:
				bl SwArrayRead					/* take data from switches */

				ldr R1, =SWITCHES_OFF
				cmp R0, R1						/* test to see if no switches are flipped */
				bne useswitches					/* use switch input for frequency if so */
				bl TerminalInput				/* otherwise, use terminal input for frequency */

				tst R1, #1						/* if TerminalInput threw an error, loop back */
				bne loop

usefrequency:
				cmp R1, #2						/* if input was from 0.1 to 0.9 */
				it eq
				ldreq R1, =#1

				bl CalcDelay					/* calculate delay corresponding to inputted frequency */
				bl FlashLEDs
				b loop

useswitches:
				mvn R0, R0
				ubfx R0, R0, #0, #8
				usat R0, #6, R0					/* if user entered in over 63Hz, saturate to 63Hz */
                b usefrequency


/******************************* Subroutines *******************************/

/****************************************************************************
* void IOShieldInit(void)
*
* Desc: This subroutine initializes the IOShield by starting the clock,
* setting ports to GPIO, and setting port directions.
*
* Params: none
* Returns: none
* MCU: K22F
* Brian Willis 2/14/2017
****************************************************************************/
IOShieldInit:
				push {lr}

				/* start clock */
				ldr R0, =SIM_SCGC5
				ldr R1, =CLOCK_DATA
				str R1, [R0]

				/* initialize port C */
				ldr R0, =PORTC_GPCLR			/* GPIO */
				ldr R1, =PIN_ASS_C
				str R1, [R0]

				ldr R0, =GPIOC_PDDR				/* input vs. output */
				ldr R1, =IO_DATA_SWITCH
				str R1, [R0]

				/* initialize port D */
				ldr R0, =PORTD_GPCLR
				ldr R1, =PIN_ASS_D
				str R1, [R0]

				ldr R0, =GPIOD_PDDR
				ldr R1, =IO_DATA_LED_D
				str R1, [R0]

				/* initialize port B */
				ldr R0, =PORTB_GPCLR
				ldr R1, =PIN_ASS_B_LOW
				str R1, [R0]
				ldr R0, =PORTB_GPCHR
				ldr R1, =PIN_ASS_B_HIGH
				str R1, [R0]

				ldr R0, =GPIOB_PDDR
				ldr R1, =IO_DATA_LED_B
				str R1, [R0]

				pop {pc}


/****************************************************************************
* INT8U SwArrayRead(void)
*
* Desc: This subroutine reads Port C and stores the data in an 8 bit integer.
*
* Params: none
* Returns: Switch data as 8 bit integer
* MCU: K22F
* Brian Willis 2/14/2017
****************************************************************************/
SwArrayRead:
				push {R9, R10, lr}

				ldr R9, =GPIOC_PDIR				/* read data from switch inputs */
				ldr R10, [R9]

				mov R0, R10						/* return integer in R0 */
				lsr R0, #2						/* convert to 8 bits */

				pop {R9, R10, pc}


/****************************************************************************
* INT16U TerminalInput(void)
*
* Desc: This subroutine reads a user-inputted frequency and ensures it is
* a positive decimal number between 0 and 64. Can read 0.1 to 0.9Hz, but
* not any fractional number past 1Hz.
*
* Params: none
* Returns: Frequency as 16-bit integer,
* 		   0 -> if input was valid
* 		   1 -> if input was not valid
* 		   2 -> if input was fraction (valid)
* MCU: K22F
* Brian Willis 3/03/2017
****************************************************************************/
TerminalInput:
				push {lr}

				ldr r0,=FreqPrompt
                bl BIOPutStrg         			/* output prompt message */

				ldr R0, =STRING_LEN
				ldr R1, =StrgBuf
				bl BIOGetStrg					/* receive input from user */
				ldr R0, [R1]

				cmp R0, #0xFF					/* check to see if input is 1 or 2 characters long */
				bmi	singlechar

firstchar:
				ubfx R5, R0, #0, #8				/* separate characters, check validity, concatenate back together */
				cmp R5,	ASCII_0					/* less than 0: non-number */
				bmi checknonnum
				cmp R5, ASCII_9					/* greater than 9: non-number */
				bgt invalidchar

				sub R5, #0x30
				ldr R3, =#10
				mul R5, R3

secondchar:
				ubfx R2, R0, #8, #8
				cmp R2,	ASCII_0
				bmi invalidchar
				cmp R2, ASCII_9
				bgt invalidchar

				sub R2, #0x30
				add R0, R5, R2

				cmp R0,	#0						/* ensure final value is from 1 to 63 */
				bmi invalidchar
				cmp R0,	#1
				bmi numtoolow
				cmp R0, #64
				bpl numtoohigh

				cmp R5, #2
				it eq
				ldreq R1, =#0						/* return no error */
				b exit


singlechar:										/* check validity for single character input */
				cmp R0,	ASCII_0					/* less than 0: non-number */
				bmi invalidchar
				cmp R0,	ASCII_1
				bmi numtoolow
				cmp R0, ASCII_9
				bgt invalidchar

				sub R0, #0x30
				ldr R1, =#0
				b exit


numtoolow:
				ldr r0,=ErrMsgLowFreq 			/* output error message */
                bl BIOPutStrg
                ldr r1, =#1						/* return error */
                b exit

numtoohigh:
				ldr r0,=ErrMsgHighFreq
                bl BIOPutStrg
                ldr r1, =#1
                b exit

invalidchar:
				ldr r0,=ErrMsgNonNum
                bl BIOPutStrg
                ldr r1, =#1
                b exit

checknonnum:
				cmp R5, ASCII_DOT				/* check if user entered fractional number */
				ittt eq
				ldreq R1, =#2					/* return fraction */
				ldreq R5, =#0
				beq secondchar
				cmp R1,	ASCII_DASH				/* check if user entered negative number */
				bne invalidchar					/* if unknown char wasn't a dash or dot, it was some other invalid char */
				ldr r0,=ErrMsgNegNum
                bl BIOPutStrg
                ldr r1, =#1
                b exit


exit:
				pop {pc}


/****************************************************************************
* void Delayus(INT32U us)
*
* Desc: This subroutine pauses the program for microseconds specified
* by its parameter.
* 120 cycles is one microsecond delay due to 120MHz clock on K22F.
* Need (us x 120) total cycles for correct delay.
*
* Params: Desired microsecond delay as 32-bit integer
* Returns: none
* MCU: K22F, system clock of 120MHz
* Brian Willis 3/03/2017
****************************************************************************/
Delayus:
				push {lr}

				ldr R3, =#CLOCK_FREQ			/* 120MHz */
				mul R1, R0, R3					/* us x clock frequency is number of necessary cycles to delay 'us' microseconds */

				ldr R2, =#0						/* counter */
				add R2, #13						/* due to instructions outside branch loop (~54 cycles avg), loop 13 times less */

				ldr R3, =#4						/* branch takes 4 total cycles each loop */
				udiv R1, R3						/* number of branch loops = (120 x us)/4 */

branch:
				cmp R2, R1
				add R2, #1
				bne branch						/* branch is 2 cycles */

				pop {pc}


/****************************************************************************
* INT32U CalcDelay(INT16U Hz, INT8U dot)
*
* Desc: This subroutine calculates the delay in microseconds that the
* program will pause for when lighting LEDs.
*
* Params: 'Hz' is Frequency in Hz
*		  'dot' determines if Hz is fractional (from 0.1 to 0.9)
*		 		1 -> if Hz parameter is to be divided by 10
* Returns: Microsecond delay as 32-bit integer
* MCU: K22F
* Brian Willis 3/01/2017
****************************************************************************/
CalcDelay:
				push {lr}

				cmp R1, #1
				ite eq
				ldreq R3, =#10000000			/* delay = 10^6/(64*Hz) or 10^7/(64*Hz) if fractional*/
				ldrne R3, =#1000000
				ldr R2, =#64
				mul R0, R2
				udiv R0, R3, R0

				pop {pc}


/****************************************************************************
* void FlashLEDs(INT32U us)
*
* Desc: This subroutine flashes the LEDs using the sinewave table.
*
* Params: Microsecond delay inbetween flashing LEDs
* Returns: none
* MCU: K22F
* Brian Willis 3/01/2017
****************************************************************************/
FlashLEDs:
				push {R4 - R8, R11, R12, lr}

				mov R12, R0						/* temp register for delay value */

				ldr R5, =GPIOD_PDOR				/* LED ports */
				ldr R6, =GPIOB_PDOR

				bl SwArrayRead					/* initialize switch value comparitor */
				mov R11, R0

flashloop:
				ldr R8, =#64					/* counter for sine table */
				ldr R4, =SinTable

tablecycle:
				cmp R8, #0
				beq flashloop

				/* between each LED light, check for either switch change or terminal input for 'q' */
				bl SwArrayRead
				cmp R0, R11						/* if user flipped a switch, terminate */
				bne terminate

				ldr R1, =SWITCHES_OFF
				cmp R0, R1						/* only check terminal if switches aren't being used */
				bne noterminal

				bl BIORead
				cmp R0, ASCII_Q					/* if user entered 'q', terminate */
				beq terminate

noterminal:
				ldrh R2, [R4], #2				/* look at SinTable entry, post increment */

				ldr R7, =ALL_BITS_SET			/* turn off Port B LEDs before writing to Port D */
				str R7, [R6]

				cmp R2, LED_0_CHECK
				ittt mi
				ldrmi R7, =LED_0
				strmi R7, [R5]
				bmi foundled

				cmp R2, LED_1_CHECK
				ittt mi
				ldrmi R7, =LED_1
				strmi R7, [R5]					/* Port D LEDs are overridden */
				bmi foundled

				cmp R2, LED_2_CHECK
				ittt mi
				ldrmi R7, =LED_2
				strmi R7, [R5]
				bmi foundled

				ldr R7, =ALL_BITS_SET			/* turn off Port D LEDs before writing to Port B */
				str R7, [R5]

				cmp R2, LED_3_CHECK
				ittt mi
				ldrmi R7, =LED_3
				strmi R7, [R6]
				bmi foundled

				cmp R2, LED_4_CHECK
				ittt mi
				ldrmi R7, =LED_4
				strmi R7, [R6]					/* Port B LEDs are overridden */
				bmi foundled

				cmp R2, LED_5_CHECK
				ittt mi
				ldrmi R7, =LED_5
				strmi R7, [R6]
				bmi foundled

				cmp R2, LED_6_CHECK
				ittt mi
				ldrmi R7, =LED_6
				strmi R7, [R6]
				bmi foundled

				ldr R7, =LED_7					/* otherwise, light LED 7 */
				str R7, [R6]

foundled:
				mov R0, R12						/* delay appropriate number of microseconds */
				bl Delayus

				sub R8, #1
				b tablecycle

terminate:
				pop {R4 - R8, R11, R12, pc}


                .section .rodata

/* Prompt user will see when asked to input frequency for LED wave */
FreqPrompt:      .asciz "\r\nInput frequency in Hz with which to display LED wave (1 to 63). Press q to quit and re-input.\r\n"

/* Error messages associated with incorrect frequency inputs */
ErrMsgHighFreq:	 .asciz "\rInput frequency must be 63Hz or lower"
ErrMsgLowFreq:	 .asciz "\rInput frequency can't be 0Hz, come on"
ErrMsgNonNum:	 .asciz "\rInput frequency must be a number ya dingus"
ErrMsgNegNum:	 .asciz "\rNegative frequency? What do I look like to you, a wizard? ( -_-)"

/* Sinewave table of 64 values that correspond to LEDs to light */
SinTable:		  .hword 0x8000, 0x8C8B, 0x98F8, 0xA528, 0xB0FB, 0xBC56, 0xC71C, 0xD133
 				  .hword 0xDA82, 0xE2F2, 0xEA6D, 0xF0E2, 0xF641, 0xFA7D, 0xFD8A, 0xFF62
 				  .hword 0xFFFF, 0xFF62, 0xFD8A, 0xFA7D, 0xF641, 0xF0E2, 0xEA6D, 0xE2F2
 				  .hword 0xDA82, 0xD133, 0xC71C, 0xBC56, 0xB0FB, 0xA528, 0x98F8, 0x8C8B
 				  .hword 0x8000, 0x7374, 0x6707, 0x5AD7, 0x4F04, 0x43A9, 0x38E3, 0x2ECC
 				  .hword 0x257D, 0x1D0D, 0x1592, 0xF1D,  0x9BE,  0x582,  0x275,  0x9D
 				  .hword 0x0, 	 0x9D,   0x275,  0x582,  0x9BE,  0xF1D,  0x1592, 0x1D0D
 				  .hword 0x257D, 0x2ECC, 0x38E3, 0x43A9, 0x4F04, 0x5AD7, 0x6707, 0x7374

                .section .bss

                .comm StrgBuf STRING_LEN



