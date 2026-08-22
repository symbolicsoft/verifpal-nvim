-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- Everything that talks to the verifpal binary.
---
--- The binary is not versioned with this plugin: a user may install the plugin
--- today and still be on whatever verifpal their package manager last shipped.
--- So the feature set is *probed* rather than assumed, once per binary, and
--- every caller asks `features()` before reaching for a flag. A plugin that
--- assumes a flag exists fails with a clap usage error the user cannot act on;
--- one that probes degrades to the older interface and says so in
--- `:checkhealth`.

local config = require("verifpal.config")

local M = {}

--- Cached per resolved binary path, so changing `path` re-probes.
local cache = {}

--- Forget every probe result. Called from setup().
function M.reset()
	cache = {}
end

--- Absolute path to the binary, or nil plus a reason.
function M.binary()
	local want = config.get("path") or "verifpal"
	local resolved
	if want:find("[/\\]") then
		resolved = vim.fn.fnamemodify(vim.fn.expand(want), ":p")
		if vim.fn.executable(resolved) ~= 1 then
			return nil, string.format("`%s` is not executable", resolved)
		end
	else
		resolved = vim.fn.exepath(want)
		if resolved == "" then
			return nil, string.format("`%s` was not found in $PATH", want)
		end
	end
	return resolved
end

local function entry(path)
	if not cache[path] then
		cache[path] = {}
	end
	return cache[path]
end

--- Run the binary and wait for it.
---
--- Reserved for work that is over in milliseconds — the capability probes and
--- the formatter. An analysis never comes through here: blocking the editor
--- for the length of a protocol verification is exactly what M.run avoids.
---@param args string[]
---@param opts table|nil { stdin = string, timeout = number }
---@return table|nil result, string|nil err
function M.run_sync(args, opts)
	opts = opts or {}
	local path, err = M.binary()
	if not path then
		return nil, err
	end
	local ok, result = pcall(function()
		return vim
			.system(vim.list_extend({ path }, args), { text = true, stdin = opts.stdin })
			:wait(opts.timeout or 15000)
	end)
	if not ok then
		return nil, string.format("could not run `%s`: %s", path, tostring(result))
	end
	return {
		code = result.code,
		signal = result.signal,
		stdout = result.stdout or "",
		stderr = result.stderr or "",
	}
end

--- The probe form: takes an already-resolved path so it cannot recurse
--- through M.binary while a probe is being cached.
local function probe(path, args, stdin)
	local ok, result = pcall(function()
		return vim
			.system(vim.list_extend({ path }, args), { text = true, stdin = stdin })
			:wait(15000)
	end)
	if not ok then
		return nil
	end
	return result
end

--- Version string reported by the binary, e.g. "1.0.4", or nil.
function M.version()
	local path, err = M.binary()
	if not path then
		return nil, err
	end
	local e = entry(path)
	if e.version == nil then
		local out = probe(path, { "--version" })
		local text = out and ((out.stdout or "") .. (out.stderr or "")) or ""
		e.version = text:match("(%d+%.%d+%.%d+)") or false
	end
	return e.version or nil
end

--- What this binary can do. Probed from its own --help, so the plugin never
--- passes a flag the binary would reject.
---
--- `json`     verify --format json, the structured report with attack traces
--- `sessions` verify --sessions k
--- `quiet`    verify --quiet, which silences everything but the result code
--- `color`    verify --color never
--- `diagram`  the `diagram` subcommand (mermaid sequence diagram)
--- `stdin`    the `internal-json` subcommand, which reads a model from stdin
function M.features()
	local path, err = M.binary()
	if not path then
		return {}, err
	end
	local e = entry(path)
	if e.features then
		return e.features
	end
	local top = probe(path, { "--help" })
	local verify = probe(path, { "verify", "--help" })
	local top_text = top and ((top.stdout or "") .. (top.stderr or "")) or ""
	local verify_text = verify and ((verify.stdout or "") .. (verify.stderr or "")) or ""
	-- clap lists subcommands two-space indented under a "Commands:" heading,
	-- each optionally followed by a description. Reading the list rather than
	-- searching the whole text keeps a subcommand named in a description from
	-- being mistaken for one that exists.
	local subcommands = {}
	local in_commands = false
	for _, line in ipairs(vim.split(top_text, "\n", { plain = true })) do
		if line:match("^%a[%a%s]*:%s*$") then
			in_commands = line:lower():match("^commands:") ~= nil
		elseif in_commands then
			local name = line:match("^%s%s+([%a][%w%-]*)")
			if name then
				subcommands[name] = true
			end
		end
	end
	e.features = {
		json = verify_text:find("--format", 1, true) ~= nil,
		sessions = verify_text:find("--sessions", 1, true) ~= nil,
		quiet = verify_text:find("--quiet", 1, true) ~= nil,
		color = verify_text:find("--color", 1, true) ~= nil,
		diagram = subcommands["diagram"] == true,
		stdin = subcommands["internal-json"] == true or top_text:find("internal-json", 1, true) ~= nil,
	}
	return e.features
end

--- Start the binary asynchronously.
---
--- `on_done` is always called on the main loop, so callers may touch buffers
--- without scheduling. Returns the handle, which has :kill().
---@param args string[]
---@param opts table|nil  { stdin = string, cwd = string, timeout = number }
---@param on_done fun(result: { code: integer, signal: integer, stdout: string, stderr: string, timed_out: boolean })
function M.run(args, opts, on_done)
	opts = opts or {}
	local path, err = M.binary()
	if not path then
		vim.schedule(function()
			on_done({ code = -1, signal = 0, stdout = "", stderr = err, timed_out = false })
		end)
		return nil
	end
	local timeout = opts.timeout or config.get("timeout")
	local cmd = vim.list_extend({ path }, args)
	local ok, handle = pcall(vim.system, cmd, {
		text = true,
		stdin = opts.stdin,
		cwd = opts.cwd,
		timeout = timeout,
	}, function(result)
		-- vim.system reports a timeout as SIGTERM (or SIGKILL if the process
		-- ignored it); a caller cancelling deliberately looks identical, so the
		-- caller marks its own cancellations instead of guessing here.
		local timed_out = result.signal ~= 0 and result.code ~= 0
		vim.schedule(function()
			on_done({
				code = result.code,
				signal = result.signal,
				stdout = result.stdout or "",
				stderr = result.stderr or "",
				timed_out = timed_out,
			})
		end)
	end)
	if not ok then
		vim.schedule(function()
			on_done({
				code = -1,
				signal = 0,
				stdout = "",
				stderr = string.format("could not start `%s`: %s", path, tostring(handle)),
				timed_out = false,
			})
		end)
		return nil
	end
	return handle
end

-- ---------------------------------------------------------------------------
-- Error rendering
-- ---------------------------------------------------------------------------

--- Verifpal renders a model error as a headline, a `--> file:line:col`
--- pointer, the offending source line, a caret span, and optional note/help
--- footnotes:
---
---     sanity error: `PUBKEY` takes 1 argument, but 2 were given
---       --> model.vp:12:7
---        |
---     12 |     ga = PUBKEY(a, c0)
---        |          ^^^^^^
---        |
---        = note: its signature is `PUBKEY(private_key)`
---
--- Verifpal 1.0.4 and earlier put the position on the headline instead:
---
---     Error: model.vp:12:2: sanity error: primitive has 2 inputs, expecting 1
---        ga = PUBKEY(a, c0)
---        ^^^^^^^^^^^^^^^^^^
---
--- Both are read here. Turning either back into a position is what lets a
--- model error land on the line that caused it instead of in a notification
--- the user has to read and then go looking for.
---@return table|nil { message, headline, kind, notes, lnum, col, end_col }
function M.parse_error(text)
	if not text or text == "" then
		return nil
	end
	local lines = vim.split(text, "\n", { plain = true })

	local headline
	for _, line in ipairs(lines) do
		if line:match("%S") then
			headline = vim.trim(line)
			break
		end
	end
	if not headline then
		return nil
	end
	headline = headline:gsub("^Error:%s*", "")

	local lnum, col
	-- Legacy: the position is a prefix of the headline. Anchoring on a `.vp`
	-- file name keeps a colon inside the message from being read as one.
	local legacy_line, legacy_col, legacy_message =
		headline:match("^[^%s]-%.vp:(%d+):(%d+):%s*(.+)$")
	if legacy_line then
		lnum, col = tonumber(legacy_line), tonumber(legacy_col)
		headline = legacy_message
	else
		for _, line in ipairs(lines) do
			local l, c = line:match("^%s*%-%->%s*.*:(%d+):(%d+)%s*$")
			if l then
				lnum, col = tonumber(l), tonumber(c)
				break
			end
		end
	end

	local kind = headline:match("^(%a[%a%s]-error):") or nil

	local width
	for _, line in ipairs(lines) do
		local carets = line:match("^%s*|%s*(%^+)") or line:match("^%s*(%^+)%s*$")
		if carets then
			width = #carets
			break
		end
	end

	local notes = {}
	for _, line in ipairs(lines) do
		local tag, body = line:match("^%s*=%s*(%a+):%s*(.+)$")
		if tag then
			notes[#notes + 1] = tag .. ": " .. body
		end
	end

	local message = headline
	if #notes > 0 then
		message = message .. "\n" .. table.concat(notes, "\n")
	end

	return {
		message = message,
		headline = headline,
		kind = kind,
		notes = notes,
		lnum = lnum and math.max(lnum - 1, 0) or 0,
		col = col and math.max(col - 1, 0) or 0,
		end_col = (col and width) and (col - 1 + width) or nil,
	}
end

return M
