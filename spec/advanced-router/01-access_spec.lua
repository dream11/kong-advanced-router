local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local inspect = require "inspect"

for _, strategy in helpers.each_strategy() do

    describe("circuit breaker plugin [#" .. strategy .. "]", function()
        local mock_host = helpers.mock_upstream_host;

        function assert_upstream(expected, resp)
            local fields_to_verify = {'host', 'port', 'request_uri', 'scheme'}
            assert.are.same(expected['host'], resp['vars']['host'])
        end

        local bp, db = helpers.get_db_utils(strategy, { "routes", "services", "plugins" }, { "advanced-router" });

        local test_service = bp.services:insert(
            {
                protocol = "http",
                host = "dummy", -- Just a dummy value. Not honoured
                port = 15555, -- Just a dummy value. Not honoured
                name = "test",
                connect_timeout = 2000
            })

        local main_route = assert(bp.routes:insert({
            methods = { "GET" },
            protocols = { "http" },
            paths = { "/main_route" },
            strip_path = false,
            preserve_host = true,
            service = test_service,
        }))

        local io_call_route = assert(bp.routes:insert({
            methods = { "GET" },
            protocols = { "http" },
            paths = { "/io_call" },
            strip_path = false,
            preserve_host = true,
            service = test_service
        }))
        local io_response = {
            data = {
                a = 'x',
                b = 'y'
            }
        }
        --bp.plugins:insert {
        --    name = "request-termination",
        --    config = {
        --        status_code = 200,
        --        content_type = "application/json",
        --        body = cjson.encode(io_response)
        --    },
        --    route = { id = io_call_route.id }
        --}

        local upstream_route = assert(bp.routes:insert({
            methods = { "GET" },
            protocols = { "http" },
            paths = { "/upstream_route" },
            strip_path = false,
            preserve_host = true,
            service = test_service
        }))
        local upstream_route_response = {
            success = true
        }
        bp.plugins:insert {
            name = "request-termination",
            config = {
                status_code = 200,
                content_type = "application/json",
                body = cjson.encode(upstream_route_response)
            },
            route = { id = upstream_route.id }
        }

        local propositions_json = {
            { condition = "extract_from_io_response('data.a') == 'x' and extract_from_io_response('data.b') == 'y'", upstream_url = "http://service_abc_xyz.com/geta" },
            { condition = "extract_from_io_response('a') == 'x' and extract_from_io_response('b') == 'z'", upstream_url = "http://service_fallback.com/getb" },
            { condition = "default", upstream_url = "http://service_shard_1.com/getc" },
        }

        local io_request_template = {
            headers = {
                ['resp-type'] = "headers.resp-type"
            }
        }

        local plugin = assert(bp.plugins:insert {
            name = "advanced-router",
            config = {
                propositions_json = cjson.encode(propositions_json),
                io_url = "http://service_io_call.com/get",
                io_request_template = cjson.encode(io_request_template),
                cache_io_response = true,
                io_http_method = "GET",
                cache_ttl_header = "edge_ttl",
                default_edge_ttl_sec = 10
            },
            route = main_route
        })

        local fixtures = {
            dns_mock = helpers.dns_mock.new()
        }
        fixtures.dns_mock:SRV {
            name = "service_abc_xyz.com",
            target = "127.0.0.1",
            port = 15555
        }
        fixtures.dns_mock:SRV {
            name = "service_fallback.com",
            target = "127.0.0.1",
            port = 15555
        }
        fixtures.dns_mock:SRV {
            name = "service_shard_1.com",
            target = "127.0.0.1",
            port = 15555
        }
        fixtures.dns_mock:SRV {
            name = "service_io_call.com",
            target = "127.0.0.1",
            port = 15555
        }
        print("Starting kong")
        assert(helpers.start_kong({
            database = strategy,
            plugins = "bundled, advanced-router",
            nginx_conf = "spec/fixtures/custom_nginx.template"
        }, nil, nil, fixtures))

        teardown(function()
            print("Stopping kong")
            helpers.stop_kong()
        end)

        before_each(function()

        end)
        after_each(function()

        end)

        it("should remain closed if request count <=  min_calls_in_window & err % >= failure_percent_threshold ",
            function()
                --local proxy_client = helpers.proxy_client()
                --local res = assert(proxy_client:send(
                --    {
                --        method = "GET",
                --        path = "/io_call",
                --    }))
                --
                --local res_body = assert(res:read_body())
                --print("res_body::" .. res_body)
                --res_body = cjson.decode(res_body)
                --
                --proxy_client:close()

                local proxy_client = helpers.proxy_client()
                local res = assert(proxy_client:send(
                    {
                        method = "GET",
                        path = "/main_route",
                        headers = {
                            ['Content-type'] = 'application/json',
                            ['resp-type'] = 'b'
                        }
                    }))
                print(inspect(res))
                local res_body = assert(res:read_body())
                print("res_body::" .. res_body)
                assert.are.same(200, res.status)
                local res_body = assert(res:read_body())
                print("res_body::" .. res_body)
                res_body = cjson.decode(res_body)
                assert_upstream({host='service_abc_xyz.com'}, res_body)
                proxy_client:close()
            end)

    end)
    break
end
