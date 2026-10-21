-- Decode a JSON value into Lua values, raising an error for invalid input.
function json_decode(str)
    local pos = 1

    -- Advance the parser past whitespace at the current position.
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

    -- Read a quoted JSON string and decode its escape sequences.
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

    -- Read a JSON number and convert it to a Lua number.
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

    -- Read a JSON array into a sequential Lua table.
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

    -- Read a JSON object into a Lua table keyed by property name.
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

    -- Dispatch the next JSON value to its parser and consume literal values.
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

