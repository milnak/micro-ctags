-- ctags - Jump to any function, class or heading.
-- Copyright 2026 Jeff Miller
-- https://github.com/milnak/micro-ctags
-- MIT license
VERSION = "1.0.0"

local micro = import("micro")
local shell = import("micro/shell")
local config = import("micro/config")
local buffer = import("micro/buffer")
local util = import("micro/util")

local go_filepath = import("path/filepath")
local go_os = import("os")
local go_runtime = import("runtime")

local json = import("./json")
local history = {}

-- Return whether Micro is running on Windows.
local function IsWindows()
    return go_runtime.GOOS == "windows"
end

-- Quote one argument for Micro's shellquote parser, including on Windows.
local function QuoteArgument(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Read a plugin setting from the ctags namespace.
local function Setting(name)
    return config.GetGlobalOption("ctags." .. name)
end

-- Report a plugin-prefixed error in Micro's info bar.
local function Fail(message)
    micro.InfoBar():Error("[ctags] " .. tostring(message))
end

-- Replace control characters so values cannot split picker fields or records.
local function CleanField(value)
    return (tostring(value or ""):gsub("[%z\1-\31\127]", " "))
end

-- Verify the configured tools and minimum fzf version, reporting failures.
local function CheckTools()
    local output, err = shell.ExecCommand(Setting("executable"), "--version")
    if err ~= nil then
        Fail("Unable to run Universal Ctags: " .. tostring(err))
        return false
    end
    if not output:match("^Universal Ctags") then
        Fail("Universal Ctags with JSON support is required.")
        return false
    end
    output, err = shell.ExecCommand(Setting("fzf"), "--version")
    if err ~= nil then
        Fail("Unable to run fzf: " .. tostring(err))
        return false
    end
    local major, minor, patch = output:match("^(%d+)%.(%d+)%.?(%d*)")
    major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch) or 0
    if major == nil or (major == 0 and (minor < 60 or (minor == 60 and patch < 2))) then
        Fail("fzf 0.60.2 or newer is required. Found: " .. output)
        return false
    end
    return true
end

-- Read and validate tags for the saved file, returning nil on failure.
function InvokeCTags(bp)
    local sort = Setting("sort")
    if sort ~= "yes" and sort ~= "no" and sort ~= "foldcase" then
        Fail("ctags.sort must be yes, no, or foldcase.")
        return nil
    end
    local output, err = shell.ExecCommand(
        Setting("executable"), "--fields=+lnSs", "--output-format=json",
        "--sort=" .. sort, "-f", "-", bp.Buf.AbsPath)
    if err ~= nil then
        Fail("ctags failed: " .. tostring(err) .. " " .. output)
        return nil
    end
    local tags = {}
    for line in output:gmatch("[^\r\n]+") do
        local ok, tag = pcall(json_decode, line)
        if not ok or type(tag) ~= "table" then
            Fail("Invalid ctags JSON: " .. tostring(tag))
            return nil
        end
        if tag._type == "tag" then
            if type(tag.name) ~= "string" or tag.name == ""
                or type(tag.line) ~= "number" or tag.line < 1
                or tag.line % 1 ~= 0 or tag.line > bp.Buf:LinesNum() then
                Fail("ctags returned an invalid tag or a line outside the buffer.")
                return nil
            end
            table.insert(tags, tag)
        end
    end
    return tags
end

-- Run the picker and restore temporary resources; return a selected line or nil.
local function InvokeFzf(bufferFilename, tags, query)
    local filename, file, openErr
    for attempt = 1, 10 do
        filename = go_filepath.Join(go_os.TempDir(),
            "micro-ctags-" .. tostring(go_os.Getpid()) .. "-" .. tostring(math.random(1, 2147483647)))
        file, openErr = go_os.OpenFile(filename, go_os.O_WRONLY + go_os.O_CREATE + go_os.O_EXCL, 384)
        if openErr == nil or not go_os.IsExist(openErr) then
            break
        end
    end
    if file == nil then
        Fail("Unable to create temporary tag file: " .. tostring(openErr))
        return nil
    end
    for _, tag in ipairs(tags) do
        local record = tostring(tag.line) .. "\t" .. CleanField(tag.kind)
            .. "\t" .. CleanField(tag.name) .. CleanField(tag.signature) .. "\n"
        local written, writeErr = file:WriteString(record)
        if writeErr ~= nil or written ~= #record then
            file:Close()
            os.remove(filename)
            Fail("Unable to write temporary tag file: " .. tostring(writeErr))
            return nil
        end
    end
    local closeErr = file:Close()
    if closeErr ~= nil then
        os.remove(filename)
        Fail("Unable to close temporary tag file: " .. tostring(closeErr))
        return nil
    end
    local windows = IsWindows()
    local inputCommand = windows and 'type "%MICRO_CTAGS_INPUT%"'
        or 'cat -- "$MICRO_CTAGS_INPUT"'
    local preview = windows and "echo Type: {2}, Line: {1}"
        or "printf 'Type: %s, Line: %s\\n' {2} {1}"
    local arguments = {
        Setting("fzf"), "--accept-nth=1", "--with-nth=3..", "--delimiter=\t",
        "--border-label=ctags", "--border=rounded", "--cycle", "--no-sort",
        "--header=Tags from " .. CleanField(bufferFilename) .. "\nEnter: jump | Esc: cancel",
        "--height=50%", "--highlight-line",
        "--ignore-case", "--info=inline", "--layout=reverse-list",
        "--margin=10%,10%,10%,10%", "--pointer=>", "--preview=" .. preview,
        "--preview-window=down:1,border-none",
        "--with-shell=" .. (windows and "" or "/bin/sh -c"),
        "--query=" .. CleanField(query),
    }
    for index, argument in ipairs(arguments) do
        arguments[index] = QuoteArgument(argument)
    end
    local environment = {
        MICRO_CTAGS_INPUT = filename,
        FZF_DEFAULT_COMMAND = inputCommand,
        FZF_DEFAULT_OPTS = "",
        FZF_DEFAULT_OPTS_FILE = "",
    }
    if windows then
        environment.SHELL = "cmd.exe"
    end
    local previous = {}
    for name, value in pairs(environment) do
        previous[name] = go_os.Getenv(name)
        local err = go_os.Setenv(name, value)
        if err ~= nil then
            for restoredName, old in pairs(previous) do
                go_os.Setenv(restoredName, old)
            end
            os.remove(filename)
            Fail(err)
            return nil
        end
    end
    local ok, output, err = pcall(shell.RunInteractiveShell, table.concat(arguments, " "), false, true)
    for name, old in pairs(previous) do
        go_os.Setenv(name, old)
    end
    os.remove(filename)
    if not ok then
        Fail("fzf failed: " .. tostring(output))
        return nil
    end
    if err ~= nil then
        local status = tostring(err):match("exit status (%d+)")
        if status ~= "1" and status ~= "130" then
            Fail("fzf failed: " .. tostring(err))
        end
        return nil
    end
    output = (output or ""):match("^%s*(.-)%s*$")
    if output == "" then
        return nil
    end
    local lineNumber = tonumber(output)
    for _, tag in ipairs(tags) do
        if tag.line == lineNumber then
            return lineNumber
        end
    end
    Fail("fzf returned an invalid line number: " .. output)
    return nil
end

-- Clear the selection, move to a valid buffer location, and reveal the cursor.
local function Jump(bp, location)
    bp.Cursor:ResetSelection()
    bp.Cursor:GotoLoc(buffer.Loc(location.X, location.Y))
    bp.Cursor:Relocate()
    bp:Relocate()
end

-- Choose a tag using the initial query and record the origin before jumping.
local function Navigate(bp, args)
    if bp.Buf.Path == "" then
        micro.InfoBar():Message("Save this buffer before looking up tags.")
        return
    end
    if bp.Buf:Modified() then
        micro.InfoBar():Message("Save changes before looking up tags; ctags reads the file on disk.")
        return
    end
    if not CheckTools() then
        return
    end
    local query = ""
    if args ~= nil and #args > 0 then
        query = table.concat(args, " ")
    elseif bp.Cursor:HasSelection() then
        query = util.String(bp.Cursor:GetSelection())
    elseif Setting("wordquery") then
        query = util.String(bp.Buf:WordAt(buffer.Loc(bp.Cursor.X, bp.Cursor.Y)))
    end
    local tags = InvokeCTags(bp)
    if tags == nil then
        return
    end
    if #tags == 0 then
        micro.InfoBar():Message("No tags found.")
        return
    end
    local _, fileName = go_filepath.Split(bp.Buf.AbsPath)
    local lineNumber = InvokeFzf(fileName, tags, query)
    if lineNumber == nil then
        return
    end
    local locations = history[bp.Buf.AbsPath] or {}
    history[bp.Buf.AbsPath] = locations
    table.insert(locations, { X = bp.Cursor.X, Y = bp.Cursor.Y })
    if #locations > 100 then
        table.remove(locations, 1)
    end
    Jump(bp, { X = 0, Y = lineNumber - 1 })
    micro.InfoBar():Message(string.format("Jumped to line %i", lineNumber))
end

-- Register plugin settings, navigation commands, and the help document.
function init()
    config.RegisterCommonOption("ctags", "executable", "ctags")
    config.RegisterCommonOption("ctags", "fzf", "fzf")
    config.RegisterCommonOption("ctags", "sort", "foldcase")
    config.RegisterCommonOption("ctags", "wordquery", true)

    config.MakeCommand("ctags", Navigate, config.NoComplete)

    -- Restore the most recent jump origin for the current file, if available.
    config.MakeCommand("ctags-back", function(bp)
        local locations = history[bp.Buf.AbsPath]
        if locations == nil or #locations == 0 then
            micro.InfoBar():Message("No previous ctags location in this buffer.")
            return
        end
        Jump(bp, table.remove(locations))
    end, config.NoComplete)

    config.AddRuntimeFile("ctags", config.RTHelp, "help/ctags.md")
end

-- Discard a file's jump history when its buffer closes.
function onBufferClose(buf)
    history[buf.AbsPath] = nil
end
