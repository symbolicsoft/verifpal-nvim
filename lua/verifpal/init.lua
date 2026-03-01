-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local M = {}

--- Path to the verifpal binary. Override via setup({ path = "..." }).
M.path = "verifpal"

--- Namespace for diagnostics.
local ns = vim.api.nvim_create_namespace("verifpal")

-- -------------------------------------------------------------------------
-- Setup
-- -------------------------------------------------------------------------

function M.setup(opts)
	opts = opts or {}
	if opts.path then
		M.path = opts.path
	end

	vim.filetype.add({
		extension = { vp = "verifpal" },
	})

	vim.api.nvim_create_user_command("VerifpalVerify", function()
		M.verify()
	end, { desc = "Run Verifpal attacker analysis on the current buffer" })

	vim.api.nvim_create_user_command("VerifpalFormat", function()
		M.format()
	end, { desc = "Format the current buffer with verifpal pretty" })

	-- K hover for .vp files
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "verifpal",
		callback = function(ev)
			vim.keymap.set("n", "K", function()
				M.hover()
			end, { buffer = ev.buf, desc = "Verifpal: show primitive/query help" })
		end,
	})
end

-- -------------------------------------------------------------------------
-- Format
-- -------------------------------------------------------------------------

function M.format()
	local bufnr = vim.api.nvim_get_current_buf()
	local file = vim.api.nvim_buf_get_name(bufnr)
	if file == "" then
		vim.notify("Verifpal: buffer has no file name", vim.log.levels.ERROR)
		return
	end
	-- Write unsaved changes before formatting
	vim.cmd("silent write")
	local result = vim.fn.system({ M.path, "pretty", file })
	if vim.v.shell_error ~= 0 then
		vim.notify("Verifpal: format failed:\n" .. result, vim.log.levels.ERROR)
		return
	end
	local lines = vim.split(result, "\n", { trimempty = false })
	-- Remove trailing empty line that verifpal pretty adds
	if #lines > 0 and lines[#lines] == "" then
		table.remove(lines)
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

-- -------------------------------------------------------------------------
-- Verify
-- -------------------------------------------------------------------------

function M.verify()
	local bufnr = vim.api.nvim_get_current_buf()
	local file = vim.api.nvim_buf_get_name(bufnr)
	if file == "" then
		vim.notify("Verifpal: buffer has no file name", vim.log.levels.ERROR)
		return
	end
	vim.cmd("silent write")

	-- Build a map of query lines: line_number -> query text
	local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local query_lines = {}
	local in_queries = false
	for i, line in ipairs(buf_lines) do
		local trimmed = line:match("^%s*(.-)%s*$")
		if trimmed:match("^queries%s*%[") then
			in_queries = true
		elseif in_queries then
			if trimmed == "]" then
				in_queries = false
			elseif trimmed:match("^//") then
				-- skip comments
			elseif trimmed ~= "" then
				table.insert(query_lines, { lnum = i - 1, text = trimmed })
			end
		end
	end

	-- Run verifpal verify --result-code
	local code = vim.fn.system({ M.path, "verify", "--result-code", file })
	if vim.v.shell_error ~= 0 then
		vim.notify("Verifpal: verification failed:\n" .. code, vim.log.levels.ERROR)
		return
	end
	code = code:match("^%s*(.-)%s*$") -- trim whitespace

	-- Parse result code: pairs of (type_char, result_char)
	local results = {}
	for i = 1, #code, 2 do
		local kind = code:sub(i, i)
		local resolved = code:sub(i + 1, i + 1) == "1"
		table.insert(results, { kind = kind, resolved = resolved })
	end

	-- Map query type chars to names
	local kind_names = {
		c = "confidentiality",
		a = "authentication",
		f = "freshness",
		u = "unlinkability",
		e = "equivalence",
	}

	-- Set diagnostics
	vim.diagnostic.reset(ns, bufnr)
	local diagnostics = {}
	for idx, r in ipairs(results) do
		local ql = query_lines[idx]
		if ql then
			local kind_name = kind_names[r.kind] or r.kind
			if r.resolved then
				table.insert(diagnostics, {
					lnum = ql.lnum,
					col = 0,
					severity = vim.diagnostic.severity.ERROR,
					source = "verifpal",
					message = kind_name .. " query FAILS",
				})
			else
				table.insert(diagnostics, {
					lnum = ql.lnum,
					col = 0,
					severity = vim.diagnostic.severity.INFO,
					source = "verifpal",
					message = kind_name .. " query passes",
				})
			end
		end
	end
	vim.diagnostic.set(ns, bufnr, diagnostics)

	local fail_count = 0
	for _, r in ipairs(results) do
		if r.resolved then
			fail_count = fail_count + 1
		end
	end
	if fail_count == 0 then
		vim.notify("Verifpal: all " .. #results .. " queries pass.", vim.log.levels.INFO)
	else
		vim.notify(
			"Verifpal: " .. fail_count .. " of " .. #results .. " queries failed.",
			vim.log.levels.WARN
		)
	end
end

-- -------------------------------------------------------------------------
-- Hover documentation
-- -------------------------------------------------------------------------

local primitive_docs = {
	ASSERT = {
		sig = "ASSERT(a, b)?",
		doc = "Checks that a and b are equal. Must be used as a checked primitive (?).",
	},
	CONCAT = {
		sig = "CONCAT(a, b, ...): c",
		doc = "Concatenates 2-5 values. Arguments are individually extractable by the attacker.",
	},
	SPLIT = {
		sig = "a, b, ... = SPLIT(c)?",
		doc = "Splits a concatenated value back into its components. Must be used as a checked primitive (?).",
	},
	PW_HASH = {
		sig = "PW_HASH(a, ...): h",
		doc = "Password hash. Protects all arguments from offline guessing.",
	},
	HASH = {
		sig = "HASH(a, ...): h",
		doc = "Cryptographic hash function. Takes 1-5 arguments. One-way: the attacker cannot recover inputs from the hash.",
	},
	HKDF = {
		sig = "k1, k2, ... = HKDF(salt, ikm, info)",
		doc = "Hash-based key derivation function. Derives 1-5 keys from a salt, input keying material, and info string.",
	},
	AEAD_ENC = {
		sig = "AEAD_ENC(key, plaintext, ad): ciphertext",
		doc = "Authenticated encryption with associated data. The associated data (ad) is always visible to the attacker.",
	},
	AEAD_DEC = {
		sig = "AEAD_DEC(key, ciphertext, ad)?: plaintext",
		doc = "Authenticated decryption. Undoes AEAD_ENC when keys and associated data match. Typically used as a checked primitive (?).",
	},
	ENC = {
		sig = "ENC(key, plaintext): ciphertext",
		doc = "Symmetric encryption. The attacker can decrypt if they know the key.",
	},
	DEC = {
		sig = "DEC(key, ciphertext): plaintext",
		doc = "Symmetric decryption. Undoes ENC when the key matches.",
	},
	MAC = {
		sig = "MAC(key, message): tag",
		doc = "Message authentication code. Produces a tag that can be verified by anyone who knows the key.",
	},
	SIGN = {
		sig = "SIGN(private_key, message): signature",
		doc = "Digital signature using a private key. Verified with SIGNVERIF using the corresponding public key G^private_key.",
	},
	SIGNVERIF = {
		sig = "SIGNVERIF(public_key, message, signature)?: nil",
		doc = "Signature verification. Checks that the signature was produced by the private key corresponding to the public key. Must be used as a checked primitive (?).",
	},
	PKE_ENC = {
		sig = "PKE_ENC(public_key, plaintext): ciphertext",
		doc = "Public-key encryption. Encrypts to a DH public key (G^sk). The holder of sk can decrypt.",
	},
	PKE_DEC = {
		sig = "PKE_DEC(private_key, ciphertext): plaintext",
		doc = "Public-key decryption. Undoes PKE_ENC when the private key corresponds to the public key used for encryption.",
	},
	SHAMIR_SPLIT = {
		sig = "s1, s2, s3 = SHAMIR_SPLIT(secret)",
		doc = "Shamir secret sharing (2-of-3). Splits a secret into 3 shares; any 2 shares can reconstruct the secret.",
	},
	SHAMIR_JOIN = {
		sig = "SHAMIR_JOIN(share_a, share_b): secret",
		doc = "Reconstructs a Shamir-split secret from 2 shares. The shares must come from the same SHAMIR_SPLIT.",
	},
	RINGSIGN = {
		sig = "RINGSIGN(sk, pk2, pk3, message): signature",
		doc = "Ring signature. Signs a message so that it can be verified against any of the three public keys, without revealing which private key was used.",
	},
	RINGSIGNVERIF = {
		sig = "RINGSIGNVERIF(pk1, pk2, pk3, message, signature)?: nil",
		doc = "Ring signature verification. Checks that the signature was produced by one of the three private keys. Must be used as a checked primitive (?).",
	},
	BLIND = {
		sig = "BLIND(blinding_factor, message): blinded",
		doc = "Blinds a message with a blinding factor. Used in blind signature schemes.",
	},
	UNBLIND = {
		sig = "UNBLIND(blinding_factor, blind_signature, message): signature",
		doc = "Removes blinding from a blind signature, producing a standard signature on the original message.",
	},
}

local query_docs = {
	confidentiality = "Checks whether a given value can be obtained by the attacker.",
	authentication = "Checks whether a value received by one principal was actually sent by the claimed sender.",
	freshness = "Checks whether a value contains a fresh (generated) component, preventing replay.",
	unlinkability = "Checks whether two values are unlinkable — the attacker cannot determine if they came from the same source.",
	equivalence = "Checks whether two or more values are equivalent from the attacker's perspective.",
}

local keyword_docs = {
	principal = "Declares a protocol principal (participant). Contains knowledge declarations and computations.",
	phase = "Declares a protocol phase boundary. Used to model key compromise: values leaked in phase N are available to the attacker from phase N onward.",
	queries = "Declares security queries to be verified against the attacker model.",
	attacker = "Declares the attacker model: active (can intercept and modify messages) or passive (can only observe).",
	knows = "Declares initial knowledge: 'knows public x' (attacker knows), 'knows private x' (attacker doesn't), 'knows password x' (protected by PW_HASH).",
	generates = "Declares freshly generated random values. These are private to the principal and marked as fresh for replay detection.",
	leaks = "Declares that a value is leaked to the attacker in the current phase.",
	public = "Qualifier: the value is known to all principals and the attacker.",
	private = "Qualifier: the value is known only to the declaring principal.",
	password = "Qualifier: the value is a password, protected from offline guessing when used inside PW_HASH.",
	precondition = "Query option: the query result is only meaningful if the precondition message was actually sent.",
}

function M.hover()
	local word = vim.fn.expand("<cword>")
	if word == "" then
		return
	end

	-- Check primitives
	local prim = primitive_docs[word]
	if prim then
		local lines = { "**" .. word .. "**", "", "`" .. prim.sig .. "`", "", prim.doc }
		vim.lsp.util.open_floating_preview(lines, "markdown", { focus = false })
		return
	end

	-- Check query types
	local qdoc = query_docs[word]
	if qdoc then
		local lines = { "**" .. word .. "** query", "", qdoc }
		vim.lsp.util.open_floating_preview(lines, "markdown", { focus = false })
		return
	end

	-- Check keywords
	local kdoc = keyword_docs[word]
	if kdoc then
		local lines = { "**" .. word .. "**", "", kdoc }
		vim.lsp.util.open_floating_preview(lines, "markdown", { focus = false })
		return
	end

	-- G and nil
	if word == "G" then
		vim.lsp.util.open_floating_preview(
			{ "**G**", "", "The Diffie-Hellman generator. `G^a` is a DH public key; `G^a^b = G^b^a` by commutativity." },
			"markdown",
			{ focus = false }
		)
		return
	end
	if word == "nil" then
		vim.lsp.util.open_floating_preview(
			{ "**nil**", "", "The null/empty value. Also used as the attacker's canonical known private key." },
			"markdown",
			{ focus = false }
		)
		return
	end
end

return M
