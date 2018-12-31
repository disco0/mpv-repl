-- repl++.lua -- Additional functions for REPL.lua -- A graphical 
-- REPL for mpv input commands

require 'set'
require 'mp'
local utils   = require 'mp.utils'
local options = require 'mp.options'
local assdraw = require 'mp.assdraw'

-- Debug
  -- Debug Profile - when set profile is active on script load, calls onload_debug
    -- _DEBUG_PROFILE_ = "__DEBUG"
  -- Debug Switch - Backup flag, flip for onload_debug call at end of script load
    -- Note: Should usually be done by detecting the configured debug profile
    -- _DEBUG_ = true
--

-- For printing/log
    local proc_arrow = '=>'
-- Blacklist of words for use in various macros
    local blacklist = Set { "set", "cycle", "cycle-values" }
-- #macro symbols and their associated text
    local macros = {}
    macros["shrpscl"]= 'print-text "[sharp] oversample <-> linear (triangle) <-> catmull_rom <-> mitchell <-> gaussian <-> bicubic [smooth]"'
    macros["font"]   = 'script-message repl-size; script-message repl-font'
    macros["curves"] =
        [[ print-text "## Commands, invoked with `script-message` ##";
            print-text "curves-brighten-show => Enter|Exit brightness mode";
            print-text "curves-cooler-show   => Enter|Exit temperature mode";
            print-text "curves-brighten      => Adjust brightness of video. Param: +/-1";
            print-text "curves-brighten-tone => Change the tone base [x] Param: +/-1";
            print-text "curves-temp-cooler   => Adjust the temperature by changing";
            print-text "                        R,G,B curve values";
            print-text "curves-temp-tone     => Change the tone base [x]";
            print-text "## Usage ##";
            print-text "In mpv, press b|y key to start manipulating color curves";
            print-text "Use arrow keys to move the point in the curve";
            print-text "r => Reset curves state";
            print-text "d => Delete the filter";
            print-text "Press b, y keys again to exit the curve mode."
        ]]
    macros["box"] = '!repl-hide; !Blackbox; !Blackbox'
    macros["vf"] = "print-text 'Example vf command => vf set perspective=0:0.32*H:W:0:0:H:W:.8*H';"
--

-- Nested print function for making shit traces
    function iprint(str)
        str = string.rep( " ", indent ) .. str
        print( str)
    end
    ip = iprint
    indent = 0
--


-- Get words from current line input and try printing them
    function print_line(line)
        local to_print = line
        local cmd      = ""
        for w in to_print:gmatch("%S+") do 
        -- if w ~= "set" then
            if not blacklist[w] then
                cmd = "print-text \"" .. w .. " " .. proc_arrow .. " ${" .. w .. "}\" "
                mp.command(cmd)
            end
        end
        update()
    end
--


-- Attempt to get type of each property in string input (not anymore)
    function get_type(line)
        local cmd = ""
        for w in line:gmatch("%S+") do 
        -- if w ~= "set" then
            if not blacklist[w] then
                local proptype = mp.get_property(tostring(w))
                print(proptype)
                local cmd = "print-text \"" .. w .. " ::= " ..  proptype .. "\""
                mp.command(cmd)
            end
        end
        update()
    end
--


-- Cycle all boolean properties passed in string input 
    function cycle_line(line)
        local cmd = ""
        for w in line:gmatch("%S+") do 
            if not blacklist[w] then
                local prop = mp.get_property(tostring(w))
                if prop == "yes" or prop == "no" then
                    toggle_property(w, "yes", "no")
                    local cmd = "print-text \"" .. w .. " " .. proc_arrow .. " ${" .. w .. "}\" "
                    mp.command(cmd)
                else
                    log_add('{\\1c&H66ccff&}', w .. " != Bool\n")
                end
            end
        end
        update()
    end
--


-- Naive implementation for (pre|ap)pending to each word in string input 
    function cons_line(prefix, line, postfix)
        go_home()
        prefix:gsub(".", function(c)
            handle_char_input(c)
        end)
        go_end()
        if postfix then
            postfix:gsub(".", function(c)
                handle_char_input(c)
            end)
            prev_char(postfix.len)
        end
        update()
    end  
--


-- Main Eval Loop for repl++ additions
     -- Current implementation only looks for instruction symbol in first
      --non-whitespace char of line, and passes it into switch
      --TODO: Tokenize to some extent where possibly useful, possibly
      --      eval word by word into valid chunks for existing switch
  function eval_line(line)
    --- Subfunctions to parse lines and statements for `!` substitution
     --   TODO: - Generalize beyond single symbol case,
     --         - Integrate do_line() code into body?
        local function parse_statements(line)
            statements = {}
            for statement in line:gmatch('[^ ;][^;]*') do
                if #statement > 0 then
                    statements[#statements + 1] = statement .. "; "
                end
            end
            update()
            return statements
        end
        local function do_line(line)
            if line:match(';') then 
                statements = parse_statements(line)
                if statements then
                    line_ = ""
                    for i, s in ipairs(statements) do
                        if s:match('![ ]*([^ ].*)') then 
                            line_ = line_ .. (s:gsub('![%s]*', "script-message "))
                        else
                            line_ = line_ .. s
                        end
                    end
                    return line_
                end
            else
                if line:match('![ ]*([^ ].*)') then 
                    line = (line:gsub('!', "script-message "))
                    return line
                else
                    return line
                end
            end
        end
        --
    -- Main function block
        -- #macro => macros['macro'].value
        if line:match("[^%s]") == "#" and line:find("^[%s]*#[^%s#]+") then
            symbol = line:match("^[%s]*#[^%s#]+"):sub(2)
            if macros[symbol] then
                line = macros[symbol]
            end
        end
        -- ! => script-message
        if line:match("!") then
            -- lol
            return (do_line(line))
        end
    end
    --
        ------ Old  
            -- function eval_line(line)
            --     if line:find("^[%s]*#[^%s#]+") then
            --         symbol = line:match("^[%s]*#[^%s#]+"):sub(2)
            --         if macros[symbol] then
            --             return macros[symbol]
            --         else
            --             return line
            --         end
            --     else
            --         return line
            --     end
            -- end

            -- Check for and process extended text expansion methods
            -- 1) `! msg val` — `!` 	 => `script-message msg val`
            -- 2) `#symbol`	  — `symbol` => `macros['symbol']` => `macro cmd`
        
        ----
--


-- Device explorer
    function device_info(text)
        if not text or text == "a" then
            plist = mp.get_property_osd("audio-device-list")
        else
            plist = mp.get_property_osd("")
        end
        pdbg(plist)
    end
--


-- Spew audio devices
	function audio_devices(text)
		plist = mp.get_property_osd("audio-device-list")
        --print(plist)
        utils_to_string(plist)
	end
--


-- List macros
    function macro_list()
        for symbol, macro in pairs(macros) do
            -- Color Format: #BBGGRR
            macro_color = "FFAD4C"
            value_color = "FFFFFF"
            
            log_add( '{\\1c&H' .. macro_color .. '&}',
                       string.format("%s:\n", symbol)  )
            log_add( '{\\1c&H' .. value_color .. '&}', 
                       string.format("%s\n",  macro)   )
        end
    end
--


-- Debug print function
    function pdbg(toPrint)
        local function pdbg_rec(toPrint)        
            if type(toPrint) == "table" then
                for _, p in ipairs(toPrint) do pdbg_rec(p) end
            else
                log_add('{\\1c&H66ccff&}', toPrint)
            end
        end
        if type(toPrint) == "table" then
            for _, p in ipairs(toPrint) do pdbg_rec(p) end
        else
            log_add('{\\1c&H66ccff&}', toPrint)
        end
    end
--


-- Native debug print function test
    function utils_to_string(toPrint)
        -- toPrint = utils.to_string(toPrint)
        -- log_add('{\\1c&H66ccff&}', 
        --         "utils_to_string output (" .. get_type(toPrint) .. ":\n" )
        log_add('{\\1c&H66ccff&}',
                "utils_to_string output: " .. utils.to_string(toPrint) .. "\n" )
    end
--


-- Show/Set REPL Font Size
    function get_REPL_font_size()
        log_add('{\\1c&H66ccff&}', "REPL Size => " .. opts.font_size .. "\n")
        update()
    end

    function set_REPL_font_size(text)
        print("set_REPL_font_size called with input " .. text)
        if tonumber(text) ~= nil then 
            opts.font_size = tonumber(text) 
        else 
            log_add('{\\1c&H66ccff&}', text .. " is not a number.\n")
        end
        update()
    end

    -- Show/Set REPL Font 
    function get_REPL_font_name()
        log_add('{\\1c&H66ccff&}', "REPL Font => " .. opts.font .. "\n")
        update()
    end
    function set_REPL_font_name(text)
        print("set_REPL_font_name called with input " .. text)
        opts.font = text
        update()
    end
--

-- Etc debug function - for whatever
    function dbg_etc(text)
        logColorBGR = "FFCC55"
        local function _log(str, altLogColor)
            logColor = altLogColor or logColorBGR  or "5555DD" 
            log_add( '{\\1c&H' .. logColor .. '&}', str )
        end
        local function _logLine(str, altLogColor)
            _log( str, altLogColor )
            _log( "\n" )
        end
        local function _str(str)
            if     str == nil          then str = "(!nil¡) "
            elseif type(str) ~= string then str = tostring(str)
            end
            return str
        end
        _logLine( "meme" )
        -- print( "func_update_info => type "        .. type(func_update_info)     )
        -- print( "func_update_info.name => "        .. func_update_info.name      )
        -- print( "func_update_info => tostring => " .. tostring(func_update_info) )
        -- _log (debug.getinfo(1,"n").name)
    end
--

-- Toggle property passed in `name`, intended for true|false but takes w/e
    function toggle_property(name, val1, val2)
        local val = mp.get_property(name)
        if(val == val1) then
            mp.set_property(name, val2)
            mp.osd_message(name .. ': ' .. val2)
        elseif(val == val2) then
            mp.set_property(name, val1)
            mp.osd_message(name .. ': ' .. val1)
        else
            mp.set_property(name, val1)
            mp.osd_message(name .. ': ' .. val .. ' => ' .. val1)
        end
    end
--


return { dbg_etc = utils_to_string,
         get_type = get_type,
         eval_line = eval_line,
         cons_line = cons_line,
         print_line = print_line,
         cycle_line = cycle_line,
         macro_list = macro_list,
         audio_devices = audio_devices,
         set_REPL_font_size = set_REPL_font_size,
         set_REPL_font_name = set_REPL_font_name,
         get_REPL_font_size = get_REPL_font_size,
         get_REPL_font_name = get_REPL_font_name  }
