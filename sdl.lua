local ffi = require 'ffi'
local sdl = require 'sdl'
local sdlAssertNonNull = require'sdl.assert'.nonnull
local table = require 'ext.table'
local assert = require 'ext.assert'
local Image = require 'image'

-- TODO this should be a default argument in xpcall
-- just like the 'err' object being thrown shouldn't append its source:line info, instead that should only be on the stacktrace.
local errorHandler = function(err)
	return err..'\n'..debug.traceback()
end

local function text(...)
	local copying = select('#', ...) > 0
	if copying then
		local tocopy = ...
		sdl.SDL_SetClipbordText(tostring(tocopy))	-- so, no \0's?
	else
		local ptr = sdlAssertNonNull(sdl.SDL_GetClipboardText())
		local str = ffi.string(ptr)
		sdl.SDL_free(ptr)
		return str
	end
end

local function image(...)
	-- do this here or once?
	local numMimeTypes = ffi.new'size_t[1]'
	local mimeTypesCstr = sdlAssertNonNull(sdl.SDL_GetClipboardMimeTypes(numMimeTypes))
	local mimeTypes = table()
	for i=0,tonumber(numMimeTypes[0])-1 do
		local mt = ffi.string(mimeTypesCstr[i])
print('has mime type', mt)		
		mimeTypes[mt] = true
	end
	sdl.SDL_free(mimeTypesCstr)

	local copying = select('#', ...) > 0
	if copying then
		local tocopy = ...
		assert(Image:isa(tocopy), "can't copy image, it's not an image")
		-- TODO sdl.SDL_SetClipboardData
	else
		-- TODO sdl.SDL_GetClipboardData
		
	end
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
