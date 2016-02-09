#!/usr/bin/perl
# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use strict;
use warnings;
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks()) + 40;

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    lua_package_path "src/lua/?.lua;/usr/local/lib/lua/?.lua;;";

    client_body_temp_path /tmp/;
    proxy_temp_path /tmp/;
    fastcgi_temp_path /tmp/;

    lua_shared_dict cachedkeys 10m; # used for redis health checks
    lua_shared_dict cachedrequests 100m;
    include ../../api-gateway/redis-upstream.conf; # generated during test script

    # register (true) Lua global variables or pre-load Lua modules at server start-up
    init_by_lua '
            ngx.apiGateway = ngx.apiGateway or {}
            local cache_cls = require "api-gateway.cache.cache"
            ngx.apiGateway.request_cache = cache_cls:new()

            local local_cache_max_ttl = 1
            local local_cache = require "api-gateway.cache.store.localCache":new({
                dict = "cachedrequests", -- defined in nginx conf as lua_shared_dict cachedkey 50m;
                ttl = function (value)
                    return math.min(local_cache_max_ttl,(ngx.var.arg_exptime or local_cache_max_ttl))
                end
            })
            local redis_cache_max_ttl = 2
            local redis_cache = require "api-gateway.cache.store.redisSetCache":new({
                ttl = function(value)
                    -- ngx.var.arg_exptime is automatically set when
                    --  /request-caching subrequest is called as:
                    --  srcache_store PUT /request-caching <key>&exptime=<srcache_expire>;
                    return math.min(redis_cache_max_ttl,(ngx.var.arg_exptime or redis_cache_max_ttl))
                end
            })

            -- NOTE: order is important
            ngx.apiGateway.request_cache:addStore(local_cache)
            ngx.apiGateway.request_cache:addStore(redis_cache)
    ';
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__


=== TEST 1: test request caching with local cache and redis
--- http_config eval: $::HttpConfig
--- config
    error_log ../test-logs/request_caching_test1_error.log debug;
    location /request-caching {
        internal;
        set $subrequest_method $echo_request_method;
        set_escape_uri $escaped_key $arg_key;

        content_by_lua '
            local sr_method = ngx.var.subrequest_method
            local cache = ngx.apiGateway.request_cache
            local key = ngx.var.escaped_key

            local rcache_cls = require "api-gateway.cache.rcache"
            local rcache = rcache_cls:new()

            rcache:handleRequest(sr_method, cache, key)
        ';
    }

    location /simulate-backend {
        add_header Cache-Control max-age=10;
        add_header Content-Type application/json;
        return 200 '{"message":"Please cache me for 10 seconds."}';
    }

    location /t {
         srcache_default_expire 1s;
         srcache_request_cache_control on; # onor Cache-control: no-cache and Pragma:no-cache

         set $key $request_uri;
         set_escape_uri $escaped_key $key;
         srcache_fetch GET /request-caching key=$escaped_key;
         srcache_store PUT /request-caching key=$escaped_key&exptime=$srcache_expire;
         # This directive controls what responses to store to the cache according to their status code.
         srcache_store_statuses 200 301 302;

         # proxy_pass/fastcgi_pass/drizzle_pass/echo/etc...
         # or even static files on the disk
         proxy_pass http://127.0.0.1:$TEST_NGINX_PORT/simulate-backend;
     }

     location /get_cached_key {
        set_escape_uri $escaped_key $arg_key;
        content_by_lua '
            local cache = ngx.apiGateway.request_cache
            if (cache:get(ngx.var.escaped_key) ~= nil) then
                ngx.print("from cache:" .. tostring(cache:get(ngx.var.escaped_key)))
            else
                ngx.status = ngx.HTTP_NOT_FOUND
                ngx.print("not found")
            end
        ';
     }

     location /sleep {
        content_by_lua '
            ngx.sleep(ngx.var.arg_time)
            ngx.say(ngx.var.arg_time)
        ';
     }

--- timeout: 20s
--- pipelined_requests eval
[
   "GET /t?p1=v1",
   "GET /get_cached_key?key=%2Ft%3Fp1%3Dv1",
   "GET /t?p1=v1",
   "GET /t?p1=v1",
   "GET /sleep?time=3.5",
   "GET /get_cached_key?key=%2Ft%3Fp1%3Dv1",
   "GET /t?p1=v1"
]
--- response_body_like eval
[
'{"message":"Please cache me for 10 seconds."}',

'from cache:HTTP/1.1 200 OK.*
Content-Type: application/json.*
Cache-Control: max-age=10.*
.*
{"message":"Please cache me for 10 seconds."}.*',

'{"message":"Please cache me for 10 seconds."}',

'{"message":"Please cache me for 10 seconds."}',

'3.5',

'not found',

'{"message":"Please cache me for 10 seconds."}',
]
--- error_code eval
[200,200,200,200,200,404,200]
--- no_error_log
[error]
--- more_headers
X-Test: test

