; MCZIMAGER.S
; 2021-06-14 BY LES BIRD
; 2021-07-01 - UPDATE TO USE PROM READ AND WRITE - SLOWER BUT ACCURATE
; 2021-07-01 - UPDATE TO INCORPORATE BOTH READ OPTIONS (G,F=DIRECT,R,W=PROM)
;
; READS ZILOG MCZ DISKS TRACK BY TRACK AND SENDS BINARY DATA TO CONSOLE
; WRITES ZILOG MCZ DISKS TRACK BY TRACK FROM CONSOLE BINARY DATA
;
; WAIT FOR 'R' TO BEGIN READING DISK FROM FLOPPY
; WAIT FOR 'W' TO BEGIN WRITING DISK TO FLOPPY
;
SERDAT:	EQU	0DEH
SERCON:	EQU	0DFH
RXRDY:	EQU	1
TXRDY:	EQU	0
DSKDAT:	EQU	0CFH
DSKCOM:	EQU	0D0H
DSSTAT:	EQU	0D0H
DSKSEL:	EQU	0D1H
CLK0:	EQU	0D4H
;       CONTROL WORDS
REST:	EQU	03
STCLK0:	EQU	10110111B
CTRMOD:	EQU	11010111B
TRIG0:	EQU	10101111B
RSTCLK:	EQU	00001011B
RDDAT:	EQU	04H		; DSKCOM 0000.0100
WRDAT:	EQU	08H		; DSKCOM 0000.1000
WRCRC:	EQU	18H
HDSTEP:	EQU	1		; DSKCOM 0000.0010
DIRECT:	EQU	0		; DSKCOM 0000.0001
READY:	EQU	5		; DSSTAT 0001.0000
T0:	EQU	6		; DSSTAT 0010.0000
CMP:	EQU	7
CRC:	EQU	7		; DSSTAT 0100.0000
WRTPTC:	EQU	7		; DSKSEL 0100.0000
;       TIMING CONSTANTS
TIM7:	EQU	67
SECT:	EQU	50
MS08:	EQU	77
MS18:	EQU	172
TIM256:	EQU	61
TM256A:	EQU	61
TIM512:	EQU	73
;
INTPNT:	EQU	12AFH
DSKVSL:	EQU	13D0H
FLOPPY:	EQU	0BFDH
PTRS:	EQU	12B4H
;
;
;
START:
	LD	(SAVSTK),SP	; SAVE RIO RETURN STACK
	LD	SP,STACK
	LD	A,13H
	LD	I,A
	EI			; ENSURE INTERRUPTS ARE ENABLED
;
	LD	HL,MSG1
	LD	DE,MSGEND
	CALL	SENDHL
BEGIN:
	LD	HL,PROMPT
	LD	DE,PROLEN
	CALL	SENDHL
	CALL 	TTYIN		; WAIT FOR COMMAND
	CP	'Q'
	JP	Z,QUIT		; QUIT THE PROGRAM RETURN TO OS
	CP	'G'		; FAST GET
	JP	Z,READ0		; DIRECT READ
	CP	'R'		; NORMAL READ
	JP	Z,READ3		; PROM READ
	CP	'W'		; NORMAL WRITE
	JP	Z,WRIT0		; PROM WRITE
	CP	'F'		; FAST WRITE
	JP	Z,WRIT3		; DIRECT WRITE VERSION
	JP	BEGIN
QUIT:
	LD	A,0DH
	CALL	TTYOUT
	LD	A,0AH
	CALL	TTYOUT
	LD	SP,(SAVSTK)
	RET
;
; DIRECT READ BYPASS PROM
;
READ0:
	CALL	SELDSK
	CALL	STRK0		; SETS (CURTRK) TO 0
READ1:
	CALL	RDTRK
	LD	HL,DATA
	LD	DE,1100H
	CALL	SENDHL
	LD	A,(CURTRK)
	CP	76		; LAST TRACK?
	JR	Z,READ2
	CALL	HDSTP1		; INCREMENTS (CURTRK)
	JR	READ1
READ2:
	CALL	DESDSK
	JR	BEGIN
;
; PROM READ
;
READ3:
	LD	A,0AH
	LD	(SCREQ),A	; BINARY READ
	XOR	A
	LD	(SCTRK),A
READ4:
	XOR	A
	LD	(SCSEC),A
	LD	HL,DATA
	LD	(SCDTA),HL
; READ 32 SECTORS USING PROM
	PUSH	HL
	CALL	RDTRK7
	POP	HL
; SEND DATA TO CONSOLE
	LD	DE,1100H
	CALL	SENDHL
;
	LD	A,(SCTRK)
	INC	A
	LD	(SCTRK),A
	CP	77
	JR	NZ,READ4
	JP	BEGIN
RDTRK7:
	LD	A,(SCSEC)
	OR	80H
	LD	(HL),A		; PUT SECTOR
	INC	HL
	LD	A,(SCTRK)
	LD	(HL),A		; PUT TRACK
	INC	HL
	PUSH	HL
	LD	(SCDTA),HL
	LD	HL,128
	LD	(SCDL),HL
	LD	IY,SCVEC
	CALL	FLOPPY		; READ DATA
	POP	HL
	LD	DE,128
	ADD	HL,DE		; ADVANCE DATA POINTER
	LD	DE,PTRS
	LD	A,(DE)		; GET BCK1
	INC	DE
	LD	(HL),A		; PUT BCK1
	INC	HL
	LD	A,(DE)		; GET BCK2
	INC	DE
	LD	(HL),A		; PUT BCK2
	INC	HL
	LD	A,(DE)		; GET FWD1
	INC	DE
	LD	(HL),A		; PUT FWD1
	INC	HL
	LD	A,(DE)		; GET FWD2
	INC	DE
	LD	(HL),A		; PUT FWD2
	INC	HL
	XOR	A
	LD	(HL),A		; CRC1 - NOT USED
	INC	HL
	LD	(HL),A		; CRC2 - NOT USED
	INC	HL
	LD	A,(SCSEC)
	INC	A
	LD	(SCSEC),A
	CP	32
	JR	NZ,RDTRK7
	RET
;
SENDHL:
	DI
SENDH1:
	LD	A,(HL)
	INC	HL
	CALL	TTYOUT
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,SENDH1
;
	EI
	RET
;
; WRITE DISK USING PROM
;
WRIT0:
	LD	A,0EH		; BINARY WRITE
	LD	(SCREQ),A
	XOR	A
	LD	(CURTRK),A
WRIT1:
	CALL	SENDRDY
	LD	HL,DATA
	LD	DE,1100H
	CALL	READHL
	CALL	WRTRK
	LD	A,(CURTRK)
	INC	A
	LD	(CURTRK),A
	CP	77
	JR	NZ,WRIT1
WRIT2:
	CALL	SENDRDY
	JP	BEGIN
;
; DIRECT WRITE WITHOUT USING PROM
;
WRIT3:
	CALL	SELDSK
	CALL	STRK0
WRIT4:
	CALL	SENDRDY
	LD	HL,DATA
	LD	DE,1100H
	CALL	READHL
	CALL	WRTRK1
	LD	A,(CURTRK)
	CP	76
	JR	Z,WRIT5
	CALL	HDSTP1		; INCREMENTS CURTRK
	JR	WRIT4
WRIT5:
	CALL	DESDSK
	CALL	SENDRDY
	JP	BEGIN
;
READHL:
	DI
READH1:
	CALL	TTYIN
	LD	(HL),A
	INC	HL
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,READH1
;
	EI
	RET
;
SENDRDY:
	LD	A,'R'
	CALL	TTYOUT
	RET
;
; SEEK TO TRACK 0
;
STRK0:
	XOR	A
	LD	(CURTRK),A
STRK1:
	IN	A,(DSSTAT)	; CHECK THE TRACK 0 LINE.
	BIT	T0,A		; IS IT THERE?
	RET	Z
	CALL	HDSTP0
	JR	STRK1
;
; SELECT DISK 0
;
SELDSK:
	LD	A,RSTCLK
	OUT	(CLK0),A
	LD	A,0
	SET	3,A
	OUT	(DSKSEL),A
;	IN	A,(DSSTAT)	; CHECK AND MAKE SURE THE
;	BIT	READY,A		; SELECTED DISK IS READY.
	RET
;
; DESELECT DISK 0
;
DESDSK:
	LD	A,RSTCLK
	OUT	(CLK0),A
	IN	A,(DSKSEL)	; FIND OUT WHICH DISK IS SELECTED.
	BIT	3,A		; SEE IF ANY DISK IS SELECTED.
	RET	Z
	AND	07H
	OUT	(DSKSEL),A	; DESELECT IT.
	RET
;
; STEP HEAD
;
HDSTP0:
	LD	B,0		; SET TO STEP TOWARDS TRACK 0
	JR	HDSTP3
HDSTP1:
	LD	A,(CURTRK)
	CP	76
	RET	Z
HDSTP2:
	INC	A
	LD	(CURTRK),A
	LD	B,0
	SET	DIRECT,B	; SET TO STEP TOWARDS TRACK 77
HDSTP3:
	LD	C,DSKCOM
	OUT	(C),B
	SET	HDSTEP,B
	OUT	(C),B		; OUTPUT THE STEP PULSE.
	EX	(SP),HL		; DELAY
	EX	(SP),HL
	RES	HDSTEP,B	; OUTPUT STEP TRAILING EDGE.
	OUT	(C),B
	CALL	HDDLY0
	RET
;
; DIRECT READ TRACK
;
RDTRK:
	LD	HL,DATA
	LD	(DATPTR),HL
	XOR	A
	LD	(CURSEC),A
; WAIT FOR SECTOR HOLE
RDTRK0:
	XOR	A
	LD	(SECFLG),A
;
	LD	HL,SCVEC
	LD	(DSKVSL),HL
;
	LD	A,CTRMOD	; INTERRUPT AT NEXT SECTOR.
	OUT	(CLK0),A
	LD	A,1
	OUT	(CLK0),A
	LD	HL,RDTRK2	; ON NEXT INTERRUPT, GO TO RDTRK2
	LD	(INTPNT),HL
; LOOP UNTIL SECTOR FLAG IS SET
RDTRK1:
	LD	A,(SECFLG)
	OR	A
	JR	Z,RDTRK1
	LD	HL,0
	LD	(DSKVSL),HL
	JR	RDTRK3
; INTERRUPT TO SET THE SECTOR FLAG
RDTRK2:
	LD	A,80H
	LD	(SECFLG),A
	LD	(SCCC),A
	RET
RDTRK3:
	DI
	LD	HL,(DATPTR)
	LD	A,(CURSEC)
	OR	80H
	LD	E,A
	LD	A,RDDAT		; PREPARE TO READ.
	LD	B,TM256A
	DJNZ	$		; TIME OUT 256 USEC BEFORE READING.
	OUT	(DSKCOM),A	; TURN ON READ CIRCUITRY.
	LD	BC,8000H+DSKDAT	; 128 BYTE SECTOR + SEC + TRK + BCK + FWD + CRC
; 400 USECS FROM INTERRUPT
	IN	A,(DSKDAT)	; READ SECTOR
	CP	E
	IN	A,(DSKDAT)	; READ TRACK	
	JR	NZ,RDTRK6
	LD	(HL),E		; STORE SECTOR
	INC	HL
	LD	(HL),A		; STORE TRACK
	INC	HL
RDTRK4:
	INI			; DATA
	NOP
	NOP
	NOP
	JR	NZ,RDTRK4
; BCK/FWD
	INI
	INI
	INI
	INI
; CRC
	INI
	INI
	LD	(DATPTR),HL
RDTRK5:
;	TURN OFF READ
	XOR	A
	OUT	(DSKCOM),A
	EI
	LD	A,(CURSEC)
	INC	A
	LD	(CURSEC),A
	CP	32		; LAST SECTOR?
	JP	NZ,RDTRK0	; NO? READ NEXT ONE
	RET			; ELSE RETURN
RDTRK6:
	EI
	XOR	A
	OUT	(DSKCOM),A	; TURN OFF READ
	JP	RDTRK0
;
; WRITE SECTOR USING PROM - REQUIRES FORMATTED DISK
;
WRTRK:
	LD	HL,DATA
	XOR	A
	LD	(CURSEC),A
;
WRTRK0:
	LD	IY,SCVEC
	LD	A,(HL)		; GET SECTOR
	AND	1FH
	LD	(SCSEC),A
	INC	HL
	LD	A,(HL)		; GET TRACK
	LD	(SCTRK),A
	INC	HL
	LD	(SCDTA),HL	; SET DATA POINTER
;
	LD	DE,80H		; SKIP 128 BYTES
	ADD	HL,DE		; JUMP TO BCK,FWD POINTER VALUES
;
	LD	A,(HL)		; BCK1
	LD	(PTRS+0),A
	INC	HL
	LD	A,(HL)		; BCK2
	LD	(PTRS+1),A
	INC	HL
	LD	A,(HL)		; FWD1
	LD	(PTRS+2),A
	INC	HL
	LD	A,(HL)		; FWD2
	LD	(PTRS+3),A
	INC	HL
;	
	PUSH	HL
	LD	HL,128
	LD	(SCDL),HL
	CALL	FLOPPY		; WRITE SECTOR
	POP	HL
;
	INC	HL		; CRC1
	INC	HL		; CRC2
;
	LD	A,(CURSEC)
	INC	A
	LD	(CURSEC),A
	CP	32		; LAST SECTOR WRITTEN?
	JP	NZ,WRTRK0
	RET
;
; DIRECT WRITE BYPASS PROM
;
WRTRK1:
	XOR	A
	LD	(CURSEC),A
;
; WAIT FOR INDEX HOLE - BEGINNING OF TRACK
;
	CALL	WAIDX
;
	LD	HL,DATA
	LD	(DATPTR),HL
WRTRK3:
	CALL	WASEC		; WAIT FOR SECTOR HOLE
;
	DI
;
	LD	A,WRDAT
	OUT	(DSKCOM),A	; WRITE ON
;
	LD	BC,8200H+DSKDAT
	LD	HL,(DATPTR)
;	LD	A,TIM512
	LD	A,58		; DELAY 928 TSECS
	DEC	A
	JR	NZ,$-1
	NOP
	NOP
; HERE AT 1288 TSECS (VS 1287 IN PROM)
	OUTI			; SECTOR
	OUTI			; TRACK
	NOP
	NOP
WRTRK5:				; WRITE 128 BYTES OF DATA
	OUTI
	NOP
	NOP
	NOP
	JR	NZ,WRTRK5
;
	OUTI			; BCK1
	OUTI			; BCK2
	OUTI			; FWD1
	LD	A,WRCRC
	OUTI			; FWD2
;
;	OUTI			; CRC1
;	OUTI			; CRC2
;
	OUT	(DSKCOM),A
	OUT	(DSKDAT),A	; CRC1
	OUT	(DSKDAT),A	; CRC2
;
	XOR	A
	OUT	(DSKDAT),A	; POSTAMBLE1
	OUT	(DSKDAT),A	; POSTAMBLE2
	OUT	(DSKCOM),A	; WRITE OFF
;
	INC	HL		; CRC1
	INC	HL		; CRC2
	LD	(DATPTR),HL
;
	EI
;
	LD	A,(CURSEC)
	INC	A
	LD	(CURSEC),A
	CP	32
	JP	NZ,WRTRK3
	RET
;
; WAIT FOR INDEX HOLE
;
; 5 MS PER SECTOR HOLE
; O...O...O...O.I.O...O...O...O...ETC
;28  29  30  31 ^ 0   1   2   3
;
WAIDX:
	CALL	WASEC		; WAIT AT LEAST ONE SECTOR
WAIDX1:
	LD	DE,SECFLG
;
	XOR	A
	LD	(SECFLG),A
	LD	(SCCC),A
;
	LD	HL,SCVEC
	LD	(DSKVSL),HL
;
	LD	A,CTRMOD	; INTERRUPT AT NEXT SECTOR.
	OUT	(CLK0),A
	LD	A,1
	OUT	(CLK0),A
	LD	HL,RDTRK2	; ON NEXT SECTOR GO TO RDTRK2
	LD	(INTPNT),HL
	LD	BC,0
WAIDX2:
	INC	BC
	LD	A,(DE)
	OR	A
	JR	Z,WAIDX2
	LD	A,B
	CP	01H		; LESS THAN 01H IS AN INDEX MARKER
	JR	NC,WAIDX1
; INDEX HOLE LOCATED
	LD	HL,0
	LD	(DSKVSL),HL
	RET
;
WASEC:
	LD	DE,SECFLG
;
	XOR	A
	LD	(SECFLG),A
	LD	(SCCC),A
;
	LD	HL,SCVEC
	LD	(DSKVSL),HL
;
	LD	A,CTRMOD	; INTERRUPT AT NEXT SECTOR.
	OUT	(CLK0),A
	LD	A,1
	OUT	(CLK0),A
	LD	HL,RDTRK2	; ON NEXT SECTOR GO TO RDTRK2
	LD	(INTPNT),HL
; LOOP UNTIL SECTOR FLAG IS SET
WASEC1:
	LD	A,(DE)
	OR	A
	JR	Z,WASEC1
;
	LD	HL,0
	LD	(DSKVSL),HL
	RET
;
; HEAD STEP DELAY
;
HDDLY0:
	LD	DE,0400H
HDDLY1:				; DELAY LOOP BEORE MOVE HEAD AGAIN
	DEC	DE
	LD	A,D
	OR	E
	JP	NZ,HDDLY1
	RET
;
; READ BYTE FROM CONSOLE
;
TTYIN:  IN 	A,(SERCON)
	BIT	RXRDY,A
	JR	Z,TTYIN		; NOT READY YET.
	IN	A,(SERDAT)
	RET
;
; WRITE BYTE TO CONSOLE
;
TTYOUT:	
	PUSH	AF
TTYOU1:
	IN	A,(SERCON)
	BIT	TXRDY,A
	JR	Z,TTYOU1
	POP	AF
	OUT	(SERDAT),A
	RET
;
;
;
CURTRK:	DEFB	0
CURSEC:	DEFB	0
SECFLG:	DEFB	0
DATPTR:	DEFW	0
;
SCVEC:
SCLUN:	DEFB	0
SCREQ:	DEFB	0EH		; WRITE BINARY
SCDTA:	DEFW	DATA
SCDL:	DEFW	128		; WRITE ONE SECTOR SO CAN SET PTRS
SCCRA:	DEFW	0
SCERA:	DEFW	0
SCCC:	DEFB	0
SCSEC:	DEFB	0
SCTRK:	DEFB	0
;
MSG1:	DEFB	0DH
	DEFB	0AH
	DEFM	'MCZIMAGER V1.1 (2021) BY LES BIRD'
	DEFB	0DH
	DEFB	0AH
	DEFM	'SENDS DISK TRACKS TO CONSOLE PORT'
	DEFB	0DH
	DEFB	0AH
	DEFM	'HOST SYSTEM SHOULD BE RUNNING MCZIMAGERHOST TO'
	DEFB	0DH
	DEFB	0AH
	DEFM	'CAPTURE THE TRACK DATA'
	DEFB	0DH
	DEFB	0AH
MSGEND:	EQU	$-MSG1
;
PROMPT:	DEFB	0DH
	DEFB	0AH
	DEFM	'IMAGER READY (Q TO QUIT)>'
PROLEN:	EQU	$-PROMPT
SAVSTK:	DEFW	0
STACKE:	DEFS	80H
STACK:	EQU	$
;
DATA:	DEFS	1100H		; 136 BYTES X 32 SECTORS (4352 BYTES)
	END
	