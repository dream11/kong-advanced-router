local inspect = require("inspect")
local cjson_safe = require "cjson.safe"
local url = require "socket.url"
local date = require "date"

local get_io_data = require("kong.plugins.advanced-router.io").get_io_data
local extract = require("kong.plugins.advanced-router.utils").extract
local replaceStringEnvVariables = require("kong.plugins.advanced-router.utils").replaceStringEnvVariables

local AdvancedRouterHandler = {}

AdvancedRouterHandler.PRIORITY = tonumber((os.getenv("PRIORITY_ADVANCED_ROUTER")))
AdvancedRouterHandler.VERSION = "1.0.0"

local boolean_functions = {}

function get_current_timestamp_utc()
    return date.diff(date(true), date(1970, 1, 1)):spanseconds()
end

function get_timestamp_utc(date_string)
    return date.diff(date(date_string), date(1970, 1, 1)):spanseconds()
end

function extract_from_io_response(key)
    --print("key::" .. inspect(key))
    --print("data::" .. inspect(kong.ctx.plugin.io_data))
    print(type(kong.ctx.plugin.io_data))
    return extract(key, kong.ctx.plugin.io_data)
end

function generate_boolean_function(proposition)
    if proposition['condition'] == 'default' then
        return assert(loadstring("return " .. "\"" .. proposition["upstream_url"] .. "\""))
    end
    return assert(loadstring("if " .. proposition["condition"] .. "then return " .. "\"" .. proposition["upstream_url"] .. "\"" .. " end"))
end

function get_upstream_url(conf)
    if boolean_functions[conf.route_id] == nil then
        boolean_functions[conf.route_id] = {}
        local propositions_json, err1 = cjson_safe.decode(conf.propositions_json)

        if err1 then
            return kong.response.exit(500, "Unable to decode proposition json")
        end

        local propositions = propositions_json
        for _, proposition in ipairs(propositions) do
            table.insert(boolean_functions[conf.route_id], generate_boolean_function(proposition))
        end
    end

    local value
    for _, boolean_function in ipairs(boolean_functions[conf.route_id]) do
        value = boolean_function()
        if value then
            break
        end
    end
    return value
end

function set_upstream(upstream_url)
    local parsed_url = url.parse(upstream_url)
    local scheme = parsed_url['port'] or 'http'
    local host = parsed_url['host']
    local path = parsed_url['path']
    local port = tonumber(parsed_url['port']) or 80
    kong.service.request.set_scheme(scheme)
    kong.log.debug("Upstream URL::" .. inspect(upstream_url))
    kong.log.debug("Parsed URL::" .. inspect(parsed_url))
    kong.service.set_target(host, port)
    if path then
        kong.service.request.set_path(path)
    end

end

function AdvancedRouterHandler:access(conf)
    local io_data, err = get_io_data(conf)
    if err then
        kong.log.err("Error in getting io data" .. inspect(err))
        return kong.response.exit(500, { error = "Error in getting io data" .. inspect(err) })
    end
    kong.ctx.plugin.io_data = io_data

    local upstream_url = get_upstream_url(conf)
    if not upstream_url then
        return kong.response.exit(500, "Not able to resolve upstream in advanced router")
    end
    upstream_url = replaceStringEnvVariables(upstream_url)
    set_upstream(upstream_url)
end

return AdvancedRouterHandler

