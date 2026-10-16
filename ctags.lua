local micro = import("micro")
local shell = import("micro/shell")
local config = import("micro/config")

local function OS()
    local home = os.getenv("HOME")
    return home ~= nil and home:sub(1, 1) == "/" and "unix" or "windows"
end

-- Example output from "ctags.exe --fields=+lnS"
-- "~Hash\t./Hash.cpp\t/^Hash::~Hash()$/;"\tf\tline:23\tlanguage:C++\tclass:foo::Hash\tsignature:()"
local function ParseCTags(output)
    local tags = {}

    for line in output:gmatch("[^\r\n]+") do
        local fields = {}

        for field in (line .. "\t"):gmatch("(.-)\t") do
            table.insert(fields, field)
        end

        if #fields >= 4 then
            local tag = {
                name = fields[1],
                path = fields[2],
                pattern = fields[3],
                kind = fields[4]
            }

            for i = 5, #fields do
            	local field = fields[i]
				local key, value = field:match("^([^:]+):(.*)$")

                if key then
                    if key == "line" then
                        value = tonumber(value)
                    elseif key == "file" then
                        value = true
                    end

                    tag[key] = value
                end
            end

            table.insert(tags, tag)
        end
    end

    return tags
end

function InvokeCTags(bp)
    local filename = bp.Buf.Path

    -- flags: "afmikKlnsStz"
    local output, err = shell.RunCommand("ctags --fields=+lnS --sort=foldcase -f - " .. filename)
    if err ~= nil then
        micro.InfoBar():Error("ctags failed: " .. tostring(err))
        return {}
    end

    return ParseCTags(output)
end

local function InvokeFzf(tags)
    local filename = os.tmpname()
    local file, openErr = io.open(filename, "w")

    if file == nil then
        micro.InfoBar():Error("Unable to create temporary tag file: " .. tostring(openErr))
        return nil
    end

    for _, tag in ipairs(tags) do
        local method = tag.name .. (tag.signature or "")
		local tagInfo = method .. "\t" .. tostring(tag.line)
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
        prefix = "CMD.EXE /C \"type " .. filename
        suffix =  "\""
    else
        prefix = "bash -c \"cat " .. filename
        suffix =  "\""
    end

	local command = prefix .. " | fzf --reverse --delimiter=\\t --no-info --header \"Press Enter to choose function, or ESC to exit\" --border-label \"ctags\" --border=rounded --margin=10% --accept-nth 2" .. suffix
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
	output = string.gsub(output, '^%s+', '')
	output = string.gsub(output, '%s+$', '')
	output = string.gsub(output, '[\n\r]+', '')
	micro.Log("[ctags] Fzf returned output: [" .. tostring(output) .. "]")

    -- Remove temporary file
    os.remove(filename)

	if output == nil or output == "" then
		micro.Log("[ctags] Fzf returned no output")
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

    local output, err = shell.RunCommand("fzf --version")
    if err ~= nil then
        micro.InfoBar():Error("[ctags] fzf is not installed or not in the system PATH.")
        return
    end

    local major, minor, patch = output:match("^%s*(%d+)%.(%d+)%.(%d+)")
    if major == nil then
        micro.InfoBar():Error("[ctags] Unable to parse fzf version: " .. output)
        return
    end

    major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch)
    -- --accept-nth requires fzf 0.60.2 or newer.
    if major == 0 and (minor < 60 or (minor == 60 and patch < 2)) then
        micro.InfoBar():Error("[ctags] fzf 0.60.2 or newer is required.")
        return
    end

    config.MakeCommand(
        "ctags",
        function(bp, args)
			-- Parse ctags for file in current buffer.

            local tags = InvokeCTags(bp)
            if tags == nil then
                micro.InfoBar():Message("No tags found.")
                return
            end

            local lineNumber = InvokeFzf(tags)
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
