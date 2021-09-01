# Kong-advanced-router

## Overview

`kong-advanced-router` is a kong plugin that provides functionality to route a request to a particular upstream from a set of predefined upstreams based on the response of an I/O call.

## Usecase

Suppose we want to proxy a request to fetch the orders of a user. We want to proxy the request to order service A if the user's status is 1, proxy to order service B if the status is 2 and to order service C otherwise. This plugin can be used to fetch the user details before proxying the request. The upstream service will be set as order service A, B, or C based on the response of this call.

## How it works

1. The plugin uses the `io_url`, `io_http_method`, `io_request_template` parameters from the config to make an I/O call
2. It caches the response based on the `cache_ttl_header` header from the I/O response if `cache_io_response` is set to true in the config.
3. It evaluates the response against a list of conditions provided in `propositions_json`.
4. It then sets the upstream target and path using the `upstream_url` of the condition that evaluates to true or to the default values if all conditions evaluate to false.
5. The plugin interpolates the `upstream_url` and the `io_url` with environment variables before using them.

## Example

```lua
 config = {
    io_url = "http://user_service/user" ,
    io_http_method = "GET",
    io_request_template = "{\"body\":{\"id\":\"headers.user_id\"}}",
    http_connect_timeout = 2000,
    http_send_timeout = 2000,
    http_read_timeout = 2000,
    cache_io_response = true,
    cache_ttl_header = "edge_ttl",
    cache_identifier = "headers.user_id",
    default_cache_ttl_sec = 10,
    propositions_json = "[
      {
        \"condition\": \"extract_from_io_response('data.status') == 1\",
        \"upstream_url\": \"http://order_service_a/orders\"
      },
      {
        \"condition\": \"extract_from_io_response('data.status') == 2\",
        \"upstream_url\": \"http://order_service_b/orders\"
      },
      {
        \"condition\": \"default\",
        \"upstream_url\": \"http://order_service_c/orders\"
      }
    ]",
    variables = {"data.status"},
}
```

For the above config applied on route `/orders`. Suppose we make the below request

```shell
curl --location --request GET 'localhost:8000/orders' \
--header 'user_id: 1'
```

The plugin first makes the below I/O call.
```shell
curl --location --request GET 'http://user_service/user' \
--header 'Content-Type: application/json' \
--data-raw '{
    "id" : 1
}'
```
Suppose the response received is

```json
{
  "data": {
    "status": 2,
    "name": "foo",
    "city": "bar"
  }
}
```

The plugin caches only the keys from the response which are defined in  `variables` in the config.

So the data cached is

```json
{
  "data.status": 2
}
```

Now this data is used to evaluate the conditions given in `propositions_json`. `extract_from_io_response` is an abstraction that is used to extract values from the response. In this case, the second condition evaluates to true i.e.
```lua
extract_from_io_response('data.status') == 2
```
Hence, the upstream url is set as `http://order_service_b/orders`

### Other abstractions that can be used in propositions_json

The plugin converts the conditions in `propositions_json` into lua functions using the `loadstring` function and keeps them in a global table against the route_id. It uses these functions for subsequent requests.


