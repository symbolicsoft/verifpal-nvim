" Vim syntax file
" Language:     Verifpal
" Maintainer:   Nadim Kobeissi <nadim@symbolic.software>
" URL:          https://verifpal.com
" SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
" SPDX-License-Identifier: GPL-3.0-only

if exists("b:current_syntax")
    finish
endif

" ---------------------------------------------------------------------------
" Comments
" ---------------------------------------------------------------------------

syn match verifpalComment "//.*$" contains=@Spell

" ---------------------------------------------------------------------------
" Block structure keywords
" ---------------------------------------------------------------------------

syn keyword verifpalBlock       principal phase queries attacker

" ---------------------------------------------------------------------------
" Attacker mode
" ---------------------------------------------------------------------------

syn keyword verifpalMode        active passive

" ---------------------------------------------------------------------------
" Declaration keywords (inside principal blocks)
" ---------------------------------------------------------------------------

syn keyword verifpalDeclaration knows generates leaks

" ---------------------------------------------------------------------------
" Qualifiers
" ---------------------------------------------------------------------------

syn keyword verifpalQualifier   public private password

" ---------------------------------------------------------------------------
" Query keywords
" ---------------------------------------------------------------------------

syn keyword verifpalQuery       confidentiality authentication freshness
syn keyword verifpalQuery       unlinkability equivalence precondition

" ---------------------------------------------------------------------------
" Cryptographic primitives (21 built-in)
" ---------------------------------------------------------------------------

syn keyword verifpalPrimitive   ASSERT CONCAT SPLIT
syn keyword verifpalPrimitive   PW_HASH HASH HKDF MAC
syn keyword verifpalPrimitive   AEAD_ENC AEAD_DEC ENC DEC
syn keyword verifpalPrimitive   SIGN SIGNVERIF PKE_ENC PKE_DEC
syn keyword verifpalPrimitive   SHAMIR_SPLIT SHAMIR_JOIN
syn keyword verifpalPrimitive   RINGSIGN RINGSIGNVERIF
syn keyword verifpalPrimitive   BLIND UNBLIND

" ---------------------------------------------------------------------------
" Special values
" ---------------------------------------------------------------------------

syn keyword verifpalSpecial     G nil

" ---------------------------------------------------------------------------
" Operators and delimiters
" ---------------------------------------------------------------------------

syn match   verifpalOperator    "="
syn match   verifpalOperator    "\^"
syn match   verifpalOperator    "?"
syn match   verifpalTransfer    "->"
syn match   verifpalTransfer    "\u2192"
syn match   verifpalDelimiter   "[(),:\[\]]"

" ---------------------------------------------------------------------------
" Phase numbers
" ---------------------------------------------------------------------------

syn match   verifpalNumber      "\<\d\+\>"

" ---------------------------------------------------------------------------
" Principal names (title-cased identifiers used as block headers and in
" message arrows — matched after keywords so keywords take priority)
" ---------------------------------------------------------------------------

syn match   verifpalPrincipal   "\<\u\w*\>" containedin=ALLBUT,verifpalComment,verifpalPrimitive

" ---------------------------------------------------------------------------
" Highlight links
" ---------------------------------------------------------------------------

hi def link verifpalComment     Comment
hi def link verifpalBlock       Statement
hi def link verifpalMode        Constant
hi def link verifpalDeclaration Keyword
hi def link verifpalQualifier   Type
hi def link verifpalQuery       Keyword
hi def link verifpalPrimitive   Function
hi def link verifpalSpecial     Constant
hi def link verifpalOperator    Operator
hi def link verifpalTransfer    Special
hi def link verifpalDelimiter   Delimiter
hi def link verifpalNumber      Number
hi def link verifpalPrincipal   Identifier

let b:current_syntax = "verifpal"
