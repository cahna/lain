
--[[
                                                  
     Licensed under GNU General Public License v2 
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

local setmetatable = setmetatable

-- Battery infos
-- lain.widgets.bat
local bat = {}

local bpath = '/sys/devices/platform/smapi/%s/%s' -- ThinkPad with smapi

-- Rudimentary detection of tp_smapi (not tested)
local function thinkpad_smapi_detect()
    local handle = io.popen('exec pgrep ktpacpid')
    local output = handle:read('*all')
    local proc_alive = (output:len() > 1 and output:find('^[1-9]-%d+\n') ~= nil)
    return proc_alive
end

-- Note: See link below for how one COULD integrate this with acpitool.
-- http://awesome.naquadah.org/wiki/Acpitools-based_battery_widget

local function worker(args)
    local args = args or {}
    local timeout = args.timeout or 30
    local battery = args.battery or "BAT0"
    local settings = args.settings or function() end

    -- Only continue if smapi battery is being used
    if not thinkpad_smapi_detect() then return error('UNABLE TO DETECT TP_SMAPI WITH ACPID') end 

    bat.widget = wibox.widget.textbox('')

    function update()
        bat_now = {
            status = "Not present",
            perc   = "N/A",
            time   = "N/A",
            watt   = "N/A"
        }

        local present = first_line(bpath:format(battery, 'installed'))

        if present == "1"
        then
          -- state can be 'idle', 'discharging', or 'charging'
          bat_now.status = first_line(bpath:format(battery, 'state'))

          if bat_now.status == 'discharging' and mins_left ~= 'not_discharging' then
            local mins_left = first_line(bpath:format(battery, 'remaining_running_time'))
            if mins_left ~= 'not_discharging' and mins_left:find('^%d+') ~= nil then
              local hrs = mins_left / 60
              local min = mins_left % 60
              bat_now.time = string.format("%02d:%02d", hrs, min)
              -- TODO: Add calculation for watts
              -- bat_now.watt = string.format("%.2fW", (rate * ratev) / 1e12)
            end
	  end

          bat_now.perc = tonumber(first_line(bpath:format(battery, 'remaining_percent')))

	  -- notifications for low and critical states
          if bat_now.perc <= 5
          then
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
          elseif bat_now.perc <= 15
          then
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
