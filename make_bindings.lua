#!/usr/bin/env luajit
--[[
based on some c bindings I wrote for https://github.com/dacap/clip
which maybe I should also put on github ...

PRO of putting all ffi-binding-header-generation code in the include project is it is all in one place to search through for repetitive includes / for replacing includes ffi.req's of prior bindings.
Another Pro: NOTICE don't bother add this to the source list in the distinfo file.  This generator doesn't need to be in the distributable.

A con is ofc that the include/ list gets bloated.

I need a good standardized way for this to search all other generated headers ... possibly (bloat) the distinfo file?

TODO still in the works, the best way to get bindings is still running this within the include/include-list.lua and copying it into this folder.
The big hurdle is in searching all prior include-generations and replacing their generated content with ffi.req statements.

TODO don't use this, use distinfo's generateBindings instead, and work in distinfo deps traversal into the generator for replacing includes with requires
--]]
local out = 'ffi.lua'	-- local filename to write to, so it can be required with "require 'clip.ffi'"
local libname = 'clip'	-- clip.dll, libclip.so, libclip.dylib
require 'ext.path'(out):write((assert(
	require 'include.generate'{
		inc = '<cclip.h>',
		out = out,
		final = function(code)
			code = code .. '\n'
				.."return require 'ffi.load' '"..libname.."'\n"
			return code
		end,
	}
)))
