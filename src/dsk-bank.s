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
;.include "errno.inc"
.include "fcntl.inc"
.include "stdio.inc"

;----------------------------------------------------------------------
;			includes SDK
;----------------------------------------------------------------------
.include "SDK.mac"
.include "types.mac"
.include "errors.inc"
.include "ch376.inc"

.ifndef XFSEEK
	XFSEEK =$3f
.endif

;----------------------------------------------------------------------
;			include application
;----------------------------------------------------------------------
.include "macros/rom_cmd.mac"
.include "macros/dsk-bank.mac"

;----------------------------------------------------------------------
;				imports
;----------------------------------------------------------------------
; From fdc.s
;.import fdc_status
.import fdc_track
.import fdc_sector
;.import fdc_data

; From ch376.s
.import SetByteRead
.import ReadUSBData
.import ByteRdGo

; From ch376.s (utile si on ne peut pas faire appel au kernel)
.import ByteLocate
.import FileOpen
;.import SetFilename
.import FileClose

;----------------------------------------------------------------------
;				exports
;----------------------------------------------------------------------
; .export __ZP_CART__:abs = VARLNG
.export __ZPSTART__:abs = VARLNG

.export dsk_side1_offset
.export fpos

; Pour ch376.s, si on ne peut pas faire appel au kernel
.exportzp zptr

; Pour dsk-cli.s
.export bank_init
.export dskname
.export mount
.export umount
.export read_track

; Pour dsk-cli (debug)
.export buf_track
.export buf_track20
.export byte_offset
.export save_track
.export save_sector

;----------------------------------------------------------------------
;			Defines / Constantes
;----------------------------------------------------------------------
CAN_USE_KERNEL = 0

;crclo := crc
;crchi := crc+1

;max_path := 49

.enum
	error_read = 1
	error_mount
	error_track
	error_fmt
	error_open
	error_readusb
	error_rdgo
.endenum

TRACK_SIZE = 6400
MAX_SECTORS = 20

NEED_SECTOR_INFOS = 0

WHOLE_TRACK = 1
; DEBUG = 1
CACHE_DIR = 1

;----------------------------------------------------------------------
;				Page zéro
;----------------------------------------------------------------------
.pushseg
	.segment "ZEROPAGE"
		unsigned short zptr
;		;unsigned short fp
.popseg

;----------------------------------------------------------------------
;				Variables
;----------------------------------------------------------------------
.pushseg
	.segment "DATA"
		unsigned short fp
		dskname:
			.asciiz "/usr/share/sedoric/s/sedoric3.dsk"
			.res	50-(*-dskname),0
;		unsigned char dsk_name[80]

		unsigned long fpos

		; Pointeur vers le nom du fichier
		.if ::CAN_USE_KERNEL
			unsigned short ptr
		.endif

;		; unsigned char fdc_status
;		unsigned char fdc_track
;		unsigned char fdc_sector
;		; unsigned char fdc_data

		; 42 pour FTDOS, fonction du fichier pour Sedoric
		unsigned char dsk_side1_offset

		unsigned char ostype

		table_lo:
			;.lobytes
		table_hi:
			;.hibytes

	.segment "BSS"
		.if WHOLE_TRACK
			unsigned char buf_track[TRACK_SIZE]
			unsigned char sectors_tbl[MAX_SECTORS*2]

			.if ::CACHE_DIR
				unsigned char buf_track20[TRACK_SIZE]
				unsigned char sectors_tbl20[MAX_SECTORS*2]
			.endif
		.else
			unsigned char buf_track[MAX_SECTORS*256]
			unsigned char sectors_tbl[MAX_SECTORS]
		.endif

		; Pour GetByte
		unsigned char PTR_MAX
		unsigned char yio

		; Pour la lecture octet par octet
		unsigned char byte_offset

		; TEMPORAIRE: pour 1er tests avec sedsd
		; unsigned char save_a
		; unsigned char save_x
		; unsigned char save_y
		unsigned char save_track
		unsigned char save_sector

		.ifdef DEBUG
			unsigned char track20_count
		.endif

		; Utile uniquement pour sedsd
		unsigned short zptr_save

;		unsigned char jsm_Command               ; $03f4
;		unsigned char fdc_status                ; $03f4
;		unsigned char fdc_track                 ; $03f5
;		unsigned char fdc_sector                ; $03f6
;		;unsigned char fdc_Data                  ; $03f7
;		unsigned char fdc_side                  ; $03f8
;		;unsigned char jsm_dcr                   ; $03f9
;		;unsigned char jsm_orma                  ; $03fa
;		;unsigned char jsm_ROMDIS                ; $03fb
;		;unsigned char jsm_DriveA                ; $03fc
;		;unsigned char jsm_DriveB                ; $03fd
;		;unsigned char jsm_DriveC                ; $03fe
;		;unsigned char jsm_DriveD                ; $03ff
;
;		dsk_side1_offset:
;			.byte 41
;
;
;		;unsigned char dskname[max_path]
;		;unsigned char dskname2[max_path]
;
;	ft_IRQ_READ_VECTOR:
;		.addr IRQ_READ_to_ftIOBuffer
;
;	.if .not IS_BANK
;		unsigned short _6502_IRQVector
;	.endif
.popseg

;----------------------------------------------------------------------
;			Chaînes statiques
;----------------------------------------------------------------------
.pushseg
	.segment "RODATA"
		dsk_header:
			.byte "MFM_DISK"

.popseg

;----------------------------------------------------------------------
;			Programme principal
;----------------------------------------------------------------------
.segment "CODE"
	jmp	dispatch_sedoric
	jmp	dispatch_ftdos
	jmp	set_dskname

.if 0
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
	; : A=function, XY=parameter bloc
	.proc dispatch
			php
			asl
			lda	table_lo
			sta	_exec+1
			lda	table_hi
			sta	_exec+2
			plp
		_exec:
			jmp	$ffff
	.endproc
.else
.if 0
	;----------------------------------------------------------------------
	; Entrée:
	;	A: Track
	;	X: Sector
	;	Y:
	;
	; Sortie:
	;	A: octet lu
	;
	; Variables:
	;	Modifiées:
	;		-
	;	Utilisées:
	;		-
	; Sous-routines:
	;	- read_track
	;
	;----------------------------------------------------------------------
	.proc dispatch
			; BUG: Sedsd arrive en mode Décimal et non Binaire
			;php
			;cld

			sta	save_x			; Track
			stx	save_y			; Sector
			; sty	save_y			;

			; [ debug
			ldy	#$00
			jsr	debug
			lda	#'/'
			sta	$bb80,y
			iny
			txa
			jsr	debug
			lda	#'*'
			sta	$bb80+5
			; ]

			; Sauvegarde le contenu de zptr (pour sedsd)
			lda	zptr
			sta	zptr_save
			lda	zptr+1
			sta	zptr_save+1

			; Secteur=0 -> banque non initialisée
			lda	fdc_sector
			bne	check

;			; C=0: ftdos
;			; C=1: sedoric
;			; [ Ouverture du fichier de la banque
;			 sec
;			 ldx	#<dskname
;			 ldy	#>dskname
;			 jsr	mount
;			; ]

			; [ Si le fichier est déjà ouvert
			; lda	#$01
			; sta	ostype
			;
			; jsr	bank_init
			; ]


		check:
			; Remet les paramètres dans les bons registres
			ldx	save_x
			ldy	save_y

			cpx	fdc_track
			bne	read

			cpy	fdc_sector
			bne	read_sect

			ldy	byte_offset

		get_byte:
			; /!\ Argument modifié par le programme
			lda	buf_track,y
			iny
			sty	byte_offset

			; Restaure le mode Décimal pour sedsd
			;plp

			; Restaure le contenu de zptr (pour sedsd)
			ldy	zptr_save
			sty	zptr
			ldy	zptr_save+1
			sty	zptr+1

			; [ debug
			ldy	#' '
			sty	$bb80+5
			; ]

			; Retour au sedoric
			ldy	#$00
			sty	$0479
			ldy	#$60
			sty	$047e
			jmp	$0477

		read:
			; C=0: ftdos
			; C=1: sedoric
			; [ Ouverture du fichier de la banque
			sec
			ldx	#<dskname
			ldy	#>dskname
			jsr	mount

			ldx	save_x
			ldy	save_y

			; Piste 20, secteur 1, face 0
			; ldx	#$14
			; ldy	#$01
			clc
			jsr	read_track
			bcs	error

			lda	#$00
			jsr	FileClose

			; Secteur demandé
		read_sect:
			ldx	save_y

			lda	sectors_tbl+MAX_SECTORS,x
			sta	get_byte+1
			lda	sectors_tbl,x
			sta	get_byte+2
			beq	error

			stx	fdc_sector

			ldy	#$00
			beq	get_byte

		error:
			; Restaure le mode Décimal pour sedsd
			;plp

			; Restaure le contenu de zptr (pour sedsd)
			ldy	zptr_save
			sty	zptr
			ldy	zptr_save+1
			sty	zptr+1

			; [ debug
			ldy	#' '
			sty	$bb80+5
			; ]

			; Retour au sedoric
			ldy	#$00
			sty	$0479
			ldy	#$60
			sty	$047e
			jmp	$0477
	.endproc
.else
;----------------------------------------------------------------------
; Entrée:
;	A: Track
;	X: Sector
;	Y:
;
; Sortie:
;	A: octet lu
;	Y: offset de l'octet lu dans le secteur
;	X: modifié
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	- read_track
;
;----------------------------------------------------------------------
.proc dispatch_sedoric
;		savezp				; [14]

		sta	save_track		; [4]
		stx	save_sector		; [4]

	.ifdef DEBUG
		ldy	#$00			; [2]
		jsr	debug			; [6]
		lda	#'/'			; [2]
		sta	$bb80,y			; [5]
		iny				; [2]
		txa				; [2]
		jsr	debug			; [4]
		lda	#'*'			; [2]
		sta	$bb80+5			; [4]
						;-----
						; [29]
	.endif

		; Banque initialisée?
		ldy	fdc_sector		; [4]
		bne	ok			; [2/3]

		; C=0: ftdos
		; C=1: sedoric
		; [ Ouverture du fichier de la banque
;		lda	#<dskname2
;		ldx	#>dskname2
;		jsr	set_dskname

		sec				; [2]
	.if ::CAN_USE_KERNEL
		ldx	#<dskname		; [2]
		ldy	#>dskname		; [2]
	.endif
		jsr	mount			; [6]
		;bne	errMount		; [2/3]
		beq	ok

	errMount:
		; [ /!\ TEMPORAIRE DEBUG
		jmp	reboot
		; ]
		sec				; [2]
		bcs	end			; [3]

	.ifdef DEBUG
	ok:
	.endif
		lda	save_track		; [4]
		ldx	save_sector		; [4]

	.ifndef DEBUG
	ok:
	.endif
		cmp	fdc_track		; [4]
		bne	get_track		; [2/3]

		cpx	fdc_sector		; [4]
		beq	read_sector		; [2/3]

	.if ::CACHE_DIR
		cmp	#$14
		beq	get_track20
	.endif
		bne	get_sector		; [2/3]

	get_track:
	.if ::CACHE_DIR
		cmp	#$14			; [2]
		bne	get_data		; [2/3]

		.ifdef DEBUG
			inc	track20_count
		.endif

	get_track20:
		sta	fdc_track		; [4]

		lda	sectors_tbl20+MAX_SECTORS,x	; [4+]
		sta	get_byte+1		; [4]
		lda	sectors_tbl20,x		; [4+]
		sta	get_byte+2		; [4]
		beq	errFormat		; [2/3]

		stx	fdc_sector		; [4]

		ldy	#$00			; [2]
		beq	get_byte		; [3]

	get_data:
	.endif

		; X=Track, Y=Sector
		tax				; [2]
		ldy	save_sector		; [4]
		jsr	read_track		; [6]
		bcs	errTrack		; [2/3]

		ldx	save_sector		; [4]

	get_sector:
		lda	sectors_tbl+MAX_SECTORS,x	; [4+]
		sta	get_byte+1		; [4]
		sta	loop_direct+1		; [4]
		lda	sectors_tbl,x		; [4+]
		sta	get_byte+2		; [4]
		sta	loop_direct+2		; [4]
		beq	errFormat		; [2/3]

		stx	fdc_sector		; [4]

		ldy	#$00			; [2]

		; [ Optimisation: transfert direct du secteur
		; si la destination est < $C000
		; beq	get_byte		; [3]
		lda	$f3+1			; [3]
		cmp	#$c0			; [2]
		bcs	get_byte		; [3]

	loop_direct:
		lda	buf_track,y		; [4+]
		sta	($f3),y			; [6]
		iny				; [2]
		bne	loop_direct		; [2/3]
		; Le sty est normalement inutile (byte_offset = 0)
		sty	byte_offset		; [4]
		beq	end			; [2/3]
		; ]

	read_sector:
		ldy	byte_offset		; [4]

	get_byte:
		; /!\ Argument modifié par le programme
		lda	buf_track,y		; [4+]
		iny				; [2]
		sty	byte_offset		; [4]

	end:
;		restorezp			; [14]

		; [ debug
	.ifdef DEBUG
		ldy	#' '			; [2]
		sty	$bb80+5			; [4]
	.endif
		; ]

		; Retour au sedoric
		ldy	#$00			; [2]
		sty	$0479			; [4]
		ldy	#$60			; [2]
		sty	$047e			; [4]

		ldy	byte_offset		; [4]
		; on renoie l'index de l'octet lu et non du suivant, d'où le dey
		; qui suit.
		dey

		jmp	$0477			; [3]

	errTrack:
	errFormat:
	; errMount:
		; [ /!\ TEMPORAIRE DEBUG
		jmp	reboot
		; ]
		sec				; [2]
		bcs	end			; [3]
.endproc
.endif
.endif

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
.proc dispatch_ftdos
		rts
.endproc

;----------------------------------------------------------------------
; Entrée:
;	AX: Adresse du nom du fichier
;
; Sortie:
;	A,Y: Modifiés
;	X: Inchangé
;
; Variables:
;	Modifiées:
;		dskname
;	Utilisées:
;		-
; Sous-routines:
;	bank_init
;
;----------------------------------------------------------------------
.proc set_dskname
		sta	ld_b0+1			; [4]
		stx	ld_b0+2			; [4]
		sta	st_bn+1			; [4]
		stx	st_bn+2			; [4]

		jsr	bank_init		; [6]

		; Si nomm de fichier nul -> end
		ldy	#$00			; [2]
	ld_b0:
		lda	$ffff			; [4]
		beq	end			; [2/3]

		dey				; [2]
	loop:
		iny				; [2]
	st_bn:
		lda	$ffff,y			; [4+]
		sta	dskname,y		; [5]
		bne	loop			; [2/3]

	end:

		; Si on veut faire la Vérification du fichier et la lecture
		; de la piste 20 maintenant plutôt que de la différer lors
		; de la première lecture d'une piste
		; C=0 -> ftdos, C=1 -> sedoric
;		sec
;	.if ::CAN_USE_KERNEL
;		ldx	#<dskname		; [2]
;		ldy	#>dskname		; [2]
;	.endif
;		jsr	mount			; [6]

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
.ifdef DEBUG
	.proc debug
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
			sta	$bb80,y			; [5]
			iny				; [2]
			rts				; [6]
	.endproc
.endif

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
.proc bank_init
		; Initialise la table des secteurs
		lda	#$00			; [2]
		ldy	#MAX_SECTORS		; [2]

	loop_init:
		sta	sectors_tbl,y		; [5]
		dey				; [2]
		bpl	loop_init		; [2/3]

		; Initialise le nom du fichier
		; sta	dsk_name		; [4]

		; Une seule face par défaut
		sta	dsk_side1_offset	; [4]

		; Initialise l'offset dans le secteur
		sta	byte_offset		; [4]

	.ifdef DEBUG
		; Compteur d'accès à la piste 20
		sta	track20_count
	.endif

		; Initialise le numéro de secteur courant
		sta	fdc_sector		; [4]

		; Initialise le numéro de piste courant
		lda	#$ff			; [2]
		sta	fdc_track		; [4]

		rts				; [6]
.endproc


; =====================================================================
;
; =====================================================================

;----------------------------------------------------------------------
; Entrée:
;	-XY: adresse nom du fichier
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
; XY: adresse du nom du fichier
; C : type OS (0: ftdos, 1: sedoric)
.if 0
	.proc mount
			lda	#$00
			rol
			sta	ostype

			; XY doit être en ram 48Ko
			; ptr doit aussi être en ram 48Ko
			stx	ptr
			sty	ptr+1

			; Initialise la banque
			; /!\ Efface dsk_name, donc cmnd_umount ne pourra pas afficher
			;     le nom du disque démonté.
			jsr	bank_init

		.if ::CAN_USE_KERNEL
			fopen	(ptr), O_RDONLY
			sta	fp
			stx	fp+1
			eor	fp+1
		.else
			lda	ptr
			ldy	ptr+1
			jsr	SetFilename
			jsr	FileOpen
		.endif

			; [ vérification de l'entête du fichier
			; ...
			; ]

			; À voir si le fichier doit rester ouvert on non
			; si oui, il faut que l'adresse XY soit persistante
			php
		.if ::CAN_USE_KERNEL
	;		fclose	(fp)
		.else
			; Pas de mise à jour de la taille du fichier
	;		lda	#$00
	;		jsr	FileClose
		.endif
			plp

			beq	error
			lda	#$00
			rts

		error:
			lda	#error_mount
			rts
	.endproc
.else
	.proc mount
			lda	#$00			; [2]
			rol				; [2]
			sta	ostype			; [4]

		.if ::CAN_USE_KERNEL
			; XY doit être en ram 48Ko
			; ptr doit aussi être en ram 48Ko
			stx	ptr			; [4]
			sty	ptr+1			; [4]
		.endif

			; Initialise la banque
			; /!\ Efface dsk_name, donc cmnd_umount ne pourra pas afficher
			;     le nom du disque démonté.
			jsr	bank_init		; [6]

		.if ::CAN_USE_KERNEL
			fopen	(ptr), O_RDONLY
			sta	fp			; [4]
			stx	fp+1			; [4]
			eor	fp+1			; [4]

			beq	error			; [2/3]

			fread buf_track, #08, 1, fp

		.else
			; lda	ptr			; [4]
			; ldy	ptr+1			; [4]

			jsr	open			; [6]
			cmp	#CH376_USB_INT_SUCCESS	; [2]
			bne	errOpen			; [2/3]
;			jsr	SetFilename		; [6]
;			jsr	FileOpen		; [6]
;			bcs	error			; [2/3]

			lda	#<$08			; [2]
			ldy	#>$08			; [2]
			jsr	SetByteRead		; [6]

			jsr	ReadUSBData		; [6]
			beq	errRead			; [2/3]

			tay				; [2]
			ldx	#$00			; [2]
		loop_byte:
			lda     CH376_DATA		; [4]
			sta	buf_track,x		; [5]
			inx				; [2]
			dey				; [2]
			bne	loop_byte		; [2/3]

			jsr	ByteRdGo		; [6]
			cmp	#CH376_USB_INT_SUCCESS	; [2]
			bne	errRdGo			; [2/3]
		.endif

			; [ vérification de l'entête du fichier
			ldy #$07			; [2]
		loop:
			lda	buf_track,y		; [4+]
			cmp	dsk_header,y		; [4+]
			bne	errFormat		; [2/3]
			dey				; [2]
			bpl	loop			; [2/3]
			; ]

			; À voir si le fichier doit resté ouvert on non
			; si oui, il faut que l'adresse XY soit persistante
		.if ::CAN_USE_KERNEL
			fclose	(fp)

		.else
			; Pas de mise à jour de la taille du fichier
			lda	#$00			; [2]
			jsr	FileClose		; [6]
		.endif

			ldx	#$14			; [2]
			ldy	#$01			; [2]
			jsr	read_track		; [6]
			bcs	errTrack		; [2/3]

			lda	#$ff			; [2]
			sta	fdc_sector		; [4]

			; Offset face 1 Ftdos / Sedoric
			lda	#$29			; [2]
			sta	dsk_side1_offset	; [4]

			lda	ostype			; [4]
			beq	end			; [2/3]

			; Sedoric, il faut lire la géométrie de la disquette (secteur 2)
		.if ::CACHE_DIR
			lda	sectors_tbl20+MAX_SECTORS+2	; [4]
			sta	get_byte+1		; [4]
			lda	sectors_tbl20+2		; [4]
			sta	get_byte+2		; [4]
			beq	errFormat		; [2/3]
		.else
			lda	sectors_tbl+MAX_SECTORS+2	; [4]
			sta	get_byte+1		; [4]
			lda	sectors_tbl+2		; [4]
			sta	get_byte+2		; [4]
			beq	errFormat		; [2/3]
		.endif

			ldx	#$06			; [2]
		get_byte:
			lda	buf_track,x		; [4+]
			sta	dsk_side1_offset	; [4]

		end:
			lda	#$00			; [2]
			rts				; [6]

		errOpen:
			; lda	#error_mount		; [2]
			lda	#error_open		; [2]
			rts				; [6]

		errRead:
			lda	#error_readusb		; [2]
			rts				; [6]

		errRdGo:
			lda	#error_rdgo		; [2]
			rts				; [6]

		errFormat:
			lda	#error_fmt		; [2]
			rts				; [6]

		errTrack:
			lda	#error_track		; [2]
			rts				; [6]
	.endproc
.endif

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
;	bank_init
;
;----------------------------------------------------------------------
.proc umount
		; Initialise la banque
		jsr	bank_init		; [6]

		; Efface le nom du fichier .dsk
		lda	#$00			; [2]
		sta	dskname			; [4]

		rts				; [6]
.endproc

;----------------------------------------------------------------------
; Entrée:
;	X: track (OS)
;	Y: sector
;
; Sortie:
;	-
;
; Variables:
;	Modifiées:
;		fpos
;		fp
;
;	Utilisées:
;		-
; Sous-routines:
;	seek_track
;	open
;	ByteLocate
;	FileClose
;	read
;	fopen
;	fseek
;	fclose
;
;----------------------------------------------------------------------
.proc read_track
		lda	#$00			; [2]
		sta	fpos-0			; [4]
		sta	fpos+3			; [4]

		jsr	seek_track		; [6]
		bcs	error			; [2/3]

		bne	cached			; [2/3]

	.if ::CAN_USE_KERNEL
		fopen	(ptr), O_RDONLY
		sta	fp			; [4]
		stx	fp+1			; [4]
		eor	fp+1			; [4]

		; beq	error

		fseek	fp, fpos, #SEEK_SET
		; TODO: vérifier si erreur fseek

	.else
		; lda	ptr			; [4]
		; ldy	ptr+1			; [4]
		jsr	open
;		jsr	SetFilename		; [6]
;		jsr	FileOpen		; [6]

		; bcs	error

		jsr	ByteLocate		; [6]
	.endif
		; On ne peut pas utiliser fread si on est dans une banque et que
		; le tampon de lecture est dans la banque
		jsr	read			; [6]
		php				; [3]

		; À voir si le fichier doit resté ouvert on non
		; si oui, il faut que l'adresse XY soit persistante
	.if ::CAN_USE_KERNEL
		fclose	(fp)

	.else
		; Pas de mise à jour de la taille du fichier
		lda	#$00			; [2]
		jsr	FileClose		; [6]
	.endif

		plp				; [4]
		; C=0: Ok
		; C=1: Erreur
		; A   : code erreur
		rts				; [6]

	cached:
		; C=0
		; Z=1
		; A=0
		lda	#$00			; [2]
		rts				; [6]

	error:
		; C=1
		; Z=0
		; A=erreur
		rts				; [6]
.endproc

;----------------------------------------------------------------------
; Entrée:
;	X: track (OS)
;	Y: sector
;
; Sortie:
;	X: Inchangé
;
; Variables:
;	Modifiées:
;		fdc_track
;		fdc_sector
;		fpos
;
;	Utilisées:
;		ostype
;		dsk_side1_offset
;
; Sous-routines:
;	-
;
; Cycles: 146
;----------------------------------------------------------------------
.proc seek_track
		; TODO: vérifier que track et sector sont dans les limites du fichier
		; Si hors limites => C=1, A=code erreur

		cpx	fdc_track		; [4]
		bne	calc_track		; [2/3]

		; N=1: piste en cache
		; Z=0: piste en cache
		; C=0: Ok
		clc				; [2]
		lda	#$ff			; [2]
		rts				; [6]

	calc_track:
		txa				; [2]

		; Sauvegarder la pistr et le secteur ici et non au début de calc_offset
		; à cause de Sedoric. (sinon il faut calculer aussi fdc_side)
		; A: piste dans le fichier
		; Y: secteur
		sta	fdc_track		; [4]
		sty	fdc_sector		; [4]

		ldx	ostype			; [4]
		beq	calc_offset		; [2/3]

	sedoric:
		cmp	#$80			; [2]
		bcc	calc_offset		; [2/3]

		; Face 1
		clc				; [2]
		and	#$7f			; [2]
		adc	dsk_side1_offset	; [4]


	calc_offset:
		; A: piste dans le fichier
		; Y: secteur
		; sta	fdc_track
		; sty	fdc_sector

		; [ TrackOffset
		ldy	#0			; [2]
		sta	fpos+1			; [4]
		sty	fpos+2			; [4]
		; sty	fpos+2
		; sty	fpos+3

		; x2
		asl	fpos+1			; [4]
		rol	fpos+2			; [4]

		; +1 -> x3
		pha				; [3]
		clc				; [2]
		adc	fpos+1			; [4]
		sta	fpos+1			; [4]
		bcc	ZZ0028			; [2/3]
		inc	fpos+2			; [6]

	ZZ0028:
		; x8 -> x24
		asl	fpos+1			; [6]
		rol	fpos+2			; [6]
		asl	fpos+1			; [6]
		rol	fpos+2			; [6]
		asl	fpos+1			; [6]
		rol	fpos+2			; [6]

		; +1 -> x25
		pla				; [4]
		clc				; [2]
		adc	fpos+1			; [4]
		sta	fpos+1			; [4]
		bcc	ZZ0029			; [2/3]
		inc	fpos+2			; [6]

	ZZ0029:
		; +256
		inc	fpos+1			; [6]
		bne	ZZ0030			; [2/3]
		inc	fpos+2			; [6]
	ZZ0030:
		;.A = fpos_L
		;.Y = fpos_H
		lda	fpos+1			; [4]
		ldy	fpos+2			; [4]
		; ]

		; N=0:
		; Z=1: Chargé
		; C=0: Ok
		lda	#$00			; [2]
		clc				; [2]
		rts				; [6]
.endproc

.if 0
	;----------------------------------------------------------------------
	;
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
	.proc ostrack
		lda	ostype
		bne	sedoric

		; [ ftdos
		txa
		bcc	check_cache

		; Face 1
		clc
		adc	dsk_side1_offset
		bne	check_cache

		; Normalement on ne peut pas arriver ici
		; beq	error

	sedoric:
		txa
		bpl	check_cache

		; Face 1
		clc
		and	#$7f
		adc	dsk_side1_offset

	check_cache:
		; A: piste dans le fichier
		; Y: secteur
		sty	fdc_sector

		cmp	fdc_track
		bne	calc_offset

		; N=1: piste en cache
		; Z=0: piste en cache
		; C=0: Ok
		clc
		lda	#$ff
		rts

	calc_offset:
		sta	fdc_track


			;----------------------------------------------------------------------
			; Si A contient le numéro de piste virtuel (OS et non FDC)
			;----------------------------------------------------------------------

			; TODO: vérifier que track et sector sont dans les limites du fichier
			; Si hors limites => C=1, A=code erreur

			cpx	cache_track
			bne	calc_track_side

			; N=1: piste en cache
			; Z=0: piste en cache
			; C=0: Ok
			clc
			lda	#$ff
			rts

		calc_track_side:
			stx	cache_track

			; Face 0 par défaut
			lda	#$00
			sta	fdc_side
			stx	fdc_track

			lda	ostype
			bne	sedoric

			; [ ftdos, ajuste fdc_track et fdc_side dans le cas où on veut utiliser
			;   step, stepIn, stepOut
			txa
			cmp	dsk_side1_offset
			bcc	calc_offset

			sbc	dsk_side1_offset
			sta	fdc_track

			; Remet la bonne valeur dans A pour le calcul de l'offset
			txa

			; Met à jour fdc_side
			inc	fdc_side

			bne	calc_offset

			; Normalement on ne peut pas arriver ici
			; beq	error

		sedoric:
			txa
			bpl	calc_offset

			; Face 1
			clc
			and	#$7f

			: ajuste fdc_track et fdc_side dans le cas ou on veut utiliser
			;   step, stepIn, stepOut
			sta	fdc_track

			adc	dsk_side1_offset

			; Met à jour fdc_side
			inc	fdc_side

		calc_offset:
			; sta	fdc_track


			;----------------------------------------------------------------------
			; Si A contient le numéro de piste et C le numéro de tête
			;----------------------------------------------------------------------
			: ajuste fdc_track et fdc_side dans le cas ou on veut utiliser
			;   step, stepIn, stepOut
			stx	fdc_track

			lda	#$00
			sta	fdc_side

			lda	ostype
			bne	sedoric

			; [ ftdos
			txa
			bcc	check_cache

			; Face 1
			clc
			adc	dsk_side1_offset

			inc	fdc_side
			bne	check_cache

			; Normalement on ne peut pas arriver ici
			; beq	error

		sedoric:
			txa
			bpl	check_cache

			; Face 1
			clc
			and	#$7f
			adc	dsk_side1_offset

			inc	fdc_side

		check_cache:
			; A: piste dans le fichier
			; Y: secteur
			sty	fdc_sector

			cmp	cache_track
			bne	calc_offset

			; N=1: piste en cache
			; Z=0: piste en cache
			; C=0: Ok
			clc
			lda	#$ff
			rts

		calc_offset:
			sta	cache_track
	.endproc
.endif

;----------------------------------------------------------------------
; Charge la totalité de la piste (6400 octets) dans le buffer
; Pour charger ub secteur il faudra ensuite parcourir la piste à la
; recherche des marqueurs.
; 153 371 cycles (sans interruptions / 172 800 avec)
;
;----------------------------------------------------------------------
;
; Entrée:
;	-
;
; Sortie:
;	-
;
; Variables:
;	Modifiées:
;		sectors_tbl
;		buf_track
;		byf_track20
;
;	Utilisées:
;		fdc_track
;
; Sous-routines:
;	find_sectors
;	SetByteRead
;	NyteRdGo
;	ReadUSBData
;
;----------------------------------------------------------------------
.if WHOLE_TRACK
	.proc read
		; 106 844 (sans interruptions, 120 760 avec) (sans le temps d'exécution de find_sectors)
			lda	#<TRACK_SIZE		; [2]
			ldy	#>TRACK_SIZE		; [2]
			jsr	SetByteRead		; [6]
			bcs	end_error		; [2/3]

			; Initialise la table des secteurs (poids forts uniquement)
			lda	#$00			; [2]
			ldy	#MAX_SECTORS		; [2]

		loop_init:
			sta	sectors_tbl+MAX_SECTORS,y	; [5]
			dey				; [2]
			bpl	loop_init		; [2/3]

			; Initialise l'adresse du tampon
			; /!\ NE FONCTIONNE PAS SI ON EST EN ROM
		.if ::CACHE_DIR
			lda	fdc_track		; [4]
			cmp	#$14			; [2]
			beq	directory		; [2/3]
		.endif

			lda	#<buf_track		; [2]
			sta	ld+1			; [4]
			lda	#>buf_track		; [2]
			sta	ld+2			; [4]

			bne	read_block		; [2/3]

		.if ::CACHE_DIR
		directory:
			lda	#<buf_track20		; [2]
			sta	ld+1			; [4]
			lda	#>buf_track20		; [2]
			sta	ld+2			; [4]

			bne	read_block		; [2/3]
		.endif

		loop:
			jsr	ByteRdGo		; [6]
			cmp	#CH376_USB_INT_SUCCESS	; [2]
			beq	end			; [2/3]

		read_block:
			jsr	ReadUSBData		; [6]
			beq	end			; [2/3]

			tay				; [2]
			ldx	#$00			; [2]

		loop_byte:
		        lda     CH376_DATA		; [4]

		ld:
			sta	buf_track,x		; [5]
			inx				; [2]
			dey				; [2]
			bne	loop_byte		; [2/3]

			; Ajuste l'adresse du tampon
			; /!\ NE FONCTIONNE PAS SI ON EST EN ROM
			clc				; [2]
			txa				; [2]
			adc	ld+1			; [4]
			sta	ld+1			; [4]
			bcc	loop			; [2/3]
			inc	ld+2			; [6]
			bne	loop			; [2/3]

		end:
			jsr	find_sectors		; [6]
			clc				; [2]
			rts				; [6]

		error:
		; [ /!\ TEMPORAIRE DEBUG
		jmp	reboot
		; ]
			lda	#error_read		; [2]
			sec				; [2]

		end_error:
		; [ /!\ TEMPORAIRE DEBUG
		jmp	reboot
		; ]
			rts				; [6]
	.endproc

	;----------------------------------------------------------------------
	;
	; Entrée:
	;	-
	;
	; Sortie:
	;	-
	;
	; Variables:
	;	Modifiées:
	;		zptr
	;	Utilisées:
	;		fdc_track
	;		buf_track
	;		buf_track20
	;		sectors_tbl
	;		sectors_tbl20
	; Sous-routines:
	;	-
	;
	;----------------------------------------------------------------------
	.proc find_sectors
		; 46 527 +28 cycles (sans interruptions 52 041 +28 avec)
			savezp				; [14]

		.if ::CACHE_DIR
			lda	fdc_track		; [4]
			cmp	#$14			; [2]
			bne	normal			; [2/3]

			; -2 pour compenser le ldy #$02
			lda	#<(buf_track20-2)	; [2]
			sta	zptr			; [3]
			lda	#>(buf_track20-2)	; [2]
			sta	zptr+1			; [3]
			bne	loop1			; [2/3]

		normal:
		.endif
			; -2 pour compenser le ldy #$02
			lda	#(<buf_track-2)		; [2]
			sta	zptr			; [3]
			lda	#>(buf_track-2)		; [2]
			sta	zptr+1			; [3]

		loop1:
			; GAP1 / GAP4 / GAP2 / GAP5

			ldy	#$00			; [2]
			ldy	#$02			; [2]
		loop2:
			; (zptr)>=max?
		.if ::CACHE_DIR
			lda	fdc_track
			cmp	#$14
			bne	normal2

			lda	zptr+1			; [3]
			cmp	#>(buf_track20+TRACK_SIZE)	; [2]
			bcc	ok			; [2/3]

			lda	zptr			; [3]
			cmp	#<(buf_track20+TRACK_SIZE)	; [2]
			bcs	end			; [2/3]
			bcc	ok
		normal2:
		.endif
			lda	zptr+1			; [3]
			cmp	#>(buf_track+TRACK_SIZE)	; [2]
			bcc	ok			; [2/3]

			lda	zptr			; [3]
			cmp	#<(buf_track+TRACK_SIZE)	; [2]
			bcs	end			; [2/3]

		ok:
			lda	(zptr),y		; [5+]
			inc	zptr			; [5]
			bne	skip			; [2/3]
			inc	zptr+1			; [5]
		skip:
			cmp	#$fe			; [2]
			bne	loop2			; [2/3]


		.if ::NEED_SECTOR_INFOS
			; Track
			; ldy	#$00
			lda	(zptr),y		; [5+]

			; Head
			iny				; [2]
			lda	(zptr),y		; [5+]

			; Sector
			iny				; [2]
			lda	(zptr),y		; [5+]
			tax				; [2]

			; Size
			iny				; [2]
			lda	(zptr),y		; [5+]

			; CRC
			iny				; [2]
			lda	(zptr),y		; [5+]

			; CRC+1
			iny				; [2]
			lda	(zptr),y		; [5+]

			iny				; [2]
		.else
			; Track
			iny				; [2]
			; Head
			iny				; [2]
			; Sector
			lda	(zptr),y		; [5+]
			tax				; [2]

			tya				; [2]
			; Ici C=1 à cause du cmp #$fe
			adc	#($04-1)		; [2]
			tay				; [2]
		.endif
			; GAP 3
			; On suppose que le format de la piste est correct et qu'on va
			; bien trouver un $FB, sinon il faut vérifier que zptr ne
			; déborde pas
		loop3:
			lda	(zptr),y		; [5+]
			iny				; [2]
			bne	skip3			; [2/3]
			inc	zptr+1			; [5]
		skip3:
			cmp	#$FB			; [2]
			bne	loop3			; [2/3]

			; Data

			; Ajuste zptr
			tya				; [2]
			clc				; [2]
			adc	zptr			; [3]
			sta	zptr			; [3]
			bcc	skip4			; [2/3]
			inc	zptr+1			; [5]
		skip4:

		.if ::CACHE_DIR
			; Utile uniquement si on veut avoir un autre buffer qui ne
			; contient que les données
			; Ici on se contente de noter l'offset de début du secteur
			; et on passe à la suite
			ldy	fdc_track		; [4]
			cpy	#$14			; [2]
			beq	directory		; [2/3]
		.endif

			sta	sectors_tbl+MAX_SECTORS,x	; [5]
			lda	zptr+1			; [3]
			sta	sectors_tbl,x		; [5]

			; Ne tient pas compte de Size,  (lecture de 256 octets)
			inc	zptr+1			; [5]
			; On saute le CRC
			; (Fait par le ldy #$02 au début de loop1)
			;ldy	#$02			; [2]
			;bne	loop1+2			; [2/3]
			bne	loop1			; [2/3]

		.if ::CACHE_DIR
			; beq normalement inutile
			beq	end			; [2/3]

		directory:
			sta	sectors_tbl20+MAX_SECTORS,x	; [5]
			lda	zptr+1			; [3]
			sta	sectors_tbl20,x		; [5]

			; Ne tient pas compte de Size,  (lecture de 256 octets)
			inc	zptr+1			; [5]
			; On saute le CRC
			; (Fait par le ldy #$02 au début de loop1)
			;ldy	#$02			; [2]
			;bne	loop1+2			; [2/3]
			bne	loop1			; [2/3]
		.endif
		end:
			restorezp			; [14]
			rts				; [6]
	.endproc
.else

;----------------------------------------------------------------------
; Charge uniquement les datas secteur dans le buffer
; 342 482 cycles (sans interruptions)
;----------------------------------------------------------------------
	.proc read
			; lda	#<buf_track
			; sta	st+1
			lda	#>buf_track
			sta	st+2

			; Initialise la table des secteurs
			lda	#$00
			ldy	#MAX_SECTORS

		loop_init:
			sta	sectors_tbl,y
			dey
			bpl	loop_init

			lda	#<TRACK_SIZE
			ldy	#>TRACK_SIZE
			jsr	SetByteRead
			bcs	end_error

			jsr	ReadUSBData
			beq	end_error

			sta	PTR_MAX

			clv

		loop1:
		; GAP1 / GAP4 / GAP2 / GAP5

		loop2:
			jsr	GetByte
		; Si fin du fichier, on force la sortie
			bvc	ZZ0022

			lda	#$FE

		ZZ0022:
			cmp	#$FE
			bne	loop2
			bvs	ZZ0023

		; ID Field
		; TODO: vérifier que la piste et la tête trouvées sont les bonnes?
		; Pour le moment, on ne conserve que le n° de secteur sur la pile
			jsr	GetByte
			; sta Track

			jsr	GetByte
			; sta Head

			jsr	GetByte
			; sta Sector
			pha

		; TODO: Vérifier la taille du secteur?
			jsr	GetByte
			; sta Size

			jsr	GetByte
			; sta CRC

			jsr	GetByte
			; sta CRC+1


		; GAP 3
		loop3:
			jsr	GetByte
			cmp	#$FB
			bne	loop3

		; Data (lecture de 256 octets)
		; Ne tient pas compte de Size
		; A voir pour sauter plus rapidement les 256 octets
		; du secteur si ce n'est pas le bon
		;
		; /!\ Modifier la boucle pour tester b4 de jsm_Data
		;       jsm_Command == $88 => ReadSector
		;       jsm_Command == $90 => ReadMulti, dans ce cas il faut faire
		;                             un sta (Z04),y
		;     ou remplacer la boucle par un jsr (6502_IRQ)
		; Met le n° de secteur trouvé dans ACC
			pla
			; pha
			; jsr	fdc_irq

			; Sauvegarde l'offset du secteur dans buf_track
			tax
			lda	st+2
			sta	sectors_tbl,x

			ldy	#$00
		loop4:
			jsr	GetByte
		st:
			sta	buf_track,y
			iny
			bne	loop4
			; Ajuste l'adresse du buffer
			inc	st+2

		; Data CRC
		; Pour le moment, on ne conserve pas le CRC
		        jsr	GetByte
		        ; sta CRC
		        jsr	GetByte
		        ; sta CRC+1

		; Secteur trouve, on sort
		; lda fdc_sector
		; cmp Sector
			; pla
			; cmp	fdc_sector
			; bne	ZZ0023

		; SEV
			; bit	sev

		ZZ0023:
			bvc	loop1

			; On a lu toute le piste
			; On vérifie si on a trouvé le secteur demandé
			ldx	fdc_sector
			lda	sectors_tbl,x
			beq	not_found

			clc
			rts

		not_found:
			clc
			rts

		end_error:
			sec
			rts
	.endproc

	;----------------------------------------------------------------------
	; GetByte:
	; Lit le prochain caractere du buffer
	;
	; Entrée:
	;
	; Sortie:
	;
	; Variables:
	;       Modifiées:
	;               - PTR_MAX
	;		- yio
	;       Utilisées:
	;               -
	; Sous-routines:
	;	- ByteRdGo
	;       - ReadUSBData
	; Entree:
	;	-
	; Sortie:
	;	ACC: Caractere lu
	;	X : Modifie (0 si appel a ByteRgGo)
	;	Y : Inchange
	;	V : 1 Fin du fichier atteinte
	;	Z,N: Fonction du caractere lu
	;----------------------------------------------------------------------
	.proc GetByte
		; Sauvegarde Y (modifié par ByteRdGo)
		; A voir pour sauvegarder aussi X (ou modifier WaitResponse pour le faire)
		        sty     yio
		        lda     PTR_MAX
		        bne     GetByte2

		        jsr     ByteRdGo
		        cmp     #CH376_USB_INT_SUCCESS
		        beq     GetByteErr

		        jsr     ReadUSBData
			beq     GetByteErr

			sta	PTR_MAX

		GetByte2:
		        lda     CH376_DATA
		        php
		        dec     PTR_MAX
		        ldy     yio
		        plp
		        rts

		GetByteErr:
		        ; SEV
		        bit     *-1
		        ldy     yio
		        rts
	.endproc

.endif

;----------------------------------------------------------------------
; 75 (-2 si yio en page 0)
; -2 octets si utilisation de dskname au lieu de (zptr)
; +11 octets si inline de ZZ0006 à la place du jsr ZZ0006 (-2 si yio en page 0)
; Entrée:
;	-AY: Adresse de la chaîne
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
;	-FileOpen
;
;----------------------------------------------------------------------
.proc open
;		sta	zptr			; [3]
;		sty	zptr+1			; [3]

		lda	#CH376_SET_FILENAME	; [2]
		sta	CH376_COMMAND		; [4]

		ldy	#$00			; [2]
;		lda	(zptr),y		; [5+]
		lda	dskname,y		; [4+]
		cmp	#'/'			; [2]
		bne	ZZ1005			; [2/3]

		sta	CH376_DATA		; [4]
		sty	CH376_DATA		; [4]
		jsr	FileOpen		; [6]

		ldy	#$01			; [2]
	ZZ1003:
		lda	#CH376_SET_FILENAME	; [2]
		sta	CH376_COMMAND		; [4]

	ZZ1005:
		;lda	(zptr),Y		; [5+]
		lda	dskname,y		; [4+]
		beq	ZZ0006			; [2/3]
		cmp	#'/'			; [2]
		beq	opendir			; [2/3]

		; Conversion minuscules/MAJUSCULES
		cmp	#'a'			; [2]
		bcc	ZZ0007			; [2/3]
		cmp	#'z'+1			; [2]
		bcs	ZZ0007			; [2/3]
		sbc	#'a'-'A'-1		; [2]

	ZZ0007:
		sta	CH376_DATA		; [4]
		iny				; [2]
		bne	ZZ1005			; [2/3]

	opendir:
;		lda	#$00			; [2]
;		sta	CH376_DATA		; [4]
;		sty	yio
;		jsr	FileOpen		; [6]
;		ldy	yio
		jsr	ZZ0006			; [6]
		cmp	#CH376_ERR_OPEN_DIR	; [2]
		bne	error			; [2/3]

		iny				; [2]

		; On teste la fin de chaîne dans le cas
		; où '/' est le dernier caracère de la chaine
		; (Nomalement impossible ici, donc le bne ZZ1003
		;  seul devrait suffire)
		; lda	(zptr),y		; [5+]
		lda	dskname,y		; [4+]
		bne	ZZ1003			; [2/3]
		beq	end			; [2/3]


	ZZ0006:
		lda	#$00			; [2]
		sta	CH376_DATA		; [4]
		sty	yio
		jsr	FileOpen		; [6]
		ldy	yio
	;        ; .AY = Code erreur, poids faible dans .A
		                                                ; .Y = .A;
	;	tay
	;	lda	#$00
		rts				; [6]

	end:
		clc
		rts

	error:
		sec
		rts
.endproc


;----------------------------------------------------------------------
;
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
;----------------------------------------------------------------------
.proc reboot
		ldy	#$0b
	loop:
		lda	_reboot,y
		sta	$bfe0,y
		dey
		bpl	loop
		jmp	$bfe0

	_reboot:
		sei
		lda	#$07
		sta	VIA2::PRA
		sta	VIA2::DDRA
		jmp	($fffc)
.endproc
