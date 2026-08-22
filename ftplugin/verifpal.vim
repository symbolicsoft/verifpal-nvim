" Vim ftplugin file
" Language:     Verifpal
" Maintainer:   Nadim Kobeissi <nadim@symbolic.software>
" URL:          https://verifpal.com
" SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
" SPDX-License-Identifier: GPL-3.0-only

if exists("b:did_ftplugin")
    finish
endif
let b:did_ftplugin = 1

setlocal commentstring=//\ %s
setlocal comments=s1:/*,mb:*,ex:*/,://

setlocal tabstop=4
setlocal shiftwidth=4
setlocal noexpandtab

setlocal matchpairs+=[:],(:)
setlocal suffixesadd=.vp

setlocal foldmethod=expr
setlocal foldexpr=v:lua.vim.lsp.foldexpr()
setlocal foldlevel=99

lua require("verifpal").attach()

let b:undo_ftplugin = "setlocal commentstring< comments< tabstop< shiftwidth<"
            \ . " expandtab< matchpairs< suffixesadd<"
            \ . " foldmethod< foldexpr< foldlevel<"
            \ . " | unlet! b:verifpal_attached"
