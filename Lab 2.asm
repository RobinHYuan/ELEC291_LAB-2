
$NOLIST
$MODEFM8LB1
$LIST

Button_Press_Check mac
	jb %0, loopB  ; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb %0, loopB  ; if the 'BOOT' button is not pressed skip
	jnb %0, $
	ljmp sudo_reset_ISR_A
	endmac	
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
mode:dbit 1
reset: dbit 1


;------------------------------------------------------------------------------------------------------
;===============
;PIN ASSIGNMENT:
;===============
BOOT_BUTTON   equ P3.7
SOUND_OUT     equ P2.1
UPDOWN        equ P0.0
RESET_TIME    equ p0.1
SECOND_ADJUST equ p0.5
MINUTE_ADJUST equ p1.2
HOUR_ADJUST   equ p1.5
AM_PM_ADJUST  equ p3.3
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
	mov	CLKSEL, #0x00 ; Second write to CLKSEL 
	

waitclockstable:
	mov a, CLKSEL
	jnb acc.7, waitclockstable 

    lcall Timer0_Init


    lcall LCD_4BIT 
    
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
	
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
	ret
;=======================
;ISR for TIMER 0
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
;------------------------------------------------------------------------------------------------------
;=============================================
; update minute every 60s
; part of the Timer 1 ISR 
;=============================================	
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
;=============================================
; update hour every 60mins
; part of the Timer 1 ISR 
;=============================================		
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
;=============================================
; update hour every 12hrs
; part of the Timer 1 ISR 
;=============================================	
day_change:
	mov a, hour
	mov a, #0x01
	mov hour, a
	ljmp Timer0_ISR_done
;=============================================
; update am/pm every 12hrs
; part of the Timer 1 ISR 
;=============================================	
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
;============================================================================
; MAIN PROGRAM

;============================================================================
main:
	lcall Initialize_All
	mov second, #0x00
	mov minute, #0x00
	mov hour,  #0x00
	mov a, #0x00
	mov am_pm_sel,a
    ; For convenience a few handy macros are included in 'LCD_4bit.inc':
	Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)
    Set_Cursor(2, 1)
    Send_Constant_String(#format)
	

loopA:

	setb mode
    clr one_second_flag 
    Set_Cursor(2, 7)     
	Display_BCD(second) 
    Set_Cursor(2, 4)     
	Display_BCD(minute) 
	Set_Cursor(2, 1)     
	Display_BCD(hour)

		
	Button_Press_Check(RESET_TIME)
	sjmp loopB
loopB:
	mov a, am_pm_sel
	jz display_am
	Set_Cursor(2, 14) 
  	Send_Constant_String(#pm)
    ljmp loopA

display_am:
	Set_Cursor(2, 14) 
    Send_Constant_String(#am)
  
    ljmp loopA

;+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++    
sudo_reset_ISR_A:
;---------------------------------
	 mov a,#0x00; we stop the timer here
	 mov TR0, a
	 mov a,#0x01; we also mask it 
	 mov reset,a
;------------------------------------------------------ 		
	jb SECOND_ADJUST,  sudo_reset_ISR_B; check whether second_adjust button is pressed
	Wait_Milli_Seconds(#50)	
	jb SECOND_ADJUST,  sudo_reset_ISR_B; if not, go check minute
	jnb SECOND_ADJUST,  $ 
	mov a, second; if pressed, add one
	add a, #0x01
	da a
	mov second, a
	sjmp sudo_reset_ISR_B ; go to minute after checking second
	
sudo_reset_ISR_B:	;check minute
	jb MINUTE_ADJUST,  sudo_reset_ISR_C
	Wait_Milli_Seconds(#50)	
	jb MINUTE_ADJUST,  sudo_reset_ISR_C
	jnb MINUTE_ADJUST,  $ 
	
	mov a, minute
	add a, #0x01
	da a
	mov minute, a
	sjmp sudo_reset_ISR_C
	

	
sudo_reset_ISR_C: ;check hour
	jb HOUR_ADJUST,  sudo_reset_ISR_D
	Wait_Milli_Seconds(#50)	
	jb HOUR_ADJUST,  sudo_reset_ISR_D
	jnb HOUR_ADJUST,  $ 
	
	mov a, hour
	add a, #0x01
	da a
	mov hour, a
	sjmp sudo_reset_ISR_D
	
sudo_reset_ISR_D: ;check am/pm
		
	jb AM_PM_ADJUST,  display
	Wait_Milli_Seconds(#50)	
	jb AM_PM_ADJUST,  display
	jnb AM_PM_ADJUST,  $
	mov a,  am_pm_sel
	cpl a
	mov am_pm_sel, a
	ljmp display
	
display: ;display result
	Set_Cursor(2, 7)     
	Display_BCD(second) 
	Set_Cursor(2, 4)     
	Display_BCD(minute)
	Set_Cursor(2, 1)     
	Display_BCD(hour)
	
	
	mov a, am_pm_sel
	jz display_am_ISR
	Set_Cursor(2, 14) 
  	Send_Constant_String(#pm)
    ljmp sudo_unmask

sudo_reset_ISR_Z:
	ljmp sudo_reset_ISR_A
	
display_am_ISR:
	Set_Cursor(2, 14) 
    Send_Constant_String(#am)
	ljmp sudo_unmask
	
sudo_unmask: ;unmask, restart timer, then go back to the regular loop
	jb RESET_TIME,  sudo_reset_ISR_Z
	Wait_Milli_Seconds(#50)	
	jb RESET_TIME,  sudo_reset_ISR_Z
	jnb RESET_TIME,  $ 
	mov a,#0x00
	mov TR0, a
	ljmp loopA
;+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ 
	  


END
