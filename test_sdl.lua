#!/usr/bin/env luajit
local ffi = require 'ffi'
local table = require 'ext.table'
local tolua = require 'ext.tolua'
local assert = require 'ext.assert'

local Clip = require 'clip.sdl'
print'high level:'
print('clip.text:', Clip.text())
print('clip.image:', Clip.image())
print('clip.get:', Clip.get())
local image = Clip.image()
if image then
	print('image width', image.width)
	print('image height', image.height)
	print('image channels', image.channels)
	image:save'clip.png'
end

-- test copying
do
	local s = 'testing setting clipboard to text'
	print('copying', tolua(s))
	local got = table.pack(Clip.text(s))
	print('copying got', tolua(got))
	local got = table.pack(Clip.text())
	print('pasting got', tolua(got))
	assert.eq(s, got[1])
end
