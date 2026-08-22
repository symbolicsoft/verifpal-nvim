-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local M = {}

function M.format(bufnr, opts)
	opts = opts or {}
	bufnr = (not bufnr or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
	local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "verifpal" })
	if #clients == 0 then
		if not opts.silent then
			vim.notify(
				"Verifpal: the language server is not attached to this buffer",
				vim.log.levels.ERROR,
				{ title = "Verifpal" }
			)
		end
		return false
	end
	vim.lsp.buf.format({
		bufnr = bufnr,
		name = "verifpal",
		async = false,
		timeout_ms = 15000,
	})
	return true
end

return M
