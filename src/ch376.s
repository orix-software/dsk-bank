; =====================================================================
;
; =====================================================================

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
.include "case.mac"
.include "ch376.inc"


;----------------------------------------------------------------------
;			include application
;----------------------------------------------------------------------

;----------------------------------------------------------------------
;				imports
;----------------------------------------------------------------------
; From main
.import fpos

; From main
.importzp zptr

; From dsk-cli.s
.import prhexa

;----------------------------------------------------------------------
;				exports
;----------------------------------------------------------------------
.export SetFilename
.export FileOpen
.export FileClose
.export SetByteRead
.export ReadUSBData
.export ByteRdGo
.export ByteLocate

.export ch376_debug

;----------------------------------------------------------------------
;			Defines / Constantes
;----------------------------------------------------------------------
DEBUG_CH376 = 1
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
	.segment "BSS"

		.if DEBUG_CH376
			unsigned char lastcmd

			unsigned char errFileOpen
			unsigned char errFileClose
			unsigned char errSetByteRead
			unsigned char errByteRdGo
			unsigned char errByteLocate

			unsigned char WaitResponseX
			unsigned char WaitResponseY
			unsigned char WaitResponseOVF
		.endif
.popseg

;----------------------------------------------------------------------
;			Chaînes statiques
;----------------------------------------------------------------------
.pushseg
	.segment "RODATA"

.popseg

;----------------------------------------------------------------------
;			Programme principal
;----------------------------------------------------------------------
.segment "CODE"

;----------------------------------------------------------------------
; Entrée:
;	AY: Adresse nom de fichier
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
.proc SetFilename
		sta	zptr			; [3]
		sty	zptr+1			; [3]
		lda	#CH376_SET_FILENAME	; [2]
		sta	CH376_COMMAND		; [4]

	.if ::DEBUG_CH376
		sta	lastcmd
	.endif

		ldy	#$ff			; [2]
	loop:
		iny				; [2]
		lda	(zptr),y		; [5+]
		sta	CH376_DATA		; [4]
		bne	loop			; [2/3]
		rts				; [6]
.endproc

;----------------------------------------------------------------------
; Entrée:
;	-
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
.proc FileOpen
		lda	#CH376_FILE_OPEN	; [2]
		sta	CH376_COMMAND		; [4]
	.if ::DEBUG_CH376
		sta	lastcmd
		jsr	WaitResponse		; [3]
		sta	errFileOpen
		rts
	.else
		jmp	WaitResponse		; [3]
	.endif
.endproc

;----------------------------------------------------------------------
; Entrée:
;	-A: 0-> pas de mise à jour de la taille du fichier, 1-> mise à jour
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
.proc FileClose
		pha				; [3]
		lda	#CH376_FILE_CLOSE	; [2]
		sta	CH376_COMMAND		; [4]
	.if ::DEBUG_CH376
		sta	lastcmd
	.endif
		pla				; [4]
		sta	CH376_DATA		; [4]
		jsr	WaitResponse		; [6]
		cmp	#CH376_USB_INT_SUCCESS	; [2]
	.if ::DEBUG_CH376
		sta	errFileClose		; [4]
	.endif
		rts				; [6]
.endproc

;----------------------------------------------------------------------
; SetByteRead
; Taille: 26
;----------------------------------------------------------------------
; Entrée:
;       - AY: Nombre d'octets a lire (.A = LSB, .Y = MSB)
;
; Sortie:
;       - A,X,Y: modifiés
;       C      : 0->Ok, 1->KO
;
; Variables:
;       Modifiées:
;               -
;       Utilisées:
;               -
; Sous-routines:
;       - WaitResponse
;
;----------------------------------------------------------------------
.proc SetByteRead
		pha				; [3]
		lda	#CH376_BYTE_READ	; [2]
		sta	CH376_COMMAND		; |4]

	.if ::DEBUG_CH376
		sta	lastcmd
	.endif

		pla				; [4]
		sta	CH376_DATA		; [4]
		sty	CH376_DATA		; [4]
		jsr	WaitResponse		; [6]

		cmp	#CH376_USB_INT_DISK_READ	; [2]
	.if ::DEBUG_CH376
		sta	errSetByteRead		; [4]
	.endif
		bne	error			; [2/3]
		clc				; [2]
		rts				; [6]

	error:
		; /!\ TEMPORAIRE POUR DEBUG
		; Drive not ready
		; lda #$c0
		sec				; [2]
		rts				; [6]
.endproc

;----------------------------------------------------------------------
; ReadUSBData:
;
; Entrée:
;       -
; Sortie:
;       ACC: Nombre d'octets à lire
;       Z  : 1->rien à lire
; Variables:
;       Modifiées:
;               -
;       Utilisées:
;               -
; Sous-routines:
;       -
;----------------------------------------------------------------------
.proc ReadUSBData
		lda	#CH376_RD_USB_DATA0	; [2]
		sta	CH376_COMMAND		; [4]

	.if ::DEBUG_CH376
		sta	lastcmd
	.endif

		lda	CH376_DATA		; [4]

		rts				; [6]
.endproc

;----------------------------------------------------------------------
; ByteRdGo
; Entrée:
;
; Sortie:
;
; Variables:
;       Modifiées:
;               -
;       Utilisées:
;               -
; Sous-routines:
;       - WaitResponse
; Ok -> INT_DISK_READ ($1d)
; Plus de donnees -> INT_SUCCESS ($14)
; X,Y: Modifies
;----------------------------------------------------------------------
.proc ByteRdGo
                lda     #CH376_BYTE_RD_GO	; [2]
                sta     CH376_COMMAND		; [4]

	.if ::DEBUG_CH376
		sta	lastcmd
	.endif

                jsr     WaitResponse		; [6]
                cmp     #CH376_USB_INT_DISK_READ	; [2]

	.if ::DEBUG_CH376
		sta	errByteRdGo		; [4]
	.endif
                rts				; [6]
.endproc

;----------------------------------------------------------------------
; ByteLocate
;----------------------------------------------------------------------
;
; Entrée:
;	-
; Sortie:
;	A: Code erreur ch376
;	Z: 1-> INT_SUCCESS, 0-> Erreur
;	X, Y: Inchangés
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		fpos
; Sous-routines:
;	WaitResponse
;----------------------------------------------------------------------
.proc ByteLocate
		lda	#CH376_BYTE_LOCATE	; [2]
		sta	CH376_COMMAND		; [4]

	.if ::DEBUG_CH376
		sta	lastcmd
	.endif

		lda	fpos			; [4]
		sta	CH376_DATA		; [4]

		lda	fpos+1			; [4]
		sta	CH376_DATA		; [4]

		lda	fpos+2			; [4]
		sta	CH376_DATA		; [4]

		lda	fpos+3			; [4]
		sta	CH376_DATA		; [4]

		jsr	WaitResponse		; [6]
		cmp	#CH376_USB_INT_SUCCESS	; [2]

	.if ::DEBUG_CH376
		sta	errByteLocate		; [4]
	.endif

		rts				; [6]
.endproc
;---------------------------------------------------------------------------
; WaitResponse:
; A voir si il faut preserver X et Y
;
; Entree:
;
; Sortie:
; Z: 0 -> ACC: Status du CH376
; Z: 1 -> Timeout
; X,Y: Modifies
;---------------------------------------------------------------------------
; 25 Octets
;---------------------------------------------------------------------------
.proc WaitResponse
	.if ::DEBUG_CH376
		lda	#$00
		sta	WaitResponseOVF
	.endif

		ldy     #$00			; [2]
        ZZZ009:
		ldx     #$00			; [2]
	ZZZ010:
		lda     CH376_COMMAND		; [4]
		bmi     ZZZ011			; [2/3]
		lda     #CH376_GET_STATUS	; [2]
		sta     CH376_COMMAND		; [4]
		lda     CH376_DATA		; [4]
	.if ::DEBUG_CH376
		stx	WaitResponseX		; [4]
		sty	WaitResponseY		; [4]
	.endif
		rts				; [6]

	ZZZ011:
		inx				; [2]
		bne     ZZZ010			; [2/3]
		iny				; [2]
		bne     ZZZ009			; [2/3]
	.if ::DEBUG_CH376
		php
		pha
		lda	#$ff
		sta	WaitResponseOVF
		stx	WaitResponseX		; [4]
		sty	WaitResponseY		; [4]
		pla
		plp
	.endif
		rts				; [6]
.endproc

;----------------------------------------------------------------------
; Entrée:
;	-
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
.proc ch376_debug
		prints	"--------------------"
		crlf

		prints	"last command: "

		do_case	lastcmd
			; case_of	CH376_SET_FILENAME
			case_of	CH376_FILE_OPEN
				prints	"FileOpen"
				lda	errFileOpen

			case_of	CH376_FILE_CLOSE
				prints	"FileClose"
				lda	errFileClose

			case_of	CH376_BYTE_READ
				prints	"SetByteRead"
				lda	errSetByteRead

			case_of	CH376_RD_USB_DATA0
				prints	"RdUsbData0"
				lda	#$00

			case_of	CH376_BYTE_RD_GO
				prints	"ByteRdGo"
				lda	errByteRdGo

			case_of	CH376_BYTE_LOCATE
				prints	"ByteLocate"
				lda	errByteLocate

			otherwise
				prints "???"
				lda	lastcmd
		end_case

		pha
		crlf
		prints	"last status : $"
		pla
		jsr	prhexa
		crlf

		prints	"WaitResponse: X=$"
		lda	WaitResponseX
		jsr	prhexa
		prints	", Y=$"
		lda	WaitResponseY
		jsr	prhexa
		prints	", Ovf= $"
		lda	WaitResponseOVF
		jsr	prhexa
		rts
.endproc

