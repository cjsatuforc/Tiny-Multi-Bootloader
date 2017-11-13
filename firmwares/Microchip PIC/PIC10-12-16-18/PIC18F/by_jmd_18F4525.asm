

	radix DEC

	; change these lines accordingly to your application	
#include "p18f4525.inc"
IdTypePIC = 0x4E			; must exists in "piccodes.ini"
#define max_flash 0xC000	; in BYTES!!! (= 'max flash memory' from "piccodes.ini")
xtal EQU 20000000		; you may want to change: _XT_OSC_1H  _HS_OSC_1H  _HSPLL_OSC_1H
baud EQU 115200			; standard TinyBld baud rates: 115200 or 19200
	; The above 5 lines can be changed and buid a bootloader for the desired frequency (and PIC type)

	;********************************************************************
	;	Tiny Bootloader		18F series		Size=100words
	;	claudiu.chiculita@ugal.ro
	;	http://www.etc.ugal.ro/cchiculita/software/picbootloader.htm
	;
	;
	;	MODIFIED BY JMD 22/06/2007
	;	1) processor type changed to 18F4525
	;	2) Config options were deprecated and unmatched : replaced
	;		XINST = extended adressing modes enable A VERIFIER
	;		PBADEN = DIGITAL/ANALOG at reset  to be checked
	; 
	; modified by Edorul:
	; EEPROM write is only compatible with "Tiny PIC Bootloader+"
	; http://sourceforge.net/projects/tinypicbootload/
	;********************************************************************


	#include "../spbrgselect.inc"	; RoundResult and baud_rate

		#define first_address max_flash-200		;100 words

;		__CONFIG is deprecated, one must use CONFIG now !
;		__CONFIG	_CONFIG1H, _OSCS_OFF_1H & _HS_OSC_1H
;		__CONFIG	_CONFIG2L, _BOR_ON_2L & _BORV_20_2L & _PWRT_ON_2L
;		__CONFIG	_CONFIG2H, _WDT_OFF_2H & _WDTPS_128_2H
;		__CONFIG	_CONFIG4L, _STVR_ON_4L & _LVP_OFF_4L & _DEBUG_OFF_4L


		CONFIG	OSC=HS,	IESO=OFF, FCMEN=OFF, PWRT=ON, BOREN=SBORDIS, BORV=0
		CONFIG	WDT=OFF, WDTPS=128
		CONFIG	MCLRE=ON, LPT1OSC=OFF, PBADEN=OFF, CCP2MX=PORTC
		CONFIG	STVREN=ON, LVP=OFF, XINST=OFF, DEBUG=OFF
		CONFIG	CP0=OFF, CP1=OFF, CP2=OFF, CPB=OFF, CPD=OFF
		CONFIG	WRT0=OFF, WRT1=OFF, WRT2=OFF, WRTB=OFF, WRTC=OFF, WRTD=OFF
		CONFIG	EBTR0=OFF, EBTR1=OFF, EBTR2=OFF, EBTRB=OFF


;----------------------------- PROGRAM ---------------------------------

	cblock 0
	crc
	i
	cnt1
	cnt2
	cnt3
	counter_hi
	counter_lo
	flag
	endc
	cblock 10
	buffer:64
	dummy4crc
	endc

SendL macro car
	movlw car
	movwf TXREG
	endm

;0000000000000000000000000 RESET 00000000000000000000000000

		ORG     0x0000
		GOTO    IntrareBootloader

;view with TabSize=4
;&&&&&&&&&&&&&&&&&&&&&&&   START     &&&&&&&&&&&&&&&&&&&&&&
;----------------------  Bootloader  ----------------------
;PC_flash:		C1h				U		H		L		x  ...  <64 bytes>   ...  crc	
;PC_eeprom:		C1h			   	40h   EEADRH  EEADR     1       EEDATA	crc					
;PC_cfg			C1h			U OR 80h	H		L		1		byte	crc
;PIC_response:	   type `K`

	ORG first_address		;space to deposit first 4 instr. of user prog.
	nop
	nop
	nop
	nop
	org first_address+8
IntrareBootloader
							;init serial port
	movlw b'00100100'
	movwf TXSTA
	movlw spbrg_value
	movwf SPBRG
	movlw b'10010000'
	movwf RCSTA
							;wait for computer
	rcall Receive
	sublw 0xC1				;Expect C1h
	bnz way_to_exit
	SendL IdTypePIC			;send PIC type
MainLoop
	SendL 'K'				; "-Everything OK, ready and waiting."
mainl
	clrf crc
	rcall Receive			;Upper
	movwf TBLPTRU
	movwf flag			;(for EEPROM and CFG cases)
	rcall Receive			;Hi
	movwf TBLPTRH
	movwf EEADRH		;(for EEPROM case)
	rcall Receive			;Lo
	movwf TBLPTRL
	movwf EEADR			;(for EEPROM case)

	rcall Receive			;count
	movwf i
	incf i
	lfsr FSR0, (buffer-1)
rcvoct						;read 64+1 bytes
	movwf TABLAT		;prepare for cfg; => store byte before crc
	rcall Receive
	movwf PREINC0
	btfss i,0		;don't know for the moment but in case of EEPROM data presence...
		movwf EEDATA		;...then store the data byte (and not the CRC!)
	decfsz i
	bra rcvoct

	tstfsz crc				;check crc
	bra ziieroare
	btfss flag,6		;is EEPROM data?
	bra noeeprom
	movlw b'00000100'	;Setup eeprom
	rcall Write
	bra waitwre
noeeprom
;----no CFG write in "Tiny PIC Bootloader+"
;		btfss flag,7		;is CFG data?
;		bra noconfig
;		tblwt*				;write TABLAT(byte before crc) to TBLPTR***
;		movlw b'11000100'	;Setup cfg
;		rcall Write
;		bra waitwre
;noconfig
;----
							;write
eraseloop
	movlw	b'10010100'		; Setup erase
	rcall Write
	TBLRD*-					; point to adr-1

writebigloop
	movlw 8					; 8groups
	movwf counter_hi
	lfsr FSR0,buffer
writesloop
	movlw 8					; 8bytes = 4instr
	movwf counter_lo
writebyte
	movf POSTINC0,w			; put 1 byte
	movwf TABLAT
	tblwt+*
	decfsz counter_lo
	bra writebyte

	movlw	b'10000100'		; Setup writes
	rcall Write
	decfsz counter_hi
	bra writesloop
waitwre
	;btfsc EECON1,WR		;for eeprom writes (wait to finish write)
	;bra waitwre			;no need: round trip time with PC bigger than 4ms

	bcf EECON1,WREN			;disable writes
	bra MainLoop

ziieroare					;CRC failed
	SendL 'N'
	bra mainl

;******** procedures ******************

Write
	movwf EECON1
	movlw 0x55
	movwf EECON2
	movlw 0xAA
	movwf EECON2
	bsf EECON1,WR			;WRITE
	nop
	;nop
	return


Receive
	movlw xtal/2000000+1	; for 20MHz => 11 => 1second delay
	movwf cnt1
rpt2
	clrf cnt2
rpt3
	clrf cnt3
rptc
	btfss PIR1,RCIF			;test RX
	bra notrcv
	movf RCREG,w			;return read data in W
	addwf crc,f				;compute crc
	return
notrcv
	decfsz cnt3
	bra rptc
	decfsz cnt2
	bra rpt3
	decfsz cnt1
	bra rpt2
	;timeout:
way_to_exit
	bcf	RCSTA,	SPEN			; deactivate UART
	bra first_address

;*************************************************************
; After reset
; Do not expect the memory to be zero,
; Do not expect registers to be initialised like in catalog.

            END