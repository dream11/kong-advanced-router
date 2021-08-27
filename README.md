# Kong-advanced-router

## Description

Routing a request to a particular service based on the response of an I/O call

Ex: Routing `/myteam` request to Team service before round lock and to PC service after roundlock by fetching round data using `/round` api of tour service before sending the request to upstream.

A set of propositions can be defined based on the I/O call response data which are evaluated for each request and routed accordingly.

For making the I/O call, all parameters of the call like URL, Method, body etc. can be defined in the config and can ge generated dynamically for each request. Results of the I/O calls are cached preventing round trips for same request.

I/O URL can be interpolated using env variables and upstream URLS can also be interpolated using I/O data.

## Implementation




Propositions Json

```json
[
    {
        "condition": "get_timestamp_utc(extract_from_io_response('round.RoundStartTime')) > get_current_timestamp_utc()",
        "upstream_url": "http://pc%TEAM_SUFFIX%.dream11%VPC_SUFFIX%.local:5000/myteam"
    },
    {
        "condition": "default",
        "upstream_url": "http://team%TEAM_SUFFIX%.dream11%VPC_SUFFIX%.local:5000/myteam"
    }
]
```

I/O request Template

```json
{
    "body": {
        "roundId": "headers.roundId"
    }
}
```

I/O Url
```json
http://tour%TEAM_SUFFIX%.dream11%VPC_SUFFIX%.local/round
```
Cache ttl header: `d11-edge-ttl`

