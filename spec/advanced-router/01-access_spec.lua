local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local inspect = require "inspect"

for _, strategy in helpers.each_strategy() do

    describe("advanced router plugin I/O data from headers [#" .. strategy .. "]", function()
        local KONG_IO_CALL_ENV = "-io-call"
        local KONG_DEFAULT_SERVICE_HOST_ENV = "-default"
        local service_one_host = 'service-one.com'
        local service_two_host_variable = 'service%data.service_host%.com'
        local service_two_host = 'service-two.com'
        local service_default_host = 'service-default.com'
        local service_default_host_variable = 'service' .. KONG_DEFAULT_SERVICE_HOST_ENV .. '.com'
        local service_io_call_host_variable = 'service%KONG_IO_CALL_ENV%.com'
        local service_io_call_host = 'service' .. KONG_IO_CALL_ENV .. '.com'
        local service_io_call_route = '/io-call'
        local service_one_route = '/service-one-route'
        local service_two_route = '/service-two-route'
        local service_default_route = '/service-default-route'

        local bp = helpers.get_db_utils(strategy, { "routes", "services", "plugins" }, { "advanced-router" });

        local test_service = bp.services:insert(
            {
                protocol = "http",
                host = "dummy",
                port = 15555,
                name = "test",
                connect_timeout = 2000
            })

        local main_route = assert(bp.routes:insert({
            methods = { "GET" },
            protocols = { "http" },
            paths = { "/main-route" },
            strip_path = false,
            preserve_host = true,
            service = test_service,
        }))

        local propositions_json = {
            { condition = "extract_from_io_response('data.service_host') == '-one' and extract_from_io_response('data.route') == '/one'", upstream_url = "http://" .. service_one_host .. service_one_route },
            { condition = "get_timestamp_utc(extract_from_io_response('data.roundstarttime')) > get_current_timestamp_utc() and extract_from_io_response('data.service_host') == '-two'", upstream_url = "http://" .. service_two_host_variable .. service_two_route },
            { condition = "default", upstream_url = "http://" .. service_default_host_variable .. service_default_route },
        }

        local io_request_template = {
            headers = {
                ['service_host'] = "headers.service_host",
                ['route'] = "headers.route",
                ['roundstarttime'] = "headers.roundstarttime"
            }
        }

        assert(bp.plugins:insert {
            name = "advanced-router",
            config = {
                propositions_json = cjson.encode(propositions_json),
                io_url = "http://" .. service_io_call_host_variable .. service_io_call_route,
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

        print("Setting SRV for " .. inspect({ service_one_host, service_two_host, service_default_host, service_io_call_host }))
        fixtures.dns_mock:SRV {
            name = service_one_host,
            target = "127.0.0.1",
            port = 15555
        }
        fixtures.dns_mock:SRV {
            name = service_two_host,
            target = "127.0.0.1",
            port = 15555
        }
        fixtures.dns_mock:SRV {
            name = service_default_host,
            target = "127.0.0.1",
            port = 15555
        }
        fixtures.dns_mock:SRV {
            name = service_io_call_host,
            target = "127.0.0.1",
            port = 15555
        }

        assert(helpers.start_kong({
            DEFAULT_SERVICE_HOST_ENV = KONG_DEFAULT_SERVICE_HOST_ENV,
            IO_CALL_ENV = KONG_IO_CALL_ENV,
            database = strategy,
            plugins = "bundled, advanced-router",
            nginx_conf = "/kong-plugin/spec/fixtures/custom_nginx.template"
        }, nil, nil, fixtures))

        function assert_upstream(expected, resp)
            local fields_to_verify = { 'host', 'uri', 'scheme' }
            for _, v in ipairs(fields_to_verify) do
                assert.are.same(expected[v], resp['vars'][v])
            end
        end

        function get_and_assert_upstream(req_data, expected_resp)
            local proxy_client = helpers.proxy_client()

            local res = assert(proxy_client:send(
                {
                    method = "GET",
                    path = "/main-route",
                    headers = kong.table.merge({ ['Content-type'] = 'application/json' }, req_data.headers)

                }))
            assert.are.same(200, res.status)
            local res_body = assert(res:read_body())
            res_body = cjson.decode(res_body)
            assert_upstream(expected_resp, res_body)
            proxy_client:close()
        end

        teardown(function()
            helpers.stop_kong()
        end)

        it("I/O data from header #service_one",
            function()
                local req_data = { headers = { service_host = '-one', route = '/one' } }
                local expected_resp = { host = service_one_host, uri = service_one_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)

        it("should remain closed if request count <=  min_calls_in_window & err % >= failure_percent_threshold #service_two",
            function()
                local req_data = { headers = { service_host = '-two', route = '/two', roundstarttime = "2025-10-17T11:15:14.000Z" } }
                local expected_resp = { host = service_two_host, uri = service_two_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)

        it("should remain closed if request count <=  min_calls_in_window & err % >= failure_percent_threshold #service_default",
            function()
                local req_data = { headers = {
                    service_host = '-default',
                    route = '/default',
                    roundstarttime = "2025-10-17T11:15:14.000Z"
                } }
                local expected_resp = { host = service_default_host, uri = service_default_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)

    end)
    break
end
