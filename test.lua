#!/usr/bin/env luajit
local ffi = require 'ffi'
local tolua = require 'ext.tolua'
local clip = require 'ffi.req' 'cclip'

local textFormat = clip.clip_text_format()
print('clip_text_format', textFormat)

local imageFormat = clip.clip_image_format()
print('clip_image_format', imageFormat)

-- [[
local lock = clip.clip_lock_new()
print('clip_lock_new', lock)
print('clip_lock_is_convertible', imageFormat, clip.clip_lock_is_convertible(lock, textFormat))

local convertToText = clip.clip_lock_is_convertible(lock, textFormat)
print()
print('clip_lock_is_convertible text', convertToText)
if convertToText then
	local len = clip.clip_lock_get_data_length(lock, textFormat)
	print('clip_lock_get_data_length', len)
	local data = ffi.new('char[?]', len+1)
	print('clip_lock_get_data', clip.clip_lock_get_data(lock, textFormat, data, len))
	data[len+1] = 0
	print('...result', tolua(ffi.string(data, len)))
end

local convertToImage = clip.clip_lock_is_convertible(lock, imageFormat)
print()
print('clip_lock_is_convertible image', convertToImage)
if convertToImage then
	local image = clip.clip_image_new()
	print('sizeof image', ffi.sizeof(image))
	local result = clip.clip_lock_get_image(lock, image) 
	if result then
	print('clip_lock_get_image', result)
		print('image', image)
		local spec = clip.clip_image_spec(image)
		print('spec', spec)
		print('	width', spec.width)
		print('	height', spec.height)
		print('	bits_per_pixel', spec.bits_per_pixel)
		print('	bytes_per_row', spec.bytes_per_row)
		print('	red_mask', spec.red_mask)
		print('	green_mask', spec.green_mask)
		print('	blue_mask', spec.blue_mask)
		print('	alpha_mask', spec.alpha_mask)
		print('	red_shift', spec.red_shift)
		print('	green_shift', spec.green_shift)
		print('	blue_shift', spec.blue_shift)
		print('	alpha_shift', spec.alpha_shift)
	end
	clip.clip_image_free(image)
end
clip.clip_lock_free(lock)
--]]

print()
-- getting length first ... seems you would want to lock the clipboard before doing this (if that's what keeps the contents from changing)
-- TODO I should really allocate the char* and the size_t* and return both ... let the user free() both ...
local len = ffi.new'size_t[1]'
if clip.clip_get_text(nil, len) then	-- weird, lock's get_len returns with the \0, but get_text_len returns without it ... should I +1 here? or nah for cpp strings that can contain \0 and don't need the final one
	print('clip_get_text len', len[0])
	local str = ffi.new('char[?]', len[0]+1)
	assert(clip.clip_get_text(str, len))
	print('clip_get_text', tolua(ffi.string(str, len[0])))
end

print'high level:'
print('clip.text:', require 'clip'.text())
print('clip.image:', require 'clip'.image())
print('clip.get:', require 'clip'.get())
local image = require 'clip'.image()
if image then 
	print('image width', image.width)
	print('image height', image.height)
	print('image channels', image.channels)
	image:save'clip.png' 
end
