-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- The plugin as a user meets it: commands, filetype attachment, save hooks.

local config = require("verifpal.config")
local verifpal = require("verifpal")

local function reset()
	verifpal.setup({})
end

T.test("plugin: every command is registered", function()
	local commands = vim.api.nvim_get_commands({})
	for _, name in ipairs({
		"VerifpalVerify",
		"VerifpalCancel",
		"VerifpalResults",
		"VerifpalClear",
		"VerifpalFormat",
		"VerifpalDiagram",
		"VerifpalInfo",
	}) do
		T.ok(commands[name] ~= nil, ":" .. name .. " exists")
		-- Neovim 0.13 moved the description of a Lua-callback command out of
		-- `definition`, which is now always empty, and into `desc`.
		local desc = commands[name].desc or commands[name].definition
		T.ok(desc ~= nil and desc ~= "", ":" .. name .. " has a description")
	end
end)

T.test("plugin: a .vp file is detected as verifpal", function()
	local path = vim.fn.tempname() .. ".vp"
	vim.fn.writefile({ "attacker[active]" }, path)
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	T.eq(vim.bo.filetype, "verifpal")
	vim.api.nvim_buf_delete(0, { force = true })
	vim.fn.delete(path)
end)

T.test("plugin: the filetype plugin sets the buffer up", function()
	local bufnr = T.buffer(T.model("plain.vp"), "attach.vp")
	vim.cmd("doautocmd FileType")
	T.eq(vim.bo[bufnr].commentstring, "// %s")
	T.eq(vim.bo[bufnr].shiftwidth, 4)
	T.eq(vim.bo[bufnr].expandtab, false)
	T.eq(vim.b[bufnr].verifpal_attached, true)
	T.matches(vim.wo.foldexpr, "vim%.lsp%.foldexpr")
	T.eq(vim.b[bufnr].verifpal_attached, true)
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("plugin: setup reports a misspelled option and keeps the rest", function()
	local saved = vim.deepcopy(config.options)
	local notifications = {}
	local original = vim.notify
	vim.notify = function(msg)
		notifications[#notifications + 1] = msg
	end
	local ok = verifpal.setup({ notfy = true, sessions = 3 })
	vim.notify = original
	T.eq(ok, false, "setup reports that something was wrong")
	T.eq(#notifications, 1)
	T.matches(notifications[1], "unknown option `notfy`")
	T.eq(config.get("sessions"), 3, "the good option still applied")
	config.options = saved
end)

T.test("plugin: setup re-attaches a buffer that is already open", function()
	local saved = vim.deepcopy(config.options)
	verifpal.setup({ notify = false })
	local bufnr = T.buffer(T.model("plain.vp"), "reattach.vp")
	vim.cmd("doautocmd FileType")
	T.eq(vim.b[bufnr].verifpal_attached, true)

	vim.bo[bufnr].omnifunc = ""
	verifpal.setup({ notify = false })
	T.eq(vim.b[bufnr].verifpal_attached, true, "a live buffer stayed attached")

	vim.api.nvim_buf_delete(bufnr, { force = true })
	config.options = saved
end)

T.test("plugin: re-attaching does not stack save hooks", function()
	local saved = vim.deepcopy(config.options)
	verifpal.setup({ format_on_save = true })
	local bufnr = T.buffer(T.model("plain.vp"), "reattach2.vp")
	vim.cmd("doautocmd FileType")

	local function hooks()
		return #vim.api.nvim_get_autocmds({
			group = "Verifpal",
			buffer = bufnr,
			event = "BufWritePre",
		})
	end
	T.eq(hooks(), 1)
	-- setup() re-attaches every open buffer, and an autocmd registered twice
	-- would format the buffer twice on every write.
	verifpal.setup({ format_on_save = true })
	verifpal.setup({ format_on_save = true })
	T.eq(hooks(), 1, "still exactly one hook")

	vim.api.nvim_buf_delete(bufnr, { force = true })
	config.options = saved
	reset()
end)

T.test("plugin: format_on_save formats the file that is written", function()
	local binary = T.binary()
	if not binary then
		T.skip("no verifpal binary")
	end
	local saved = vim.deepcopy(config.options)
	local path = vim.fn.tempname() .. ".vp"
	vim.fn.writefile({
		"attacker[active]",
		"principal Alice[",
		"knows public c0",
		"]",
		"queries[",
		"confidentiality? c0",
		"]",
	}, path)

	verifpal.setup({ path = binary, format_on_save = true, notify = false })
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	T.attached(vim.api.nvim_get_current_buf())
	vim.cmd("silent write")
	local written = table.concat(vim.fn.readfile(path), "\n")
	T.matches(written, "\n\tknows public c0\n", "the written file is canonical")
	T.matches(written, "^attacker%[active%]\n\nprincipal Alice%[\n")

	vim.api.nvim_buf_delete(0, { force = true })
	vim.fn.delete(path)
	config.options = saved
	reset()
end)

T.test("plugin: verify_on_save runs the analysis after a write", function()
	local binary = T.binary()
	if not binary then
		T.skip("no verifpal binary")
	end
	local saved = vim.deepcopy(config.options)
	local path = vim.fn.tempname() .. ".vp"
	vim.fn.writefile(T.model("plain.vp"), path)

	verifpal.setup({ path = binary, verify_on_save = true, notify = false })
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	local bufnr = vim.api.nvim_get_current_buf()
	T.attached(bufnr)

	local done = false
	vim.api.nvim_create_autocmd("User", {
		pattern = "VerifpalVerifyDone",
		once = true,
		callback = function()
			done = true
		end,
	})
	vim.cmd("silent write")
	T.wait(function()
		return done
	end, 120000)
	T.ok(verifpal.report(bufnr) ~= nil, "a report landed without asking for one")

	vim.api.nvim_buf_delete(bufnr, { force = true })
	vim.fn.delete(path)
	config.options = saved
	reset()
end)

T.test("plugin: info describes the binary in use", function()
	local binary = T.binary()
	if not binary then
		T.skip("no verifpal binary")
	end
	local saved = vim.deepcopy(config.options)
	verifpal.setup({ path = binary })
	local lines = verifpal.info()
	T.matches(lines[1], "^binary:")
	T.matches(lines[2], "^version: %d+%.%d+%.%d+")
	T.matches(lines[3], "^server:")
	config.options = saved
	reset()
end)

T.test("plugin: checkhealth runs without throwing", function()
	local health = require("verifpal.health")
	local reported = {}
	local originals = {}
	for _, name in ipairs({ "start", "ok", "warn", "error", "info" }) do
		originals[name] = vim.health[name]
		vim.health[name] = function(message)
			reported[#reported + 1] = message
		end
	end
	-- health.lua caches vim.health's functions at load time, so exercise it
	-- through a fresh require rather than trusting the swap alone.
	package.loaded["verifpal.health"] = nil
	local ok, err = pcall(function()
		require("verifpal.health").check()
	end)
	for name, fn in pairs(originals) do
		vim.health[name] = fn
	end
	package.loaded["verifpal.health"] = health
	T.ok(ok, "checkhealth did not throw: " .. tostring(err))
	T.ok(#reported > 0, "and it reported something")
end)
