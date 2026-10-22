local commands, settings, errors, messages, calls = {}, {}, {}, {}, {}
local environment = {}
local runtime = { GOOS = "windows" }
local version, tagOutput, execError, fzfOutput, fzfError, fzfThrows
local lastArguments, lastRecords, lastFilename
local testDirectory = arg[0]:match("^(.*[/\\])") or ""
local passed = 0

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function splitArguments(command)
    local arguments, value, quoted, escaped, started = {}, "", false, false, false
    for index = 1, #command do
        local character = command:sub(index, index)
        if escaped then
            value, escaped = value .. character, false
        elseif character == "\\" and not quoted then
            escaped, started = true, true
        elseif character == "'" then
            quoted, started = not quoted, true
        elseif character:match("%s") and not quoted then
            if started then
                table.insert(arguments, value)
                value, started = "", false
            end
        else
            value, started = value .. character, true
        end
    end
    assert(not quoted and not escaped, "Balanced command quoting")
    if started then table.insert(arguments, value) end
    return arguments
end

local function option(prefix)
    for _, argument in ipairs(lastArguments or {}) do
        if argument:sub(1, #prefix) == prefix then
            return argument:sub(#prefix + 1)
        end
    end
end

local modules = {
    micro = {
        InfoBar = function()
            return {
                Error = function(_, message) table.insert(errors, message) end,
                Message = function(_, message) table.insert(messages, message) end,
            }
        end,
    },
    ["micro/config"] = {
        RegisterCommonOption = function(plugin, name, value) settings[plugin .. "." .. name] = value end,
        GetGlobalOption = function(name) return settings[name] end,
        MakeCommand = function(name, command) commands[name] = command end,
        AddRuntimeFile = function(plugin, filetype, path) end,
    },
    ["micro/buffer"] = { Loc = function(column, row) return { X = column, Y = row } end },
    ["micro/util"] = { String = function(value) return value end },
    runtime = runtime,
    os = {
        Getenv = function(name) return environment[name] or "" end,
        Setenv = function(name, value) environment[name] = value end,
        TempDir = function() return os.getenv("TEMP") or "/tmp" end,
        Getpid = function() return 12345 end,
        O_WRONLY = 1, O_CREATE = 2, O_EXCL = 4,
        IsExist = function(err) return false end,
        OpenFile = function(filename, flags, mode)
            equal(flags, 7, "Exclusive file creation")
            equal(mode, 384, "Private file permissions")
            local file, err = io.open(filename, "w")
            if file == nil then return nil, err end
            return {
                WriteString = function(_, text)
                    local ok, writeErr = file:write(text)
                    return ok and #text or 0, writeErr
                end,
                Close = function()
                    local ok, closeErr = file:close()
                    if not ok then return closeErr end
                end,
            }
        end,
    },
    ["path/filepath"] = {
        Split = function(path) return path:match("^(.*[/\\])(.-)$") end,
        Join = function(directory, name) return directory .. "/" .. name end,
    },
    ["micro/shell"] = {
        ExecCommand = function(executable, ...)
            local arguments = { ... }
            table.insert(calls, { executable = executable, arguments = arguments })
            if arguments[1] == "--version" then
                if executable == settings["ctags.executable"] then return "Universal Ctags 6.1.0" end
                return version
            end
            return tagOutput, execError
        end,
        RunInteractiveShell = function(command, wait, getOutput)
            equal(wait, false, "Do not pause after fzf")
            equal(getOutput, true, "Capture fzf selection")
            lastArguments = splitArguments(command)
            lastFilename = environment.MICRO_CTAGS_INPUT
            local file = assert(io.open(lastFilename, "r"))
            lastRecords = file:read("*a")
            file:close()
            equal(environment.FZF_DEFAULT_OPTS, "", "Isolate global fzf options")
            equal(environment.FZF_DEFAULT_OPTS_FILE, "", "Isolate global fzf option file")
            if runtime.GOOS == "windows" then
                equal(environment.FZF_DEFAULT_COMMAND, 'type "%MICRO_CTAGS_INPUT%"', "Windows input")
                equal(option("--with-shell="), "", "Allow fzf to detect the Windows shell type")
                equal(environment.SHELL, "cmd.exe", "Select CMD through the environment")
            else
                equal(environment.FZF_DEFAULT_COMMAND, 'cat -- "$MICRO_CTAGS_INPUT"', "Unix input")
                equal(environment.SHELL, "pwsh.exe", "Do not override the Unix shell environment")
            end
            if fzfThrows then error("simulated launch exception") end
            return fzfOutput, fzfError
        end,
    },
}

function import(name)
    if name == "./json" then
        dofile(testDirectory .. "../json.lua")
        return {}
    end
    return assert(modules[name], "Unexpected import: " .. name)
end

dofile(testDirectory .. "../ctags.lua")
init()

local function pane()
    local buf = { Path = "example.lua", AbsPath = "C:/a space & %name%/example.lua", modified = false }
    function buf:Modified() return self.modified end
    function buf:LinesNum() return 20 end
    function buf:WordAt() return "target" end
    local cursor = { X = 4, Y = 1, selection = nil }
    function cursor:HasSelection() return self.selection ~= nil end
    function cursor:GetSelection() return self.selection end
    function cursor:ResetSelection() self.selection = nil end
    function cursor:GotoLoc(location) self.X, self.Y = location.X, location.Y end
    function cursor:Relocate() self.Y = math.max(0, math.min(self.Y, buf:LinesNum() - 1)) end
    local bp = { Buf = buf, Cursor = cursor }
    function bp:Relocate() self.relocated = true end
    return bp
end

local function reset()
    errors, messages, calls = {}, {}, {}
    lastArguments, lastRecords, lastFilename = nil, nil, nil
    version, execError, fzfOutput, fzfError, fzfThrows = "0.60.2 (test)", nil, "7\r\n", nil, false
    tagOutput = '{"_type":"tag","name":"target","line":7,"kind":"function","scope":"Example","signature":"(first, second)"}'
    settings["ctags.executable"], settings["ctags.fzf"] = "ctags", "fzf"
    settings["ctags.sort"], settings["ctags.wordquery"] = "foldcase", true
    environment = { SHELL = "pwsh.exe", FZF_DEFAULT_COMMAND = "original command", FZF_DEFAULT_OPTS = "--multi", FZF_DEFAULT_OPTS_FILE = "original file" }
    return pane()
end

local function checkCleanup()
    if lastFilename then
        local file = io.open(lastFilename, "r")
        if file then file:close() end
        equal(file, nil, "Temporary file removed")
    end
    equal(environment.FZF_DEFAULT_COMMAND, "original command", "Restore input command")
    equal(environment.FZF_DEFAULT_OPTS, "--multi", "Restore user options")
    equal(environment.FZF_DEFAULT_OPTS_FILE, "original file", "Restore option file")
    equal(environment.SHELL, "pwsh.exe", "Restore user's shell")
    equal(environment.MICRO_CTAGS_INPUT or "", "", "Clear temporary input path")
end

local function test(name, run)
    local bp = reset()
    run(bp)
    checkCleanup()
    passed = passed + 1
    print("PASS " .. name)
end

for _, platform in ipairs({ "windows", "linux" }) do
    runtime.GOOS = platform
    test(platform .. " navigation, fields, and jump back", function(bp)
        commands.ctags(bp, {})
        equal(#errors, 0, "No navigation errors: " .. table.concat(errors, "; "))
        equal(bp.Cursor.Y, 6, "Jump to tag")
        equal(bp.relocated, true, "Reveal cursor")
        equal(option("--query="), "target", "Word under cursor")
        equal(option("--with-nth="), "3..", "Display full signature")
        equal(option("--delimiter="), "\t", "Tab delimiter")
        equal(lastRecords, "7\tfunction\ttarget(first, second)\n", "Name and full signature without scope")
        equal(option("--footer="), nil, "No unsupported footer")
        if platform == "linux" then
            assert(option("--preview="):find("printf", 1, true), "POSIX preview")
        else
            assert(not option("--preview="):find(";", 1, true), "Windows preview")
        end
        commands["ctags-back"](bp)
        equal(bp.Cursor.X, 4, "Restore column")
        equal(bp.Cursor.Y, 1, "Restore row")
    end)
    test(platform .. " Markdown heading without ancestor scopes", function(bp)
        tagOutput = '{"_type":"tag","name":"All platforms","line":7,"kind":"section","scope":"micro-ctags - Jump functionality\\\"\\\"Install"}'
        commands.ctags(bp, {})
        equal(#errors, 0, "No heading errors")
        equal(lastRecords, "7\tsection\tAll platforms\n", "Display only the heading name")
    end)
    test(platform .. " hostile query stays one argument", function(bp)
        local query = [[quote' " $(touch injected) `cmd` & | %PATH% !value! C:\path]]
        bp.Cursor.selection = query
        commands.ctags(bp, {})
        equal(option("--query="), query, "Preserve literal query")
        equal(#lastArguments, 20, "No injected arguments")
    end)
end

for _, status in ipairs({ "1", "130" }) do
    test("quiet fzf exit " .. status, function(bp)
        fzfOutput, fzfError = "", "exit status " .. status
        commands.ctags(bp, {})
        equal(#errors, 0, "Cancellation is not an error")
        equal(bp.Cursor.Y, 1, "Do not jump")
    end)
end

test("fzf failure cleanup", function(bp)
    fzfError = "exit status 2"
    commands.ctags(bp, {})
    equal(#errors, 1, "Report launch failure")
    equal(bp.Cursor.Y, 1, "Do not jump")
end)
test("fzf exception cleanup", function(bp)
    fzfThrows = true
    commands.ctags(bp, {})
    equal(#errors, 1, "Report exception")
end)
test("empty fzf output", function(bp)
    fzfOutput = nil
    commands.ctags(bp, {})
    equal(#errors, 0, "Empty selection is quiet")
end)
test("unexpected selected line", function(bp)
    fzfOutput = "8"
    commands.ctags(bp, {})
    equal(#errors, 1, "Reject line absent from tags")
    equal(bp.Cursor.Y, 1, "Do not jump")
end)

for _, invalid in ipairs({ "broken JSON", "null", "true", "{} trailing",
    '{"_type":"tag","name":"bad","line":0}',
    '{"_type":"tag","name":"bad","line":1.5}',
    '{"_type":"tag","name":"bad","line":21}',
    '{"_type":"tag","name":"bad","line":"7"}',
    '{"_type":"tag","line":7}' }) do
    test("reject " .. invalid, function(bp)
        tagOutput = invalid
        commands.ctags(bp, {})
        equal(#errors, 1, "Report invalid JSON or tag")
        equal(lastArguments, nil, "Do not launch fzf")
    end)
end

for _, supported in ipairs({ "0.60.2", "0.60.3", "0.61.0", "1.0.0" }) do
    test("accept fzf " .. supported, function(bp)
        version = supported
        commands.ctags(bp, {})
        equal(#errors, 0, "Supported version")
        equal(bp.Cursor.Y, 6, "Jump")
    end)
end
for _, unsupported in ipairs({ "0.60.1", "0.60", "0.59.9", "unknown" }) do
    test("reject fzf " .. unsupported, function(bp)
        version = unsupported
        commands.ctags(bp, {})
        equal(#errors, 1, "Unsupported version")
        equal(lastArguments, nil, "Do not launch fzf")
    end)
end

test("unsaved buffer", function(bp)
    bp.Buf.modified = true
    commands.ctags(bp, {})
    equal(#calls, 0, "Do not read stale disk contents")
    assert(messages[1]:find("Save changes", 1, true))
end)
test("unnamed buffer", function(bp)
    bp.Buf.Path = ""
    commands.ctags(bp, {})
    equal(#calls, 0, "Do not invoke tools")
    assert(messages[1]:find("Save this buffer", 1, true))
end)
test("explicit query and configured executables", function(bp)
    settings["ctags.executable"], settings["ctags.fzf"] = "C:/tools with spaces/ctags.exe", "C:/tools with spaces/fzf.exe"
    settings["ctags.sort"] = "no"
    commands.ctags(bp, { "explicit", "query" })
    equal(option("--query="), "explicit query", "Command argument query")
    equal(lastArguments[1], settings["ctags.fzf"], "Configured fzf")
    equal(calls[3].executable, settings["ctags.executable"], "Configured ctags")
    equal(calls[3].arguments[3], "--sort=no", "Configured sorting")
    equal(calls[3].arguments[6], bp.Buf.AbsPath, "Use absolute file path")
end)
test("disable word query", function(bp)
    settings["ctags.wordquery"] = false
    commands.ctags(bp, {})
    equal(option("--query="), "", "Browse all tags")
end)
test("ctags process failure", function(bp)
    execError = "exit status 1"
    commands.ctags(bp, {})
    equal(#errors, 1, "One actionable error")
    equal(#messages, 0, "Do not replace error with no tags message")
end)
test("no tags", function(bp)
    tagOutput = '{"_type":"ptag","name":"metadata"}'
    commands.ctags(bp, {})
    equal(#errors, 0, "Metadata ignored")
    equal(messages[1], "No tags found.", "Empty tags message")
end)
test("sanitize record control characters", function(bp)
    tagOutput = '{"_type":"tag","name":"target\\tname\\nextra","line":7,"kind":"function","signature":"(a,\\tb)"}'
    commands.ctags(bp, {})
    equal(lastRecords, "7\tfunction\ttarget name extra(a, b)\n", "Exactly three fields and one record")
end)
test("invalid sort setting", function(bp)
    settings["ctags.sort"] = "invalid"
    commands.ctags(bp, {})
    equal(#errors, 1, "Reject invalid sort")
    equal(lastArguments, nil, "Do not launch fzf")
end)

test("history survives a different buffer wrapper", function(bp)
    commands.ctags(bp, {})
    local other = pane()
    other.Cursor.X, other.Cursor.Y = 0, 6
    commands["ctags-back"](other)
    equal(other.Cursor.X, 4, "Restore column through a fresh wrapper")
    equal(other.Cursor.Y, 1, "Restore row through a fresh wrapper")
end)
test("closing a buffer clears history", function(bp)
    commands.ctags(bp, {})
    onBufferClose(bp.Buf)
    commands["ctags-back"](bp)
    equal(bp.Cursor.Y, 6, "Do not restore a closed buffer's history")
    equal(messages[#messages], "No previous ctags location in this buffer.", "Empty history message")
end)

print(string.format("%d tests passed", passed))
