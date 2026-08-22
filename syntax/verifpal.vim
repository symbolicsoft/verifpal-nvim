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

syn keyword verifpalTodo        contained TODO FIXME XXX NOTE
syn match   verifpalComment     "//.*$" contains=verifpalTodo,@Spell
syn region  verifpalComment     start="/\*" end="\*/" contains=verifpalTodo,@Spell

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
" Cryptographic primitives (25 built-in)
"
" Matched without case sensitivity because Verifpal resolves primitive names
" that way — `pubkey(a)` and `PUBKEY(a)` are the same call. This is safe rather
" than greedy: every primitive's lowercase name is a reserved word, so no
" constant can be called `hash` or `enc` and be mistaken for one.
" ---------------------------------------------------------------------------

syn case ignore
syn keyword verifpalPrimitive   ASSERT CONCAT SPLIT
syn keyword verifpalPrimitive   PW_HASH HASH HKDF MAC
syn keyword verifpalPrimitive   AEAD_ENC AEAD_DEC ENC DEC
syn keyword verifpalPrimitive   SIGN SIGNVERIF PKE_ENC PKE_DEC
syn keyword verifpalPrimitive   SHAMIR_SPLIT SHAMIR_JOIN
syn keyword verifpalPrimitive   RINGSIGN RINGSIGNVERIF
syn keyword verifpalPrimitive   BLIND UNBLIND
syn keyword verifpalPrimitive   PUBKEY DH_KEX
syn keyword verifpalPrimitive   KEM_ENCAP KEM_DECAP
syn case match

" ---------------------------------------------------------------------------
" Special values
" ---------------------------------------------------------------------------

syn keyword verifpalSpecial     nil
syn match   verifpalSpecial     "\<_\>"

" ---------------------------------------------------------------------------
" Operators and delimiters
" ---------------------------------------------------------------------------

" `?` marks a checked primitive: a failed check halts the principal, which is
" the single most consequential character in a model. It gets its own group so
" a colour scheme can make it visible.
syn match   verifpalCheck       "?"
syn match   verifpalOperator    "="
syn match   verifpalTransfer    "->"
syn match   verifpalTransfer    "\%u2192"
syn match   verifpalDelimiter   "[(),:\[\]]"

" ---------------------------------------------------------------------------
" Phase numbers
" ---------------------------------------------------------------------------

syn match   verifpalNumber      "\<\d\+\>"

" ---------------------------------------------------------------------------
" Principal names: title-cased identifiers, as block headers and either side
" of a message arrow. Matched after the keyword rules so keywords win.
" ---------------------------------------------------------------------------

syn match   verifpalPrincipal   "\<\u\w*\>"

" ---------------------------------------------------------------------------
" Declared weakening assumptions, e.g. SIGN[forgeable](sk, m) or
" AEAD_ENC[weak from phase 2](k, m, ad).
"
" `weak`, `forgeable`, `malleable` and `from` are contextual keywords: the
" parser recognises them only inside a capability parameter list, and keeps
" them out of its reserved words so that a model may still name a constant
" `weak` or `from`. Matching them the same way — anchored on the bracket that
" introduces them, which in turn must follow a primitive name — is what keeps
" such a model highlighted correctly.
"
" Defined last on purpose: where two syntax items can match at one position
" Vim prefers the one defined later, and this region has to outrank the
" bracket's own delimiter match.
" ---------------------------------------------------------------------------

syn region  verifpalCapabilityList matchgroup=verifpalDelimiter
            \ start="\w\@<=\[\%(\s*\%(weak\|forgeable\|malleable\)\>\)\@="
            \ end="\]" oneline
            \ contains=verifpalCapability,verifpalNumber,verifpalDelimiter
syn keyword verifpalCapability  contained weak forgeable malleable phase from

" ---------------------------------------------------------------------------
" Highlight links
" ---------------------------------------------------------------------------

hi def link verifpalComment     Comment
hi def link verifpalTodo        Todo
hi def link verifpalBlock       Statement
hi def link verifpalMode        Constant
hi def link verifpalDeclaration Keyword
hi def link verifpalQualifier   Type
hi def link verifpalQuery       Keyword
hi def link verifpalCapability  Exception
hi def link verifpalPrimitive   Function
hi def link verifpalSpecial     Constant
hi def link verifpalCheck       Special
hi def link verifpalOperator    Operator
hi def link verifpalTransfer    Special
hi def link verifpalDelimiter   Delimiter
hi def link verifpalNumber      Number
hi def link verifpalPrincipal   Identifier

let b:current_syntax = "verifpal"
