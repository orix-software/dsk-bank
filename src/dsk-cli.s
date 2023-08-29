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

;----------------------------------------------------------------------
;			include application
;----------------------------------------------------------------------
.include "macros/rom_cmd.mac"

;----------------------------------------------------------------------
;				imports
;----------------------------------------------------------------------
; From dsk-bank.s
.importzp zptr
.import dskname
.import fp

.import bank_init
.import mount
.import umount
.import read_track


; From fdc.s
;.import fdc_status
;.import fdc_track
;.import fdc_sector
;.import fdc_data

; From ch376.s
;.import SetByteRead
;.import ReadUSBData
;.import ByteRdGo

; From ch376.s (utile si on ne peut pas faire appel au kernel)
;.import ByteLocate
;.import FileOpen
;.import SetFilename
.import FileClose

; Pour cmnd_debug
; From fdc.s
.import fdc_track
.import fdc_sector
; From dsk-bank.s
.import buf_track
.import buf_track20
.import byte_offset
.import save_track
.import save_sector
; From ch376.s
.import ch376_debug

;----------------------------------------------------------------------
;				exports
;----------------------------------------------------------------------
;export __ZP_CART__:abs = VARLNG

;.export dsk_side1_offset
;.export fpos

; Pour ch376.s, si on ne peut pas faire appel au kernel
;.exportzp zptr

; Pour ch376.s (debug)
.export prhexa

;----------------------------------------------------------------------
;			Defines / Constantes
;----------------------------------------------------------------------
CAN_USE_KERNEL = 0

.enum
	error_read = 1
	error_mount
	error_track
	error_fmt
	error_open
	error_readusb
	error_rdgo
.endenum

;----------------------------------------------------------------------
;				Page zéro
;----------------------------------------------------------------------
.pushseg
	.segment "ZEROPAGE"
		unsigned char errFlag
;		unsigned short zptr
;		;unsigned short fp
.popseg

;----------------------------------------------------------------------
;				Variables
;----------------------------------------------------------------------
.pushseg
	.segment "DATA"

	.segment "BSS"
.popseg

;----------------------------------------------------------------------
;			Chaînes statiques
;----------------------------------------------------------------------
.pushseg
	.segment "RODATA"

.popseg

;----------------------------------------------------------------------
; Définition de la rom
;----------------------------------------------------------------------
	;----------------------------------------------------------------------
	; Liste des commandes
	;----------------------------------------------------------------------
		add_command "dsk", cmnd_mount
		; add_command "seek", cmnd_seek
		; add_command "read", cmnd_read
		add_command "eject", cmnd_umount
		add_command "dskinfo", cmnd_debug

	;----------------------------------------------------------------------
	; Vecteurs Orix: rom_type, parse_vector, rom_signature
	;
	; /!\ Déplacer set_orix_vector en fin de programme si on utilise
	;     les macros command / endcommand
	;----------------------------------------------------------------------
		set_orix_vectors $01, $0000, "DSK LIB"
		; set_orix_vectors $01, $0000, rom_signature

	;----------------------------------------------------------------------
	; Vecteurs 6502: nmi, reset, irq
	;----------------------------------------------------------------------
		set_cpu_vectors bank_init, bank_init, IRQVECTOR

	;----------------------------------------------------------------------
	; Signature de la rom
	;----------------------------------------------------------------------
		; rom_signature: .asciiz "Example ROM"


;----------------------------------------------------------------------
;			Programme principal
;----------------------------------------------------------------------
.segment "CODE"

;----------------------------------------------------------------------
; Entrée:
;	- AY: adresse de la ligne de commande (A=LSB)
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
.proc cmnd_mount
		clc
		adc	#.strlen("dsk")
		jsr	get_param
		; beq	end_noparam
		bne	suite
		jmp	end_noparam
	suite:

		tya
		clc
		adc	zptr
		sta	zptr
		lda	zptr+1
		adc	#$00
		sta	zptr+1

		ldy	#$00
		lda	(zptr),y
		cmp	#'/'
		beq	absolute_path

		getcwd
		sta	path+1
		sty	path+2

		ldx	#$ff
	loop:
		inx
	path:
		lda	$fff,x
		sta	dskname,x
		bne	loop

		dex
		beq	relative_path

		; Ajoute le '/' final
		inx
		lda	#'/'
		sta	dskname,x

		jmp	relative_path


	absolute_path:
		ldx	#$ff

	relative_path:
		ldy	#$ff

	absolute_loop:
		iny
		inx
		lda	(zptr),y
		sta	dskname,x
		beq	end
		cmp	#' '
		bne	absolute_loop
	end:
		lda	#$00
		sta	(zptr),y
		sta	dskname,x

.if 0
		; C=0: ftdos
		sec
		ldx	zptr
		ldy	zptr+1
		jsr	mount

		php
		ldy	#$00
		ldx	#$03
		.byte	$00, XDECIM
		crlf
		plp
		bcs	end_error

		; Piste 20, secteur 1, face 0
		ldx	#$14
		ldy	#$01
		clc
		jsr	read_track

	.if ::CAN_USE_KERNEL
		fclose	(fp)
	.else
		; Pas de mise à jour de la taille du fichier
		lda	#$00
		jsr	FileClose
	.endif
		rts

	end_error:
		rts

	end_noparam:
		print	dskname
		crlf
		rts

.else
		lda	#$00
		sta	errFlag

		; Initialise la banque
		jsr	bank_init

		; Monte le disque
		; C=0 => FTDOS
		; C=1 => Sedoric
		sec
		jsr	mount
		beq	exit

	errOpen:
		sta	errFlag
		do_case
			case_of error_mount
				prints	"File not found: "

			case_of error_fmt
				prints	"Bad file format: "

			case_of error_track
				prints	"Track 20 not found: "

			case_of error_open
				prints	"Open error: "
			case_of error_readusb
				prints	"ReadUSBData error: "
			case_of	error_rdgo
				prints	"ByteRdGo error: "
		end_case

	end_noparam:
		print	dskname
		crlf

		lda	errFlag
		beq	exit

		ldy	#$00
		sty	dskname

	exit:
		ldx	#$00
		rts
.endif

.endproc

;----------------------------------------------------------------------
; Entrée:
;	- AY: adresse de la ligne de commande (A=LSB)
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
.proc cmnd_seek
		clc
		adc	#.strlen("seek")
		jsr	get_param
		beq	end

	end:
		rts
.endproc

;----------------------------------------------------------------------
; Entrée:
;	- AY: adresse de la ligne de commande (A=LSB)
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
.proc cmnd_read
		clc
		adc	#.strlen("read")
		jsr	get_param
		beq	end

	end:
		rts
.endproc

;----------------------------------------------------------------------
; Entrée:
;	- AY: adresse de la ligne de commande (A=LSB)
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
.proc cmnd_umount
		clc
		adc	#.strlen("eject")
		jsr	get_param
		bne	end_error

		print	dskname
		crlf
	end:
		jmp	umount

	end_error:
		; Paramètre indiqué alors qu'il n'en faut pas
		jmp	umount
.endproc

;----------------------------------------------------------------------
; Entrée:
;	- AY: adresse de la ligne de commande (A=LSB)
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
.proc cmnd_debug
;		clc
;		adc	#.strlen("dskinfo")
;		jsr	get_param
;		bne	end_noparam


		prints	"dskname     : "
		print	dskname
		crlf
		crlf

		prints	"fdc_track   : $"
		lda	fdc_track
		jsr	prhexa
		crlf

		prints	"fdc_sector  : $"
		lda	fdc_sector
		jsr	prhexa
		crlf

		prints	"byte_offset : $"
		lda	byte_offset
		jsr	prhexa
		crlf
		crlf

		prints	"save_track  : $"
		lda	save_track
		jsr	prhexa
		crlf

		prints	"save_sector : $"
		lda	save_sector
		jsr	prhexa
		crlf
		crlf

		prints	"buf_track   : $"
		lda	#>buf_track
		jsr	prhexa
		lda	#<buf_track
		jsr	prhexa
		crlf

		prints	"buf_track20 : $"
		lda	#>buf_track20
		jsr	prhexa
		lda	#<buf_track20
		jsr	prhexa
		crlf

		jsr	ch376_debug
		crlf
	end_noparam:
		rts
.endproc

.proc prhexa
	hnout1:
		;cmp	#10
		;bcc	nibout

	hexout1:
		pha				; [3]

		; High nibble
		lsr				; [2]
		lsr				; [2]
		lsr				; [2]
		lsr				; [2]
		jsr	nibout			; [6]

		; Low nibble
		pla				; [4]
		and	#$0f			; [2]

	nibout:
		ora	#$30			; [2]
		cmp	#$3a			; [2]
		bcc	nibo1			; [2/3]
		adc	#$06			; [2]

	nibo1:
		; sta	$bb80,y			; [5]
		; iny				; [2]
		cputc
		rts				; [6]
.endproc

;----------------------------------------------------------------------
; Entrée:
;	-
;
; Sortie:
;	- Y: offset vers le 1er caractère du paramètre
;	- Z: 1-> pas de paramètre, 0-> paramètre pésent
;	- work_ptr: pointeur ligne de commande
;
; Variables:
;	Modifiées:
;		- zptr
;	Utilisées:
;		-
; Sous-routines:
;	-
;
;----------------------------------------------------------------------
.proc get_param
		; On se déplace après la commande
		sta	zptr
		bcc	suite
		iny

	suite:
		sty	zptr+1

		; Saute les espaces après la commande
		ldx	#$ff
		ldy	#$ff
	loop:
		iny
		lda	(zptr),y
		beq	no_param
		cmp	#' '
		beq	loop

		rts

	no_param:
		rts
.endproc


