local ffi = require 'ffi'
local clip = require 'ffi.req' 'cclip'
local asserteq = require 'ext.assert'.eq
local assertne = require 'ext.assert'.ne
local Image = require 'image'

-- TODO this should be a default argument in xpcall
-- just like the 'err' object being thrown shouldn't append its source:line info, instead that should only be on the stacktrace.
local errorHandler = function(err)
	return err..'\n'..debug.traceback()
end

local textFormat = clip.clip_text_format()
local function text()
	local result
	local lock = clip.clip_lock_new()
	assert(xpcall(function()
		if clip.clip_lock_is_convertible(lock, textFormat) then
			local len = clip.clip_lock_get_data_length(lock, textFormat)
			local data = ffi.new('char[?]', len)
			if clip.clip_lock_get_data(lock, textFormat, data, len) then
				result = ffi.string(data, len)
			end	
		end
	end, errorHandler))
	clip.clip_lock_free(lock)	-- TODO this in a 'finally'
	return result
end

local imageFormat = clip.clip_image_format()
local function image()
	local result
	local lock = clip.clip_lock_new()
	assert(xpcall(function()	
		if clip.clip_lock_is_convertible(lock, imageFormat) then
			local clipImage = clip.clip_image_new()
			if clip.clip_lock_get_image(lock, clipImage) then
				local spec = clip.clip_image_spec(clipImage)
				asserteq(spec.bits_per_pixel, 32, 'clipboard bpp')
				result = Image(tonumber(spec.width), tonumber(spec.height), tonumber(bit.rshift(spec.bits_per_pixel, 3)), 'unsigned char')
				local dstRowSize = result.width * result.channels
				local dstp = clip.clip_image_data(clipImage)
				local srcp = result.buffer
				assertne(dstp, nil, 'dstp')
				for y=0,result.height-1 do
					ffi.copy(srcp, dstp, dstRowSize)
					srcp = srcp + dstRowSize
					dstp = dstp + spec.bytes_per_row
				end
			end
			clip.clip_image_free(clipImage)
		end
	end, errorHandler))
	clip.clip_lock_free(lock)
	return result
end

local function get()
	-- TODO this is lazy, instead use a single lock
	return text() or image()
end

return {
	text = text,
	image = image,
	get = get,
}
