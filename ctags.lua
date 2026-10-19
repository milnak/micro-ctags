local micro = import("micro")
local shell = import("micro/shell")
local config = import("micro/config")

local function OS()
    local home = os.getenv("HOME")
    return home ~= nil and home:sub(1, 1) == "/" and "unix" or "windows"
end

local function json_decode(str)
    local pos = 1

    local function skip_ws()
        while str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local parse_value

    local escapes = {
        ['"']  = '"',
        ['\\'] = '\\',
        ['/']  = '/',
        ['b']  = '\b',
        ['f']  = '\f',
        ['n']  = '\n',
        ['r']  = '\r',
        ['t']  = '\t',
    }

    local function parse_string()
        -- Skip opening quote.
        pos = pos + 1

        local result = {}

        while pos <= #str do
            local c = str:sub(pos, pos)

            if c == '"' then
                pos = pos + 1
                return table.concat(result)
            elseif c == '\\' then
                pos = pos + 1
                local esc = str:sub(pos, pos)

                if escapes[esc] then
                    result[#result + 1] = escapes[esc]
                    pos = pos + 1
                elseif esc == 'u' then
                    local hex = str:sub(pos + 1, pos + 4)

                    if not hex:match("^%x%x%x%x$") then
                        error("Invalid JSON unicode escape at position " .. pos)
                    end

                    local code = tonumber(hex, 16)

                    -- UTF-8 encode the code point.
                    if code <= 0x7f then
                        result[#result + 1] = string.char(code)
                    elseif code <= 0x7ff then
                        result[#result + 1] = string.char(
                            0xc0 + math.floor(code / 0x40),
                            0x80 + (code % 0x40)
                        )
                    else
                        result[#result + 1] = string.char(
                            0xe0 + math.floor(code / 0x1000),
                            0x80 + (math.floor(code / 0x40) % 0x40),
                            0x80 + (code % 0x40)
                        )
                    end

                    pos = pos + 5
                else
                    error("Invalid JSON escape at position " .. pos)
                end
            else
                result[#result + 1] = c
                pos = pos + 1
            end
        end

        error("Unterminated JSON string")
    end

    local function parse_number()
        local start = pos

        while str:sub(pos, pos):match("[0-9eE+%.%-]") do
            pos = pos + 1
        end

        local n = tonumber(str:sub(start, pos - 1))

        if n == nil then
            error("Invalid JSON number at position " .. start)
        end

        return n
    end

    local function parse_array()
        local result = {}

        pos = pos + 1
        skip_ws()

        if str:sub(pos, pos) == ']' then
            pos = pos + 1
            return result
        end

        while true do
            result[#result + 1] = parse_value()

            skip_ws()

            local c = str:sub(pos, pos)

            if c == ']' then
                pos = pos + 1
                return result
            elseif c ~= ',' then
                error("Expected ',' or ']' at position " .. pos)
            end

            pos = pos + 1
            skip_ws()
        end
    end

    local function parse_object()
        local result = {}

        pos = pos + 1
        skip_ws()

        if str:sub(pos, pos) == '}' then
            pos = pos + 1
            return result
        end

        while true do
            skip_ws()

            if str:sub(pos, pos) ~= '"' then
                error("Expected JSON object key at position " .. pos)
            end

            local key = parse_string()

            skip_ws()

            if str:sub(pos, pos) ~= ':' then
                error("Expected ':' at position " .. pos)
            end

            pos = pos + 1
            skip_ws()

            result[key] = parse_value()

            skip_ws()

            local c = str:sub(pos, pos)

            if c == '}' then
                pos = pos + 1
                return result
            elseif c ~= ',' then
                error("Expected ',' or '}' at position " .. pos)
            end

            pos = pos + 1
        end
    end

    function parse_value()
        skip_ws()

        local c = str:sub(pos, pos)

        if c == '"' then
            return parse_string()
        elseif c == '{' then
            return parse_object()
        elseif c == '[' then
            return parse_array()
        elseif c == '-' or c:match("%d") then
            return parse_number()
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        end

        error("Invalid JSON value at position " .. pos)
    end

    local result = parse_value()

    skip_ws()

    if pos <= #str then
        error("Unexpected data at position " .. pos)
    end

    return result
end

-- Example output from "ctags.exe --fields=+lnS --output-format=json":
-- {"_type": "tag", "name": "All platforms", "path": ".\\README.md", ...}
local function ParseCTagsJson(output)
    local tags = {}

    for line in output:gmatch("[^\r\n]+") do
        micro.Log("[ctags] Parsing JSON line: " .. line)
        local tag = json_decode(line)

        if tag ~= nil and tag._type == "tag" then
            table.insert(tags, tag)
        end
    end

    return tags
end

function InvokeCTags(bp)
    local bufferFilename = bp.Buf.Path

    local ctagsCommand = "ctags --fields=+lnS --output-format=json --sort=foldcase -f - " .. bufferFilename
    micro.Log("[ctags] Running command: " .. ctagsCommand)
    local output, err = shell.RunCommand(ctagsCommand)
    if err ~= nil then
        micro.InfoBar():Error("ctags failed: " .. tostring(err))
        return {}
    end

    return ParseCTagsJson(output)
end

local function InvokeFzf(bufferFilename, tags)
    local function get_filename(path)
        -- Match the last segment after the last '/' or '\'
        return path:match("([^/\\]+)$")
    end

    local function trim_string(str)
        str = string.gsub(str, '^%s+', '')
        str = string.gsub(str, '%s+$', '')
        str = string.gsub(str, '[\n\r]+', '')
        return str
    end

    local filename = os.tmpname()
    local file, openErr = io.open(filename, "w")

    if file == nil then
        micro.InfoBar():Error("Unable to create temporary tag file: " .. tostring(openErr))
        return nil
    end

    for _, tag in ipairs(tags) do
        -- {1} = name[..signature]
        -- {2} = line
        -- {3} = kind
        local tagInfo = tag.name .. (tag.signature or "")
            .. "·" .. tostring(tag.line)
            .. "·" .. tostring(tag.kind)
        local ok, writeErr = file:write(tagInfo .. "\n")
        micro.Log("[ctags] Writing tag to temporary file: " .. tagInfo)

        if ok == nil then
            file:close()
            os.remove(filename)
            micro.InfoBar():Error("Unable to write temporary tag file: " .. tostring(writeErr))
            return nil
        end
    end

    local closed, closeErr = file:close()

    if closed == nil then
        os.remove(filename)
        micro.InfoBar():Error("Unable to close temporary tag file: " .. tostring(closeErr))
        return nil
    end

    micro.Log("[ctags] Temporary tag file created: " .. filename)

    -- Run fzf to select a tag from the temporary file

    local prefix
    local suffix
    if OS() == "windows" then
        prefix = "CMD.EXE /C type " .. filename
        suffix = ""
    else
        prefix = "bash -c \"cat " .. filename
        suffix = "\""
    end

    -- --header \"Press Enter to choose function, or ESC to exit\"
    local command = prefix
        .. " | fzf --reverse"
        .. " --header \"Tags from '" .. get_filename(bufferFilename) .. "'\""
        .. " --delimiter \"·\""
        .. " --no-info"
        .. " --margin \"20%\""
        .. " --border=rounded"
        .. " --border-label \"ctags\""
        .. " --with-nth \"1\""
        .. " --accept-nth \"2\""
        .. " --preview-window \"down:1\""
        .. " --preview-window \"border-sharp\""
        .. " --preview \"echo Type: {3}; Line: {2}\""
        .. suffix
    micro.Log("[ctags] Running command: " .. command)

    -- Use RunInteractiveShell rather than popen() for better control over the shell environment.
    -- param 2: non-interactive shell. Don't want output from fzf sent to screen.
    -- param 3: wait for the command to complete before returning.
    local output, err = shell.RunInteractiveShell(command, false, true)
    if err ~= nil then
        micro.Log("fzf failed: " .. tostring(err))
        return nil
    end
    -- clean up stdout -- remove leading/trailing whitespace and newlines
    output = trim_string(output)
    micro.Log("[ctags] Fzf returned output: [" .. tostring(output) .. "]")

    -- Remove temporary file
    os.remove(filename)

    if output == nil or output == "" then
        micro.InfoBar():Error("[ctags] Fzf returned no output")
        return nil
    end


    local lineNumber = tonumber(output)

    if lineNumber == nil then
        micro.InfoBar():Error("fzf returned an invalid line number: " .. tostring(output))
        return nil
    end

    return lineNumber
end

function init()
    local output, err = shell.RunCommand("ctags --version")
    if err ~= nil then
        micro.InfoBar():Error("[ctags] ctags is not installed or not in the system PATH.")
        return
    end

    local ctagsFlavor = output:match("^([a-zA-Z]+)")
    if ctagsFlavor ~= "Universal" then
        micro.InfoBar():Error("[ctags] Universal Ctags is required. Found: " .. tostring(ctagsFlavor))
        return
    end

    local output, err = shell.RunCommand("fzf --version")
    if err ~= nil then
        micro.InfoBar():Error("[ctags] fzf is not installed or not in the system PATH.")
        return
    end

    -- e.g. "0.29 (devel)", "0.74.5 (c0a193e0)"
    local major, minor = output:match("^(%d+)%.(%d+)")
    if major == nil then
        micro.InfoBar():Error("[ctags] Unable to parse fzf version: " .. output)
        return
    end

    local major, minor = tonumber(major), tonumber(minor)
    -- --accept-nth requires fzf 0.60.2 or newer.
    if major == 0 and minor < 61 then
        micro.InfoBar():Error("[ctags] fzf 0.60.2 or newer is required. Found: " .. output)
        return
    end

    config.MakeCommand(
        "ctags",
        function(bp, args)
            local bufferFilename = bp.Buf.Path
            -- Parse ctags for file in current buffer.

            local tags = InvokeCTags(bp)
            if tags == nil or #tags == 0 then
                micro.InfoBar():Message("No tags found.")
                return
            end

            local lineNumber = InvokeFzf(bufferFilename, tags)
            if lineNumber == nil then
                micro.Log("[ctags] Cancelled.")
                return
            end

            -- Jump to the line number in the current buffer.
            micro.Log("[ctags] Jumping to line number: " .. lineNumber)
            bp.Cursor.Y = lineNumber - 1
            micro.InfoBar():Message(string.format("Jumped to line %i", lineNumber))
        end,
        config.NoComplete
    )
end
