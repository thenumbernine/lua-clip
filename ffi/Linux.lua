--[[
Here's the start of me porting libclip/clip_x11.cpp into pure-LuaJIT

It's got threads and C++ classes so it will be messy.
--]]
local ffi = require 'ffi'
local class = require 'ext.class'
local vector = require 'ffi.cpp.vector-lua'
local Mutex = require 'thread.mutex'
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
	pthread_mutex_t* mutex_id;
}]]
local ThreadArgType = ffi.typeof(ThreadArgTypeCode)

function Manager:init()
	self.buffer = vector'uint8_t'
	self.atoms = vector'xcb_atom_t'
	self.notify_callbacks = vector(func_bool)
	self.m_lock = Mutex()
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
local ThreadArgType = ffi.typeof([[<?=ThreadArgTypeCode?>]])
local ThreadArgPtrType ffi.typeof('$*', ThreadArgType)
arg = ffi.cast(ThreadArgPtrType, arg)
local m_mutex_id = arg.mutex_id

-- process_x11_events

local xcb = require 'xcb'	-- TODO?
require 'ffi.req' 'c.stdlib'	-- free()
local Mutex = require 'thread.mutex'

local mutex = setmetatable({
	id = ffi.new('pthread_mutex_id[1]', m_mutex_id),
	destroy = function() end,
} Mutex)

-- [==[ TODO more stuff that needs to be duplicated in each thread
local function clear_data()
	m_data:clear()
	m_image:clear()
end
--]==]

local stop
local event -- xcb_generic_event_t* event;
while not stop do
	local event = xcb.xcb_wait_for_event(self.m_connection)
	if event == nil then break end

	local type = bit.band(event.response_type, bit.bnot(0x80))

	if type == xcb.XCB_DESTROY_NOTIFY then
		-- To stop the message loop we can just destroy the window
		stop = true
	-- Someone else has new content in the clipboard, so is
	-- notifying us that we should delete our data now.
	elseif type == xcb.XCB_SELECTION_CLEAR then
		event = ffi.cast('xcb_selection_clear_event_t*', event)

		if event.selection == get_atom(CLIPBOARD) then
			mutex:lock()
			clear_data() -- Clear our clipboard data
			mutex:unlock()
		end

	-- Someone is requesting the clipboard content from us.
	elseif type == xcb.XCB_SELECTION_REQUEST then
		event = ffi.cast('xcb_selection_request_event_t*', event)

	-- We've requested the clipboard content and this is the answer.
	elseif type == xcb.XCB_SELECTION_NOTIFY then
		handle_selection_notify_event(
			ffi.cast('xcb_selection_notify_event_t*', event)

	elseif type == xcb.XCB_PROPERTY_NOTIFY then
		handle_property_notify_event(
			ffi.cast('xcb_property_notify_event_t*', event)
	end

	ffi.C.free(event)
end
]=],
			{	-- template vars:
				ThreadArgTypeCode = ThreadArgTypeCode,
			}
		), 
		ThreadArgType{
			mutex_id = self.m_mutex.id,
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
