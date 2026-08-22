-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- Commands and filetype registration. Deliberately does no work beyond this:
--- the modules that talk to the binary are required lazily, inside the command
--- bodies, so opening Neovim without a `.vp` file costs nothing.

if vim.g.loaded_verifpal then
	return
end
vim.g.loaded_verifpal = true

if vim.fn.has("nvim-0.10") ~= 1 then
	vim.notify(
		"verifpal.nvim requires Neovim 0.10 or newer (it uses vim.system).",
		vim.log.levels.ERROR,
		{ title = "Verifpal" }
	)
	return
end

vim.filetype.add({ extension = { vp = "verifpal" } })

local function command(name, fn, opts)
	vim.api.nvim_create_user_command(name, fn, opts)
end

command("VerifpalVerify", function(args)
	local sessions = tonumber(args.args)
	if args.args ~= "" and not sessions then
		vim.notify(
			"Verifpal: :VerifpalVerify takes an optional session count",
			vim.log.levels.ERROR,
			{ title = "Verifpal" }
		)
		return
	end
	require("verifpal").verify(0, { sessions = sessions })
end, {
	nargs = "?",
	desc = "Verifpal: run the attacker analysis on this buffer",
})

command("VerifpalCancel", function()
	if not require("verifpal").cancel(0) then
		vim.notify("Verifpal: nothing to cancel", vim.log.levels.INFO, { title = "Verifpal" })
	end
end, { desc = "Verifpal: stop the running analysis" })

command("VerifpalResults", function()
	require("verifpal").results(0)
end, { desc = "Verifpal: show the last analysis, with attack traces" })

command("VerifpalClear", function()
	require("verifpal").clear(0)
end, { desc = "Verifpal: clear verification diagnostics" })

command("VerifpalFormat", function()
	require("verifpal").format(0)
end, { desc = "Verifpal: reformat this buffer" })

command("VerifpalDiagram", function(args)
	require("verifpal").diagram(0, args.bang)
end, {
	bang = true,
	desc = "Verifpal: show the protocol diagram (! for mermaid source)",
})

command("VerifpalInfo", function()
	local lines = require("verifpal").info()
	vim.api.nvim_echo(
		vim.tbl_map(function(line)
			return { line .. "\n" }
		end, lines),
		true,
		{}
	)
end, { desc = "Verifpal: report the binary this plugin will use" })
