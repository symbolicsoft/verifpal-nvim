-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

std = "lua51"
globals = { "vim" }
read_globals = { "T" }

-- The test runner injects its harness as a global on purpose: spec files are
-- loaded with dofile and have no package path of their own.
files["tests/*_spec.lua"] = { globals = { "T" } }

max_line_length = false
