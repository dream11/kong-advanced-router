local http = require "resty.http"
local cjson_safe = require "cjson.safe"
local inspect = require "inspect"

local generate_signature_hash = require("kong.plugins.advanced-router.utils").generate_signature_hash
local extract = require "kong.plugins.advanced-router.utils".extract
local belongs = require "kong.plugins.advanced-router.utils".belongs
local replaceStringEnvVariables = require "kong.plugins.advanced-router.utils".replaceStringEnvVariables

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
        return value
    else
        value = extract(key, kong.request.get_query())
        return value
    end
    return value
end

function extract_io_data_from_request(conf)
    local io_request_template = cjson_safe.decode(conf.io_request_template)
    local io_req = {
        headers = {},
        query = {},
        body = {}
    }
    local req_parts = { "headers", "query", "body" }

    -- This loop parses the io_request_template and populates each field from request data
    for _, part in ipairs(req_parts) do
        if io_request_template[part] then
            for key, value in pairs(io_request_template[part]) do
                local i = string.find(value, "%.")
                if i then
                    local from_part = value:sub(1, i - 1)
                    if belongs(part, req_parts) then
                        io_req[part][key] = extract_from_request(from_part, value:sub(i + 1))
                    else
                        io_req[part][key] = value
                    end
                else
                    io_req[part][key] = value
                end
            end
        end
    end
    return io_req
end

function get_cache_key(data)
    local json_string = cjson_safe.encode(data)
    local hash = generate_signature_hash(json_string)
    return hash
end

function get_io_data_from_remote(request_data, conf)
    kong.log.debug("Making io call::" .. inspect(request_data))
    local client = get_http_client(conf)
    request_data.headers["Content-Type"] = "application/json"
    local res, err1 = client:request_uri(
        request_data.io_url,
        {
            method = request_data.io_http_method,
            headers = request_data.headers,
            body = cjson_safe.encode(request_data.body),
            query = request_data.query
        }
    )
    kong.log.debug("IO call error::" .. inspect(err1))
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
    kong.log.debug("Data from I/O::" .. inspect(bodyJson))
    local cacheTTL
    if conf.cache_io_response then
        cacheTTL = res.headers[conf.cache_ttl_header] or conf["default_edge_ttl_sec"]
    else
        cacheTTL = -1
    end

    return bodyJson, nil, tonumber(cacheTTL)
end

function get_io_data(request_data, conf)
    local cache_key = get_cache_key(request_data)
    kong.log.debug("cache_key::" .. cache_key)
    -- TODO: Check all options parameters
    -- ttl values are overridden if callback returns ttl as third return value
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
    kong.log.debug("conf" .. inspect(conf))
    io_request["io_url"] = replaceStringEnvVariables(conf.io_url)
    io_request["io_http_method"] = conf.io_http_method
    return io_request
end

function _M.get_io_data(conf)
    local io_request = create_io_request(conf)
    return get_io_data(io_request, conf)
end

return _M
