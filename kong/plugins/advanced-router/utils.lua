local pl_utils = require "pl.utils"
local sha256 = require "resty.sha256"
local encode_base64 = ngx.encode_base64

local _M = {}

function _M.replaceStringEnvVariables(s, data)
    return
    string.gsub(
        s,
        "%%[A-Za-z_]+%%",
        function(str)
            local variable = string.sub(str, 2, string.len(str) - 1)
            if data then
                local value_from_data = _M.extract(variable, data)
                if value_from_data then
                    return value_from_data
                end
            end
            return os.getenv(variable)
        end
    )
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

function _M.generate_signature_hash(s)
    local digest = sha256:new()
    digest:update(s)
    local hash = encode_base64(digest:final())
    return hash
end

function _M.belongs(val, tbl)
    print(require "inspect"(tbl))
    for _, v in pairs(tbl) do
        if v == val then
            return true
        end
    end
    return false
end

return _M