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

plan tests => repeat_each() * (blocks() * 3 );

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    include /etc/api-gateway/environment.conf.d/api-gateway-env.http.conf;
    # include all APIs being proxied
    include /etc/api-gateway/conf.d/*.conf;
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__


=== TEST 1: test cache manager stores are saved in order
--- http_config eval: $::HttpConfig
--- config
    error_log ../cache_test1_error.log debug;
    location /t {
        content_by_lua '
            local cache_cls = require "api-gateway.cache.cache"
            local cache = cache_cls:new()
            local local_cache = require "api-gateway.cache.store.localCache":new({
                dict = "cachedkeys", -- defined in nginx conf as lua_shared_dict cachedkey 50m;
                ttl = 1  -- static ttl in seconds
            })

            local redis_cache = require "api-gateway.cache.store.redisHashCache":new({
                field = "test-field",
                ttl = 2 -- static ttl in seconds
            })

            local stores = cache:getStores()
            assert(stores ~= nil, "getStores() should not be nil initially")
            assert(table.getn(stores) == 0, "getStores() should be empty initially, but it is " .. tostring(table.getn(stores)))

            -- NOTE: order is important
            cache:addStore(local_cache)
            cache:addStore(redis_cache)

            assert(stores ~= nil, "getStores() should not be nil")
            assert(table.getn(stores) == 2, "getStores() should return 2 stores")

            assert(stores[1]:getName() == "local_cache", "1st store should be names local_store but it is " .. tostring(stores[1]:getName()))
            assert(stores[2]:getName() == "redis_hash_cache", "2nd store should be names redis_hash_cache but it is " .. tostring(stores[2]:getName()))

            ngx.say("OK")
        ';
    }

--- timeout: 5s
--- request
GET /t
--- response_body_like eval
["OK"]
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test


=== TEST 2: test that local cache store is populated from a second level store
--- http_config eval: $::HttpConfig
--- config
    error_log ../cache_test2_error.log debug;
    location /t {
        content_by_lua '
            local cache_cls = require "api-gateway.cache.cache"
            local cache = cache_cls:new()
            local local_cache = require "api-gateway.cache.store.localCache":new({
                dict = "cachedkeys", -- defined in nginx conf as lua_shared_dict cachedkey 50m;
                ttl = 1  -- static ttl in seconds
            })
            local redis_cache = require "api-gateway.cache.store.redisSetCache":new({
                ttl = 2  -- static ttl in seconds
            })

            -- Set only the local cache store
            local stores = cache:getStores()
            cache:addStore(local_cache)
            cache:addStore(redis_cache)
            assert(stores ~= nil, "getStores() should not be nil")
            assert(table.getn(stores) == 2, "getStores() should return 1 stores")

            --1. set item in cache through cache
            local key = "key1"
            local value = "value1"
            cache:put(key, value)
            local value_in_cache = cache:get(key)
            assert(value_in_cache == value, "Value for the key should be value1 but instead it was " .. tostring(value_in_cache))

            local value_in_redis_hash_cache = redis_cache:get(key)
            assert(value_in_redis_hash_cache == value, "Value for the key should be value1 in redis but instead it was " .. tostring(value_in_redis_hash_cache))

            --2. delete from local store, using the local_cache store instance
            local_cache:evict(key)

            assert(local_cache:get(key) == nil, "Value in local_cache should be nil but instead was " .. tostring(local_cache:get(key)))

            --3. get from cache through cache. Key should still be set
            assert(cache:get(key) == value, "Value in cache should be value1 but instead was " .. tostring(cache:get(key)))
            assert(redis_cache:get(key) == value, "Value in redis_cache should be value1 but instead was " .. tostring(redis_cache:get(key)))
            assert(local_cache:get(key) == value, "Value in local_cache should be value1 but instead was " .. tostring(local_cache:get(key)))

            ngx.say("OK")
        ';
    }

--- timeout: 5s
--- request
GET /t
--- response_body_like eval
["OK"]
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test


=== TEST 3: test that items can be expired from cache
--- http_config eval: $::HttpConfig
--- config
    error_log ../cache_test3_error.log debug;
    location /t {
        content_by_lua '
            local cache_cls = require "api-gateway.cache.cache"
            local cache = cache_cls:new()
            local local_cache = require "api-gateway.cache.store.localCache":new({
                dict = "cachedkeys", -- defined in nginx conf as lua_shared_dict cachedkey 50m;
                ttl = 1  -- static ttl in seconds
            })
            local redis_cache = require "api-gateway.cache.store.redisSetCache":new({
                ttl = 2  -- static ttl in seconds
            })

            -- Set only the local cache store
            local stores = cache:getStores()
            cache:addStore(local_cache)
            cache:addStore(redis_cache)
            assert(stores ~= nil, "getStores() should not be nil")
            assert(table.getn(stores) == 2, "getStores() should return 1 stores")

            --1. set item in cache through cache with TTL of 1s
            local key = "key1"
            local value = "value1"
            cache:put(key, value)

            assert(local_cache:get(key) == value, "Value in local_cache should be value1 but instead was " .. tostring(local_cache:get(key)))

            --2. pause for 2s
            ngx.sleep(2)

            --3. test that the item does not exist anymore
            assert(local_cache:get(key) == nil, "Value in local_cache should be nil but instead was " .. tostring(local_cache:get(key)))

            ngx.say("OK")
        ';
    }

--- timeout: 5s
--- request
GET /t
--- response_body_like eval
["OK"]
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test


=== TEST 4: test that ttl_function overrides the static ttl
--- http_config eval: $::HttpConfig
--- config
    error_log ../cache_test4_error.log debug;
    location /t {
        content_by_lua '
            --1. set item in cache through cache with TTL of 10s
            --2. set a TTL_function to expire the item in 1s
            --3. wait for 1s then get the item from cache
            --4. test that the item does not exist anymore
            ngx.say("OK")
        ';
    }

--- timeout: 5s
--- request
GET /t
--- response_body_like eval
["OK"]
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test


