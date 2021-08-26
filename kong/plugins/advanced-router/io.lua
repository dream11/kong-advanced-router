local http = require "resty.http"
local cjson_safe = require "cjson.safe"
local inspect = require "inspect"
local pl_utils = require "pl.utils"
local pl_tablex = require "pl.tablex"

local extract = require "kong.plugins.advanced-router.utils".extract
local interpolate_string_env = require "kong.plugins.advanced-router.utils".interpolate_string_env

local _M = {}

local function get_http_client(conf)
    local client = http.new()
    client:set_timeouts(
        conf["http_connect_timeout"],
        conf["http_read_timeout"],
        conf["http_send_timeout"]
    )
    return client
end

function extract_from_request(object, key)
    local value
    if object == 'headers' then
        value = extract(string.lower(key), kong.request.get_headers())
    else
        value = extract(key, kong.request.get_query())
    end
    return value
end

function get_io_request_template(conf)
    return cjson_safe.decode(conf.io_request_template), nil, 120
end

function extract_io_data_from_request(conf)
    -- TODO - Done: cache this for each route
    local cache_key = 'io_request_template:' .. conf.route_id
    local io_request_template = kong.cache:get(cache_key, {}, get_io_request_template, conf)

    local io_req = {
        headers = {},
        query = {},
        body = {}
    }
    local req_parts = { "headers", "query", "body" }

    -- This loop parses the io_request_template and populates each field from request data
    for _, req_part in ipairs(req_parts) do
        if io_request_template[req_part] then
            -- Ex: req_part = headers, key = a, value = headers.a
            for key, value in pairs(io_request_template[req_part]) do
                local first_part, second_part = pl_utils.splitv(value, '%.')
                if second_part and pl_tablex.find(req_parts, first_part) then
                    io_req[req_part][key] = extract_from_request(first_part, second_part)
                else
                    io_req[req_part][key] = value
                end
            end
        end
    end
    return io_req
end

function get_io_data_from_remote(request_data, conf)
    local client = get_http_client(conf)
    local res, err1 = client:request_uri(
        request_data.io_url,
        {
            method = request_data.io_http_method,
            headers = pl_tablex.merge(request_data.headers, { ['Content-Type'] = 'application/json' }),
            body = cjson_safe.encode(request_data.body),
            query = request_data.query
        }
    )
    if not res or err1 then
        return nil, err1
    end
    if not err1 and res and res.status ~= 200 then
        return nil, "IO call failed - Response status:" .. res.status
    end
    local bodyJson, err2 = cjson_safe.decode(res["body"])
    if not bodyJson then
        return nil, err2
    end
    local cacheTTL
    if conf.cache_io_response then
        cacheTTL = res.headers[conf.cache_ttl_header] or conf["default_cache_ttl_sec"]
    else
        cacheTTL = -1
    end
    return bodyJson, nil, tonumber(cacheTTL)
end

function get_io_data(request_data, conf)
    local cache_key = request_data['cache_key']
    -- These values are default ttl values if they are not returned from callback function
    local options = {
        ttl = 60,
        neg_ttl = 60
    }
    local io_data, err = kong.cache:get(cache_key, options, get_io_data_from_remote, request_data, conf)
    if err then
        kong.log.err("Error in loading app-version config from cache", err)
        return nil, err
    end
    return io_data
end

function create_io_request(conf)
    local io_request = extract_io_data_from_request(conf)
    -- TODO - Done - cached inside function: not p0 cache this and check perfa
    local req_part, key = pl_utils.splitv(conf.cache_identifier, "%.")

    local cache_identifier = extract_from_request(req_part, key)
    if not cache_identifier then
        return kong.response.exit(400, { error = "Cache identifier not found in request:: " .. conf.cache_identifier })
    end

    io_request["cache_key"] = conf.io_http_method .. ':' .. conf.io_url .. ':' .. extract_from_request(req_part, key)
    io_request["io_url"] = interpolate_string_env(conf.io_url)
    io_request["io_http_method"] = conf.io_http_method

    return io_request
end

function _M.get_io_data(conf)
    local io_request = create_io_request(conf)
    return get_io_data(io_request, conf)
end

return _M
