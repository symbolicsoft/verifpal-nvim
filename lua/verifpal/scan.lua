-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- A lexer for the Verifpal language, good enough for everything the editor
--- needs to know structurally: where the queries are, how deeply a line nests,
--- and where a block begins and ends.
---
--- The language has no string literals, so comments and brackets are the whole
--- lexical story — which is why this is a scanner and not a parser. Blanking
--- comments before looking at brackets is the point: a `]` inside a comment
--- used to close the queries block early and shift every diagnostic after it
--- onto the wrong line.

local M = {}

local QUERY_KINDS = {
	confidentiality = true,
	authentication = true,
	freshness = true,
	unlinkability = true,
	equivalence = true,
}

M.QUERY_KINDS = QUERY_KINDS

--- Tokenize `lines` (1-based list of strings) into words and punctuation,
--- carrying 0-based positions and the bracket depth each token sits at.
---
--- A `[` reports the depth *outside* it and a `]` the depth it returns to, so
--- both brackets of a block carry the same depth and the block's contents sit
--- one deeper.
---@param lines string[]
---@return table[] tokens
function M.tokens(lines)
	local tokens = {}
	local in_block_comment = false
	local depth = 0
	for i = 1, #lines do
		local line = lines[i]
		local n = #line
		local j = 1
		while j <= n do
			if in_block_comment then
				local _, e = line:find("*/", j, true)
				if e then
					in_block_comment = false
					j = e + 1
				else
					j = n + 1
				end
			else
				local c = line:sub(j, j)
				local nxt = line:sub(j + 1, j + 1)
				if c == "/" and nxt == "/" then
					j = n + 1
				elseif c == "/" and nxt == "*" then
					in_block_comment = true
					j = j + 2
				elseif c:match("[%a_]") then
					local word = line:match("^[%a_][%w_]*", j)
					tokens[#tokens + 1] = {
						kind = "word",
						text = word,
						lnum = i - 1,
						col = j - 1,
						depth = depth,
					}
					j = j + #word
				elseif c == "[" then
					tokens[#tokens + 1] =
						{ kind = "punct", text = c, lnum = i - 1, col = j - 1, depth = depth }
					depth = depth + 1
					j = j + 1
				elseif c == "]" then
					depth = math.max(0, depth - 1)
					tokens[#tokens + 1] =
						{ kind = "punct", text = c, lnum = i - 1, col = j - 1, depth = depth }
					j = j + 1
				elseif c:match("%s") then
					j = j + 1
				else
					tokens[#tokens + 1] =
						{ kind = "punct", text = c, lnum = i - 1, col = j - 1, depth = depth }
					j = j + 1
				end
			end
		end
	end
	return tokens
end

--- Bracket depth at the start and end of every line, and whether the line's
--- first token is a closing bracket. Folding and indenting both read this.
---@param lines string[]
---@return table[] one entry per line: { start = n, finish = n, closes = bool }
function M.depths(lines)
	local tokens = M.tokens(lines)
	local per_line = {}
	for i = 1, #lines do
		per_line[i] = { start = 0, finish = 0, closes = false }
	end
	local depth = 0
	local index = 1
	for i = 1, #lines do
		per_line[i].start = depth
		local first = true
		while index <= #tokens and tokens[index].lnum == i - 1 do
			local tok = tokens[index]
			if tok.kind == "punct" and tok.text == "[" then
				depth = tok.depth + 1
			elseif tok.kind == "punct" and tok.text == "]" then
				depth = tok.depth
				if first then
					per_line[i].closes = true
				end
			end
			first = false
			index = index + 1
		end
		per_line[i].finish = depth
	end
	return per_line
end

--- Every query written in the model's `queries` block, in model order — which
--- is the order verifpal reports results in, and therefore the order that maps
--- a result onto a line.
---
--- A query is anchored on its kind keyword followed by `?` at the top level of
--- the block, so a query carrying an option block (`authentication? A -> B: x[
--- precondition[...] ]`) counts once no matter how many lines it spans, and a
--- `precondition` inside one is not mistaken for a query of its own.
---@param lines string[]
---@return table[] queries { lnum, col, end_col, kind }
---@return table|nil block { start_lnum, end_lnum }
function M.queries(lines)
	local tokens = M.tokens(lines)
	local queries = {}
	local block = nil
	local i = 1
	while i <= #tokens do
		local tok = tokens[i]
		if not block then
			local opener = tokens[i + 1]
			if
				tok.kind == "word"
				and tok.text:lower() == "queries"
				and tok.depth == 0
				and opener
				and opener.kind == "punct"
				and opener.text == "["
			then
				block = { start_lnum = tok.lnum, end_lnum = nil }
				i = i + 1
			end
		else
			if tok.kind == "punct" and tok.text == "]" and tok.depth == 0 then
				block.end_lnum = tok.lnum
				break
			end
			if tok.kind == "word" and tok.depth == 1 and QUERY_KINDS[tok.text:lower()] then
				local mark = tokens[i + 1]
				if mark and mark.kind == "punct" and mark.text == "?" then
					queries[#queries + 1] = {
						lnum = tok.lnum,
						col = tok.col,
						end_col = mark.col + 1,
						kind = tok.text:lower(),
					}
					i = i + 1
				end
			end
		end
		i = i + 1
	end
	if block and not block.end_lnum then
		block.end_lnum = #lines - 1
	end
	return queries, block
end

--- Strip comments from a line, replacing them with spaces so every remaining
--- character keeps its column. Used by the completion context probe.
---@param lines string[]
---@return string[]
function M.blank_comments(lines)
	local out = {}
	local in_block_comment = false
	for i = 1, #lines do
		local line = lines[i]
		local chars = {}
		local n = #line
		local j = 1
		while j <= n do
			local c = line:sub(j, j)
			local nxt = line:sub(j + 1, j + 1)
			if in_block_comment then
				chars[#chars + 1] = " "
				if c == "*" and nxt == "/" then
					chars[#chars + 1] = " "
					in_block_comment = false
					j = j + 1
				end
			elseif c == "/" and nxt == "/" then
				for _ = j, n do
					chars[#chars + 1] = " "
				end
				j = n
			elseif c == "/" and nxt == "*" then
				in_block_comment = true
				chars[#chars + 1] = " "
				chars[#chars + 1] = " "
				j = j + 1
			else
				chars[#chars + 1] = c
			end
			j = j + 1
		end
		out[i] = table.concat(chars)
	end
	return out
end

return M
