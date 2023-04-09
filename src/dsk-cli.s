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

;----------------------------------------------------------------------
;				exports
;----------------------------------------------------------------------
;export __ZP_CART__:abs = VARLNG

;.export dsk_side1_offset
;.export fpos

; Pour ch376.s, si on ne peut pas faire appel au kernel
;.exportzp zptr

;----------------------------------------------------------------------
;			Defines / Constantes
;----------------------------------------------------------------------
CAN_USE_KERNEL = 0

;----------------------------------------------------------------------
;				Page zéro
;----------------------------------------------------------------------
.pushseg
	.segment "ZEROPAGE"
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
		add_command "mount2", cmnd_mount
		add_command "seek", cmnd_seek
		add_command "read", cmnd_read
		add_command "umount", cmnd_umount

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
		adc	#.strlen("mount2")
		jsr	get_param
		beq	end_noparam

		tya
		clc
		adc	zptr
		sta	zptr
		lda	zptr+1
		adc	#$00
		sta	zptr+1

		ldy	#$ff
	loop:
		iny
		lda	(zptr),y
		sta	dskname,y
		beq	end
		cmp	#' '
		bne	loop
	end:
		lda	#$00
		sta	(zptr),y
		sta	dskname,y

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
		adc	#.strlen("umount")
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


