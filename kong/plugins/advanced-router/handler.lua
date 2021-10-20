local inspect = require "inspect"
local cjson_safe = require "cjson.safe"
local url = require "socket.url"
local date = require "date"
local pl_utils = require "pl.utils"

local kong = kong
local debug = kong.log.debug

local get_io_data = require("kong.plugins.advanced-router.io").get_io_data
local interpolate_string_env = require("kong.plugins.advanced-router.utils").interpolate_string_env

local AdvancedRouterHandler = {}
AdvancedRouterHandler.PRIORITY = tonumber(os.getenv("PRIORITY_ADVANCED_ROUTER"))
AdvancedRouterHandler.VERSION = "1.0.0"

local boolean_functions = {}

function get_current_timestamp_utc()
    return date.diff(date(true), date(1970, 1, 1)):spanseconds()
end

function get_timestamp_utc(date_string)
    return date.diff(date(date_string), date(1970, 1, 1)):spanseconds()
end

function extract_from_io_response(key)
    return kong.ctx.plugin.io_data[key]
end

function generate_boolean_function(proposition)

    if proposition['condition'] == 'default' then
        return assert(loadstring("return " .. "\"" .. proposition["upstream_url"] .. "\""))
    end
    local upstream_url = proposition["upstream_url"]
    return assert(loadstring("if " .. proposition["condition"] .. " then return " .. "\"" .. upstream_url .. "\"" .. " end"))
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
    return interpolate_string_env(value)
end

function set_upstream(upstream_url)
    local parsed_url = url.parse(upstream_url)
    local host = parsed_url['host']
    local port = tonumber(parsed_url['port']) or 80
    local scheme = parsed_url['scheme'] or 'http'
    local path = parsed_url['path']
    debug("Setting upstream values::")
    debug("Host::" .. host)
    debug("Port::" .. port)
    debug("Path::" .. path)
    debug("Protocol::" .. scheme)
    kong.service.request.set_scheme(scheme)
    kong.service.set_target(host, port)
    if parsed_url['path'] then
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
    set_upstream(upstream_url)
end

function AdvancedRouterHandler:init_worker()
    kong.worker_events.register(
        function(data)
            if type(data) ~= "string" then
                return
            end

            local key_parts = pl_utils.split(data, ":")
            if key_parts[1] ~= "plugins" or key_parts[2] ~= "advanced-router" then
                return
            end
            local route_id = key_parts[3]
            kong.log.info("Invalidating boolean functions of route :: " .. route_id)
            if boolean_functions[route_id] ~= nil then
                boolean_functions[route_id] = nil
            end
            kong.log.info("Invalidating io_request_template of route :: " .. route_id)
            kong.cache:invalidate('io_request_template' .. route_id, false)

        end,
        "mlcache",
        "mlcache:invalidations:kong_core_db_cache"
    )
end

return AdvancedRouterHandler


