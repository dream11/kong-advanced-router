local typedefs = require "kong.db.schema.typedefs"
local json_safe = require "cjson.safe"

local function json_validator(config_string)
    local config_table, err = json_safe.decode(config_string)

    if config_table == nil then
        return nil, "Invalid Json " .. inspect(err)
    end

    return true
end

local function schema_validator(conf)
    return json_validator(conf.propositions_json) and json_validator(conf.io_request_template)
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
                            default = "[\n    {\n      \"condition\":\"extract('a') == 'x' and extract('b') == 'y'\",\n      \"value\":\"alpha.com\"\n    },\n    {\n      \"condition\":\"extract('a') == z or extract('b') == 'z'\",\n      \"value\":\"beta.com\"\n    },\n    {\n      \"condition\":\"default\",\n      \"value\":\"default.com\"\n    }\n]"
                        }
                    },
                    {
                        io_url = {
                            type = "string",
                            default = "http://192.168.1.40/round"

                        }
                    },
                    {
                        io_request_template = {
                            type = "string",
                            default = "{\n  \"header\": {\n    \"a\":extract_from_request(\"header.x\")\n  },\n  \"query\": {\n    \"b\": extract_from_request(\"query.y\")\n  },\n  \"body\": {\n    \"c\": extract_from_request(\"body.z\"),\n    \"d\": \"hardcoded\"\n  }\n}"

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

