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

" Comments. Verifpal accepts both // line comments and /* */ block comments,
" and `pretty` preserves either when formatting.
setlocal commentstring=//\ %s
setlocal comments=s1:/*,mb:*,ex:*/,://

" `verifpal pretty` writes hard tabs, so a buffer that will be formatted is
" already committed to them.
setlocal tabstop=4
setlocal shiftwidth=4
setlocal noexpandtab

" A model's own words. `_` is already in 'iskeyword', which is what lets K
" over AEAD_ENC or PW_HASH find the whole primitive rather than half of it.
setlocal matchpairs+=[:],(:)
setlocal suffixesadd=.vp

" Hover, completion, folding, indenting and any save hooks. Doing this from
" the ftplugin rather than a FileType autocmd is what makes the plugin work
" without a setup() call, and keeps it working under lazy loading.
lua require("verifpal").attach()

let b:undo_ftplugin = "setlocal commentstring< comments< tabstop< shiftwidth<"
            \ . " expandtab< matchpairs< suffixesadd< omnifunc< indentexpr<"
            \ . " indentkeys< foldmethod< foldexpr< foldlevel<"
            \ . " | unlet! b:verifpal_attached"
