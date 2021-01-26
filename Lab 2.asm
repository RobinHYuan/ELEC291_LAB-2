
$NOLIST
$MODEFM8LB1
$LIST

;------------------------------------------------------------------------------------------------------
;====================
;HARDWARE PARAMETERS:
;====================

;Note: 
;	The frequency of the oscillator is 24 mHz.
;	However, we will divide it by 48, and then feed it to the Timer 1 and Timer 2
;	As a result, F_{timer 1}=(24mHz/48)/(2^16-60536) = 100Hz
;	Hence, the interrupt frequency of Timer1 is exactly 100 Hz

CLK           EQU 24000000 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 100
TIMER0_RELOAD EQU 60536


;------------------------------------------------------------------------------------------------------
;=================
;ISR VECTOR TABLE:
;=================

; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	reti
	
;------------------------------------------------------------------------------------------------------
;====================
;VARIABLE DECLARATION
;====================

dseg at 0x30
Count1s:      ds 1 
second:  ds 1 
minute:ds 1
hour: ds 1
bseg
one_second_flag: dbit 1 ;
am_pm_sel: dbit 1; // 0 stands for am; 1 stands for pm


;------------------------------------------------------------------------------------------------------
;===============
;PIN ASSIGNMENT:
;===============
BOOT_BUTTON   equ P3.7
SOUND_OUT     equ P2.1
UPDOWN        equ P0.0

cseg
LCD_RS equ P2.0
LCD_RW equ P1.7
LCD_E  equ P1.6
LCD_D4 equ P1.1
LCD_D5 equ P1.0
LCD_D6 equ P0.7
LCD_D7 equ P0.6
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

Initial_Message:  db 'Time:', 0
format: db '  :  :  ',0
am: db 'AM',0
pm: db 'PM',0
;------------------------------------------------------------------------------------------------------
;=======================
;HARDWARE INITIALIZATION
;=======================

Initialize_All:
    ; DISABLE WDT: provide Watchdog disable keys
	mov	WDTCN,#0xDE ; First key
	mov	WDTCN,#0xAD ; Second key

	; Setup the stack start to the begining of memory only accesible with pointers
    mov SP, #7FH
    
    ; Enable crossbar and weak pull-ups
	mov	XBR0,#0x00
	mov	XBR1,#0x00
	mov	XBR2,#0x40

	mov	P2MDOUT,#0x02 ; make sound output pin (P2.1) push-pull
	
	; Switch clock to 24 MHz
	mov	CLKSEL, #0x00 ; 
	mov	CLKSEL, #0x00 ; Second write to CLKSEL is required according to the user manual (page 77)
	
	; Wait for 24 MHz clock to stabilze by checking bit DIVRDY in CLKSEL
waitclockstable:
	mov a, CLKSEL
	jnb acc.7, waitclockstable 

	; Initialize the two timers used in this program
    lcall Timer0_Init


    lcall LCD_4BIT ; Initialize LCD
    
    setb EA   ; Enable Global interrupts

	ret

;------------------------------------------------------------------------------------------------------
;=======================
;INITIALIZE TIMER 0
;=======================	

Timer0_Init:
	mov CKCON0, #00000010B ; Timer 0 uses the system clock/48
	mov a, TMOD
	anl a, #0xf0 ; Clear the bits for timer 0
	orl a, #0x01 ; Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
	ret
;=======================
;ISR for TIMER 1
;=======================	
Timer0_ISR:
	clr TF0

	clr TR0
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	setb TR0
	
	push acc
	push psw

	inc Count1s
	mov a, count1s
	cjne a, #102, Timer0_ISR_done
	
	setb one_second_flag
	clr a
	mov Count1s, a
	
	mov a, second
	add a, #0x01
	da a 
	mov second, a
	
	mov a, #0x60
	subb a, second
	
	jz minute_change

Timer0_ISR_done:

	pop psw
	pop acc
	reti
	
minute_change:
	mov a, second
	mov a, #0x00
	mov second, a
	
	mov a, minute
	add a,#0x01
	da a
	mov minute, a
	
	mov a, #0x60
	subb a, minute
	jz hour_change
	ljmp Timer0_ISR_done
	
hour_change:
	mov a, minute
	mov a, #0x00
	mov minute, a
	
	mov a, hour
	add a,#0x01
	da a
	mov hour, a
	
	mov a, #0x12
	subb a, hour
	jz am_pm_change
	
	mov a, #0x13
	subb a, hour
	jz day_change
	
	ljmp Timer0_ISR_done
day_change:
	mov a, hour
	mov a, #0x01
	mov hour, a
	ljmp Timer0_ISR_done
am_pm_change:
	mov a, am_pm_sel
	jz pm_am_change
	clr a
	mov am_pm_sel, a
	ljmp Timer0_ISR_done
pm_am_change:
	mov a, #0x01
	mov am_pm_sel, a
	ljmp Timer0_ISR_done
;------------------------------------------------------------------------------------------------------
cseg
;============================================================================
; MAIN PROGRAM
;============================================================================
main:
	lcall Initialize_All
	mov second, #0x00
	mov minute, #0x19
	mov hour,  #0x22
	mov a, #0x01
	mov am_pm_sel,a
    ; For convenience a few handy macros are included in 'LCD_4bit.inc':
	Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)
    Set_Cursor(2, 1)
    Send_Constant_String(#format)
	

loop:
    clr one_second_flag 
    Set_Cursor(2, 7)     
	Display_BCD(second) 
    Set_Cursor(2, 4)     
	Display_BCD(minute) 
	Set_Cursor(2, 1)     
	Display_BCD(hour)
	mov a, am_pm_sel
	jz display_am
	Set_Cursor(2, 14) 
  	Send_Constant_String(#pm) 
    ljmp loop

display_am:
 Set_Cursor(2, 14) 
  Send_Constant_String(#am)
  ljmp loop
END
