local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local inspect = require "inspect"

for _, strategy in helpers.each_strategy() do

    describe("advanced router plugin I/O data from headers [#" .. strategy .. "]", function()
        local KONG_IO_CALL_HOST_ENV = "-io-call"
        local KONG_SERVICE_ONE_HOST_ENV = "-one"

        local service_io_call_host_variable = 'service%KONG_IO_CALL_HOST_ENV%.com'
        local service_io_call_host = 'service' .. KONG_IO_CALL_HOST_ENV .. '.com'

        local service_one_host = 'service' .. KONG_SERVICE_ONE_HOST_ENV .. '.com'
        local service_one_host_interpolate = 'service%KONG_SERVICE_ONE_HOST_ENV%.com'

        local service_two_host = 'service-two.com'
        local service_two_host_interpolate = 'service%data.service_host%.com'

        local service_default_host = 'service-default.com'

        local service_io_call_route = '/io-call'
        local service_one_route = '/service-one-route'
        local service_two_route = '/service-two-route'
        local service_default_route = '/service-default-route'

        local bp, db = helpers.get_db_utils(strategy, { "routes", "services", "plugins" }, { "advanced-router" });


        local fixtures = {
            dns_mock = helpers.dns_mock.new()
        }

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

        function setup_db(propositions_json, io_request_template, service_io_call_host)
            local test_service = assert(bp.services:insert(
                {
                    protocol = "http",
                    host = "dummy",
                    port = 15555,
                    name = "test",
                    connect_timeout = 2000
                }))

            local main_route = assert(bp.routes:insert({
                methods = { "GET", "POST" },
                protocols = { "http" },
                paths = { "/main-route" },
                strip_path = false,
                preserve_host = true,
                service = test_service,
            }))

            assert(bp.plugins:insert {
                name = "advanced-router",
                config = {
                    propositions_json = cjson.encode(propositions_json),
                    io_url = "http://" .. service_io_call_host .. service_io_call_route,
                    io_request_template = cjson.encode(io_request_template),
                    cache_io_response = true,
                    io_http_method = "GET",
                    cache_ttl_header = "edge_ttl",
                    default_edge_ttl_sec = 10
                },
                route = main_route
            })

            assert(helpers.start_kong({
                SERVICE_ONE_HOST_ENV = KONG_SERVICE_ONE_HOST_ENV,
                IO_CALL_HOST_ENV = KONG_IO_CALL_HOST_ENV,
                database = strategy,
                plugins = "bundled, advanced-router",
                nginx_conf = "/kong-plugin/spec/fixtures/custom_nginx.template"
            }, nil, nil, fixtures))
        end

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
                    method = req_data.method or "GET",
                    path = "/main-route",
                    headers = kong.table.merge({ ['Content-type'] = 'application/json' }, req_data.headers),
                    query = req_data.query,
                    body = cjson.encode(req_data.body)
                }))
            assert.are.same(200, res.status)
            local res_body = assert(res:read_body())
            res_body = cjson.decode(res_body)
            assert_upstream(expected_resp, res_body)
            proxy_client:close()
        end

        describe("Should generate correct I/O call using I/O request template #template", function()

            lazy_setup(function()
                local propositions_json = {
                    { condition = "extract_from_io_response('data.service_host') == '-one' and extract_from_io_response('data.route') == '/one'", upstream_url = "http://" .. service_one_host .. service_one_route },
                    { condition = "default", upstream_url = "http://" .. service_default_host .. service_default_route },
                }

                local io_request_template = {
                    headers = {
                        ['service_host'] = "headers.service_host",
                        ['route'] = "headers.route"
                    },
                    query = {
                        ['service_host'] = "query.service_host",
                        ['route'] = "query.route"
                    },
                    body = {
                        ['service_host'] = "query.service_host1",
                        ['route'] = "query.route1"
                    }
                }
                setup_db(propositions_json, io_request_template, service_io_call_host)
            end)

            teardown(function()
                helpers.stop_kong()
                db:truncate()
            end)

            it("Should send data in headers correctly  #template_header", function()
                local req_data = { headers = { service_host = '-one', route = '/one' } }
                local expected_resp = { host = service_one_host, uri = service_one_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)

            it("Should send data in query parameters correctly  #template_query", function()
                local req_data = { query = { service_host = '-one', route = '/one' } }
                local expected_resp = { host = service_one_host, uri = service_one_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)

            it("Should send data in body correctly  #template_body", function()
                local req_data = { query = { service_host1 = '-one', route1 = '/one', method = 'POST' } }
                local expected_resp = { host = service_one_host, uri = service_one_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)
        end)

        describe("Should evaluate conditions using IO data correctly #static", function()

            lazy_setup(function()
                local propositions_json = {
                    { condition = "extract_from_io_response('data.service_host') == '-one' and extract_from_io_response('data.route') == '/one'", upstream_url = "http://" .. service_one_host .. service_one_route },
                    { condition = "extract_from_io_response('data.service_host') == '-two' and extract_from_io_response('data.route') == '/two'", upstream_url = "http://" .. service_two_host .. service_two_route },
                    { condition = "default", upstream_url = "http://" .. service_default_host .. service_default_route },
                }

                local io_request_template = {
                    headers = {
                        ['service_host'] = "headers.service_host",
                        ['route'] = "headers.route",
                        ['roundstarttime'] = "headers.roundstarttime"
                    }
                }
                setup_db(propositions_json, io_request_template, service_io_call_host)
            end)

            teardown(function()
                helpers.stop_kong()
                db:truncate()
            end)

            it("Should match first condition  #service_one", function()
                local req_data = { headers = { service_host = '-one', route = '/one', roundstarttime = "2925-10-17T11:15:14.000Z" } }
                local expected_resp = { host = service_one_host, uri = service_one_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)

            it("Should match second condition #service_two", function()
                local req_data = { headers = { service_host = '-two', route = '/two', roundstarttime = "1925-10-17T11:15:14.000Z" } }
                local expected_resp = { host = service_two_host, uri = service_two_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)

            it("Should match default condition when none of the above is satisfied #service_default", function()
                local req_data = { headers = { route = '/default', roundstarttime = "1925-10-17T11:15:14.000Z" } }
                local expected_resp = { host = service_default_host, uri = service_default_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)
        end)

        describe("Should evaluate conditions using timestamp correctly #time", function()

            lazy_setup(function()
                local propositions_json = {
                    { condition = "get_timestamp_utc(extract_from_io_response('data.roundstarttime')) > get_current_timestamp_utc() and extract_from_io_response('data.route') == '/one'", upstream_url = "http://" .. service_one_host .. service_one_route },
                    { condition = "get_timestamp_utc(extract_from_io_response('data.roundstarttime')) < get_current_timestamp_utc() and extract_from_io_response('data.route') == '/two'", upstream_url = "http://" .. service_two_host .. service_two_route },
                    { condition = "default", upstream_url = "http://" .. service_default_host .. service_default_route },
                }

                local io_request_template = {
                    headers = {
                        ['service_host'] = "headers.service_host",
                        ['route'] = "headers.route",
                        ['roundstarttime'] = "headers.roundstarttime"
                    }
                }
                setup_db(propositions_json, io_request_template, service_io_call_host)
            end)

            teardown(function()
                helpers.stop_kong()
                db:truncate()
            end)

            it("Should match first condition  #service_one1", function()
                local req_data = { headers = { service_host = '-one', route = '/one', roundstarttime = "2925-10-17T11:15:14.000Z" } }
                local expected_resp = { host = service_one_host, uri = service_one_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)

            it("Should match second condition #service_two2", function()
                local req_data = { headers = { service_host = '-two', route = '/two', roundstarttime = "1925-10-17T11:15:14.000Z" } }
                local expected_resp = { host = service_two_host, uri = service_two_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)

            it("Should match default condition #service_default1", function()
                local req_data = { headers = { service_host = '-two', route = '/one', roundstarttime = "1925-10-17T11:15:14.000Z" } }
                local expected_resp = { host = service_default_host, uri = service_default_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)
        end)

        describe("Should interpolate I/O call host and Upstream urls correctly #interpolate", function()

            lazy_setup(function()
                local propositions_json = {
                    { condition = "extract_from_io_response('data.service_host') == '-one' and extract_from_io_response('data.route') == '/one'", upstream_url = "http://" .. service_one_host_interpolate .. service_one_route },
                    { condition = "extract_from_io_response('data.service_host') == '-two' and extract_from_io_response('data.route') == '/two'", upstream_url = "http://" .. service_two_host_interpolate .. service_two_route },
                    { condition = "default", upstream_url = "http://" .. service_default_host .. service_default_route },
                }

                local io_request_template = {
                    headers = {
                        ['service_host'] = "headers.service_host",
                        ['route'] = "headers.route",
                        ['roundstarttime'] = "headers.roundstarttime"
                    }
                }
                setup_db(propositions_json, io_request_template, service_io_call_host_variable)
            end)

            teardown(function()
                helpers.stop_kong()
                db:truncate()
            end)

            it("Should interpolate I/O  Host using environment variables #IOCall", function()
                local req_data = { headers = { service_host = '-default', route = '/default' } }
                local expected_resp = { host = service_default_host, uri = service_default_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)

            it("Should interpolate upstream_url of first condition from env variable #UpEnv", function()
                local req_data = { headers = { service_host = '-one', route = '/one' } }
                local expected_resp = { host = service_one_host, uri = service_one_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)

            it("Should interpolate upstream_url of second condition from I/O data #UpIO", function()
                local req_data = { headers = { service_host = '-two', route = '/two' } }
                local expected_resp = { host = service_two_host, uri = service_two_route, scheme = 'http' }
                get_and_assert_upstream(req_data, expected_resp)
            end)

        end)

    end)
    break
end
