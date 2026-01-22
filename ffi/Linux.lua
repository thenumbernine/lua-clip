--[[
Here's the start of me porting libclip/clip_x11.cpp into pure-LuaJIT

It's got threads and C++ classes so it will be messy.
--]]
local ffi = require 'ffi'
local class = require 'ext.class'
local Mutex = require 'thread.mutex'
local Cond = require 'thread.cond'
local xcb = require 'xcb'	-- TODO?


local func_bool = ffi.typeof'bool()'


-- this is a replacement for libclip's clip/ffi.lua bindings, but just for the Linux/X11 implementation
local M = {}


function M.clip_empty_format() return 0 end
function M.clip_text_format() return 1 end
function M.clip_image_format() return 2 end


local Manager = class()

-- needs to be defined both here and in the thread code
local ThreadArgTypeCode = [[struct {
	xcb_connection_t* m_connection;
	pthread_mutex_t* m_mutex_id;
}]]
local ThreadArgType = ffi.typeof(ThreadArgTypeCode)

function Manager:init()
	self.m_mutex = Mutex()
	self.m_cv = Cond()
	self.m_window = 0
	self.m_incr_process = false

	-- TODO verify these return false and not 0 ...
	
	self.m_connection = xcb.xcb_connect(nil, nil)
	if not self.m_connection then return end
	
	local setup = xcb.xcb_get_setup(self.m_connection)
	if not setup then return end

	local screen = xcb.xcb_setup_roots_iterator(setup).data
	if not screen then return end

	local event_mask = ffi.new('int[1]', bit.bor(
		xcb.XCB_EVENT_MASK_PROPERTY_CHANGE,
		xcb.XCB_EVENT_MASK_STRUCTURE_NOTIFY
	))
	 
	self.m_window = xcb.xcb_generate_id(self.m_connection)

		xcb.xcb_create_window(
		self.m_connection,
		0,
		self.m_window,
		screen.root,
		0, 0, 1, 1, 0,
		xcb.XCB_WINDOW_CLASS_INPUT_OUTPUT,
		screen.root_visual,
		xcb.XCB_CW_EVENT_MASK,
		event_mask
	)

	self.m_thread = Thread(
		template([=[
-- process_x11_events
local ffi = require 'ffi'
local table = require 'ext.table'
local xcb = require 'xcb'	-- TODO?
require 'ffi.req' 'c.stdlib'	-- free()
local vector = require 'ffi.cpp.vector'

local CLIP_SUPPORT_SAVE_TARGETS = true
local vector_xcb_atom_t = vector'xcb_atom_t'
local vector_uint8_t = vector'uint8_t'

local ThreadArgType = ffi.typeof([[<?=ThreadArgTypeCode?>]])
local ThreadArgPtrType ffi.typeof('$*', ThreadArgType)

arg = ffi.cast(ThreadArgPtrType, arg)
local m_connection = args.m_connection

local Mutex = require 'thread.mutex'
local mutex = Mutex:wrap(arg.m_mutex_id)

local Cond = require 'thread.cond'
local cv = Cond:wrap(arg.m_cv_id),


local m_atoms = {}
local function getAtom(name)
	local result = m_atoms[name]
	if result then return result end
		local cookie = xcb.xcb_intern_atom(m_connection, 0, #name, name)
		local reply = xcb.xcb_intern_atom_reply(m_connection, cookie, nil	)
	if reply ~= nil then
		result = reply.atom
		m_atoms[name] = result
		ffi.C.free(reply)
	end
	return result
end

local m_image
local m_data = table()
local function clearData()
	m_data = table()
	m_image = nil
end

local function handleSelectionClearEvent(event)
	if event.selection == getAtom'CLIPBOARD' then
		mutex:lock()
		clearData() -- Clear our clipboard data
		mutex:unlock()
	end
end

local function getAndDeleteProperty(window, property, atom, delete_prop)
	local cookie = xcb.xcb_get_property(
		m_connection,
		delete_prop,
		window,
		property,
		atom,
		0,
		0x1fffffff -- 0x1fffffff = INT32_MAX / 4
	)
		
	local err = ffi.new'xcb_generic_error_t*[1]'
	local reply = xcb.xcb_get_property_reply(m_connection, cookie, err);
	if err[0] ~= nil then
		print('XCB clipboard error', err[0])	-- TODO report error
		ffi.C.free(err[0])
	end
	return reply
end

-- TODO can I just use image/luajit/png? esp its rw-in-memory stuff?

local x11WritePngWriteDataFn(
	png, -- png_structp 
	buf, -- png_bytep 
	len -- png_size_t 
)
	std::vector<uint8_t>& output = *(std::vector<uint8_t>*)png_get_io_ptr(png);
	const size_t i = output.size();
	output.resize(i+len);
	std::copy(buf, buf+len, output.begin()+i);
end

local function x11WritePng(m_image, output)
	png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING,
																						nil, nil, nil);
	if (!png)
		return false;

	png_infop info = png_create_info_struct(png);
	if (!info) {
		png_destroy_write_struct(&png, nil);
		return false;
	}

	if (setjmp(png_jmpbuf(png))) {
		png_destroy_write_struct(&png, &info);
		return false;
	}

	png_set_write_fn(png,
									 (png_voidp)&output,
									 x11WritePngWriteDataFn,
									 nil);		-- No need for a flush function

	const image_spec& spec = image.spec();
	int color_type = (spec.alpha_mask ?
										PNG_COLOR_TYPE_RGB_ALPHA:
										PNG_COLOR_TYPE_RGB);

	png_set_IHDR(png, info,
							 spec.width, spec.height, 8, color_type,
							 PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_BASE, PNG_FILTER_TYPE_BASE);
	png_write_info(png, info);
	png_set_packing(png);

	png_bytep row =
		(png_bytep)png_malloc(png, png_get_rowbytes(png, info));

	for (png_uint_32 y=0; y<spec.height; ++y) {
		const uint32_t* src =
			(const uint32_t*)(((const uint8_t*)image.data())
												+ y*spec.bytes_per_row);
		uint8_t* dst = row;
		unsigned int x, c;

		for (x=0; x<spec.width; x++) {
			c = *(src++);
			*(dst++) = (c & spec.red_mask	) >> spec.red_shift;
			*(dst++) = (c & spec.green_mask) >> spec.green_shift;
			*(dst++) = (c & spec.blue_mask ) >> spec.blue_shift;
			if (color_type == PNG_COLOR_TYPE_RGB_ALPHA)
				*(dst++) = (c & spec.alpha_mask) >> spec.alpha_shift;
		}

		png_write_rows(png, &row, 1);
	}

	png_free(png, row);
	png_write_end(png, info);
	png_destroy_write_struct(&png, &info);
	return true;

end

local function encodeDataOnDemand(index, value)
	if value.first == getAtom'image/png' then
	assert(m_image:is_valid());
	if not m_image:is_valid())
		return
	end
	 
	local output = vector_uint8_t()
		if x11WritePng(m_image, output) then
			value.second = output
		end
		-- else { TODO report png conversion errors }
	end
end

local function setRequestorPropertyWithClipboardContent(requestor, property, target)
	local index, value = m_data:find(target)
	if not index then
		-- Nothing to do (unsupported target)
		return false
	end

	-- This can be null of the data was set from an image but we
	-- didn't encode the image yet (e.g. to image/png format).
	if value == nil then
			encodeDataOnDemand(index, value)

		-- Return nothing, the given "target" cannot be constructed
		-- (maybe by some encoding error).
		if value == nil then
			return false
		end
	end

	-- Set the "property" of "requestor" with the
	-- clipboard content in the requested format ("target").
	xcb.xcb_change_property(
		m_connection,
		xcb.XCB_PROP_MODE_REPLACE,
		requestor,
		property,
		target,
		8,
		value.size(),
		value	-- TODO something about dereference and cast ... put it in a [1]?
	)
	return true
end

local function handleSelectionRequestEvent(event)
	mutex:lock()

	if event.target == getAtom'TARGETS' then
		local targets = vector_xcb_atom_t()
		targets:push_back(getAtom'TARGETS')
		if CLIP_SUPPORT_SAVE_TARGETS
			targets.push_back(getAtom(SAVE_TARGETS));
			targets.push_back(getAtom(MULTIPLE));
		end
		for _,v in ipairs(m_data) do
			targets:push_back(v)
		end

		-- Set the "property" of "requestor" with the clipboard
		-- formats ("targets", atoms) that we provide.
		xcb.xcb_change_property(
			m_connection,
			xcb.XCB_PROP_MODE_REPLACE,
			event.requestor,
			event.property,
			getAtom'ATOM',
			8 * ffi.sizeof'xcb_atom_t',
			#targets,
			targets.v
		)
	elseif event.target == getAtom'SAVE_TARGETS' 
	and CLIP_SUPPORT_SAVE_TARGETS
	then
		-- Do nothing
	elseif event.target == getAtom'MULTIPLE'
	and CLIP_SUPPORT_SAVE_TARGETS
		local reply = getAndDeleteProperty(
			event.requestor,
			event.property,
			getAtom'ATOM_PAIR',
			false
		)
			
		if reply then
			local count = math.floor(xcb.xcb_get_property_value_length(reply) / ffi.sizeof'xcb_atom_t')
			local ptr = ffi.cast('xcb_atom_t*', xcb.xcb_get_property_value(reply))
			for i=0,count-1,2 do
				local target = ptr[i]
				local property = ptr[i+1]

				if not setRequestorPropertyWithClipboardContent(
					event.requestor,
					property,
					target
				) then
					xcb.xcb_change_property(
						m_connection,
						xcb.XCB_PROP_MODE_REPLACE,
						event.requestor,
						event.property,
						xcb.XCB_ATOM_NONE, 
						0, 0, nil
					)
				end
			end

			ffi.C.free(reply)
		end
	else
		if not setRequestorPropertyWithClipboardContent(
			event.requestor,
			event.property,
			event.target
		) then
			-- If the requested "target" type is not present in our
			-- clipboard, we continue normally sending a SelectionNotify
			-- to the "requestor" anyway because some text editors
			-- (e.g. Emacs) request the TIMESTAMP target (without asking
			-- if it's present in TARGETS) after asking for UTF8_STRING.
			--
			-- Sending the SelectionNotify will wake up the "requestor"
			-- that is asking for the clipboard content. In this way we
			-- avoid a "Timed out waiting for reply from selection owner"
			-- error in Emacs (and probably other text editors).
		end
	end

	-- Notify the "requestor" that we've already updated the property.
	local notify = xcb_selection_notify_event_t()
	notify.response_type = xcb.XCB_SELECTION_NOTIFY
	notify.pad0					= 0
	notify.sequence			= 0
	notify.time					= event.time
	notify.requestor		 = event.requestor
	notify.selection		 = event.selection
	notify.target				= event.target
	notify.property			= event.property

	xcb.xcb_send_event(
		m_connection,
		false,
		event.requestor,
		xcb.XCB_EVENT_MASK_NO_EVENT, -- SelectionNotify events go without mask
		ffi.cast('const char*', notify)
	)

	xcb.xcb_flush(m_connection)
end

-- Concatenates the new data received in "reply" into "m_reply_data" buffer.
local copy_reply_data(xcb_get_property_reply_t* reply) {
	local src = ffi.cast('const uint8_t*', xcb.xcb_get_property_value(reply))
	-- n = length of "src" in bytes
	local n = xcb.xcb_get_property_value_length(reply)

	local req = m_reply_offset + n
	if not m_reply_data then
		m_reply_data = vector_uint8_t(req)
	-- The "m_reply_data" size can be smaller because the size
	-- specified in INCR property is just a lower bound.
	elseif req > #m_reply_data then
		m_reply_data:resize(req)
	end

	ffi.copy(src, src + n, m_reply_data.v + m_reply_offset)
	m_reply_offset = m_reply_offset + n
end

-- Calls the current m_callback() to handle the clipboard content received from the owner.
local function call_callback(reply)
	m_callback_result = false;
	if m_callback then
		m_callback_result = m_callback()
	end

	cv:signal()

	m_reply_data:reset()
end

local function handleSelectionNotifyEvent(event)
	assert(event.requestor == m_window);

	if event.target == getAtom'TARGETS' then
		m_target_atom = getAtom'ATOM'
	else
		m_target_atom = event.target
	end

	local reply = getAndDeleteProperty(
		event.requestor,
		event.property,
		m_target_atom
	)
	if reply then
		-- In this case, We're going to receive the clipboard content in
		-- chunks of data with several PropertyNotify events.
		if reply.type == getAtom'INCR' then
			ffi.C.free(reply)

			reply = getAndDeleteProperty(
				event.requestor,
				event.property,
				get_atom'INCR'
			)

			if reply then
				if xcb.xcb_get_property_value_length(reply) == 4 then
					local n = ffi.cast('uint32_t*', xcb.xcb_get_property_value(reply))[0]
					m_reply_data = vector_uint8_t(n)
					m_reply_offset = 0
					m_incr_process = true
					m_incr_received = true
				end
				ffi.C.free(reply)
			end
		else
			-- Simple case, the whole clipboard content in just one reply
			-- (without the INCR method).
			m_reply_data:clear()
			m_reply_offset = 0
			copyReplyData(reply)
			callCallback(reply)
			ffi.C.free(reply)
		end
	end
end

local function handlePropertyNotifyEvent(event) 
	if m_incr_process 
	and event.state == xcb.XCB_PROPERTY_NEW_VALUE 
	and event.atom == getAtom'CLIPBOARD'
	then
		local reply = getAndDeleteProperty(
			event.window,
			event.atom,
			m_target_atom
		)
		if reply then
			m_incr_received = true

			-- When the length is 0 it means that the content was
			-- completely sent by the selection owner.
			if xcb.xcb_get_property_value_length(reply) > 0 then
				copyReplyData(reply)
			else
				-- Now that m_reply_data has the complete clipboard content,
				-- we can call the m_callback.
				callCallback(reply)
				m_incr_process = false
			end
			ffi.C.free(reply)
		end
	end
end



local stop
local event -- xcb_generic_event_t* event;
while not stop do
	local event = xcb.xcb_wait_for_event(m_connection)
	if event == nil then break end

	local type = bit.band(event.response_type, bit.bnot(0x80))

	if type == xcb.XCB_DESTROY_NOTIFY then
		-- To stop the message loop we can just destroy the window
		stop = true
	-- Someone else has new content in the clipboard, so is
	-- notifying us that we should delete our data now.
	elseif type == xcb.XCB_SELECTION_CLEAR then
		handleSelectionClearEvent(ffi.cast('xcb_selection_clear_event_t*', event))

	-- Someone is requesting the clipboard content from us.
	elseif type == xcb.XCB_SELECTION_REQUEST then
		handleSelectionRequestEvent(ffi.cast('xcb_selection_request_event_t*', event))

	-- We've requested the clipboard content and this is the answer.
	elseif type == xcb.XCB_SELECTION_NOTIFY then
		handleSelectionNotifyEvent(ffi.cast('xcb_selection_notify_event_t*', event)

	elseif type == xcb.XCB_PROPERTY_NOTIFY then
		handlePropertyNotifyEvent(ffi.cast('xcb_property_notify_event_t*', event)
	end

	ffi.C.free(event)
end
]=],
			{	-- template vars:
				ThreadArgTypeCode = ThreadArgTypeCode,
			}
		), 
		ThreadArgType{
			m_mutex_id = self.m_mutex.id,
			m_cv_id = self.m_cv.id,
			m_connection = self.m_connection,
		}
	)
end


local manager
local function get_manager()
	manager = manager or Manager()
	return manager
end


local Lock = class()

function Lock:init()
	self.m_locked = get_manager():try_lock()
end


function M.clip_lock_new()
	return Lock()
end

return M
