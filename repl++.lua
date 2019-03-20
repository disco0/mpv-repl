-- repl++.lua -- Additional functions for REPL.lua -- A graphical
-- REPL for mpv input commands

require 'set'
require 'mp'
local utils   = require 'mp.utils'
local options = require 'mp.options'
local assdraw = require 'mp.assdraw'

REPL_LOG = {}
REPL_LOG['macros'] = false


-- For printing/log
    local proc_arrow = '=>'
-- Blacklist of words for use in various macros
    local blacklist = Set { "set", "cycle", "cycle-values" }
-- #macro symbols and their associated text
    local macros = {}
    -- Player and script Management
    macros["font"]     = 'script-message repl-font'
    macros["print"]    = 'script-message repl-size'
    macros["printalt"] = '!repl-size '
    macros["bbox"]     = '!repl-hide; !Blackbox;'
    macros["cbox"]     = '!repl-hide; !Colorbox;'
    macros["box"]      = '#bbox ;'
    macros["safe"]     = 'define_section "no_accidents" "S ignore\nq ignore\nQ ignore\nENTER ignore\nq-q-q quit\n" "force"; enable-section "no_accidents"; print-text "Press q three times to exit as normal."'
    macros["safep"]    = '!type define_section "no_accidents" "S ignore\nq ignore\nQ ignore\nENTER ignore\nq-q-q quit\n" "force"; enable-section "no_accidents";  print-text "Press q three times to exit as normal."'
    macros["nosafe"]   = 'disable_section "no_accidents"; show-text "no_accidents section disabled."; print-text "no_accidents section disabled.";'

    -- Info text
    macros["shrpscl"]  = 'print-text "[sharp] oversample <-> linear (triangle) <-> catmull_rom <-> mitchell <-> gaussian <-> bicubic [smooth]"'
    macros["vf"]       = "print-text 'Example vf command => vf set perspective=0:0.32*H:W:0:0:H:W:.8*H';"
    macros["curves"]   =
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
            for statement in line:gmatch('[^ ;][^;]*[;]?') do
                if #statement > 0 then
                    if statement:sub(-1):match(';') then
                        statements[#statements + 1] = statement
                    else
                        statements[#statements + 1] = statement .. ';'
                    end
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
        -- Macro processing block
        -- #macro => macros['macro'].value
        do
            -- New logging stuff
            local pref = '[macros]'
            local function dbg_macros( log_text )
                if REPL_LOG['macros'] then
                    local macroLogColor = "88CCFF" -- #88CCFF #88FFCC #FFCC88 #FF88CC #CCFF88 #CC88FF
                    dbg_etc( pref .. log_text, macroLogColor )
                end
            end

            --> TODO:   I think the issue with the repl not drawing immediately
            ---       might be in the macro block, at the moment its currently
            ---       replacing the whole line instead the macro token ( even
            ---       if this isn't the reason, its retarded )
            dbg_macros( [[ Entering macro expansion block. ]] )
            if line:match("[^%s]") == "#" and line:find("^[%s]*#[^%s#;]+") then
                local symbol_read = line:match("^[%s]*#[^%s#;]+"):sub(2)

                dbg_macros( [[ # prefix found in line. ]] )
                dbg_macros( [[ line:match("^[%s]*#[^%s#;]+"):sub(2) => ']] .. symbol_read .. "'" )

                if macros[symbol_read] then
                    line = line:gsub(
                        '^([^#]*)(#[^%s]+)(.*)$',
                        function( pre, macro, post )
                            -- not sure if you can just return a string held together with spit in lua
                            local  expanded_line =  pre .. macros[symbol_read] .. post
                            return expanded_line
                    end)

                    dbg_macros( [[ [new] Result using line:gsub to expand macro in place instead of replacing the whole line => ]] .. "\n\t"  .. line )
                    -- dbg_macros( [[ [old] Established, lazier method => ]] .. "\n\t"  .. line )
                    dbg_macros( [[ Replacing value of line with macros[]] .. symbol_read .. '].' )
                    dbg_macros( [[ macros[" ]] .. symbol_read .. [[ "] => ']] ..  macros[symbol_read] .. "'.'" )
                    dbg_macros( [[ This is still debug output, if you have not seen a second copy of the macro expansion (or its byproducts in the log) there is still a issue." ]] )
                end
            end
        end
        -- ! => script-message
        if line:match('[^"]*!') then
            -- lol
            return (do_line(line))
        else --????? Why did this go away
            return line
        end
    end
  -- New line eval code
  function eval_line_new(line)
    --- Subfunctions to parse lines and statements for `!` substitution
        --   TODO: - Generalize beyond single symbol case,
        --         - Integrate do_line() code into body?
        local function parse_statements(line)
            statements = {}
            for statement in line:gmatch('[^ ;][^;]*[;]?') do
                if #statement > 0 then
                    if statement:sub(-1):match(';') then
                        statements[#statements + 1] = statement
                    else
                        statements[#statements + 1] = statement .. ';'
                    end
                end
            end
            update()
            return statements
        end


        -- New logging stuff
        function dbg_macros( log_text )
            local debug_prefix = '[macros]'
            if REPL_LOG['macros'] then
                local macroLogColor = "88CCFF"
                dbg_etc( debug_prefix .. log_text, macroLogColor )
            end
        end


        local function expand_macros(line)
            dbg_macros( [[ Entering macro expansion block. ]] )
            if line:match("[^%s]") == "#" and line:find("^[%s]*#[^%s#;]+") then
                local symbol_read = line:match("^[%s]*#[^%s#;]+"):sub(2)

                dbg_macros( [[ # prefix found in line. ]] )
                dbg_macros( [[ line:match("^[%s]*#[^%s#;]+"):sub(2) => ']] .. symbol_read .. "'" )

                if macros[symbol_read] then
                    line = line:gsub(
                        '^([^#]*)(#[^%s]+)(.*)$',
                        function( pre, macro, post )
                            -- not sure if you can just return a string held together with spit in lua
                            local  expanded_line =  pre .. macros[symbol_read] .. post
                            return expanded_line
                    end)

                    dbg_macros( [[ [new] Result using line:gsub to expand macro in place instead of replacing the whole line => ]] .. "\n\t"  .. line )
                    -- dbg_macros( [[ [old] Established, lazier method => ]] .. "\n\t"  .. line )
                    dbg_macros( [[ Replacing value of line with macros[]] .. symbol_read .. '].' )
                    dbg_macros( [[ macros[" ]] .. symbol_read .. [[ "] => ']] ..  macros[symbol_read] .. "'.'" )
                    dbg_macros( [[ This is still debug output, if you have not seen a second copy of the macro expansion (or its byproducts in the log) there is still a issue." ]] )
                end
            end
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

        -- Macro processing block
        -- #macro => macros['macro'].value


        line = expand_macros( line )
        -- do
            -- --> TODO:   I think the issue with the repl not drawing immediately
            -- ---       might be in the macro block, at the moment its currently
            -- ---       replacing the whole line instead the macro token ( even
            -- ---       if this isn't the reason, its retarded )
            -- dbg_macros( [[ Entering macro expansion block. ]] )
            -- if line:match("[^%s]") == "#" and line:find("^[%s]*#[^%s#;]+") then
            --     local symbol_read = line:match("^[%s]*#[^%s#;]+"):sub(2)

            --     dbg_macros( [[ # prefix found in line. ]] )
            --     dbg_macros( [[ line:match("^[%s]*#[^%s#;]+"):sub(2) => ']] .. symbol_read .. "'" )

            --     if macros[symbol_read] then
            --         line = line:gsub(
            --             '^([^#]*)(#[^%s]+)(.*)$',
            --             function( pre, macro, post )
            --                 -- not sure if you can just return a string held together with spit in lua
            --                 local  expanded_line =  pre .. macros[symbol_read] .. post
            --                 return expanded_line
            --         end)

            --         dbg_macros( [[ [new] Result using line:gsub to expand macro in place instead of replacing the whole line => ]] .. "\n\t"  .. line )
            --         -- dbg_macros( [[ [old] Established, lazier method => ]] .. "\n\t"  .. line )
            --         dbg_macros( [[ Replacing value of line with macros[]] .. symbol_read .. '].' )
            --         dbg_macros( [[ macros[" ]] .. symbol_read .. [[ "] => ']] ..  macros[symbol_read] .. "'.'" )
            --         dbg_macros( [[ This is still debug output, if you have not seen a second copy of the macro expansion (or its byproducts in the log) there is still a issue." ]] )
            --     end
            -- end
        -- end
        -- ! => script-message
        if line:match('[^"]*!') then
            -- lol
            return (do_line(line))
        else
            return (do_line(line))
            -- return line
        end
    end
--

--


-- Device explorer
    function device_info(text)
        if not text or text == "a" then
            plist = mp.get_property_osd("audio-device-list")
        else
            plist = mp.get_property_osd(text)
        end
        pdbg(plist)
    end
--


-- Enum list
    function list_info(text)
        -- Stub
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
    function utils_to_string( toPrint )
        -- toPrint = utils.to_string(toPrint)
        -- log_add('{\\1c&H66ccff&}',
        --         "utils_to_string output (" .. get_type(toPrint) .. ":\n" )


        -- selectPrint = utils.to_string(toPrint):gsub('^[%[]|[%]]$',''):gsub( '(["]+[}]?[,]?[{]?.*?"filename":")', '\n')


        local selectPrint = utils.parse_json( utils.to_string(toPrint) )
        if selectPrint:len() < 0 then
            selectPrint = utils.to_string(toPrint) .. " "
        end
        log_add( '{\\1c&H66ccff&}', "utils_to_string output: " .. selectPrint .. "\n" )
        pdbg(selectPrint)
        -- log_add( '{\\1c&H66ccff&}', "utils_to_string output: " .. selectPrint .. "\n" )
    --    log_add( '{\\1c&H66ccff&}', "utils_to_string output: " .. utils.to_string(toPrint)                                     .. "\n" )
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
        -- print("set_REPL_font_name called with input " .. text)
        opts.font = text
        update()
    end
--

-- Etc debug function - for whatever
    function dbg_etc(text, altLogColor)
        local altLogColor = altLogColor or "FFCC55" --#55CCFF #55FFCC #FFCC55 #FF55CC #CCFF55 #CC55FF
        local function _log(str, altLogColor)
            local logColor = altLogColor or "5555DD" --#DD5555 #55DD55 #5555DD
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
        _logLine( text, altLogColor )
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
         device_info = device_info,
         audio_devices = audio_devices,
         set_REPL_font_size = set_REPL_font_size,
         set_REPL_font_name = set_REPL_font_name,
         get_REPL_font_size = get_REPL_font_size,
         get_REPL_font_name = get_REPL_font_name  }