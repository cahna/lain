
--[[
												  
	 Licensed under GNU General Public License v2 
	  * (c) 2013,      Conor Heine
	  * (c) 2013,      Luke Bonham                
	  * (c) 2010-2012, Peter Hofmann              

--]]

local helpers      = require('lain.helpers')
local newtimer     = helpers.newtimer
local first_line   = helpers.first_line

local naughty      = require("naughty")
local wibox        = require("wibox")

local math         = { floor  = math.floor }
local string       = { format = string.format }
local io           = { popen  = io.popen }
local table        = { insert = table.insert }

local setmetatable, ipairs, tonumber = setmetatable, ipairs, tonumber

-- Battery infos
-- lain.widgets.bat
local bat = {}

-- Typical path to battery / psu info
local psu = {
  path = '/sys/class/power_supply/%s/%s',
  files = {},
  needed = {
	'present',
	'power_now',
	'voltage_now',
	'energy_now',
	'energy_full',
	'status'
  }
}

-- ThinkPad with smapi
local smapi = {
  path = '/sys/devices/platform/smapi/%s/%s',
  files = {},
  needed = {
	'installed',
	'remaining_running_time',
	'remaining_percent',
	'state'
  }
}

--[[ 
  Rudimentary automagic detection of tp_smapi (not tested): 
   1. Checks for ktpacpid (thinkpad's acpi daemon)
   2. Checks for the 'state' parameter in the smapi folder location

   * Note: See link below for how one COULD integrate this with acpitool.
	 http://awesome.naquadah.org/wiki/Acpitools-based_battery_widget
   * TODO: Needs testing with a non-thinkpad and someone else's Thinkpad 
   * TODO: (reccomendation) Replace smapi.needed file checks with luaposix? 
		ie: return posix.stat('/sys/devices/platform/smapi', 'type') == 'directory'
		(Don't want to add a dependency, for now)
 ]]
local function thinkpad_smapi_detect(battery)
	local handle = io.popen('exec pgrep ktpacpid')
	local output = handle:read('*all')
	local proc_alive = (output:len() > 1 and output:find('^[1-9]-%d+\n') ~= nil)
	handle:close()
	return proc_alive and first_line(smapi.path:format(battery, 'state')) ~= nil
end

-- Tries reading the given files. Returns: status(bool), failed_files(table)
-- Also, memoizes string.format calls within config table for use in worker()
local function setup_files(config, battery)
  local failed = {}
  local all_success = true
  for _,file in ipairs(config.needed) do
	config.files[file] = config.path:format(battery, file)
	if first_line(config.files[file]) == nil then
	  all_success = false
	  table.insert(failed, config.files[file])
	end
  end
  return all_success, failed
end

local function worker(args)
	local args = args or {}
	local timeout = args.timeout or 30
	local battery = args.battery or "BAT0"
	local settings = args.settings or function() end

	local is_tp = thinkpad_smapi_detect(battery) -- Check for smapi
	local b = is_tp and smapi or psu -- set battery config

	-- Gracefully check file locations and notify failures
	local success, failures = setup_files(b, battery)
	if success ~= true then
		for _,file in ipairs(failures) do
			naughty.notify({
				text = file,
				title = battery.." widget may not work correctly. Unable to read file:",
				position = "top_right",
				timeout = 15,
				fg="#202020",
				bg="#cdcdcd",
				ontop = true
			})
	  	end
	end

	bat.widget = wibox.widget.textbox('')

	function update()
		bat_now = {
			status = "Not present",
			perc   = "N/A",
			time   = "N/A",
			watt   = "N/A"
		}

		local present = first_line((is_tp and b.files.installed or b.files.present))

		if present == "1" then
		  if is_tp then -- Thinkpad
			bat_now.status = first_line(b.files.state) -- 'idle', 'discharging', or 'charging'

			if bat_now.status == 'discharging' and mins_left ~= 'not_discharging' then
			  local mins_left = first_line(b.files.remaining_running_time)
			  
			  if mins_left ~= 'not_discharging' and mins_left:find('^%d+') ~= nil then
				local hrs = mins_left / 60
				local min = mins_left % 60

				bat_now.time = string.format("%02d:%02d", hrs, min)
				
				-- TODO: Add calculation for watts
				-- bat_now.watt = string.format("%.2fW", (rate * ratev) / 1e12)
			  end
			  end
			
			bat_now.perc = tonumber(first_line(b.files.remaining_percent))
		  else -- Not thinkpad
			local rate = first_line(b.files.power_now)
			local ratev = first_line(b.files.voltage_now)
			local rem = first_line(b.files.energy_now)
			local tot = first_line(b.files.energy_full)
			bat_now.status = first_line(b.files.status)

			local time_rat = 0
			if bat_now.status == "Charging"
			then
				time_rat = (tot - rem) / rate
			elseif bat_now.status == "Discharging"
			then
				time_rat = rem / rate
			end

			local hrs = math.floor(time_rat)
			local min = (time_rat - hrs) * 60

			bat_now.time = string.format("%02d:%02d", hrs, min)
			bat_now.perc = (rem / tot) * 100
			bat_now.watt = string.format("%.2fW", (rate * ratev) / 1e12)
		  end

		  -- notifications for low and critical states
		  if bat_now.perc <= 5 then
			  bat.id = naughty.notify({
				  text = "shutdown imminent",
				  title = "battery nearly exhausted",
				  position = "top_right",
				  timeout = 15,
				  fg="#000000",
				  bg="#ffffff",
				  ontop = true,
				  replaces_id = bat.id
			  }).id
		  elseif bat_now.perc <= 15 then
			  bat.id = naughty.notify({
				  text = "plug the cable",
				  title = "battery low",
				  position = "top_right",
				  timeout = 15,
				  fg="#202020",
				  bg="#cdcdcd",
				  ontop = true,
				  replaces_id = bat.id
			  }).id
		  end

			bat_now.perc = string.format("%d", bat_now.perc)
		end

		widget = bat.widget
		settings()
	end

	newtimer("bat", timeout, update)

	return bat.widget
end

return setmetatable(bat, { __call = function(_, ...) return worker(...) end })
