/* $Id: nasm-bison.y,v 1.25 2001/08/19 05:44:53 peter Exp $
 * Main bison parser
 *
 *  Copyright (C) 2001  Peter Johnson, Michael Urman
 *
 *  This file is part of YASM.
 *
 *  YASM is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  YASM is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */
%{
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <math.h>
#include <stdlib.h>
#include "util.h"
#include "symrec.h"
#include "globals.h"
#include "bytecode.h"
#include "errwarn.h"
#include "expr.h"

#define YYDEBUG 1

void init_table(void);
extern int nasm_parser_lex(void);
extern void yyerror(char *);
static unsigned long ConvertCharConstToInt(char *);
void nasm_parser_error(char *);

%}

%union {
    unsigned long int_val;
    char *str_val;
    double double_val;
    symrec *sym;
    struct {
	char *name;
	int line;
    } syminfo;
    unsigned char groupdata[4];
    effaddr ea_val;
    expr *exp;
    immval im_val;
    targetval tgt_val;
    datavalhead datahead;
    dataval *data;
    bytecode bc;
}

%token <int_val> INTNUM
%token <double_val> FLTNUM
%token <str_val> DIRECTIVE_NAME DIRECTIVE_VAL STRING
%token <int_val> BYTE WORD DWORD QWORD TWORD DQWORD
%token <int_val> DECLARE_DATA
%token <int_val> RESERVE_SPACE
%token INCBIN EQU TIMES
%token SEG WRT NEAR SHORT FAR NOSPLIT ORG
%token TO
%token O16 O32 A16 A32 LOCK REPNZ REP REPZ
%token <int_val> OPERSIZE ADDRSIZE
%token <int_val> CR4 CRREG_NOTCR4 DRREG TRREG ST0 FPUREG_NOTST0 MMXREG XMMREG
%token <int_val> REG_EAX REG_ECX REG_EDX REG_EBX REG_ESP REG_EBP REG_ESI REG_EDI
%token <int_val> REG_AX REG_CX REG_DX REG_BX REG_SP REG_BP REG_SI REG_DI
%token <int_val> REG_AL REG_CL REG_DL REG_BL REG_AH REG_CH REG_DH REG_BH
%token <int_val> REG_ES REG_CS REG_SS REG_DS REG_FS REG_GS
%token LEFT_OP RIGHT_OP SIGNDIV SIGNMOD
%token <syminfo> ID LOCAL_ID SPECIAL_ID

/* instruction tokens (dynamically generated) */
/* @TOKENS@ */

/* @TYPES@ */

%type <bc> line exp instr instrbase label

%type <int_val> fpureg reg32 reg16 reg8 segreg
%type <ea_val> mem memaddr memexp memfar
%type <ea_val> mem8x mem16x mem32x mem64x mem80x mem128x
%type <ea_val> mem8 mem16 mem32 mem64 mem80 mem128 mem1632
%type <ea_val> rm8x rm16x rm32x /*rm64x rm128x*/
%type <ea_val> rm8 rm16 rm32 rm64 rm128
%type <im_val> imm imm8x imm16x imm32x imm8 imm16 imm32
%type <exp> expr expr_no_string
%type <syminfo> explabel
%type <sym> label_id
%type <tgt_val> target
%type <data> dataval
%type <datahead> datavals

%left '|'
%left '^'
%left '&'
%left LEFT_OP RIGHT_OP
%left '-' '+'
%left '*' '/' SIGNDIV '%' SIGNMOD
%nonassoc UNARYOP

%%
input: /* empty */
    | input line { OutputError(); OutputWarning(); line_number++; }
;

line: '\n'	{ $$.type = BC_EMPTY; }
    | exp '\n' { DebugPrintBC(&$1); $$ = $1; }
    | directive '\n' { $$.type = BC_EMPTY; }
    | error '\n' {
	Error(ERR_INVALID_LINE, (char *)NULL);
	$$.type = BC_EMPTY;
	yyerrok;
    }
;

exp: instr
    | DECLARE_DATA datavals	{ BuildBC_Data(&$$, &$2, $1); }
    | RESERVE_SPACE expr	{ BuildBC_Reserve(&$$, $2, $1); }
    | label exp			{ $$ = $2; }
    | label			{ $$.type = BC_EMPTY; }
;

datavals: dataval		{
	STAILQ_INIT(&$$);
	STAILQ_INSERT_TAIL(&$$, $1, link);
    }
    | datavals ',' dataval	{
	STAILQ_INSERT_TAIL(&$1, $3, link);
	$$ = $1;
    }
;

dataval: expr_no_string		{ $$ = dataval_new_expr($1); }
    | FLTNUM			{ $$ = dataval_new_float($1); }
    | STRING			{ $$ = dataval_new_string($1); }
    | error			{
	Error(ERR_EXPR_SYNTAX, (char *)NULL);
	$$ = (dataval *)NULL;
    }
;

label: label_id { $1->value = 0; } /* TODO: calculate offset */
    | label_id ':' { $1->value = 0; } /* TODO: calculate offset */
;

label_id: ID { $$ = locallabel_base = sym_def_get ($1.name, SYM_LABEL); }
    | SPECIAL_ID { $$ = sym_def_get ($1.name, SYM_LABEL); }
    | LOCAL_ID { $$ = sym_def_get ($1.name, SYM_LABEL); }
;

/* directives */
directive: '[' DIRECTIVE_NAME DIRECTIVE_VAL ']' {
	printf("Directive: Name='%s' Value='%s'\n", $2, $3);
    }
    | '[' DIRECTIVE_NAME DIRECTIVE_VAL error {
	Error(ERR_MISSING, "%c", ']');
    }
    | '[' DIRECTIVE_NAME error {
	Error(ERR_MISSING_ARG, (char *)NULL, $2);
    }
;

/* register groupings */
fpureg: ST0
    | FPUREG_NOTST0
;

reg32: REG_EAX
    | REG_ECX
    | REG_EDX
    | REG_EBX
    | REG_ESP
    | REG_EBP
    | REG_ESI
    | REG_EDI
    | DWORD reg32
;

reg16: REG_AX
    | REG_CX
    | REG_DX
    | REG_BX
    | REG_SP
    | REG_BP
    | REG_SI
    | REG_DI
    | WORD reg16
;

reg8: REG_AL
    | REG_CL
    | REG_DL
    | REG_BL
    | REG_AH
    | REG_CH
    | REG_DH
    | REG_BH
    | BYTE reg8
;

segreg:  REG_ES
    | REG_SS
    | REG_DS
    | REG_FS
    | REG_GS
    | REG_CS
    | WORD segreg
;

/* memory addresses */
memexp: expr		{ expr_simplify ($1); ConvertExprToEA (&$$, $1); }
;

memaddr: memexp			{ $$ = $1; $$.segment = 0; }
    | REG_CS ':' memaddr	{ $$ = $3; SetEASegment(&$$, 0x2E); }
    | REG_SS ':' memaddr	{ $$ = $3; SetEASegment(&$$, 0x36); }
    | REG_DS ':' memaddr	{ $$ = $3; SetEASegment(&$$, 0x3E); }
    | REG_ES ':' memaddr	{ $$ = $3; SetEASegment(&$$, 0x26); }
    | REG_FS ':' memaddr	{ $$ = $3; SetEASegment(&$$, 0x64); }
    | REG_GS ':' memaddr	{ $$ = $3; SetEASegment(&$$, 0x65); }
    | BYTE memaddr		{ $$ = $2; SetEALen(&$$, 1); }
    | WORD memaddr		{ $$ = $2; SetEALen(&$$, 2); }
    | DWORD memaddr		{ $$ = $2; SetEALen(&$$, 4); }
;

mem: '[' memaddr ']' { $$ = $2; }
;

/* explicit memory */
mem8x: BYTE mem		{ $$ = $2; }
;
mem16x: WORD mem	{ $$ = $2; }
;
mem32x: DWORD mem	{ $$ = $2; }
;
mem64x: QWORD mem	{ $$ = $2; }
;
mem80x: TWORD mem	{ $$ = $2; }
;
mem128x: DQWORD mem	{ $$ = $2; }
;

/* FAR memory, for jmp and call */
memfar: FAR mem		{ $$ = $2; }
;

/* implicit memory */
mem8: mem
    | mem8x
;
mem16: mem
    | mem16x
;
mem32: mem
    | mem32x
;
mem64: mem
    | mem64x
;
mem80: mem
    | mem80x
;
mem128: mem
    | mem128x
;

/* both 16 and 32 bit memory */
mem1632: mem
    | mem16x
    | mem32x
;

/* explicit register or memory */
rm8x: reg8	{ (void)ConvertRegToEA(&$$, $1); }
    | mem8x
;
rm16x: reg16	{ (void)ConvertRegToEA(&$$, $1); }
    | mem16x
;
rm32x: reg32	{ (void)ConvertRegToEA(&$$, $1); }
    | mem32x
;
/* not needed:
rm64x: MMXREG	{ (void)ConvertRegToEA(&$$, $1); }
    | mem64x
;
rm128x: XMMREG	{ (void)ConvertRegToEA(&$$, $1); }
    | mem128x
;
*/

/* implicit register or memory */
rm8: reg8	{ (void)ConvertRegToEA(&$$, $1); }
    | mem8
;
rm16: reg16	{ (void)ConvertRegToEA(&$$, $1); }
    | mem16
;
rm32: reg32	{ (void)ConvertRegToEA(&$$, $1); }
    | mem32
;
rm64: MMXREG	{ (void)ConvertRegToEA(&$$, $1); }
    | mem64
;
rm128: XMMREG	{ (void)ConvertRegToEA(&$$, $1); }
    | mem128
;

/* immediate values */
imm: expr		{ expr_simplify ($1); ConvertExprToImm (&$$, $1); }
;

/* explicit immediates */
imm8x: BYTE imm	{ $$ = $2; }
;
imm16x: WORD imm	{ $$ = $2; }
;
imm32x: DWORD imm	{ $$ = $2; }
;

/* implicit immediates */
imm8: imm
    | imm8x
;
imm16: imm
    | imm16x
;
imm32: imm
    | imm32x
;

/* jump targets */
target: expr		{ $$.val = $1; $$.op_sel = JR_NONE; }
    | SHORT target	{ $$ = $2; SetOpcodeSel(&$$.op_sel, JR_SHORT_FORCED); }
    | NEAR target	{ $$ = $2; SetOpcodeSel(&$$.op_sel, JR_NEAR_FORCED); }
;

/* expression trees */
expr_no_string: INTNUM	{ $$ = expr_new_ident (EXPR_NUM, ExprNum($1)); }
    | explabel		{ $$ = expr_new_ident (EXPR_SYM, ExprSym(sym_use_get ($1.name, SYM_LABEL))); }
    /*| expr '||' expr	{ $$ = expr_new_tree ($1, EXPR_LOR, $3); }*/
    | expr '|' expr	{ $$ = expr_new_tree ($1, EXPR_OR, $3); }
    | expr '^' expr	{ $$ = expr_new_tree ($1, EXPR_XOR, $3); }
    /*| expr '&&' expr	{ $$ = expr_new_tree ($1, EXPR_LAND, $3); }*/
    | expr '&' expr	{ $$ = expr_new_tree ($1, EXPR_AND, $3); }
    /*| expr '==' expr	{ $$ = expr_new_tree ($1, EXPR_EQUALS, $3); }*/
    /*| expr '>' expr	{ $$ = expr_new_tree ($1, EXPR_GT, $3); }*/
    /*| expr '<' expr	{ $$ = expr_new_tree ($1, EXPR_GT, $3); }*/
    /*| expr '>=' expr	{ $$ = expr_new_tree ($1, EXPR_GE, $3); }*/
    /*| expr '<=' expr	{ $$ = expr_new_tree ($1, EXPR_GE, $3); }*/
    /*| expr '!=' expr	{ $$ = expr_new_tree ($1, EXPR_NE, $3); }*/
    | expr LEFT_OP expr	{ $$ = expr_new_tree ($1, EXPR_SHL, $3); }
    | expr RIGHT_OP expr	{ $$ = expr_new_tree ($1, EXPR_SHR, $3); }
    | expr '+' expr	{ $$ = expr_new_tree ($1, EXPR_ADD, $3); }
    | expr '-' expr	{ $$ = expr_new_tree ($1, EXPR_SUB, $3); }
    | expr '*' expr	{ $$ = expr_new_tree ($1, EXPR_MUL, $3); }
    | expr '/' expr	{ $$ = expr_new_tree ($1, EXPR_DIV, $3); }
    | expr '%' expr	{ $$ = expr_new_tree ($1, EXPR_MOD, $3); }
    | '+' expr %prec UNARYOP	{ $$ = $2; }
    | '-' expr %prec UNARYOP	{ $$ = expr_new_branch (EXPR_NEG, $2); }
    /*| '!' expr		{ $$ = expr_new_branch (EXPR_LNOT, $2); }*/
    | '~' expr %prec UNARYOP	{ $$ = expr_new_branch (EXPR_NOT, $2); }
    | '(' expr ')'	{ $$ = $2; }
;

expr: expr_no_string
    | STRING		{ $$ = expr_new_ident (EXPR_NUM, ExprNum(ConvertCharConstToInt($1))); }
;

explabel: ID | SPECIAL_ID | LOCAL_ID ;

instr: instrbase
    | OPERSIZE instr	{ $$ = $2; SetInsnOperSizeOverride(&$$, $1); }
    | ADDRSIZE instr	{ $$ = $2; SetInsnAddrSizeOverride(&$$, $1); }
    | REG_CS instr	{ $$ = $2; SetEASegment(&$$.data.insn.ea, 0x2E); }
    | REG_SS instr	{ $$ = $2; SetEASegment(&$$.data.insn.ea, 0x36); }
    | REG_DS instr	{ $$ = $2; SetEASegment(&$$.data.insn.ea, 0x3E); }
    | REG_ES instr	{ $$ = $2; SetEASegment(&$$.data.insn.ea, 0x26); }
    | REG_FS instr	{ $$ = $2; SetEASegment(&$$.data.insn.ea, 0x64); }
    | REG_GS instr	{ $$ = $2; SetEASegment(&$$.data.insn.ea, 0x65); }
    | LOCK instr	{ $$ = $2; SetInsnLockRepPrefix(&$$, 0xF0); }
    | REPNZ instr	{ $$ = $2; SetInsnLockRepPrefix(&$$, 0xF2); }
    | REP instr		{ $$ = $2; SetInsnLockRepPrefix(&$$, 0xF3); }
    | REPZ instr	{ $$ = $2; SetInsnLockRepPrefix(&$$, 0xF4); }
;

/* instruction grammars (dynamically generated) */
/* @INSTRUCTIONS@ */

%%

static unsigned long
ConvertCharConstToInt(char *cc)
{
    unsigned long retval = 0;
    size_t len = strlen(cc);

    if(len > 4)
	Warning(WARN_CHAR_CONST_TOO_BIG, (char *)NULL);

    switch(len) {
	case 4:
	    retval |= (unsigned long)cc[3];
	    retval <<= 8;
	case 3:
	    retval |= (unsigned long)cc[2];
	    retval <<= 8;
	case 2:
	    retval |= (unsigned long)cc[1];
	    retval <<= 8;
	case 1:
	    retval |= (unsigned long)cc[0];
    }

    return retval;
}

void
nasm_parser_error(char *s)
{
    yyerror(s);
}

