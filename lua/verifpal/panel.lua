-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- Scratch windows: the results panel and the protocol diagram.
---
--- The results panel exists because the interesting half of a verdict does not
--- fit in a diagnostic. When a query is contradicted, verifpal minimizes the
--- attack and narrates what remains as numbered causal steps, in the names the
--- model gave the values. Those steps are the reason to trust the verdict, and
--- reading them is how a modelling mistake is told apart from a real attack.

local config = require("verifpal.config")

local M = {}

local ns = vim.api.nvim_create_namespace("verifpal-panel")

--- One reusable window per kind, so repeated runs update in place instead of
--- stacking splits.
local windows = {}

local function close(kind)
	local entry = windows[kind]
	if entry and entry.win and vim.api.nvim_win_is_valid(entry.win) then
		-- Closing the last window is an error, not a no-op, and a panel can
		-- legitimately be the only one left.
		pcall(vim.api.nvim_win_close, entry.win, true)
	end
	if entry and entry.buf and vim.api.nvim_buf_is_valid(entry.buf) then
		pcall(vim.api.nvim_buf_delete, entry.buf, { force = true })
	end
	windows[kind] = nil
end

M.close = close

--- Open (or reuse) a scratch window and fill it with `lines`.
---@param kind string
---@param name string
---@param lines string[]
---@param highlights table[] { lnum, col, end_col, group }
---@param on_enter fun(buf: integer, win: integer)|nil
local function render(kind, name, lines, highlights, on_enter)
	local origin = vim.api.nvim_get_current_win()
	local entry = windows[kind]

	if not (entry and entry.buf and vim.api.nvim_buf_is_valid(entry.buf)) then
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].swapfile = false
		vim.api.nvim_buf_set_name(buf, name)
		entry = { buf = buf }
		windows[kind] = entry
	end

	if not (entry.win and vim.api.nvim_win_is_valid(entry.win)) then
		local split = config.get("panel.split") or "botright"
		local height = config.get("panel.height") or 20
		vim.cmd(string.format("%s %dsplit", split, height))
		entry.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(entry.win, entry.buf)
		-- Conclusions and trace steps are prose, and a trace step is often
		-- wider than a split. Wrapping with 'breakindent' keeps a wrapped step
		-- aligned under the step it belongs to.
		vim.wo[entry.win].wrap = true
		vim.wo[entry.win].linebreak = true
		vim.wo[entry.win].breakindent = true
		vim.wo[entry.win].number = false
		vim.wo[entry.win].relativenumber = false
		vim.wo[entry.win].signcolumn = "no"
		vim.wo[entry.win].spell = false
		vim.wo[entry.win].cursorline = true
	end

	vim.bo[entry.buf].modifiable = true
	vim.api.nvim_buf_set_lines(entry.buf, 0, -1, false, lines)
	vim.bo[entry.buf].modifiable = false
	vim.bo[entry.buf].modified = false

	vim.api.nvim_buf_clear_namespace(entry.buf, ns, 0, -1)
	for _, hl in ipairs(highlights or {}) do
		pcall(vim.api.nvim_buf_set_extmark, entry.buf, ns, hl.lnum, hl.col, {
			end_col = hl.end_col,
			hl_group = hl.group,
		})
	end

	vim.keymap.set("n", "q", function()
		close(kind)
	end, { buffer = entry.buf, nowait = true, desc = "Verifpal: close panel" })

	if on_enter then
		on_enter(entry.buf, entry.win)
	end

	if config.get("panel.focus") then
		vim.api.nvim_set_current_win(entry.win)
	elseif vim.api.nvim_win_is_valid(origin) then
		vim.api.nvim_set_current_win(origin)
	end
	return entry.buf, entry.win
end

-- ---------------------------------------------------------------------------
-- Results panel
-- ---------------------------------------------------------------------------

--- A horizontal rule as wide as `text` renders, not as many bytes as it
--- occupies: the em dash in a header is three bytes and one column.
local function rule(text)
	local width = type(text) == "number" and text or vim.fn.strdisplaywidth(text)
	return string.rep("─", math.max(width, 8))
end

--- Build the panel's text and the highlight spans over it.
---@param report table
---@param model_name string
function M.render_report(report, model_name)
	local lines, hl, jumps = {}, {}, {}

	local function add(text, group, col, end_col)
		lines[#lines + 1] = text
		if group then
			hl[#hl + 1] = {
				lnum = #lines - 1,
				col = col or 0,
				end_col = end_col or #text,
				group = group,
			}
		end
		return #lines - 1
	end

	local header = "Verifpal — " .. (model_name or "model")
	add(header, "Title")

	if report.error then
		add(rule(header), "Comment")
		add("")
		for _, line in ipairs(vim.split(report.error, "\n", { plain = true })) do
			add(line, "DiagnosticError")
		end
		return lines, hl, jumps
	end

	local facts = {}
	if report.code and report.code ~= "" then
		facts[#facts + 1] = report.code
	end
	if report.sessions then
		facts[#facts + 1] = report.sessions .. " sessions"
	end
	if report.elapsed_ms then
		facts[#facts + 1] = report.elapsed_ms .. " ms"
	end
	local total = #report.queries
	local attacks = report.attacks or 0
	facts[#facts + 1] = attacks == 0
			and string.format("%d quer%s hold", total, total == 1 and "y" or "ies")
		or string.format("%d of %d contradicted", attacks, total)
	add(table.concat(facts, "  ·  "), "Comment")
	add(rule(header), "Comment")

	if report.assumptions and #report.assumptions > 0 then
		add("")
		add(
			string.format(
				"Declared weakening assumption%s — every verdict below is conditional on %s:",
				#report.assumptions == 1 and "" or "s",
				#report.assumptions == 1 and "it" or "them"
			),
			"WarningMsg"
		)
		for _, a in ipairs(report.assumptions) do
			local term = a.term or "?"
			if a.from_phase and a.from_phase > 0 then
				term = term .. "  (from phase " .. a.from_phase .. ")"
			end
			add("  " .. term, "DiagnosticWarn")
		end
	end

	if total == 0 then
		add("")
		add("This model declares no queries, so there is nothing to verify.", "Comment")
		return lines, hl, jumps
	end

	for index, result in ipairs(report.queries) do
		add("")
		local verdict = result.resolved and "FAIL" or "PASS"
		local group = result.resolved and "DiagnosticError" or "DiagnosticOk"
		local label = result.query
		if not label or label == "" then
			label = (result.kind or "query") .. "?"
		end
		local lnum = add(verdict .. "  " .. label, group, 0, #verdict)
		jumps[lnum] = index

		if result.conclusion and result.conclusion ~= "" then
			for _, part in ipairs(vim.split(result.conclusion, "\n", { plain = true })) do
				add("      " .. part, "Normal")
			end
		end
		for _, step in ipairs(result.trace or {}) do
			add("      " .. step, "Comment")
		end
		for _, precondition in ipairs(result.preconditions or {}) do
			add("      " .. precondition, "DiagnosticHint")
		end
	end

	if report.degraded then
		add("")
		add(
			"This verifpal predates `verify --format json`; upgrade for narrated attack traces.",
			"DiagnosticHint"
		)
	end

	return lines, hl, jumps
end

--- Show a verification report. `<CR>` on a query jumps to it in the model.
---@param report table
---@param source_buf integer
function M.results(report, source_buf)
	local name = vim.api.nvim_buf_get_name(source_buf)
	name = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]"
	local lines, hl, jumps = M.render_report(report, name)

	render("results", "verifpal://results", lines, hl, function(buf)
		vim.keymap.set("n", "<CR>", function()
			local cursor = vim.api.nvim_win_get_cursor(0)[1] - 1
			local index = jumps[cursor]
			if not index then
				return
			end
			if not vim.api.nvim_buf_is_valid(source_buf) then
				return
			end
			local query = (report.queries or {})[index]
			if not query or not query.line then
				return
			end
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_get_buf(win) == source_buf then
					vim.api.nvim_set_current_win(win)
					vim.api.nvim_win_set_cursor(win, { query.line, math.max((query.column or 1) - 1, 0) })
					vim.cmd("normal! zz")
					return
				end
			end
		end, { buffer = buf, nowait = true, desc = "Verifpal: jump to query" })
	end)
end

-- ---------------------------------------------------------------------------
-- Diagram
-- ---------------------------------------------------------------------------

--- Turn verifpal's mermaid-flavoured diagram body into something readable in a
--- terminal: each principal's steps indented under its name, and each message
--- on its own line between them.
---@param body string[] lines of `Note over X: ...` and `A->B:...`
---@return string[] lines, table[] highlights
function M.render_diagram(body)
	local lines, hl = {}, {}

	local function add(text, group)
		lines[#lines + 1] = text
		if group then
			hl[#hl + 1] = { lnum = #lines - 1, col = 0, end_col = #text, group = group }
		end
	end

	local current
	for _, raw in ipairs(body) do
		local line = vim.trim(raw)
		if line == "" or line == "sequenceDiagram" then
			goto continue
		end
		local who, note = line:match("^Note over ([^:]+):%s*(.*)$")
		if who then
			who = vim.trim(who)
			if who ~= current then
				if current then
					add("")
				end
				add(who, "Title")
				current = who
			end
			add("    " .. note, "Normal")
			goto continue
		end
		local sender, recipient, payload = line:match("^([%w_]+)%s*%-+>>?%s*([%w_]+)%s*:%s*(.*)$")
		if sender then
			if #lines > 0 then
				add("")
			end
			add(string.format("%s ──▶ %s :  %s", sender, recipient, payload), "Special")
			add("")
			current = nil
			goto continue
		end
		add(line, "Comment")
		current = nil
		::continue::
	end

	if #lines == 0 then
		add("This model describes no messages.", "Comment")
	end
	return lines, hl
end

--- Show a protocol diagram.
---@param body string[]
---@param model_name string
---@param raw boolean show the mermaid source instead of the rendered view
function M.diagram(body, model_name, raw)
	local lines, hl
	if raw then
		lines, hl = {}, {}
		for _, line in ipairs(body) do
			lines[#lines + 1] = line
		end
	else
		lines, hl = M.render_diagram(body)
	end
	local header = "Verifpal — " .. (model_name or "model")
	table.insert(lines, 1, header)
	table.insert(lines, 2, rule(header))
	table.insert(lines, 3, "")
	for _, entry in ipairs(hl) do
		entry.lnum = entry.lnum + 3
	end
	table.insert(hl, 1, { lnum = 0, col = 0, end_col = #header, group = "Title" })
	table.insert(hl, 2, { lnum = 1, col = 0, end_col = #rule(header), group = "Comment" })
	render("diagram", "verifpal://diagram", lines, hl)
end

return M
