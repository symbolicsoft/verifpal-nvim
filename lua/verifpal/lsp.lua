-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local config = require("verifpal.config")

local M = {}

local NAME = "verifpal"

local reports = {}
local running = {}
local listeners = {}

local function notify(message, level)
	if not config.get("notify") then
		return
	end
	vim.schedule(function()
		vim.notify("Verifpal: " .. message, level or vim.log.levels.INFO, { title = "Verifpal" })
	end)
end

local function normalise(report)
	local out = {
		code = report.code,
		sessions = report.sessions,
		elapsed_ms = report.elapsedMs,
		attacks = report.attacks,
		error = report.error,
		queries = {},
		assumptions = {},
	}
	for _, a in ipairs(report.assumptions or {}) do
		out.assumptions[#out.assumptions + 1] = {
			term = a.term,
			capability = a.capability,
			from_phase = a.fromPhase,
		}
	end
	for _, q in ipairs(report.queries or {}) do
		local trace = {}
		for i, step in ipairs(q.steps or {}) do
			trace[i] = string.format("%d. %s", i, step.text)
		end
		out.queries[#out.queries + 1] = {
			query = q.query,
			kind = q.kind,
			resolved = q.resolved,
			conclusion = q.conclusion,
			summary = q.summary,
			trace = trace,
			preconditions = q.preconditions or {},
			line = q.range and q.range.line or 1,
			column = q.range and q.range.column or 1,
		}
	end
	return out
end

local function on_report(report)
	local uri = report.uri
	running[uri] = nil
	if not report.ok then
		reports[uri] = report.cancelled and nil or normalise(report)
		if report.cancelled then
			notify("analysis cancelled")
		elseif report.error then
			notify(report.error, vim.log.levels.ERROR)
		end
	else
		reports[uri] = normalise(report)
		local r = reports[uri]
		local attacks = r.attacks or 0
		notify(
			string.format(
				"%s  ·  %d of %d contradicted",
				r.code or "",
				attacks,
				#r.queries
			),
			attacks > 0 and vim.log.levels.WARN or vim.log.levels.INFO
		)
	end
	local waiting = listeners[uri] or {}
	listeners[uri] = nil
	for _, fn in ipairs(waiting) do
		pcall(fn, reports[uri])
	end
	pcall(vim.api.nvim_exec_autocmds, "User", {
		pattern = "VerifpalVerifyDone",
		data = { uri = uri, report = reports[uri] },
	})
end

function M.setup()
	if vim.lsp.config == nil then
		return false
	end
	local cli = require("verifpal.cli")
	local binary, why = cli.binary()
	if not binary then
		notify(why .. "; install it from https://verifpal.com", vim.log.levels.ERROR)
		return false
	end
	if not cli.supports_lsp() then
		notify(
			"this verifpal has no `lsp` subcommand; upgrade to 1.1 or newer",
			vim.log.levels.ERROR
		)
		return false
	end
	vim.lsp.config(NAME, {
		cmd = { binary, "lsp", "--stdio" },
		filetypes = { "verifpal" },
		root_markers = { ".git" },
		single_file_support = true,
		settings = {
			verifpal = {
				validateOnType = true,
				sessions = config.get("sessions"),
			},
		},
		handlers = {
			["verifpal/analysisReport"] = function(_, result)
				if result then
					on_report(result)
				end
			end,
		},
	})
	vim.lsp.enable(NAME)
	return true
end

function M.client(bufnr)
	local clients = vim.lsp.get_clients({ bufnr = bufnr or 0, name = NAME })
	return clients[1]
end

function M.uri(bufnr)
	return vim.uri_from_bufnr(bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr)
end

function M.command(bufnr, command, arguments, on_result)
	local client = M.client(bufnr)
	if not client then
		return false
	end
	client:request("workspace/executeCommand", {
		command = command,
		arguments = arguments,
	}, function(err, result)
		if on_result then
			on_result(err, result)
		end
	end, bufnr)
	return true
end

function M.verify(bufnr, opts)
	opts = opts or {}
	local uri = M.uri(bufnr)
	local sessions = opts.sessions or config.get("sessions")
	local ok = M.command(bufnr, "verifpal.analyze", { { uri = uri, sessions = sessions } }, function(err, result)
		if err or not result or not result.accepted then
			running[uri] = nil
			notify("the language server declined to analyze this buffer", vim.log.levels.ERROR)
		end
	end)
	if not ok then
		notify("the language server is not attached to this buffer", vim.log.levels.ERROR)
		return false
	end
	running[uri] = true
	reports[uri] = nil
	if opts.on_done then
		listeners[uri] = listeners[uri] or {}
		table.insert(listeners[uri], opts.on_done)
	end
	return true
end

function M.cancel(bufnr)
	local uri = M.uri(bufnr)
	if not running[uri] then
		return false
	end
	M.command(bufnr, "verifpal.cancelAnalysis", { { uri = uri } })
	running[uri] = nil
	return true
end

function M.clear(bufnr)
	local uri = M.uri(bufnr)
	reports[uri] = nil
	running[uri] = nil
	local client = M.client(bufnr)
	if client then
		local ns = vim.lsp.diagnostic.get_namespace(client.id, false)
		vim.diagnostic.reset(ns, bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr)
	end
end

function M.report(bufnr)
	return reports[M.uri(bufnr)]
end

function M.running(bufnr)
	return running[M.uri(bufnr)] == true
end

local SPINNER = { "|", "/", "-", "\\" }

function M.status(bufnr)
	local uri = M.uri(bufnr)
	if running[uri] then
		local frame = math.floor(vim.uv.now() / 120) % #SPINNER + 1
		return SPINNER[frame] .. " Verifpal"
	end
	local report = reports[uri]
	if not report or not report.code then
		return ""
	end
	local attacks = report.attacks or 0
	return string.format("%s %s", attacks > 0 and "✗" or "✓", report.code)
end

function M.diagram(bufnr, on_result)
	return M.command(bufnr, "verifpal.diagram", { { uri = M.uri(bufnr) } }, on_result)
end

return M
