		BITS	16
		ORG	0x100				; DOS loads us here
Start:		; backup old KB interrupt
		XOR	AX, AX
		MOV	ES, AX				; ES = 0
		MOV	AX, [ES:0x24]
		MOV	[OldKBHandler], AX
		MOV	AX, [ES:0x26]
		MOV	[OldKBHandler + 2], AX
;		; install new KB interrupt
		MOV	WORD [ES:0x24], KBHandler
		MOV	WORD [ES:0x26], CS
		; set video mode 0x13
		MOV	AX, 0x13
		INT	0x10
		; make ES point to the VGA memory
		MOV	AX, 0xA000
		MOV	ES, AX
		CALL	DrawBoard
		CALL	DrawPlayer
.gameLoop:	CALL	WaitFrame
		CALL	UpdatePlayer
		; check for exit
		CMP	BYTE [Quit], 1
		JNZ	.gameLoop
		; restore text mode 0x03
		MOV	AX, 0x03
		INT	0x10
		; restore old KB interrupt
		XOR	AX, AX
		MOV	ES, AX
		MOV	AX, [OldKBHandler]
		MOV	[ES:0x24], AX
		MOV	AX, [OldKBHandler + 2]
		MOV	[ES:0x26], AX
		; exit
		MOV	AX, 0x4C00			; return code 0
		INT	0x21

KBHandler:	PUSH	AX
		IN	AL, 0x60			; get key event
.testEsc:	CMP	AL, 0x01			; ESC pressed?
		JNE	.testUp
		MOV	[Quit], AL
.testUp:	CMP	AL, 72
		JNE	.testLeft
		MOV	BYTE [MoveDir], 1
.testLeft:	CMP	AL, 75
		JNE	.testRight
		MOV	BYTE [MoveDir], 2
.testRight	CMP	AL, 77
		JNE	.testDown
		MOV	BYTE [MoveDir], 3
.testDown	CMP	AL, 80
		JNE	.done
		MOV	BYTE [MoveDir], 4
.done:		MOV	AL, 0x20			; ACK
		OUT	0x20, AL			; send ACK
		POP	AX
		IRET

WaitFrame:	PUSH	DX
		MOV	DX, 0x03DA
.waitRetrace:	IN	AL, DX
		TEST	AL, 0x08			; are we in retrace?
		JNZ	.waitRetrace
.endRefresh:	IN	AL, DX
		TEST	AL, 0x08			; are we in refresh?
		JZ	.endRefresh
		POP DX
		RET


DrawBoard:	PUSHA
		MOV	BX, Board
		MOV	SI, 0				; index into board
		MOV	CH, 0				; row
		MOV	WORD [RowBase], 0
.drawRow:	MOV	WORD [TileBase], 0
		MOV	CL, 0				; col
.rowLoop:	MOV	AL, [BX + SI]			; get tile
		CMP	AL, 0				; is tile 0?
		JZ	.nextTile
		DEC	AL
		CALL	DrawTile
.nextTile:	ADD	WORD [TileBase], 16
		INC	SI
		INC	CL
		CMP	CL, 8
		JNZ	.rowLoop
		ADD	WORD [RowBase], 5120
		INC	CH
		CMP	CH, 9
		JNZ	.drawRow
		POPA
		RET


; AL = Tile #
DrawTile:	PUSH	SI
		PUSH	DI
		MOV	AH, 0				; clear out high bits
		SHL	AX, 8				; get tile index
		ADD	AX, Tiles			; get pointer
		MOV	SI, AX
		MOV	DI, [RowBase]
		ADD	DI, [TileBase]
		CALL	BlitTile
		POP	DI
		POP	SI
		RET


EraseTile:	PUSH	DI
		PUSH	CX
		PUSH	DX
		MOV	DI, [RowBase]
		ADD	DI, [TileBase]
		XOR	AX, AX				; clear AX
		CLD					; increment
		MOV	CH, 0				; clear hi-counter
		MOV	DL, 0x10			; 16 rows
.row:		MOV	CL, 0x08			; 8 word writes
		REP	STOSW				; write 0000
		DEC	DL				; next row?
		JZ	.done
		ADD	DI, 304				; next row
		JMP	.row
.done:		POP	DX
		POP	CX
		POP	DI
		RET


MoveTable:	DW	MoveUp, MoveLeft, MoveRight, MoveDown
UpdatePlayer:	MOV	AL, [MoveDir]
		AND	AL, AL				; are we moving?
		JE	.done
		; get index into move table into SI
		XOR	AH, AH				; clear hi bit
		MOV	[MoveDir], AH			; clear motion
		MOV	SI, AX
		DEC	SI
		SHL	SI, 1				; *2 for word addrs
		CALL	ErasePlayer
		MOV	AX, [MoveTable + SI]		; get move function
		CALL	AX
		CALL	UpdateUnder
		JMP	DrawPlayer
.done:		RET


MoveRight:	ADD	WORD [PlayerTileBase], 16	; move player 16px right
		INC	BYTE [PlayerCol]
		RET

MoveDown:	ADD	WORD [PlayerRowBase], 16 * 320	; move player 16px down
		INC	BYTE [PlayerRow]
		RET

MoveLeft:	SUB	WORD [PlayerTileBase], 16	; move player 16px left
		DEC	BYTE [PlayerCol]
		RET

MoveUp:		SUB	WORD [PlayerRowBase], 16 * 320	; move player 16px up
		DEC	BYTE [PlayerRow]
		RET


ErasePlayer:	MOV	AX, [PlayerRowBase]
		MOV	[RowBase], AX
		MOV	AX, [PlayerTileBase]
		MOV	[TileBase], AX
		MOV	AL, [UnderTile]
		AND	AL, AL
		JZ	EraseTile
		DEC	AL
		JMP	DrawTile


DrawPlayer:	PUSH	SI
		PUSH	DI
		MOV	SI, PlayerTile
		MOV	DI, [PlayerRowBase]
		ADD	DI, [PlayerTileBase]
		CALL	BlitTile
		POP	DI
		POP	SI
		RET


UpdateUnder:	PUSH	SI
		XOR	AH, AH
		MOV	AL, [PlayerRow]
		SHL	AL, 3				; row * 8 bc 8 cols/row
		ADD	AL, BYTE [PlayerCol]
		MOV	SI, AX
		MOV	AL, [Board + SI]
		MOV	[UnderTile], AL
		POP SI
		RET


; SI = Tile*, DI = Dest*
BlitTile:	PUSH	CX
		PUSH	DX
		CLD					; increment
		MOV	CH, 0				; clear hi-counter
		MOV	DL, 0x10			; 16 rows
.row:		MOV	CL, 0x08			; 8 word copies
		REP	MOVSW
		DEC	DL
		JZ	.done
		ADD	DI, 304				; move to next row
		JMP	.row
.done:		POP	DX
		POP	CX
		RET

RowBase:	DW	0
TileBase:	DW	0

START_ROW	EQU	2
START_COL	EQU	2

PlayerRow:	DB	START_ROW
PlayerCol:	DB	START_COL

MoveDir:	DB	0

PlayerRowBase:	DW	START_ROW * 320 * 16
PlayerTileBase:	DW	START_COL * 16
UnderTile:	DB	0

Board:		INCBIN	"board.dat"

PlayerTile:	INCBIN	"player.dat"

Tiles:		INCBIN	"wall.dat"

OldKBHandler:	DD	0

Quit:		DB	0
