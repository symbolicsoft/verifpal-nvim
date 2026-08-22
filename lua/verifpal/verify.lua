-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- Running the attacker analysis and turning its verdict into diagnostics.
---
--- Two things here are deliberate. First, the analysis runs asynchronously:
--- verifying a real protocol model takes seconds to minutes, and a synchronous
--- run freezes the editor for the whole of it. Second, the buffer is analyzed
--- rather than the file on disk — the plugin writes a copy to a scratch
--- directory under the buffer's own name instead of saving over the user's
--- file, so an unsaved or unnamed buffer verifies, and no command silently
--- writes to disk.

local cli = require("verifpal.cli")
local config = require("verifpal.config")
local scan = require("verifpal.scan")

local M = {}

local ns = vim.api.nvim_create_namespace("verifpal")

--- Per-buffer analysis state, keyed by buffer number.
local state = {}

--- Normalise a buffer argument. Neovim's API reads 0 as "the current buffer",
--- and every entry point here accepts it — but 0 is also a perfectly good
--- table key, so storing state under it would file one buffer's results in a
--- drawer nothing else looks in.
local function resolve(bufnr)
	if not bufnr or bufnr == 0 then
		return vim.api.nvim_get_current_buf()
	end
	return bufnr
end

local SPINNER = { "-", "\\", "|", "/" }

--- Fired when an analysis starts and when it finishes, so a configuration can
--- react without polling: `:autocmd User VerifpalVerifyDone ...`.
local function announce(event, bufnr)
	pcall(vim.api.nvim_exec_autocmds, "User", {
		pattern = event,
		modeline = false,
		data = { buf = bufnr },
	})
end

--- A statusline is redrawn on events, not on a clock, so a spinner nothing
--- nudges would sit on one frame for the length of the analysis. One timer
--- for as long as an analysis runs is what makes the indicator mean anything.
local ticker = { timer = nil, running = 0 }

local function ticker_start()
	ticker.running = ticker.running + 1
	if ticker.timer then
		return
	end
	local timer = vim.uv.new_timer()
	if not timer then
		return
	end
	ticker.timer = timer
	timer:start(
		120,
		120,
		vim.schedule_wrap(function()
			pcall(vim.cmd, "redrawstatus")
		end)
	)
end

local function ticker_stop()
	ticker.running = math.max(ticker.running - 1, 0)
	if ticker.running > 0 or not ticker.timer then
		return
	end
	ticker.timer:stop()
	ticker.timer:close()
	ticker.timer = nil
	pcall(vim.cmd, "redrawstatus")
end

--- Bare vim.notify ignores `title`, so the prefix is what identifies the
--- source in a default setup; notification plugins get the title as well.
local function notify(msg, level)
	if not config.get("notify") then
		return
	end
	if not tostring(msg):match("^Verifpal") then
		msg = "Verifpal: " .. msg
	end
	vim.notify(msg, level or vim.log.levels.INFO, { title = "Verifpal" })
end

local function buffer_state(bufnr)
	bufnr = resolve(bufnr)
	if not state[bufnr] then
		state[bufnr] = {}
	end
	return state[bufnr]
end

--- The last report for a buffer, for the results panel and statuslines.
function M.report(bufnr)
	return buffer_state(bufnr).report
end

--- True while an analysis is in flight.
function M.running(bufnr)
	return buffer_state(bufnr).handle ~= nil
end

--- A one-line status for a statusline, or "" when there is nothing to say.
--- Reports progress while running and the result code once finished.
function M.status(bufnr)
	local s = buffer_state(bufnr)
	if s.handle then
		local tick = math.floor(vim.uv.now() / 120) % #SPINNER + 1
		return "verifpal " .. SPINNER[tick]
	end
	if not s.report then
		return ""
	end
	if s.report.error then
		return "verifpal !"
	end
	local attacks = s.report.attacks or 0
	if attacks == 0 then
		return "verifpal ok"
	end
	return string.format("verifpal %d attack%s", attacks, attacks == 1 and "" or "s")
end

-- ---------------------------------------------------------------------------
-- Feeding the buffer to the binary
-- ---------------------------------------------------------------------------

--- verifpal requires the model's file name to end in `.vp` and to be at most
--- 64 characters, so a scratch copy keeps the buffer's own basename where it
--- can: an error then reads `mymodel.vp:6:2` and not some temporary name the
--- user has never seen.
local function scratch_copy(bufnr, lines)
	local name = vim.api.nvim_buf_get_name(bufnr)
	local base = name ~= "" and vim.fn.fnamemodify(name, ":t") or "buffer.vp"
	if not base:match("%.vp$") then
		base = base .. ".vp"
	end
	if #base > 64 then
		base = "model.vp"
	end
	local dir = vim.fn.tempname()
	if vim.fn.mkdir(dir, "p") ~= 1 then
		return nil, "could not create a scratch directory for the model"
	end
	local path = dir .. "/" .. base
	local ok, err = pcall(vim.fn.writefile, lines, path)
	if not ok then
		return nil, tostring(err)
	end
	return path, nil, dir
end

--- Where should the binary read this model from? An unmodified, named,
--- `.vp` buffer is already on disk exactly as we would write it, so use it.
local function model_source(bufnr, lines)
	local name = vim.api.nvim_buf_get_name(bufnr)
	local modified = vim.bo[bufnr].modified
	if name ~= "" and not modified and name:match("%.vp$") and vim.fn.filereadable(name) == 1 then
		return name, nil, nil
	end
	return scratch_copy(bufnr, lines)
end

local function cleanup(dir)
	if dir then
		pcall(vim.fn.delete, dir, "rf")
	end
end

-- ---------------------------------------------------------------------------
-- Reading the binary's answer
-- ---------------------------------------------------------------------------

local KIND_OF_LETTER = {
	c = "confidentiality",
	a = "authentication",
	f = "freshness",
	u = "unlinkability",
	e = "equivalence",
}

--- Split a result code such as "c0a1f1" into per-query verdicts. The code is
--- the compact form of the whole answer: one letter for the query kind and one
--- digit for whether the attacker resolved it, in model order.
---@return table[]|nil
function M.parse_result_code(code)
	if not code then
		return nil
	end
	code = vim.trim(code)
	if code == "" then
		return {}
	end
	if not code:match("^[cafue01]+$") or #code % 2 ~= 0 then
		return nil
	end
	local results = {}
	for i = 1, #code, 2 do
		local letter = code:sub(i, i)
		local digit = code:sub(i + 1, i + 1)
		local kind = KIND_OF_LETTER[letter]
		if not kind or (digit ~= "0" and digit ~= "1") then
			return nil
		end
		results[#results + 1] = { kind = kind, resolved = digit == "1" }
	end
	return results
end

--- Normalise `verify --format json` into the report the rest of the plugin
--- reads.
local function report_from_json(stdout)
	local ok, decoded = pcall(vim.json.decode, stdout)
	if not ok or type(decoded) ~= "table" or type(decoded.models) ~= "table" then
		return nil
	end
	local model = decoded.models[1]
	if type(model) ~= "table" then
		return nil
	end
	if model.ok == false then
		return { error = model.error or "verification failed", version = decoded.version }
	end
	local queries = {}
	for _, q in ipairs(model.queries or {}) do
		queries[#queries + 1] = {
			query = q.query,
			kind = q.kind,
			resolved = q.resolved == true,
			conclusion = q.conclusion,
			trace = q.trace or {},
			preconditions = q.preconditions or {},
		}
	end
	local assumptions = {}
	for _, a in ipairs(model.assumptions or {}) do
		assumptions[#assumptions + 1] = {
			term = a.Term,
			capability = a.Capability,
			from_phase = a.FromPhase,
		}
	end
	return {
		version = decoded.version,
		file = model.model or model.file,
		sessions = model.sessions,
		code = model.code or "",
		attacks = model.attacks or 0,
		elapsed_ms = model.elapsedMs,
		assumptions = assumptions,
		queries = queries,
	}
end

--- Fall back to the result code when the binary predates `--format json`.
--- The verdict is still exact — the code is the same answer in a compact form
--- — but there is no narrated trace to show, and the panel says so.
local function report_from_text(stdout)
	local out = vim.split(stdout, "\n", { plain = true })
	-- The code is printed last, and it is empty for a model with no queries —
	-- so the *last* line is the code, and taking the last non-empty one would
	-- read the closing banner as a result.
	if #out > 0 and out[#out] == "" then
		table.remove(out)
	end
	local code = out[#out] and vim.trim(out[#out]) or nil
	local results = M.parse_result_code(code)
	if not results then
		return nil
	end
	local queries = {}
	local attacks = 0
	for _, r in ipairs(results) do
		if r.resolved then
			attacks = attacks + 1
		end
		queries[#queries + 1] = {
			kind = r.kind,
			resolved = r.resolved,
			query = r.kind .. "?",
			trace = {},
			preconditions = {},
		}
	end
	-- Declared weakening assumptions are announced under a header before the
	-- results. A model analyzed under one is not analyzed on its own terms, so
	-- surfacing them matters even without the structured report.
	local assumptions = {}
	local in_assumptions = false
	for _, raw in ipairs(vim.split(stdout, "\n", { plain = true })) do
		local line = raw:gsub("\27%[[%d;]*m", "")
		if line:match("declared weakening assumption") then
			in_assumptions = true
		elseif in_assumptions then
			local term = line:match("^%s*Warning%s*[^%s]*%s*(.+)$")
			if term then
				assumptions[#assumptions + 1] = { term = vim.trim(term) }
			else
				in_assumptions = false
			end
		end
	end
	return {
		code = code,
		attacks = attacks,
		queries = queries,
		assumptions = assumptions,
		degraded = true,
	}
end

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------

--- Anchor each result on the line of the query that produced it.
---
--- Results arrive in model order and so do the queries the scanner finds, so
--- position is the mapping — but only if the two agree on what kind each query
--- is. When they do not, something has been misread, and putting a verdict on
--- a line that did not produce it is worse than putting them all on the block
--- header, so that is what happens instead.
---@return table[] anchors, boolean aligned
local function anchor_queries(lines, results)
	local queries, block = scan.queries(lines)
	local aligned = #queries == #results
	if aligned then
		for i, q in ipairs(queries) do
			if results[i].kind and q.kind ~= results[i].kind then
				aligned = false
				break
			end
		end
	end
	if aligned then
		return queries, true
	end
	local fallback = block and block.start_lnum or 0
	local anchors = {}
	for i = 1, #results do
		anchors[i] = { lnum = fallback, col = 0, end_col = nil }
	end
	return anchors, false
end

local function query_label(result)
	if result.query and result.query ~= "" and result.query ~= (result.kind .. "?") then
		return result.query
	end
	return (result.kind or "query") .. " query"
end

local function diagnostic_message(result)
	if not result.resolved then
		local text = "no attack found"
		if result.conclusion and result.conclusion ~= "" then
			text = text .. " — " .. result.conclusion
		end
		return text
	end
	local text = "attack found"
	if result.conclusion and result.conclusion ~= "" then
		text = text .. " — " .. result.conclusion
	end
	if config.get("diagnostics.trace") and #(result.trace or {}) > 0 then
		text = text .. "\n\nAttack trace:\n" .. table.concat(result.trace, "\n")
	end
	for _, precondition in ipairs(result.preconditions or {}) do
		text = text .. "\n" .. precondition
	end
	return text
end

--- Replace the buffer's diagnostics with the verdicts in `report`.
function M.apply_diagnostics(bufnr, report)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	vim.diagnostic.reset(ns, bufnr)
	if not config.get("diagnostics.enabled") then
		return
	end

	local diagnostics = {}

	if report.error then
		local parsed = cli.parse_error(report.error)
		local line_count = vim.api.nvim_buf_line_count(bufnr)
		local lnum = math.min(parsed and parsed.lnum or 0, math.max(line_count - 1, 0))
		-- verifpal counts columns in characters; a diagnostic wants bytes.
		-- They differ the moment a line holds anything non-ASCII, which a
		-- comment above the offending code readily does.
		local text = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
		local function byte_of(char_col)
			if not char_col then
				return nil
			end
			local at = vim.fn.byteidx(text, char_col)
			return at >= 0 and at or #text
		end
		diagnostics[#diagnostics + 1] = {
			lnum = lnum,
			col = byte_of(parsed and parsed.col) or 0,
			end_lnum = lnum,
			end_col = byte_of(parsed and parsed.end_col),
			severity = vim.diagnostic.severity.ERROR,
			source = "verifpal",
			message = parsed and parsed.message or report.error,
		}
		vim.diagnostic.set(ns, bufnr, diagnostics)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local anchors, aligned = anchor_queries(lines, report.queries)
	report.aligned = aligned

	local pass_severity = config.get("diagnostics.pass")
	for i, result in ipairs(report.queries) do
		local anchor = anchors[i]
		local severity = result.resolved and config.get("diagnostics.attack") or pass_severity
		if anchor and severity then
			diagnostics[#diagnostics + 1] = {
				lnum = anchor.lnum,
				col = anchor.col or 0,
				end_lnum = anchor.lnum,
				end_col = anchor.end_col,
				severity = severity,
				source = "verifpal",
				message = diagnostic_message(result),
				user_data = { verifpal = { index = i, result = result } },
			}
		end
	end
	vim.diagnostic.set(ns, bufnr, diagnostics)
end

--- Clear everything this plugin put on a buffer.
function M.clear(bufnr)
	bufnr = resolve(bufnr)
	vim.diagnostic.reset(ns, bufnr)
	state[bufnr] = nil
end

function M.namespace()
	return ns
end

-- ---------------------------------------------------------------------------
-- Summaries
-- ---------------------------------------------------------------------------

local function summarise(report)
	local total = #report.queries
	if total == 0 then
		return "no queries to verify", vim.log.levels.WARN
	end
	local attacks = report.attacks or 0
	local text
	if attacks == 0 then
		text = string.format("all %d quer%s hold", total, total == 1 and "y" or "ies")
	else
		text = string.format("%d of %d queries contradicted", attacks, total)
	end
	if report.code and report.code ~= "" then
		text = text .. " (" .. report.code .. ")"
	end
	local trailer = {}
	if report.sessions then
		trailer[#trailer + 1] = report.sessions .. " sessions"
	end
	if report.elapsed_ms then
		trailer[#trailer + 1] = report.elapsed_ms .. " ms"
	end
	if #trailer > 0 then
		text = text .. " · " .. table.concat(trailer, " · ")
	end

	local level = attacks == 0 and vim.log.levels.INFO or vim.log.levels.WARN

	-- A model that declares a weakening assumption is not being analyzed on
	-- its own terms: an attack found under one is genuine only under that
	-- assumption, and a query that holds is conditional on it. Neither is an
	-- unconditional result, so neither is reported as one.
	if report.assumptions and #report.assumptions > 0 then
		local terms = {}
		for _, a in ipairs(report.assumptions) do
			local term = a.term or "?"
			if a.from_phase and a.from_phase > 0 then
				term = term .. " (from phase " .. a.from_phase .. ")"
			end
			terms[#terms + 1] = "  " .. term
		end
		text = text
			.. string.format(
				"\nConditional on %d declared weakening assumption%s:\n",
				#report.assumptions,
				#report.assumptions == 1 and "" or "s"
			)
			.. table.concat(terms, "\n")
		level = vim.log.levels.WARN
	end

	if report.aligned == false then
		text = text
			.. "\nCould not match results to query lines; diagnostics are on the queries block."
	end
	if report.degraded then
		text = text .. "\nThis verifpal predates `verify --format json`: no attack traces available."
	end
	return text, level
end

-- ---------------------------------------------------------------------------
-- Running
-- ---------------------------------------------------------------------------

--- Stop the analysis running for a buffer, if any.
function M.cancel(bufnr)
	local s = buffer_state(bufnr)
	if not s.handle then
		return false
	end
	s.cancelled = true
	pcall(function()
		s.handle:kill("sigterm")
	end)
	return true
end

--- Verify the buffer.
---@param bufnr integer|nil
---@param opts table|nil { sessions = integer, silent = boolean, on_done = fun(report) }
function M.verify(bufnr, opts)
	bufnr = resolve(bufnr)
	opts = opts or {}
	local s = buffer_state(bufnr)

	if s.handle then
		notify("an analysis is already running for this buffer", vim.log.levels.WARN)
		return
	end

	local path, err = cli.binary()
	if not path then
		notify(err, vim.log.levels.ERROR)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local model_path, copy_err, scratch_dir = model_source(bufnr, lines)
	if not model_path then
		notify(copy_err, vim.log.levels.ERROR)
		return
	end

	local features = cli.features()
	local args = { "verify" }
	local sessions = opts.sessions or config.get("sessions")
	if sessions and features.sessions then
		vim.list_extend(args, { "--sessions", tostring(sessions) })
	end
	if features.json then
		vim.list_extend(args, { "--format", "json" })
	else
		args[#args + 1] = "--result-code"
		if features.quiet then
			args[#args + 1] = "--quiet"
		end
		if features.color then
			vim.list_extend(args, { "--color", "never" })
		end
	end
	args[#args + 1] = model_path

	s.cancelled = false
	s.started_at = vim.uv.now()
	if not opts.silent then
		vim.api.nvim_echo({ { "Verifpal: analyzing…", "Comment" } }, false, {})
	end
	ticker_start()
	announce("VerifpalVerifyStart", bufnr)

	s.handle = cli.run(args, {}, function(result)
		s.handle = nil
		ticker_stop()
		cleanup(scratch_dir)
		local cancelled = s.cancelled
		s.cancelled = false
		if cancelled then
			if not opts.silent then
				vim.api.nvim_echo({ { "Verifpal: analysis cancelled", "Comment" } }, false, {})
			end
			return
		end

		local report
		if features.json then
			report = report_from_json(result.stdout)
		elseif result.code == 0 then
			report = report_from_text(result.stdout)
		end

		if not report then
			local text = vim.trim(result.stderr)
			if text == "" then
				text = vim.trim(result.stdout)
			end
			if result.timed_out then
				text = string.format(
					"analysis timed out after %d ms; raise `timeout` or lower `sessions`",
					config.get("timeout")
				)
			end
			if text == "" then
				text = "verifpal produced no output"
			end
			report = { error = text }
		end

		report.queries = report.queries or {}
		s.report = report
		M.apply_diagnostics(bufnr, report)

		if report.error then
			local parsed = cli.parse_error(report.error)
			notify(parsed and parsed.headline or report.error, vim.log.levels.ERROR)
		elseif not opts.silent then
			local text, level = summarise(report)
			notify(text, level)
		end

		announce("VerifpalVerifyDone", bufnr)
		if opts.on_done then
			opts.on_done(report)
		end
	end)

	if not s.handle then
		cleanup(scratch_dir)
	end
end

return M
