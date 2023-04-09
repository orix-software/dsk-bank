;mount: filename => AY
;umount:
;reset:

;seek_track: A=track, Y=side
;read_sector: A=sector, XY=buffer

;----------------------------------------------------------------------
;			includes cc65
;----------------------------------------------------------------------
.feature string_escapes

.include "telestrat.inc"

;----------------------------------------------------------------------
;			includes SDK
;----------------------------------------------------------------------
.include "SDK.mac"
.include "types.mac"


;----------------------------------------------------------------------
;			include application
;----------------------------------------------------------------------

;----------------------------------------------------------------------
;				imports
;----------------------------------------------------------------------
; From main
.import dsk_side1_offset
.import fpos

; From ch376.s
.import ByteLocate

;----------------------------------------------------------------------
;				exports
;----------------------------------------------------------------------
;.export fdc_status
.export fdc_track
.export fdc_sector
;.export fdc_data

;----------------------------------------------------------------------
;			Defines / Constantes
;----------------------------------------------------------------------
FDC_LOST_DATA = %00000100

;----------------------------------------------------------------------
;				Page zéro
;----------------------------------------------------------------------
.pushseg
	.segment "ZEROPAGE"

.popseg

;----------------------------------------------------------------------
;				Variables
;----------------------------------------------------------------------
.pushseg
	.segment "DATA"
		; Registres:
		;		Read		Write
		;	00	Status reg	Command reg
		;	01	Track reg	Track reg
		;	10	Sector reg	Sector reg
		;	11	Data reg	Data reg

		; Dans l'idéal devraient être des registres de la carte
		unsigned char fdc_status
		unsigned char fdc_track
		unsigned char fdc_sector
		; unsigned char fdc_data

		; Interne
		unsigned char fdc_dirc
		unsigned char fdc_side

.popseg

;----------------------------------------------------------------------
;			Tables statiques
;----------------------------------------------------------------------
.pushseg
	.segment "RODATA"
		fn_table_lo:
					; Type I
					; 00       01    02    03    04      05      06       07
			.lobytes	restore, seek, step, step, stepIn, stepIn, stepOut, stepOut

					; Type II
					; 08          09          10           11
			.lobytes	readSector, readSector, writeSector, writeSector

					; Type III et IV
					; 12           13  (IV)        14         15
			.lobytes	readAddress, forceInterrupt, readTrack, writeTrack

		fn_table_hi:
					; Type I
					; 00       01    02    03    04      05      06       07
			.hibytes	restore, seek, step, step, stepIn, stepIn, stepOut, stepOut

					; Type II
					; 08          09          10           11
			.hibytes	readSector, readSector, writeSector, writeSector

					; Type III et IV
					; 12           13  (iV)        14         15
			.hibytes	readAddress, forceInterrupt, readTrack, writeTrack

.popseg

;----------------------------------------------------------------------
;			Programme principal
;----------------------------------------------------------------------
.segment "CODE"

;----------------------------------------------------------------------
; Entrée:
;	- A: Commande FDC
;
; Sortie:
;	-
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;
;----------------------------------------------------------------------
; : A=function, XY=parameter bloc
.proc fdc_dispatch
		; Sauvegarde P et A
		php
		pha

		; La commande est dans le quartet haut
		lsr
		lsr
		lsr
		lsr

		tax
		lda	fn_table_lo,x
		sta	_exec+1
		lda	fn_table_hi,x
		sta	_exec+2

		; Restaure A et P
		pla
		plp
	_exec:
		jmp	$ffff
.endproc


; =====================================================================
; FDC - Commandes Type I
; r1 r0: stepping rate
; h: head load
; V: verification
; u: update
; =====================================================================
;----------------------------------------------------------------------
; 0 0 0 0 h V r1 r0
;----------------------------------------------------------------------
.proc restore
		; Seek to Track 00
		lda	#$00
		sta	fdc_track
		sta	fdc_sector
		sta	fdc_side

		jmp	seek
.endproc

;----------------------------------------------------------------------
; 0 0 0 1 h V r1 r0
;----------------------------------------------------------------------
.proc seek
		; Seek to track fdc_track
		; Vérifier que les valeurs sont correctes par rapport au
		; fichier .dsk (side, track)
		lda	fdc_side
		beq	suite

		clc
		adc	dsk_side1_offset

	suite:
		; jsr	TrackOffset
		; [ TrackOffset
		ldy	#0
		sta	fpos+1
		sty	fpos+2
		; sty	fpos+2
		; sty	fpos+3

		; x2
		asl	fpos+1
		rol	fpos+2

		; +1 -> x3
		pha
		clc
		adc	fpos+1
		sta	fpos+1
		bcc	ZZ0028
		inc	fpos+2

	ZZ0028:
		; x8 -> x24
		asl	fpos+1
		rol	fpos+2
		asl	fpos+1
		rol	fpos+2
		asl	fpos+1
		rol	fpos+2

		; +1 -> x25
		pla
		clc
		adc	fpos+1
		sta	fpos+1
		bcc	ZZ0029
		inc	fpos+2

	ZZ0029:
		; +256
		inc	fpos+1
		bne	ZZ0030
		inc	fpos+2
	ZZ0030:
		; ]

		jmp	ByteLocate
.endproc

;----------------------------------------------------------------------
; 0 0 1 u h V r1 r0
;----------------------------------------------------------------------
.proc step
		; Step-In ou Step-Out
		; Vérifier le flag u de la commande pur savoir si il faut
		; mettre à jour fdc_track
		lda	fdc_dirc
		bmi	step_out
		jmp	stepIn

	step_out:
		jmp	stepOut
.endproc

;----------------------------------------------------------------------
; 0 1 0 u h V r1 r0
;----------------------------------------------------------------------
.proc stepIn
		; Vérifier qu'on ne dépasse pas la piste maximale
		lda	#$01
		sta	fdc_dirc
		inc	fdc_track
		jmp	seek
.endproc

;----------------------------------------------------------------------
; 0 1 1 u h V r1 r0
;----------------------------------------------------------------------
.proc stepOut
		; Vérifier qu'on n'est pas en deça de la piste 00
		lda	#$ff
		sta	fdc_dirc
		dec	fdc_track
		jmp	seek
.endproc

; =====================================================================
; FDC - Commandes Type II
; m: multiple
; S: Side select (1791/3) / Sector length (1795/7)
; E: Delay
; C: Side Compare (1791/3) / Side Select (1795/7)
; a0: data address mark (0: Data Mark, 1: Deleted Data Mark)
; =====================================================================
;----------------------------------------------------------------------
; 1 0 0 m S E C 0
;----------------------------------------------------------------------
.proc readSector
		; Suppose qu'on est placé sur la bonne piste
.endproc

;----------------------------------------------------------------------
; 1 0 1 m S E C a0
;----------------------------------------------------------------------
.proc writeSector
		lda	#FDC_LOST_DATA
		sta	fdc_status
		rts
.endproc

; =====================================================================
; FDC - Commandes Type III
; =====================================================================
;----------------------------------------------------------------------
; 1 1 0 0 0 E 0 0
;----------------------------------------------------------------------
.proc readAddress
		; Retour: A=head, X=sector, Y=track
		rts
.endproc

;----------------------------------------------------------------------
; 1 1 1 0 0 E 0 0
;----------------------------------------------------------------------
.proc readTrack
		rts
.endproc

;----------------------------------------------------------------------
; 1 1 1 1 0 E 0 0
; Data: $00 - $f4 => Data
;	$f5 => write $A1, preset CRC
;	$f6 => write $C2
;	$f7 => generate 2 CRC bytes
;	$f8 - $ff => Data
;		$fb: Data Address Mark
;		$fc: Index Mark
;		$fe: ID address Mark
;
;	IBM system 34 format - 256 bytes/sector
;
;	Number of Bytes (decimal)       Value of byte written
;		80                      4E
;		12                      00
;		3                       F6 (writes C2)
;		1                       FC (index mark)
;		50                      4E
;	+-----------
;	|       12                      00
;	|       3                       F5 (writes A1)
;	|       1                       FE (ID address mark)
;	|       1                       Track number
;	|       1                       Side number
;	|       1                       Sector Number
;	|       1                       01 (sector length)
;	|       1                       F7 (2 CRCs written)
;	|       22                      4E
;	|       12                      00
;	|       3                       F5 (writes A1)
;	|       1                       FB (data address mark)
;	|       256                     DATA
;	|       1                       F7 (2 CRCs written)
;	|       54                      4E
;	+-----------
;		to the end        4E
;
;----------------------------------------------------------------------
.proc writeTrack
		rts
.endproc

; =====================================================================
; FDC - Commandes Type IV
; =====================================================================
;----------------------------------------------------------------------
; 1 1 0 1 i3 i2 i1 i0
;----------------------------------------------------------------------
.proc forceInterrupt
		rts
.endproc

