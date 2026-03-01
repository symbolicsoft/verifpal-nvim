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

" Comments
setlocal commentstring=//\ %s
setlocal comments=://

" Indentation
setlocal tabstop=4
setlocal shiftwidth=4
setlocal noexpandtab

" Folding on bracket blocks (principal [...], queries [...])
setlocal foldmethod=marker
setlocal foldmarker=[,]
setlocal foldlevel=99

" Match brackets
setlocal matchpairs+=[:],(:)

" Undo buffer-local settings when filetype changes
let b:undo_ftplugin = "setlocal commentstring< comments< tabstop< shiftwidth< expandtab< foldmethod< foldmarker< foldlevel< matchpairs<"
