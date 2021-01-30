
$NOLIST
$MODEFM8LB1
$LIST

Button_Press_Check mac
	jb %0, loopB  ; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb %0, loopB  ; if the 'BOOT' button is not pressed skip
	jnb %0, $
	ljmp sudo_reset_ISR_begin
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
TIMER1_RATE   EQU 1000*2    
TIMER1_RELOAD EQU ((65536-(CLK/(TIMER0_RATE))))

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
ljmp	BUZZ_ISR
	
;------------------------------------------------------------------------------------------------------
;====================
;VARIABLE DECLARATION
;====================

dseg at 0x30
Count1s:      ds 1 
second:  ds 1 
minute:ds 1
hour: ds 1
alarm_second:  ds 1 
alarm_minute:ds 1
alarm_hour: ds 1
alarm_counter: ds 1
bseg
one_second_flag: dbit 1 ;
am_pm_sel: dbit 1; // 0 stands for am; 1 stands for pm
mode:  dbit 1
reset: dbit 1
alarm: dbit 1
alarm_am_pm_sel: dbit 1
alarm_time :dbit 1
alarm_setup: dbit 1
alarm_On_off:dbit 1
;------------------------------------------------------------------------------------------------------
;===============
;PIN ASSIGNMENT:
;===============
BOOT_BUTTON   equ P3.7
SOUND_OUT     equ P2.1
ON_OFF        equ p2.2
RESET_TIME    equ p0.1
SECOND_ADJUST equ p0.5
MINUTE_ADJUST equ p1.2
HOUR_ADJUST   equ p1.5
AM_PM_ADJUST  equ p3.3
ALARM_SET     equ p3.0
ALARM_DISPLAY equ p2.4
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

Initial_Message:  db 'Time:              ', 0
Alarm_Message:  db 'ALARM:', 0
format: db '  :  :  ',0
am: db 'AM',0
pm: db 'PM',0
on: db 'ON ',0
off: db 'OFF',0
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
	lcall BUZZ_Init
	
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
	
	ljmp second_change


second_change:	
	mov a, second
	add a, #0x01
	da a 
	mov second, a
	
	mov a, #0x60
	subb a, second
	
	jz minute_change

Timer0_ISR_done:
	ljmp Timer0_Alarm_Check
Timer0_ISR_end:	
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
	sjmp hour_change2
hour_change2:
	clr c	
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
	mov second, #0x55
	mov minute, #0x59
	mov hour,  #0x11
	mov alarm_setup, a
	mov alarm_second, #0x00
	mov alarm_minute, #0x00
	mov alarm_hour,  #0x12
	mov a,#0x01
	mov alarm_am_pm_sel,a
	mov alarm_On_off,a
	mov a, #0x00
	mov am_pm_sel,a
    mov alarm_time,a
	mov alarm_counter,a
;	mov alarm_On_off,a
	clr TR2
	

loopA:

	setb mode
    clr one_second_flag 
    	
	jb ALARM_SET,loopD   
	Wait_Milli_Seconds(#50)
	jb ALARM_SET, loopD
	jnb ALARM_SET, $
	ljmp sudo_alarm_ISR_begin

loopD:
	jb ALARM_DISPLAY,loopC   
	Wait_Milli_Seconds(#50)
	jb ALARM_DISPLAY, loopC
	jnb ALARM_DISPLAY, $
	ljmp display_alarm
loopC:
	Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)
    Set_Cursor(2, 1)
    Send_Constant_String(#format)   
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
    
    
sudo_alarm_ISR_begin:
    mov alarm_second, #0x00
	mov alarm_minute, #0x00
	mov alarm_hour,  #0x00
	mov a,#0x01
	mov alarm_setup, a
	sjmp sudo_alarm_ISR_A
sudo_alarm_ISR_A:

 	jb SECOND_ADJUST,  sudo_alarm_ISR_B
	Wait_Milli_Seconds(#50)	
	jb SECOND_ADJUST,  sudo_alarm_ISR_B
	jnb SECOND_ADJUST,  $ 
	mov a, alarm_second
	add a, #0x01
	da a
	CJNE a, #0x60, INCSEC
	mov alarm_second, #0x00
	sjmp sudo_alarm_ISR_B
INCSEC:
	mov alarm_second, a
	sjmp sudo_alarm_ISR_B
	
sudo_alarm_ISR_B:

	jb MINUTE_ADJUST,  sudo_alarm_ISR_C
	Wait_Milli_Seconds(#50)	
	jb MINUTE_ADJUST,  sudo_alarm_ISR_C
	jnb MINUTE_ADJUST,  $ 
	
	mov a, alarm_minute
	add a, #0x01
	da a
	CJNE a, #0x60, INC_MIN
	mov alarm_minute, #0x00
	sjmp sudo_alarm_ISR_C
INC_MIN:
	mov alarm_minute, a
	sjmp sudo_alarm_ISR_C
sudo_alarm_ISR_C:
	jb HOUR_ADJUST,  sudo_alarm_ISR_D
	Wait_Milli_Seconds(#50)	
	jb HOUR_ADJUST,  sudo_alarm_ISR_D
	jnb HOUR_ADJUST,  $ 
	
	mov a, alarm_hour
	add a, #0x01
	da a

    
	mov alarm_hour,a
	subb a, #0x13
	jnz sudo_alarm_ISR_D
	mov alarm_hour, #0x00
	sjmp sudo_alarm_ISR_D

sudo_alarm_ISR_D:	
	jb AM_PM_ADJUST,  alarm_off
	Wait_Milli_Seconds(#50)	
	jb AM_PM_ADJUST,  alarm_off
	jnb AM_PM_ADJUST,  $
	mov a, alarm_am_pm_sel
	jz alarm_pm_am_change
	clr a
	mov alarm_am_pm_sel, a
	ljmp alarm_off
alarm_pm_am_change:
	mov a, #0x01
	mov alarm_am_pm_sel, a
	ljmp alarm_off
alarm_off:
	jb ON_OFF,  display_alarm
	Wait_Milli_Seconds(#50)	
	jb ON_OFF,  display_alarm
	jnb ON_OFF,  $ 
	mov a, alarm_On_off
	jz alarm_on
	clr a
	mov alarm_On_off,a
	clr tr2
	ljmp display_alarm
alarm_on:
	mov a, #0x01
	mov alarm_On_off , a
	ljmp display_alarm
display_alarm:			
	Set_Cursor(1, 1)
    Send_Constant_String(#Alarm_Message)
    Set_Cursor(2, 1)
    Send_Constant_String(#format)
  	Set_Cursor(2, 7)     
	Display_BCD(alarm_second) 
    Set_Cursor(2, 4)     
	Display_BCD(alarm_minute) 
	Set_Cursor(2, 1)     
	Display_BCD(alarm_hour)
	
	mov a,alarm_On_off
	jz display_off
	Set_Cursor(1, 14)
    Send_Constant_String(#on)
    sjmp display_pm_alarm
display_off:
	Set_Cursor(1, 14)
    Send_Constant_String(#off)
    sjmp display_pm_alarm
display_pm_alarm:
	mov a, alarm_am_pm_sel
	jz display_am_alarm
	Set_Cursor(2, 14) 
  	Send_Constant_String(#pm)
    ljmp sudo_alarm_ISR_End
 sudo_alarm_ISR_A_MID:
 	ljmp sudo_alarm_ISR_A
 	   
sudo_alarm_ISR_End:
	jb ALARM_SET,sudo_alarm_ISR_A_MID
	Wait_Milli_Seconds(#50)
	jb ALARM_SET, sudo_alarm_ISR_A_MID
	jnb ALARM_SET, $
	ljmp loopA
	
display_am_alarm:
	Set_Cursor(2, 14) 
    Send_Constant_String(#am)
	ljmp sudo_alarm_ISR_End

;+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++    
sudo_reset_ISR_begin:
	mov second, #0x00
	mov minute, #0x00
	mov hour,  #0x00
	sjmp sudo_reset_ISR_A
sudo_reset_ISR_A:
;---------------------------------
	 mov a,#0x00
	 mov TR0, a
	 mov a,#0x01
	 mov reset,a

;------------------------------------------------------ 		
	jb SECOND_ADJUST,  sudo_reset_ISR_B
	Wait_Milli_Seconds(#50)	
	jb SECOND_ADJUST,  sudo_reset_ISR_B
	jnb SECOND_ADJUST,  $ 
	mov a, second
	add a, #0x01
	da a
	mov second, a
	CJNE a, #0x60, INC_timeSEC
	mov second, #0x00
	sjmp sudo_reset_ISR_B
INC_timeSEC:
	mov second, a
	sjmp sudo_reset_ISR_B
	
sudo_reset_ISR_B:	
	jb MINUTE_ADJUST,  sudo_reset_ISR_C
	Wait_Milli_Seconds(#50)	
	jb MINUTE_ADJUST,  sudo_reset_ISR_C
	jnb MINUTE_ADJUST,  $ 
	
	mov a, minute
	add a, #0x01
	da a
	mov minute, a
	CJNE a, #0x60, INC_timeMIN
	mov minute, #0x00
	sjmp sudo_reset_ISR_C
INC_timeMIN:
	mov minute, a
	sjmp sudo_reset_ISR_C
	
	
sudo_reset_ISR_C:
	jb HOUR_ADJUST,  sudo_reset_ISR_D
	Wait_Milli_Seconds(#50)	
	jb HOUR_ADJUST,  sudo_reset_ISR_D
	jnb HOUR_ADJUST,  $ 
	
	mov a, hour
	add a, #0x01
	da a
	mov hour, a
	CJNE a, #0x13, INC_timeHOUR
	mov hour, #0x00
	sjmp sudo_reset_ISR_D
INC_timeHOUR:
	mov hour, a
	sjmp sudo_reset_ISR_D
	
sudo_reset_ISR_D:		
	jb AM_PM_ADJUST,  display
	Wait_Milli_Seconds(#50)	
	jb AM_PM_ADJUST,  display
	jnb AM_PM_ADJUST,  $
	mov a, am_pm_sel
	jz time_pm_am_change
	clr a
	mov am_pm_sel, a
	ljmp display
time_pm_am_change:
	mov a, #0x01
	mov am_pm_sel, a
	ljmp display
display:
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
	
sudo_unmask:
	jb RESET_TIME,  sudo_reset_ISR_Z
	Wait_Milli_Seconds(#50)	
	jb RESET_TIME,  sudo_reset_ISR_Z
	jnb RESET_TIME,  $ 
	mov a,#0x00
	mov TR0, a
	ljmp loopA
;+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ 
Timer0_ISR_end_b:
	ljmp Timer0_ISR_end	  

Timer0_Alarm_Check:
	mov a,alarm_On_off
	jnz Timer0_Alarm_Check2
	mov a,#0x00
	mov tr2,a
	ljmp Timer0_ISR_end
Timer0_Alarm_Check2:
	clr c
	mov a, alarm_setup
	jz Timer0_ISR_end_b
	
	clr c;
	mov a, alarm_hour 
	subb a, hour
	jnz Timer0_ISR_end_b
	
	clr c
	mov a, alarm_minute
	subb a,minute
	jnz Timer0_ISR_end_b
	
	clr c
	mov a, alarm_second
	subb a,second
	jnz Timer0_ISR_end_b
	
	clr c
	mov a, alarm_am_pm_sel
	subb a, am_pm_sel
	jnz Timer0_ISR_end_b
	
	setb TR2
	ljmp Timer0_ISR_end
	
;===============================================================================================
BUZZ_Init:
	orl CKCON0, #0b00010000 ; Timer 2 uses the system clock
	mov TMR2CN0, #0 ; Stop timer/counter.  Autoreload mode.
	mov TMR2H, #high(TIMER1_RELOAD)
	mov TMR2L, #low(TIMER1_RELOAD)
	mov TMR2RLH, #high(TIMER1_RELOAD)
	mov TMR2RLL, #low(TIMER1_RELOAD)

    setb ET2 
    setb TR2  
	ret

BUZZ_ISR:
	clr TF2h
	push acc  
	mov a, alarm_On_off
	jnz BUZZ
	clr tr2
	ljmp BUZZ_ISR_END
BUZZ:
	setb TR2
	cpl SOUND_OUT ; Toggle the pin connected to the speaker
	ljmp BUZZ_ISR_END
BUZZ_ISR_END:
	pop acc
	reti
