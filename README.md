# verifpal-nvim

Neovim plugin for [Verifpal](https://verifpal.com) — syntax highlighting, verification diagnostics, formatting, and hover documentation for `.vp` cryptographic protocol models.

## Installation

### lazy.nvim

```lua
{
  "symbolicsoft/verifpal-nvim",
  ft = "verifpal",
}
```

With a custom binary path:

```lua
{
  "symbolicsoft/verifpal-nvim",
  ft = "verifpal",
  opts = { path = "/usr/local/bin/verifpal" },
}
```

### packer.nvim

```lua
use {
  "symbolicsoft/verifpal-nvim",
  config = function() require("verifpal").setup() end,
}
```

## Features

### Verification Diagnostics

Run `:VerifpalVerify` to analyze the current model. Results appear as Neovim diagnostics on each query line — failed queries show as errors in the sign column, passing queries as info.

### Formatting

Run `:VerifpalFormat` to reformat the current buffer using `verifpal pretty`.

### Hover Documentation

Press `K` over any primitive, query type, or keyword to see contextual documentation in a floating window. Covers all 21 cryptographic primitives, 5 query types, and language keywords.

### Syntax Highlighting

Full highlighting for block keywords (`principal`, `phase`, `queries`, `attacker`), attacker modes (`active`, `passive`), declarations (`knows`, `generates`, `leaks`), qualifiers (`public`, `private`, `password`), query types (`confidentiality`, `authentication`, `freshness`, `unlinkability`, `equivalence`, `precondition`), all 21 primitives (`AEAD_ENC`, `AEAD_DEC`, `ENC`, `DEC`, `SIGN`, `SIGNVERIF`, `HASH`, `HKDF`, `PKE_ENC`, `PKE_DEC`, `SHAMIR_SPLIT`, `SHAMIR_JOIN`, `RINGSIGN`, `RINGSIGNVERIF`, `BLIND`, `UNBLIND`, `MAC`, `PW_HASH`, `ASSERT`, `CONCAT`, `SPLIT`), special values (`G`, `nil`), operators (`=`, `^`, `?`, `->`, `→`), and principal names, phase numbers, and delimiters.
### Comment Support

`commentstring` is set to `// %s` for `gc` (vim-commentary / Comment.nvim) and native comment toggling.

### Folding

Bracket-based folding on `principal Alice[...]` and `queries[...]` blocks.

## Commands

| Command | Description |
|---------|-------------|
| `:VerifpalVerify` | Run attacker analysis, show results as diagnostics |
| `:VerifpalFormat` | Format the current buffer |

## Requirements

- Neovim 0.9+
- [Verifpal](https://verifpal.com) binary in `$PATH` (or specify via `opts.path`)

## License

GPL-3.0 — see [LICENSE](LICENSE).
