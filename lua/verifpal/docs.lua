-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- Documentation for the Verifpal language, as the engine actually implements
--- it.
---
--- `arity`, `outputs`, `checked` and `assumptions` are transcribed from the
--- primitive spec table in verifpal's `src/primitive/spec.rs`. They are here
--- rather than derived at runtime because they are what a reader wants before
--- writing the call, and because hover has to work whether or not a binary is
--- installed. When a primitive changes in the engine, it changes here; the
--- test suite checks the list against `verifpal`'s own parser when a binary is
--- available.

local M = {}

--- All 25 built-in primitives. `assumptions` lists the declared weakening
--- assumptions the primitive accepts in its bracket parameter list.
M.primitives = {
	ASSERT = {
		sig = "ASSERT(value1, value2)?",
		arity = "2 arguments",
		outputs = 1,
		checked = "expected",
		doc = "Checks that two values are equal. It has no useful output: the `?` is the whole point, because that is what makes a mismatch halt the principal. Written unchecked it constrains nothing.",
	},
	CONCAT = {
		sig = "CONCAT(value1, value2, ...): concatenated",
		arity = "2 to 5 arguments",
		outputs = 1,
		doc = "Concatenates 2 to 5 values. The attacker can pull the arguments back out individually, so CONCAT hides nothing; it exists to carry several values where one is expected.",
	},
	SPLIT = {
		sig = "a, b, ... = SPLIT(concatenated)?",
		arity = "1 argument",
		outputs = "1 to 5",
		checked = "expected",
		doc = "Splits a concatenated value back into its components. Written checked, a value that was not a CONCAT of the right width halts the principal — which is usually what you want, since an unchecked SPLIT accepts whatever it is handed.",
	},
	HASH = {
		sig = "HASH(value1, ...): digest",
		arity = "1 to 5 arguments",
		outputs = 1,
		assumptions = { "weak" },
		doc = "Cryptographic hash. One-way: the attacker cannot recover the inputs from the digest, but can recompute the digest from inputs it already knows. HASH[weak] models a preimage attack, revealing every argument.",
	},
	PW_HASH = {
		sig = "PW_HASH(value1, ...): digest",
		arity = "1 to 5 arguments",
		outputs = 1,
		assumptions = { "weak" },
		doc = "Password hash. Unlike HASH, it protects a `knows password` argument from offline guessing: the attacker cannot confirm a guess even holding every other argument. PW_HASH[weak] gives that protection up.",
	},
	HKDF = {
		sig = "k1, k2, ... = HKDF(salt, ikm, info)",
		arity = "3 arguments",
		outputs = "1 to 5",
		doc = "Hash-based key derivation. Derives up to 5 independent keys from a salt, input keying material and an info string. Bind the outputs in one assignment: each is a distinct key.",
	},
	MAC = {
		sig = "MAC(key, message): tag",
		arity = "2 arguments",
		outputs = 1,
		assumptions = { "forgeable" },
		doc = "Message authentication code. Anyone holding the key can produce and check the tag. Verify one with `ASSERT(received, MAC(key, message))?`. MAC[forgeable] lets the attacker produce a tag without the key.",
	},
	AEAD_ENC = {
		sig = "AEAD_ENC(key, plaintext, ad): ciphertext",
		arity = "3 arguments",
		outputs = 1,
		assumptions = { "weak", "forgeable" },
		doc = "Authenticated encryption with associated data. `ad` is not encrypted, but AEAD_DEC must be given it exactly. Verifpal does not treat `ad` as recoverable from the ciphertext: send it on the wire if the attacker should see it.",
	},
	AEAD_DEC = {
		sig = "AEAD_DEC(key, ciphertext, ad)?: plaintext",
		arity = "3 arguments",
		outputs = 1,
		checked = "optional",
		doc = "Authenticated decryption. Undoes AEAD_ENC when the key and the associated data both match. Written with `?` it models a real AEAD: a forged or retargeted ciphertext halts the principal instead of yielding garbage.",
	},
	ENC = {
		sig = "ENC(key, plaintext): ciphertext",
		arity = "2 arguments",
		outputs = 1,
		assumptions = { "weak", "malleable" },
		doc = "Unauthenticated symmetric encryption. It hides the plaintext but vouches for nothing: anyone holding the key can decrypt, and nothing detects tampering. Prefer AEAD_ENC unless you mean to model a raw cipher.",
	},
	DEC = {
		sig = "DEC(key, ciphertext): plaintext",
		arity = "2 arguments",
		outputs = 1,
		doc = "Symmetric decryption. Undoes ENC when the key matches. It cannot be checked, because an unauthenticated cipher has nothing to check: a wrong key yields a value, not a failure.",
	},
	PUBKEY = {
		sig = "PUBKEY(private_key): public_key",
		arity = "1 argument",
		outputs = 1,
		assumptions = { "weak" },
		doc = "Derives the public key of a private value — think g^a. Used for Diffie-Hellman, signatures, public-key encryption and ring signatures. Its argument may not itself be a public key.",
	},
	DH_KEX = {
		sig = "DH_KEX(public_key, private_key): shared_secret",
		arity = "2 arguments",
		outputs = 1,
		doc = "Diffie-Hellman key exchange. DH_KEX(PUBKEY(a), b) and DH_KEX(PUBKEY(b), a) are the same value, which is how the shared secret is agreed. Its second argument may not be a public key, and it may not nest inside another DH_KEX.",
	},
	SIGN = {
		sig = "SIGN(private_key, message): signature",
		arity = "2 arguments",
		outputs = 1,
		assumptions = { "forgeable" },
		doc = "Digital signature. Checked with SIGNVERIF against PUBKEY(private_key). SIGN[forgeable] models a broken signature scheme: the attacker produces signatures without the private key.",
	},
	SIGNVERIF = {
		sig = "SIGNVERIF(public_key, message, signature)?",
		arity = "3 arguments",
		outputs = 1,
		checked = "expected",
		doc = "Signature verification against PUBKEY(private_key). Write it checked: an unchecked SIGNVERIF is a verification whose result nobody acts on, which is not authentication.",
	},
	PKE_ENC = {
		sig = "PKE_ENC(public_key, plaintext): ciphertext",
		arity = "2 arguments",
		outputs = 1,
		assumptions = { "weak" },
		doc = "Public-key encryption to PUBKEY(sk). Only the holder of sk can decrypt. It authenticates nothing: anyone can encrypt to a public key.",
	},
	PKE_DEC = {
		sig = "PKE_DEC(private_key, ciphertext): plaintext",
		arity = "2 arguments",
		outputs = 1,
		doc = "Public-key decryption. Undoes PKE_ENC when the private key matches the public key used to encrypt.",
	},
	SHAMIR_SPLIT = {
		sig = "s1, s2, s3 = SHAMIR_SPLIT(secret)",
		arity = "1 argument",
		outputs = 3,
		doc = "Shamir secret sharing, 2-of-3. Produces exactly three shares; any two of them reconstruct the secret and any one of them reveals nothing.",
	},
	SHAMIR_JOIN = {
		sig = "SHAMIR_JOIN(share_a, share_b): secret",
		arity = "2 arguments",
		outputs = 1,
		doc = "Reconstructs a secret from two distinct shares of the same SHAMIR_SPLIT. Two copies of one share do not reconstruct anything.",
	},
	RINGSIGN = {
		sig = "RINGSIGN(private_key, pk_b, pk_c, message): signature",
		arity = "4 arguments",
		outputs = 1,
		assumptions = { "forgeable" },
		doc = "Ring signature. The signer's own private key plus the public keys of the other two ring members. The signature verifies against the ring without revealing which member produced it.",
	},
	RINGSIGNVERIF = {
		sig = "RINGSIGNVERIF(pk_a, pk_b, pk_c, message, signature)?",
		arity = "5 arguments",
		outputs = 1,
		checked = "expected",
		doc = "Ring signature verification against all three public keys. It succeeds for a signature by any ring member and never tells you which — which is why an `unlinkability?` query over ring signatures holds where the same query over ordinary signatures fails.",
	},
	BLIND = {
		sig = "BLIND(blinding_factor, message): blinded",
		arity = "2 arguments",
		outputs = 1,
		doc = "Blinds a message so it can be signed without being read. The signer sees only the blinded value.",
	},
	UNBLIND = {
		sig = "UNBLIND(blinding_factor, message, blind_signature): signature",
		arity = "3 arguments",
		outputs = 1,
		doc = "Removes the blinding from a signature over BLIND(k, m), yielding an ordinary signature over m that SIGNVERIF accepts. Note the argument order: the original message is second and the blind signature third.",
	},
	KEM_ENCAP = {
		sig = "shared_secret, ciphertext = KEM_ENCAP(encapsulation_key, randomness)",
		arity = "2 arguments",
		outputs = 2,
		assumptions = { "weak" },
		doc = "Key encapsulation, for post-quantum KEMs such as ML-KEM. Produces two values: the shared secret and the ciphertext carrying it. The randomness must be a fresh `generates` value — reusing it reproduces the same shared secret.",
	},
	KEM_DECAP = {
		sig = "KEM_DECAP(decapsulation_key, ciphertext)?: shared_secret",
		arity = "2 arguments",
		outputs = 1,
		checked = "optional",
		doc = "Key decapsulation. Recovers the secret encapsulated to PUBKEY(dk). Its first argument must be the private decapsulation key, never a public key. Check it with `?` to model a KEM with explicit rejection.",
	},
}

--- The five query kinds, plus the option that may follow one.
M.queries = {
	confidentiality = {
		sig = "confidentiality? value",
		doc = "Fails when the attacker can obtain the value. This is the query for secrecy, and — with a `phase` after the key is leaked — for forward secrecy.",
	},
	authentication = {
		sig = "authentication? Sender -> Recipient: value",
		doc = "Fails when the recipient successfully uses a value the attacker authored rather than one the named sender produced. The recipient must actually compute with the value: storing it and never using it is not something authentication can be broken on, and Verifpal rejects such a query rather than answering it.",
	},
	freshness = {
		sig = "freshness? value",
		doc = "Fails when the value contains no freshly generated component, so an identical value could be replayed in another session. No attacker choice affects the answer: it is a property of how the model builds the value.",
	},
	unlinkability = {
		sig = "unlinkability? value_a, value_b",
		doc = "Fails when the attacker can exhibit a witness linking two or more observable values to a common origin — by holding both and seeing they are equal, by a verification that succeeds over both under one key, or by reconstructing both from one secret it holds.",
	},
	equivalence = {
		sig = "equivalence? value_a, value_b",
		doc = "Fails when the queried values do not all resolve to the same thing under attack — a key agreement in which the two sides end up with different keys. Halting a principal is not a divergence: a principal that aborted has no value to disagree with.",
	},
	precondition = {
		sig = "confidentiality? m[ precondition[ Bob -> Alice: ack ] ]",
		doc = "Query option. When the query fails, the result also reports whether the named message was still sent — the difference between an attack the protocol runs into and one it would abort before reaching.",
	},
}

--- Declared weakening assumptions, written between a primitive's name and its
--- arguments: PUBKEY[weak](a), AEAD_ENC[weak, forgeable from phase 2](k, m, ad).
M.assumptions = {
	weak = {
		sig = "AEAD_ENC[weak](key, plaintext, ad)",
		doc = "Confidentiality is lost: holding the term is enough to recover what it protects. Accepted by HASH and PW_HASH (a preimage, recovering every argument), AEAD_ENC, ENC and PKE_ENC (the plaintext), KEM_ENCAP (the shared secret), and PUBKEY (the private key). PUBKEY[weak] is the discrete logarithm problem falling, which makes every DH_KEX built on that key computable.",
	},
	forgeable = {
		sig = "SIGN[forgeable](private_key, message)",
		doc = "Authenticity is lost: the term becomes constructible without its secret argument. Accepted by SIGN, MAC, RINGSIGN and AEAD_ENC. Kept separate from `weak` so that AEAD_ENC[forgeable] can say the attacker may manufacture a ciphertext the recipient accepts while still being unable to read yours.",
	},
	malleable = {
		sig = "ENC[malleable](key, plaintext)",
		doc = "A ciphertext the attacker already holds can be reshaped into another the recipient still accepts — the symbolic shape of a bit-flipping attack on an unauthenticated cipher. Accepted by ENC alone, varying the plaintext. It licenses retargeting a ciphertext, not conjuring one: the attacker must already hold a term of the same shape under the same key.",
	},
	from = {
		sig = "PUBKEY[weak from phase 1](private_key)",
		doc = "Delays an assumption: it is not in force until the named phase, and holds from there onward. Cryptanalysis does not un-happen, which is why this reads `from` a phase rather than `in` one.",
	},
}

--- Block structure, declarations and qualifiers.
M.keywords = {
	attacker = {
		sig = "attacker[active]",
		doc = "Declares the attacker model, once, before any principal. `active` reads the network and may drop, replay or replace any unguarded value; `passive` only observes.",
	},
	active = {
		sig = "attacker[active]",
		doc = "Attacker model: reads every message and may drop, replay or replace anything not guarded with square brackets.",
	},
	passive = {
		sig = "attacker[passive]",
		doc = "Attacker model: observes the network and derives what it can, but alters nothing. Useful as a first pass — a query that fails against a passive attacker fails against any attacker.",
	},
	principal = {
		sig = "principal Alice[ ... ]",
		doc = "Declares a principal and what it does. A principal may be declared again later to continue after a message arrives. Names are title-cased, and there may be at most 128 of them.",
	},
	phase = {
		sig = "phase[1]",
		doc = "Opens a new protocol phase. Phases must increment by exactly 1. Everything the attacker learns in a later phase is unavailable to it earlier, which is what makes `phase` the way to model key compromise and to ask for forward secrecy.",
	},
	queries = {
		sig = "queries[ ... ]",
		doc = "The security properties to check. The block must exist and must come last: nothing may follow it.",
	},
	knows = {
		sig = "knows private long_term_key",
		doc = "Declares knowledge the principal starts with, qualified `public`, `private` or `password`. Two principals writing the same `knows private x` share that value.",
	},
	generates = {
		sig = "generates nonce",
		doc = "Declares a fresh random value, private to this principal and unique to this session. Freshness is what `freshness?` looks for and what stops a value being replayed.",
	},
	leaks = {
		sig = "leaks long_term_key",
		doc = "Hands a value the principal knows to the attacker, from this phase onward. Combined with `phase`, this is how a compromise is modelled.",
	},
	public = {
		sig = "knows public c0",
		doc = "Qualifier: known to every principal and to the attacker.",
	},
	private = {
		sig = "knows private k",
		doc = "Qualifier: known to the principals that declare it, and not to the attacker.",
	},
	password = {
		sig = "knows password pw",
		doc = "Qualifier: a low-entropy secret. The attacker can guess it offline wherever it appears, unless every enclosing use passes it through PW_HASH.",
	},
	nil_ = {
		sig = "nil",
		doc = "The empty value, and the attacker's own canonical private key: `PUBKEY(nil)` is the public key an active attacker substitutes when it wants a Diffie-Hellman share it can compute.",
	},
}

--- Anything the language recognises, addressed by the word under the cursor.
--- Lookup is case-insensitive because Verifpal is: `pubkey(a)` and `PUBKEY(a)`
--- are the same call, and `pretty` normalises the case for you.
---@param word string
---@return table|nil entry, string|nil category
function M.lookup(word)
	if not word or word == "" then
		return nil
	end
	local upper = word:upper()
	if M.primitives[upper] then
		return M.primitives[upper], "primitive"
	end
	local lower = word:lower()
	if M.assumptions[lower] then
		return M.assumptions[lower], "assumption"
	end
	if M.queries[lower] then
		return M.queries[lower], "query"
	end
	if lower == "nil" then
		return M.keywords.nil_, "keyword"
	end
	if lower ~= "nil_" and M.keywords[lower] then
		return M.keywords[lower], "keyword"
	end
	return nil
end

local function join(list, sep)
	return table.concat(list, sep)
end

--- Render an entry as markdown lines for a hover window.
---@param word string
---@param entry table
---@param category string
---@return string[]
function M.render(word, entry, category)
	local title = category == "primitive" and word:upper() or word:lower()
	local lines = { "**" .. title .. "**", "", "`" .. entry.sig .. "`", "" }

	local facts = {}
	if entry.arity then
		facts[#facts + 1] = entry.arity
	end
	if entry.outputs then
		local n = tostring(entry.outputs)
		facts[#facts + 1] = n == "1" and "1 output" or (n .. " outputs")
	end
	if entry.checked == "expected" then
		facts[#facts + 1] = "usually written checked (`?`)"
	elseif entry.checked == "optional" then
		facts[#facts + 1] = "may be written checked (`?`)"
	end
	if entry.assumptions then
		local marked = {}
		for _, name in ipairs(entry.assumptions) do
			marked[#marked + 1] = "`[" .. name .. "]`"
		end
		facts[#facts + 1] = "accepts " .. join(marked, ", ")
	end
	if #facts > 0 then
		lines[#lines + 1] = join(facts, " · ")
		lines[#lines + 1] = ""
	end

	lines[#lines + 1] = entry.doc
	return lines
end

--- Every completable word, with the metadata a completion menu wants.
---@return table[] { word, kind, menu, info }
function M.completions()
	local items = {}
	for name, entry in pairs(M.primitives) do
		items[#items + 1] = {
			word = name,
			kind = "primitive",
			menu = entry.sig,
			info = join(M.render(name, entry, "primitive"), "\n"),
		}
	end
	for name, entry in pairs(M.queries) do
		items[#items + 1] = {
			word = name,
			kind = "query",
			menu = entry.sig,
			info = join(M.render(name, entry, "query"), "\n"),
		}
	end
	for name, entry in pairs(M.assumptions) do
		items[#items + 1] = {
			word = name,
			kind = "assumption",
			menu = entry.sig,
			info = join(M.render(name, entry, "assumption"), "\n"),
		}
	end
	for name, entry in pairs(M.keywords) do
		if name ~= "nil_" then
			items[#items + 1] = {
				word = name,
				kind = "keyword",
				menu = entry.sig,
				info = join(M.render(name, entry, "keyword"), "\n"),
			}
		end
	end
	table.sort(items, function(a, b)
		return a.word < b.word
	end)
	return items
end

return M
