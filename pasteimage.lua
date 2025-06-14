#!/usr/bin/env rua
local Clip = require 'clip'
local image = Clip.image()
if not image then
	io.stderr:write'no image in clipboard\n'
else
	local fn = assert(..., "expected out filename")
	image:save(fn)
end
