local micro = import("micro")
local shell = import("micro/shell")
local config = import("micro/config")

local json = require("json")

-- Detect the shell platform from the HOME environment variable.
local function OS()
    -- Returns "unix" or "windows" based on the HOME environment variable
    -- Maybe there's a better way to do this, but I haven't figured one out yet.
    local home = os.getenv("HOME")
    return home ~= nil and home:sub(1, 1) == "/" and "unix" or "windows"
end

-- Collect tag records from newline-delimited ctags JSON output.
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

-- Run ctags for the current buffer and return its tags, or an empty table on failure.
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

-- Present tags in fzf with an optional query and return the selected line or nil.
local function InvokeFzf(bufferFilename, tags, query)
    -- Strip surrounding whitespace and all line breaks from shell output.
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
        -- IMPORTANT: Ensure the order here matches the fzf indices
        -- {1} = line_number
        -- {2} = kind
        -- {3} = name[..signature]
        local tagInfo =
            tostring(tag.line)
            .. "·" .. tostring(tag.kind)
            .. "·" .. tag.name .. (tag.signature or "")
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
    local quoteChar
    local altQuoteChar
    local suffix
    if OS() == "windows" then
        prefix = "CMD.EXE /C type " .. filename
        quoteChar = "\""
        suffix = ""
    else
        prefix = "bash -c \"cat " .. filename
        quoteChar = "'"
        suffix = "\""
    end

    -- IMPORTANT: Ensure the indices here match the ctags file output
    -- {1} = line_number
    -- {2} = kind
    -- {3} = name[..signature]
    local command = prefix
        .. " | fzf"
        -- Define which fields to print on accept
        .. " --accept-nth " .. quoteChar .. "1" .. quoteChar
        -- Transform the presentation of each line using field index expressions
        .. " --with-nth " .. quoteChar .. "3" .. quoteChar
        -- Field delimiter regex (default: AWK-style)
        .. " --delimiter " .. quoteChar .. "·" .. quoteChar
        .. " --border-label " .. quoteChar .. "ctags" .. quoteChar
        .. " --border " .. quoteChar .. "rounded" .. quoteChar
        .. " --cycle"
        .. " --footer " .. quoteChar .. "Tags from " .. bufferFilename .. quoteChar
        .. " --header " .. quoteChar .. "Press Enter to choose function, or ESC to exit" .. quoteChar
        .. " --highlight-line"
        .. " --ignore-case"
        .. " --info " .. quoteChar .. "inline" .. quoteChar
        .. " --input-border " .. quoteChar .. "dashed" .. quoteChar
        .. " --layout " .. quoteChar .. "reverse-list" .. quoteChar
        .. " --margin " .. quoteChar .. "10%,10%,10%,10%" .. quoteChar
        .. " --pointer " .. quoteChar .. "➤" .. quoteChar
        .. " --preview " .. quoteChar .. "echo Type: {2}; Line: {1}" .. quoteChar
        .. " --preview-window " .. quoteChar .. "border-sharp" .. quoteChar
        .. " --preview-window " .. quoteChar .. "down:1" .. quoteChar
    if query ~= nil then
        command = command .. " --query " .. quoteChar .. query .. quoteChar
    end
    command = command .. suffix

    micro.Log("[ctags] Running command: " .. command)

    -- Use RunInteractiveShell rather than popen() for better control over the shell environment.
    -- param 2: non-interactive shell. Don't want output from fzf sent to screen.
    -- param 3: wait for the command to complete before returning.
    local output, err = shell.RunInteractiveShell(command, false, true)
    if err ~= nil then
        micro.InfoBar():Error("fzf failed: " .. tostring(err))
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

-- Check required tools and versions, then register the ctags navigation command.
function init()
    local output, err = shell.ExecCommand("ctags", "--version")
    if err ~= nil then
        -- err is a golang "errors.New(...)"
        micro.InfoBar():Error(err)
        return
    else
        micro.Log("[ctags] ctags version: " .. output:match("[^\r\n]+"))
    end

    local ctagsFlavor = output:match("^([a-zA-Z]+)")
    if ctagsFlavor ~= "Universal" then
        micro.InfoBar():Error("[ctags] Universal Ctags is required. Found: " .. tostring(ctagsFlavor))
        return
    end

    local output, err = shell.ExecCommand("fzf", "--version")
    if err ~= nil then
        micro.InfoBar():Error(err)
        return
    else
        micro.Log("[ctags] fzf version: " .. output)
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
        -- Use selected text to filter tags, then jump to the chosen tag's line.
        function(bp, args)
            -- Use selection as initial fzf query, if available.
            local query = nil

            if bp.Cursor:HasSelection() then
                local from, to = bp.Cursor.CurSelection[1], bp.Cursor.CurSelection[2]
                if (from.Y == to.Y) then
                    query = bp.Buf:Line(from.Y):sub(from.X + 1, to.X)
                end
            end


            -- Parse ctags for file in current buffer.

            local tags = InvokeCTags(bp)
            if tags == nil or #tags == 0 then
                micro.InfoBar():Message("No tags found.")
                return
            end

            -- Invoke fzf to select a tag from the list of tags.

            local lineNumber = InvokeFzf(bp.Buf.GetName(bp.Buf), tags, query)
            if lineNumber == nil then
                micro.Log("[ctags] Cancelled.")
                return
            end

            -- Jump to the line number for the selected tag.

            micro.Log("[ctags] Jumping to line number: " .. lineNumber)
            bp.Cursor.Y = lineNumber - 1
            micro.InfoBar():Message(string.format("Jumped to line %i", lineNumber))
        end,
        config.NoComplete
    )
end
