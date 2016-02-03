api-gateway-cachemanager
========================
Lua library for managing multiple cache stores.

Table of Contents
=================
* [Motivation](#motivation)
* [Status](#status)
 

Status
======

This library is still under active development and is NOT YET production ready.

Motivation
==========
Part of the work for building an API Gateway ofen involves validating if the incoming request is valid. The [API Gateway](https://github.com/adobe-apiplatform/apigateway) uses a simple [request-validation](https://github.com/adobe-apiplatform/api-gateway-request-validation#validating-requests) framework that makes a `subrequest` for each validator, expecting a `200` response code back, else the request is considered invalid. These validators/subrequests often depend on other REST APIs with variable latencies.  

For performance reasons the Gateway caches validation responses as often as possible. To make the cache more effective in a distributed deployment the API Gateway uses a multi-layered caching mechanism: 

1. L1 Cache - the local memory of the Gateway, usually based on [lua_shared_dict](https://github.com/openresty/lua-nginx-module#lua_shared_dict)
2. L2 Cache - a remote caching service, usually based on [Redis](http://redis.io/)

The L1 Cache keeps the items in memory for shorter periods than L2 cache. This multi layered caching mechanism has a big impact on the latency and performance of the API Gateway.


