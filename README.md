#Kong-advanced-router

Propositions Json

```json
[
    {
        "condition": "get_timestamp_utc(extract_from_io_response('round.RoundStartTime')) > get_current_timestamp_utc()",
        "upstream_url": "http://pc%TEAM_SUFFIX%.dream11%VPC_SUFFIX%.local:5000/myteam"
    },
    {
        "condition": "default",
        "upstream_url": "http://team%TEAM_SUFFIX%.dream11%VPC_SUFFIX%.local:5000/myteam1"
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

