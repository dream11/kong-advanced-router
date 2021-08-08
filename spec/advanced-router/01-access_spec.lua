local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local inspect = require "inspect"

for _, strategy in helpers.each_strategy() do

    describe("advanced router plugin 1 [#" .. strategy .. "]", function()
        local KONG_IO_CALL_ENV = "-io-call"
        local KONG_DEFAULT_SERVICE_HOST_ENV = "-default"
        local service_one_host = 'service-one.com'
        local service_two_host_variable = 'service%data.host%.com'
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
            { condition = "extract_from_io_response('data.host') == '-one' and extract_from_io_response('data.route') == '/one'", upstream_url = "http://" .. service_one_host .. service_one_route },
            { condition = "get_timestamp_utc(extract_from_io_response('data.RoundStartTime')) > get_current_timestamp_utc() and extract_from_io_response('data.host') == '-two'", upstream_url = "http://" .. service_two_host_variable .. service_two_route },
            { condition = "default", upstream_url = "http://" .. service_default_host_variable .. service_default_route },
        }

        local io_request_template = {
            headers = {
                ['io-resp-type'] = "headers.io-resp-type"
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

        function get_and_assert_upstream(req_headers, expected_resp)
            local proxy_client = helpers.proxy_client()

            local res = assert(proxy_client:send(
                {
                    method = "GET",
                    path = "/main-route",
                    headers = kong.table.merge({ ['Content-type'] = 'application/json' }, req_headers)

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

        before_each(function()

        end)
        after_each(function()

        end)

        it("should remain closed if request count <=  min_calls_in_window & err % >= failure_percent_threshold #service_one",
            function()
                get_and_assert_upstream({ ['io-resp-type'] = 'one' }, { host = service_one_host, uri = service_one_route, scheme = 'http' })
            end)

        it("should remain closed if request count <=  min_calls_in_window & err % >= failure_percent_threshold #service_two",
            function()

                get_and_assert_upstream({ ['io-resp-type'] = 'two' }, { host = service_two_host, uri = service_two_route, scheme = 'http' })
            end)

        it("should remain closed if request count <=  min_calls_in_window & err % >= failure_percent_threshold #default",
            function()

                get_and_assert_upstream({ ['io-resp-type'] = 'default' }, { host = service_default_host, uri = service_default_route, scheme = 'http' })
            end)

    end)
    break

    describe("advanced router plugin 2 [#" .. strategy .. "]", function()
        local service_a_host = 'service%%.com'
        local service_b_host = 'service_b.com'
        local service_default_host = 'service_default.com'
        local service_io_call_host = 'service_io_call.com'
        local service_a_route = '/service_a_route'
        local service_b_route = '/service_b_route'
        local service_default_route = '/service_default_route'

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
            paths = { "/main_route" },
            strip_path = false,
            preserve_host = true,
            service = test_service,
        }))

        local propositions_json = {
            { condition = "extract_from_io_response('data.a') == 'x' and extract_from_io_response('data.b') == 'y'", upstream_url = "http://" .. service_one_host .. service_one_route },
            { condition = "get_timestamp_utc('data.RoundStartTime') > get_current_timestamp_utc() and extract_from_io_response('data.b') == 'z'", upstream_url = "http://" .. service_two_host .. service_two_route },
            { condition = "default", upstream_url = "http://" .. service_default_host_variable .. service_default_route },
        }

        local io_request_template = {
            headers = {
                ['io-resp-type'] = "headers.io-resp-type"
            }
        }

        assert(bp.plugins:insert {
            name = "advanced-router",
            config = {
                propositions_json = cjson.encode(propositions_json),
                io_url = "http://" .. service_io_call_host .. "/io_call",
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
            name = service_a_host,
            target = "127.0.0.1",
            port = 15555
        }
        fixtures.dns_mock:SRV {
            name = service_b_host,
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

        function get_and_assert_upstream(req_headers, expected_resp)
            local proxy_client = helpers.proxy_client()

            local res = assert(proxy_client:send(
                {
                    method = "GET",
                    path = "/main_route",
                    headers = kong.table.merge({ ['Content-type'] = 'application/json' }, req_headers)

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

        it("should remain closed if request count <=  min_calls_in_window & err % >= failure_percent_threshold #service_1a",
            function()
                get_and_assert_upstream({ ['io-resp-type'] = 'a' }, { host = service_a_host, uri = service_a_route, scheme = 'http' })
            end)

        it("should remain closed if request count <=  min_calls_in_window & err % >= failure_percent_threshold #service_1b",
            function()

                get_and_assert_upstream({ ['io-resp-type'] = 'b' }, { host = service_b_host, uri = service_b_route, scheme = 'http' })
            end)

        it("should remain closed if request count <=  min_calls_in_window & err % >= failure_percent_threshold #defaul1t",
            function()

                get_and_assert_upstream({ ['io-resp-type'] = 'default' }, { host = service_default_host, uri = service_default_route, scheme = 'http' })
            end)

    end)
    break
end
