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
    lua_shared_dict cachedkeys 10m;
    include ../../api-gateway/redis-upstream.conf; # generated during test script
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__


=== TEST 1: test the put, get and evit methods in the redis set cache
--- http_config eval: $::HttpConfig
--- config
    error_log ../hashCache_redis_test1_error.log debug;
    location /t {
        content_by_lua '
            local redis_cache = require "api-gateway.cache.store.redisSetCache":new({
                field = "test-field",
                ttl = 1 -- static ttl in seconds
            })

            --1. set item in cache through cache
            local key = "key1"
            local value = "value1"
            redis_cache:put(key, value)
            local value_in_cache = redis_cache:get(key)
            assert(value_in_cache == value, "Value for the key should be value1 but instead it was " .. tostring(value_in_cache))

            --2. delete from local store, using the redis_cache store instance
            redis_cache:evict(key)

            assert(redis_cache:get(key) == nil, "Value in redis cache should be nil but instead was " .. tostring(redis_cache:get(key)))

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




