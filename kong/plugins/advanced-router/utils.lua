local pl_utils = require "pl.utils"
local inspect = require "inspect"

local _M = {}

function interpolate_string_env_cb(s)
    local ttl = 36000
    return string.gsub(
        s,
        "%%[A-Za-z_%.]+%%",
        function(str)
            local variable = string.sub(str, 2, string.len(str) - 1)
            return os.getenv(variable)
        end
    ), nil, ttl
end


function _M.interpolate_string_env(s)
    local result, err = kong.cache:get('interpolate:' .. s, {}, interpolate_string_env_cb, s)
    if err then
        kong.log.err("Error in interpolating string::" .. inspect(s))
        return kong.response.exit(500, { error = "Something went wrong" })
    end
    return result
end

function _M.extract(key, data)
    if type(data) ~= 'table' then
        return
    end
    local keys_array = pl_utils.split(key, "%.")
    local root_key = table.remove(keys_array, 1)
    if #keys_array > 0 then
        return _M.extract(table.concat(keys_array, '.'), data[root_key])
    else
        return data[root_key]
    end
end

return _M
