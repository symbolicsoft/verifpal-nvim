# verifpal-nvim

Neovim support for [Verifpal](https://verifpal.com), the symbolic formal
verification tool for cryptographic protocols. Write a protocol model in a
`.vp` file, run the attacker analysis without leaving the editor, and read the
attack it found in the names your model gave the values.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "symbolicsoft/verifpal-nvim", ft = "verifpal" }
```

With a binary somewhere unusual:

```lua
{
  "symbolicsoft/verifpal-nvim",
  ft = "verifpal",
  opts = { path = "/usr/local/bin/verifpal" },
}
```

With [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use "symbolicsoft/verifpal-nvim"
```

`setup()` is optional. Every default works on its own.

Needs Neovim 0.10 or newer, and the `verifpal` binary for anything that runs
an analysis. Everything else — highlighting, hover, completion, folding —
works without it. `:checkhealth verifpal` reports what was found.

## Verification

`:VerifpalVerify` runs the attacker analysis and puts each query's verdict on
its own line as a diagnostic: an error where the attacker contradicted the
query, an info mark where it held.

The analysis runs in the background, so the editor stays usable while it
works, and `:VerifpalCancel` stops it. The buffer is analyzed as it stands,
unsaved edits included — nothing is written to your file.

A model that does not parse, or that fails one of verifpal's sanity checks,
gets a single diagnostic on the line that caused it, carrying whatever note or
help verifpal attached to the error.

`:VerifpalVerify 1` analyzes one session per principal instead of the default
two. Session replication costs roughly four times the work; one session is the
escape hatch for a model too large to afford it.

## Attack traces

`:VerifpalResults` opens a panel with each query's conclusion and, where the
attacker won, the minimized attack narrated as numbered causal steps:

```
Verifpal — simple.vp
c1a1  ·  2 sessions  ·  1 ms  ·  2 of 2 contradicted
────────────────────

FAIL  confidentiality? m1
      m1 (m1) is obtained by Attacker.
      1. Attacker constructs PUBKEY(nil) from nil.
      2. Attacker replaces ga (sent by Alice to Bob) with PUBKEY(nil).
      3. Attacker observes e1 on the wire.
      4. Attacker observes gb on the wire.
      5. Attacker constructs gab from gb, nil.
      6. Attacker opens e1 with gab, obtaining m1.
```

The trace is the reason to believe a verdict, and reading it is how a
modelling mistake is told apart from a real attack. `<CR>` on a query jumps to
it in the model; `q` closes the panel.

The trace is also carried in the diagnostic itself, so `vim.diagnostic.open_float()`
shows the whole attack without opening the panel.

## Declared weakening assumptions

If the model declares any — `PUBKEY[weak](a)`, `SIGN[forgeable](sk, m)`,
`ENC[malleable](k, m)` — they are listed in the summary and at the top of the
results panel.

A model that declares one is not being analyzed on its own terms: an attack
found under it is genuine only under that assumption, and a query that holds
is conditional on it. Neither is an unconditional result, so neither is
reported as one.

## Documentation and completion

`K` over any primitive, query kind, weakening assumption or keyword shows its
signature, arity, output count, whether it may be checked with `?`, which
weakening assumptions it accepts, and what it means. Lookup is
case-insensitive, because Verifpal is: `pubkey(a)` and `PUBKEY(a)` are the
same call.

`<C-x><C-o>` completes the language, offering what makes sense where the
cursor is: query kinds inside `queries[ ... ]`, weakening assumptions inside a
primitive's parameter list, qualifiers after `knows`, primitives inside a
`principal` block.

## Formatting

`:VerifpalFormat` reformats the buffer with verifpal's canonical formatter.
Comments survive, the cursor stays put, an already-canonical buffer is not
touched at all, and nothing is saved to disk. `format_on_save = true` runs it
on every write.

## Diagrams

`:VerifpalDiagram` shows the protocol as each principal's steps in order, with
the messages between them called out:

```
Alice
    knows public c0
    generates a
    ga = PUBKEY(a)

Alice ──▶ Bob :  ga

Bob
    gab = DH_KEX(ga, b)
    e1 = AEAD_ENC(gab, m1, c0)
```

`:VerifpalDiagram!` gives verifpal's mermaid `sequenceDiagram` source instead.

## Editing

Syntax highlighting covers block keywords, attacker modes, declarations,
qualifiers, all five query kinds, all 25 primitives, declared weakening
assumptions, the checked-primitive `?`, the anonymous constant `_`, `nil`,
both arrow forms (`->` and `→`), and both comment forms.

Folding and indenting are driven by the model's own bracket structure rather
than by matching line shapes, so a guarded value (`[ga]`) and a capability
parameter (`SIGN[forgeable]`) create no folds, and a bracket inside a comment
closes nothing.

## Commands

| Command | Description |
|---------|-------------|
| `:VerifpalVerify [n]` | Run the attacker analysis, optionally with `n` sessions |
| `:VerifpalCancel` | Stop the running analysis |
| `:VerifpalResults` | Show the last analysis, with attack traces |
| `:VerifpalClear` | Clear this plugin's diagnostics |
| `:VerifpalFormat` | Reformat the buffer |
| `:VerifpalDiagram[!]` | Show the protocol diagram (`!` for mermaid source) |
| `:VerifpalInfo` | Report the binary in use and what it supports |

## Configuration

```lua
require("verifpal").setup({
  path = "verifpal",        -- binary path, or a name looked up in $PATH
  sessions = nil,           -- nil defers to verifpal's own default of 2
  timeout = 600000,         -- ms before a running analysis is killed
  verify_on_save = false,
  format_on_save = false,
  hover_key = "K",          -- or false to bind nothing
  completion = true,
  fold = true,
  indent = true,
  notify = true,
  diagnostics = {
    enabled = true,
    attack = vim.diagnostic.severity.ERROR,
    pass = vim.diagnostic.severity.INFO,  -- or false to mark nothing
    trace = true,           -- carry the attack trace in the diagnostic
  },
  panel = { split = "botright", height = 20, focus = true },
})
```

A misspelled option is reported rather than silently ignored.

For a statusline: `require("verifpal").statusline()` returns a spinner while
an analysis runs and the verdict once it has finished.

See `:help verifpal` for the rest, including the Lua API.

## Older verifpal releases

The plugin probes the binary it finds rather than assuming a version, so an
older verifpal degrades instead of failing. Without `verify --format json`,
verdicts still come from verifpal's own result code and remain exact, but
there are no attack traces or timings — and the plugin says so rather than
leaving you to wonder. `:checkhealth verifpal` reports which interfaces the
binary you have supports.

## Development

```sh
make test    # headless test suite
make check   # luacheck and stylua, if installed
```

The suite runs against whichever verifpal it finds, preferring a
`../verifpal/target/release/verifpal` build beside this checkout.
`VERIFPAL_BIN=/path/to/verifpal make test` points it at a specific one, which
is how the compatibility paths are exercised against an older release. Tests
that need a binary skip themselves when there is none.

## License

GPL-3.0 — see [LICENSE](LICENSE).
