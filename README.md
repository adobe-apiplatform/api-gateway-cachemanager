api-gateway-cachemanager
========================
Lua library for managing multiple cache stores.

Table of Contents
=================
* [Status](#status)
* [Synopsis] (#synopsis)
* [Motivation](#motivation)
* [Integration with other caching modules](#integration-with-other-caching-modules)
* [Features](#features)
* [Developer guide](#developer-guide)
 

Status
======

This library is under development and is considered production ready.

Synopsis
========


```nginx
http {
    # define the local shared dictionary to cache requests in memory
    lua_shared_dict cachedrequests 100m;

    # register (true) Lua global variables or pre-load Lua modules at server start-up
    init_by_lua '
            ngx.apiGateway = ngx.apiGateway or {}
            local cache_cls = require "api-gateway.cache.cache"
            ngx.apiGateway.request_cache = cache_cls:new()
            
            -- define a local cache with a max TTL of 10s
            local local_cache_max_ttl = 10
            local local_cache = require "api-gateway.cache.store.localCache":new({
                dict = "cachedrequests", 
                ttl = function (value)
                    return math.min(local_cache_max_ttl,(ngx.var.arg_exptime or local_cache_max_ttl))
                end
            })
            
            -- define a remote Redis cache with  max TTL of 5 minutes
            local redis_cache_max_ttl = 300
            local redis_cache = require "api-gateway.cache.store.redisSetCache":new({
                ttl = function(value)
                    -- ngx.var.arg_exptime is automatically set when
                    --  /request-caching subrequest is called as:
                    --  srcache_store PUT /request-caching <key>&exptime=<srcache_expire>;
                    return math.min(redis_cache_max_ttl,(ngx.var.arg_exptime or redis_cache_max_ttl))
                end
            })

            -- NOTE: order is important as cache stores are checked in the same order
            ngx.apiGateway.request_cache:addStore(local_cache)
            ngx.apiGateway.request_cache:addStore(redis_cache)
    ';            
}

# define a location block for srcache-nginx-module
location /request-caching {
    internal;
    set $subrequest_method $echo_request_method; # GET or PUT
    set_escape_uri $escaped_key $arg_key;        # Cache KEY

    content_by_lua '
        local sr_method = ngx.var.subrequest_method
        local cache = ngx.apiGateway.request_cache  -- instance of cache.lua defined in init_by_lua
        local key = ngx.var.escaped_key

        local rcache_cls = require "api-gateway.cache.request.rcache"
        local rcache = rcache_cls:new()
        
        rcache:handleRequest(sr_method, cache, key) 
    ';
}
            
# a sample location that enables caching 
location /foo {
     srcache_default_expire 1s;
     srcache_request_cache_control on; # honor Cache-control: no-cache and Pragma:no-cache

     set $key $request_uri;                 # cache key is the entire request_uri which includes query string
     set_escape_uri $escaped_key $key;      # 

     # hooks to get/put items from/into cache
     srcache_fetch GET /request-caching key=$escaped_key;                          
     srcache_store PUT /request-caching key=$escaped_key&exptime=$srcache_expire;  
     
     srcache_store_statuses 200 301 302;    # This directive controls what responses to store to the cache 
                                            # according to their status code.

     # proxy_pass/fastcgi_pass/drizzle_pass/echo/etc...
     # or even static files on the disk
 }            
            

```

Motivation
==========
Simplify the logic to manage a multi-layered cache.  

Part of the work for building an API Gateway often involves validating if the incoming request is valid. 
The [API Gateway](https://github.com/adobe-apiplatform/apigateway) uses a simple [request-validation](https://github.com/adobe-apiplatform/api-gateway-request-validation#validating-requests) framework that makes a `subrequest` for each validator, expecting a `200` response code back, else the request is considered invalid. 
These validators/subrequests often depend on other REST APIs, each with its own variable latency.  

For performance reasons the Gateway caches validation responses as often as possible. To make the cache more effective in a distributed deployment the API Gateway uses a multi-layered caching mechanism: 

1. L1 Cache - the local memory of the Gateway, usually based on [lua_shared_dict](https://github.com/openresty/lua-nginx-module#lua_shared_dict)
2. L2 Cache - a remote caching service, usually based on [Redis](http://redis.io/)

The L1 Cache keeps the items in memory for shorter periods than L2 cache. This multi layered caching mechanism has a big impact on the latency and performance of the API Gateway.

[Back to TOC](#table-of-contents)

Integration with other caching modules
======================================

This module is compatible with other popular caching modules in the [Openresty](https://openresty.org/) community:

1. [srcache-nginx-module](https://github.com/openresty/srcache-nginx-module) - Use this module for main request caching. 
    `srcache` module provides a hook in the configuration defining a `subrequest` to be called to `GET`/`PUT` items from/into a cache.
    In the `subrequest` [cache.lua](src/lua/api-gateway/cache/cache.lua) can be used to work with multiple cache stores ( in-memory or remote ) at the same time.
    See the `init_by_lua` block in the [Synopsis](#synopsis) for a sample to setup multiple cache stores with a cache.      
2. [lua-resty-lrucache](https://github.com/openresty/lua-resty-lrucache) - Use this module for a LRU Cache based on LuaJIT FFI at each nginx process level. 
3. [lua_shared_dict](https://github.com/openresty/lua-nginx-module#lua_shared_dict) - Use this module for a shared cache cross nginx processes, which is not affected by an nginx reload.
    [localCache.lua](src/lua/api-gateway/cache/localCache.lua) implementation leverages this directive.
 
[Back to TOC](#table-of-contents)



Features
========

1. It allows caching of the validation responses
2. It allows caching inside local memory and/or in Redis
3. It may be extend to accept other caching layers
4. The caching mechanism can be easily accessed by invoking the `cache:get(key)` and the `cache:put(key,value)` methods

[Back to TOC](#table-of-contents)

Developer guide
===============

## Install the api-gateway first
 Since this module is running inside the `api-gateway`, make sure the api-gateway binary is installed under `/usr/local/sbin`.
 You should have 2 binaries in there: `api-gateway` and `nginx`, the latter being only a symbolik link.

## Update git submodules
```
git submodule update --init --recursive
```

## Running the tests

### With docker

```
make test-docker
```
This command spins up 2 containers ( Redis and API Gateway ) and executes the tests in `test/perl`

### With native binary
```
make test
```

The tests are based on the `test-nginx` library.
This library is added a git submodule under `test/resources/test-nginx/` folder, from `https://github.com/agentzh/test-nginx`.

Test files are located in `test/perl`.
The other libraries such as `Redis`, `test-nginx` are located in `test/resources/`.
Other files used when running the test are also located in `test/resources`.

When tests execute with `make tests`, a few things are happening:
* `Redis` server is compiled and installed in `target/redis-${redis_version}`. The compilation happens only once, not for every tests run, unless `make clear` is executed.
* `Redis` server is started
* `api-gateway` process is started for each test and then closed. The root folder for `api-gateway` is `target/servroot`
* some test files may output the logs to separate files under `target/test-logs`
* when tests complete successfully, `Redis` server is closed

### Prerequisites
#### MacOS
First make sure you have `Test::Nginx` installed. You can get it from CPAN with something like that:
```
sudo perl -MCPAN -e 'install Test::Nginx'
sudo perl -MCPAN -e 'install Test::LongString'
```
( ref: http://forum.nginx.org/read.php?2,185570,185679 )

Then make sure an `nginx` executable is found in path by symlinking the `api-gateway` executable:
```
ln -s /usr/local/sbin/api-gateway /usr/local/sbin/nginx
export PATH=$PATH:/usr/local/sbin/
```
For openresty you can execute:
```
export PATH=$PATH:/usr/local/openresty/nginx/sbin/
```

#### Other Linux systems:
For the moment, follow the MacOS instructions.

### Executing the tests
 To execute the test issue the following command:
 ```
 make test
 ```
 The build script builds and starts a `Redis` server, shutting it down at the end of the tests.
 The `Redis` server is compiled only the first time, and reused afterwards during the tests execution.
 The default configuration for `Redis` is found under: `test/resources/redis/redis-test.conf`

 If you want to run a single test, the following command helps:
 ```
 PATH=/usr/local/sbin:$PATH TEST_NGINX_SERVROOT=`pwd`/target/servroot TEST_NGINX_PORT=1989 prove -I ./test/resources/test-nginx/lib -I ./test/resources/test-nginx/inc -r ./test/perl/api-gateway/cache/cache.t
 ```
 This command only executes the test `cache.t`.


#### Troubleshooting tests

When executing the tests the `test-nginx`library stores the nginx configuration under `target/servroot/`.
It's often useful to consult the logs when a test fails.
If you run a test but can't seem to find the logs you can edit the configuration for that test specifying an `error_log` location:
```
error_log ../test-logs/validatorHandler_test6_error.log debug;
```

For Redis logs, you can consult `target/redis-test.log` file.

Resources
=========

* Testing Nginx : http://search.cpan.org/~agent/Test-Nginx-0.22/lib/Test/Nginx/Socket.pm 
