local ffi = require 'ffi'
local clip = require 'ffi.req' 'cclip'
local table = require 'ext.table'
local asserteq = require 'ext.assert'.eq
local assertne = require 'ext.assert'.ne
local Image = require 'image'

-- TODO this should be a default argument in xpcall
-- just like the 'err' object being thrown shouldn't append its source:line info, instead that should only be on the stacktrace.
local errorHandler = function(err)
	return err..'\n'..debug.traceback()
end

local textFormat = clip.clip_text_format()
local function text(...)
	local result
	local lock = clip.clip_lock_new()
	local copying = select('#', ...) > 0
	local tocopy = ...
	assert(xpcall(function()
		if copying then 	-- setting clipboard
			tocopy = tostring(tocopy)
			-- TODO do we need null term?
			assert(clip.clip_lock_clear(lock), 'clipboard clear failed')
			assert(clip.clip_lock_set_data(lock, textFormat, ffi.cast('char const*', tocopy), #tocopy), 'clipboard set text failed')
		else	-- returning clipboard
			if clip.clip_lock_is_convertible(lock, textFormat) then
				local len = clip.clip_lock_get_data_length(lock, textFormat)
				local data = ffi.new('char[?]', len)
				if clip.clip_lock_get_data(lock, textFormat, data, len) then
					-- ok so the libclip test_text says that you should expect a \0 in the trailing output
					-- likewise I copied/pasted the same string apart from libclip and it did look the same
					-- so here's me removing it if it is present
					if len>0 and data[len-1] == 0 then len = len - 1 end
					result = ffi.string(data, len)
				end
			end
		end
	end, errorHandler))
	clip.clip_lock_free(lock)	-- TODO this in a 'finally'
	return result
end

local imageFormat = clip.clip_image_format()
local function image(...)
	local result
	local lock = clip.clip_lock_new()
	local copying = select('#', ...) > 0
	local tocopy = ...
	assert(xpcall(function()
		if copying then
			assert(Image:isa(tocopy), "can't paste image, it's not an image")
			assert(clip.clip_lock_clear(lock), "clipboard clear failed")
			asserteq(ffi.sizeof(tocopy.format), 1, 'image.format')	-- ... right?
			-- can only handle 32bpp images soooo ...
			if tocopy.channels < 4 then
				local blank = Image(tocopy.width, tocopy.height, 1, tocopy.format):clear()	-- WARNING this will give you transparent alpha ...
				tocopy = tocopy:combine(table{blank}:rep(4 - tocopy.channels):unpack())
			end
			asserteq(tocopy.channels, 4, 'channels')
			local spec = ffi.new'ClipImageSpec[1]'
			spec[0].width = tocopy.width
			spec[0].height = tocopy.height
			spec[0].bits_per_pixel = bit.lshift(tocopy.channels, 3) * ffi.sizeof(tocopy.format)
			spec[0].bytes_per_row = tocopy.width * tocopy.channels * ffi.sizeof(tocopy.format)
			spec[0].red_mask = 0xff
			spec[0].green_mask = 0xff00
			spec[0].blue_mask = 0xff0000
			spec[0].alpha_mask = 0xff000000
			spec[0].red_shift = 0
			spec[0].green_shift = 8
			spec[0].blue_shift = 16
			spec[0].alpha_shift = 24
			local clipImage = clip.clip_image_new_pp(tocopy.buffer, spec)
			assert(clip.clip_lock_set_image(lock, clipImage))
		else
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
