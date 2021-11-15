[![Continuous Integration](https://github.com/dream11/kong-advanced-router/actions/workflows/ci.yml/badge.svg)](https://github.com/dream11/kong-advanced-router/actions/workflows/ci.yml)
![License](https://img.shields.io/badge/license-MIT-green.svg)

# Kong-advanced-router

## Overview

`kong-advanced-router` is a kong plugin that allows you to make an intermediate HTTP call and based on the response, the original request can be conditionally proxied to an upstream host.

## Usecase

Let's say you want to proxy a request to fetch the orders of a user. The flow is:

1. Get the user details (user_status) by making an intermediate call to user-service.
2. Based on the value of user_status from step 1, conditionally proxy the original request.
3. Proxy the request to service A if user_status is 1, service B if user_status is 2 and to service C otherwise.

## Parameters

### The following config parameters are used to configure the intermediate HTTP call

| Key | Default  | Type  | Required | Description |
| --- | --- | --- | --- | --- |
| io_url |  | string | true | URL |
| io_http_method | GET | string | false | HTTP Method (GET, POST)|
| io_request_template |   | string | true | Template of the I/O call in JSON. Must be a valid json string |
| http_connect_timeout | 5000 | number | false | HTTP Connect timeout (ms) |
| http_send_timeout | 5000 | number | false | HTTP Send timeout (ms) |
| http_read_timeout | 5000 | number | false | HTTP Read timeout (ms) |
| cache_io_response | true | boolean | false | If the response received doesn't change frequently, you can cache it in memory |
| cache_ttl_header |  | string | true | Dynamically set the TTL of cached response using a response header |
| cache_identifier |  | string | true | Key in the request which uniquely identifies the intermediate HTTP request. This is used to create the cache key against which the response is cached |
| default_cache_ttl_sec |  | number | true | Default TTL if `cache_ttl_header` header is not present in the response |

### Other config parameters

| Key | Default  | Type  | Required | Description |
| --- | --- | --- | --- | --- |

| propositions_json |  | string | true | Array of conditions and URLs that are used to set the upstream URL. Must be a valid json string. The conditions should follow correct Lua syntax |
| variables |  | [string] | true | List of all the keys from the response that are used for creating conditions in propositions_json |

### io_request_template syntax

```json
  {
      "body": {
          "a": "headers.x"
      }, 
      "headers": {
          "b": "query.y"
      },
      "query": {
          "c": "header.z",
          "d": 1
      }
  }

```

Body, headers and query of the intermediate HTTP call can be composed from the headers and query of the incoming request and constant values.

## Installation

### via [luarocks](https://luarocks.org/modules/dream11/kong-advanced-router)

```bash
luarocks install kong-advanced-router
```

You will also need to enable this plugin by any of the below ways:
* By adding it to the list of enabled plugins using `KONG_PLUGINS` environment variable

      export KONG_PLUGINS=advanced-router

* By adding it to the `plugins` key in `kong.conf`

      plugins=advanced-router

## Internal Working

1. The plugin uses `io_url`, `io_http_method`, `io_request_template` parameters from the config to prepare the intermediate HTTP call.
2. It caches the response based on the `cache_ttl_header` response header if `cache_io_response` is set to *true* in the config.
3. It evaluates the response against a list of conditions provided in `propositions_json`.
4. It then sets the upstream target and path using the `upstream_url` of the condition that evaluates to true or to the default values if all conditions evaluate to false.
5. If none of the conditions evaluates to false, upstream_url of default condition is used.
6. The plugin interpolates the `upstream_url` and the `io_url` with environment variables before using them.

## Usage

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

Now this data is used to evaluate the conditions given in `propositions_json`. `extract_from_io_response` is an abstraction that is used to extract values from the I/O call response body. In this case, the second condition evaluates to true i.e.

```lua
extract_from_io_response('data.status') == 2
```

Hence, the upstream url is set as `http://order_service_b/orders`

### Other functions that can be used in the condition part of propositions_json

The below functions can be used to write conditions in *propositions_json*

1. `extract_from_io_response(key)` - Returns the value of the provided key from the HTTP response body. Nested keys can be passed by concatenating with dot (.). Eg - `data.status`
2. `get_timestamp_utc(datestring)` - Returns the UTC timestamp of a datestring. It internally uses the [Tieske/date](https://github.com/Tieske/date) module. This can be used to write conditions based on the timestring data from the HTTP response.
3. `get_current_timestamp_utc` - Returns the current timestamp in UTC. This can be used to compare the time string in HTTP response body to current time.

## Caveats

 1. All upstream_url endpoints mentioned in propositions_json should ideally have the same request signature. If not, clients need to implement the response handling logic.
 2. The plugin does not parse the request body so the data required to create the intermediate HTTP call must be present in the query string or headers of incoming requests.
 3. `proposition_json` cannot have conditions with comparision to `null`.
 4. Be very careful of the responses you want to cache in memory. Data that is not frequently changing and is common across all users is a good usecase for caching. It saves an extra hop (intermediate HTTP call) by reading the response from cache.
