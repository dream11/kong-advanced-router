local typedefs = require "kong.db.schema.typedefs"
local json_safe = require "cjson.safe"
local url = require "socket.url"

local belongs = require "kong.plugins.advanced-router.utils".belongs

local function json_validator(config_string)
    local decoded, err = json_safe.decode(config_string)

    if decoded == nil then
        return nil, "Invalid Json " .. inspect(err)
    end

    return true, nil, decoded
end

local function validate_propositions_json(config_string)
    -- This functions validates the port and protocols of the upstream urls in the propositions_json
    local result, err, propositions_json = json_validator(config_string)
    if not result then
        return nil, err
    end
    local valid_schemes = { 'http', 'https' }
    for _, v in ipairs(propositions_json) do
        local upstream_url = v['upstream_url']
        local parsed_url = url.parse(upstream_url)
        local scheme = parsed_url['port'] or 'http'
        if not belongs(scheme, valid_schemes) then
            return nil, "Invalid protocol: " .. scheme " for url: " .. upstream_url
        end

        if parsed_url['port'] and not tonumber(parsed_url['port']) then
            return nil, "Invalid port: " .. parsed_url['port'] " for url: " .. upstream_url
        end
    end
    return true
end

local function schema_validator(conf)
    return validate_propositions_json(conf.propositions_json) and json_validator(conf.io_request_template)
end

return {
    name = "advanced-router",
    fields = {
        { consumer = typedefs.no_consumer },
        { protocols = typedefs.protocols_http },
        {
            config = {
                type = "record",
                fields = {
                    {
                        propositions_json = {
                            type = "string",
                            default = "[\n    {\n      \"condition\":\"extract_from_io_response('a') == 'x' and extract_from_io_response('b') == 'y'\",\n      \"upstream_url\":\"alpha.com\"\n    },\n    {\n      \"condition\":\"extract_from_io_response('a') == z or extract_from_io_response('b') == 'z'\",\n      \"upstream_url\":\"beta.com\"\n    },\n    {\n      \"condition\":\"default\",\n      \"upstream_url\":\"default.com\"\n    }\n]"
                        }
                    },
                    {
                        io_url = {
                            type = "string",
                            default = "http://io-call%placeholder%/round"
                        }
                    },
                    {
                        io_request_template = {
                            type = "string",
                            default = "{\n  \"headers\": {\n    \"a\":\"headers.x\"\n  },\n  \"query\": {\n    \"b\": \"query.y\"\n  },\n  \"body\": {\n    \"c\": \"query.z\",\n    \"d\": \"hardcoded\"\n  }\n}"
                        }
                    },
                    {
                        cache_io_response = {
                            type = "boolean",
                            default = true
                        }
                    },
                    {
                        io_http_method = {
                            type = "string",
                            default = "GET",
                            one_of = { "GET", "POST" }
                        }
                    },
                    {
                        cache_ttl_header = {
                            type = "string",
                            required = true
                        }
                    },
                    {
                        default_edge_ttl_sec = {
                            type = "number",
                            required = true
                        }
                    }
                },
                custom_validator = schema_validator
            }
        }
    },
    entity_checks = {
    }
}

