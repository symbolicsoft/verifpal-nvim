-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- Minimal init for headless runs: `nvim --headless -u tests/minimal.lua`.
--- Loads this checkout the way a plugin manager would, and nothing else.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.g.mapleader = " "

vim.cmd("filetype plugin indent on")
vim.cmd("syntax enable")
vim.cmd("runtime! plugin/**/*.lua")
vim.cmd("runtime! plugin/**/*.vim")
