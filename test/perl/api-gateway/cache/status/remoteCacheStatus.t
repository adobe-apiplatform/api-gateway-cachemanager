# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use strict;
use warnings;
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(4);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3) - 6;

my $pwd = cwd();

our $HttpConfig = <<_EOC_;

    lua_socket_log_errors off;

    lua_package_path "src/lua/?.lua;/usr/local/lib/lua/?.lua;;";

    client_body_temp_path /tmp/;
    proxy_temp_path /tmp/;
    fastcgi_temp_path /tmp/;

    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        require "resty.core"
    ';
    lua_shared_dict cachedkeys 10m;
    include ../../api-gateway/redis-upstream.conf; # generated during test script

    init_worker_by_lua '
        local function loadrequire(module)
            ngx.log(ngx.DEBUG, "Loading module [" .. tostring(module) .. "]")
            local function requiref(module)
                require(module)
            end

            local res = pcall(requiref, module)
            if not (res) then
                ngx.log(ngx.WARN, "Could not load module [", module, "].")
                return nil
            end
            return require(module)
        end

        local function initRedisHealthCheck()
            ngx.shared.cachedkeys:flush_all()

            local hc = loadrequire("resty.upstream.healthcheck")
            if (hc == nil) then
                return
            end

            local ok, err = hc.spawn_checker{
                shm = "cachedkeys", -- defined by "lua_shared_dict"
                upstream = "cache_read_only_backend", -- defined by "upstream"
                type = "http",
                http_req = "PING\\\\r\\\\n", -- raw HTTP request for checking

                interval = 2000, -- run the check cycle every X ms
                timeout = 1500, -- timeout in ms for network operations
                fall = 2, -- # of successive failures before turning a peer down
                rise = 2, -- # of successive successes before turning a peer up
            }
            if not ok then
                ngx.log(ngx.ERR, "failed to spawn health checker: ", err)
                return
            end
        end
        initRedisHealthCheck()
    ';

    upstream cache_rw_backend {
        server 127.0.0.1:6379;
    }
_EOC_

#no_diff();
no_long_string();
run_tests();


__DATA__

=== TEST 1: health check (good case), test with one server in upstream
--- http_config eval
"$::HttpConfig"
. q{
upstream cache_read_only_backend {
    server 127.0.0.1:6379;
}
}
--- config
    location = /test1 {
        access_log off;
        content_by_lua '
            ngx.sleep(5.52)

            local hc = require "resty.upstream.healthcheck"
            ngx.log(ngx.INFO,"[Test1]: Status is: \\n" .. hc.status_page())

            local HealthCheckCls = require "api-gateway.cache.status.remoteCacheStatus"
            local healthCheck = HealthCheckCls:new()

            local redisUpstreamHealthResult = healthCheck:getStatus("cache_read_only_backend")

            local responseString = ""
            for key,value in ipairs(redisUpstreamHealthResult) do
                responseString = responseString .. value
            end

            ngx.log(ngx.INFO,"\\n responseString is ".. responseString)
            ngx.print(responseString)

            local redisToRead = healthCheck:getHealthyServer("cache_read_only_backend")
            ngx.log(ngx.INFO,"redis to read is ".. tostring(redisToRead))
            ngx.say("Selected Redis Node:", tostring(redisToRead))
        ';
    }
--- timeout: 20s
--- request
GET /test1

--- response_body
127.0.0.1:6379 up
Selected Redis Node:127.0.0.1:6379

--- no_error_log
[error]


=== TEST 2: health check (bad case), test with a down backup
--- http_config eval
"$::HttpConfig"
. q{
    upstream cache_read_only_backend {
        server 127.0.0.1:6379;
        server localhost:12256 backup;
    }
}
--- config
    location = /test2 {
        access_log off;
        content_by_lua '
            ngx.sleep(5.52)

            local hc = require "resty.upstream.healthcheck"
            ngx.log(ngx.INFO,"[Test2]: Status is: \\n" .. hc.status_page())

            local HealthCheckCls = require "api-gateway.cache.status.remoteCacheStatus"
            local healthCheck = HealthCheckCls:new()

            local redisUpstreamHealthResult = healthCheck:getStatus("cache_read_only_backend")

            local responseString = ""
            for key,value in ipairs(redisUpstreamHealthResult) do
                responseString = responseString .. value
            end

            ngx.log(ngx.INFO,"\\n responseString is ".. responseString)
            ngx.print(responseString)

            local redisToRead = healthCheck:getHealthyServer("cache_read_only_backend")
            ngx.log(ngx.INFO,"redis to read is ".. tostring(redisToRead))
            ngx.say("Selected Redis Node:", tostring(redisToRead))
        ';
    }
--- timeout: 20s
--- request
GET /test2

--- response_body
127.0.0.1:6379 up
127.0.0.1:12256 DOWN
Selected Redis Node:127.0.0.1:6379
--- no_error_log

=== TEST 3: health check (bad case), test that backup is selected in the end
--- http_config eval
"$::HttpConfig"
. q{
    upstream cache_read_only_backend {
        server 127.0.0.1:12256;
        server 127.0.0.1:12257;
        server 127.0.0.1:6379 backup;
    }
}
--- config
    location = /test2 {
        access_log off;
        content_by_lua '
            ngx.sleep(5.52)

            local hc = require "resty.upstream.healthcheck"
            ngx.log(ngx.INFO,"[Test3]: Status is: \\n" .. hc.status_page())

            local HealthCheckCls = require "api-gateway.cache.status.remoteCacheStatus"
            local healthCheck = HealthCheckCls:new()

            local redisUpstreamHealthResult = healthCheck:getStatus("cache_read_only_backend")

            local responseString = ""
            for key,value in ipairs(redisUpstreamHealthResult) do
                responseString = responseString .. value
            end

            ngx.log(ngx.INFO,"\\n responseString is ".. responseString)
            ngx.print(responseString)

            local redisToRead, redisHost, redisPort = healthCheck:getHealthyServer("cache_read_only_backend")
            ngx.log(ngx.INFO,"redis to read is ".. tostring(redisToRead))
            ngx.say("Selected Redis Node:", tostring(redisToRead), ",port:", tostring(redisPort))
        ';
    }
--- timeout: 20s
--- request
GET /test2

--- response_body
127.0.0.1:12256 DOWN
127.0.0.1:12257 DOWN
127.0.0.1:6379 up
Selected Redis Node:127.0.0.1:6379,port:6379
--- no_error_log


=== TEST 4: health check (bad case), all nodes are down
--- http_config eval
"$::HttpConfig"
. q{
    upstream cache_read_only_backend {
        server 127.0.0.1:12256;
        server 127.0.0.1:12257;
        server localhost:12258 backup;
    }
}
--- config
    location = /test2 {
        access_log off;
        content_by_lua '
            ngx.sleep(5.52)

            local hc = require "resty.upstream.healthcheck"
            ngx.log(ngx.INFO,"[Test4]: Status is: \\n" .. hc.status_page())

            local HealthCheckCls = require "api-gateway.cache.status.remoteCacheStatus"
            local healthCheck = HealthCheckCls:new()

            local redisUpstreamHealthResult = healthCheck:getStatus("cache_read_only_backend")

            local responseString = ""
            for key,value in ipairs(redisUpstreamHealthResult) do
                responseString = responseString .. value
            end

            ngx.log(ngx.INFO,"\\n responseString is ".. responseString)
            ngx.print(responseString)

            local redisToRead, redisHost, redisPort = healthCheck:getHealthyServer("cache_read_only_backend")
            ngx.log(ngx.INFO,"redis to read is ".. tostring(redisToRead))
            ngx.say("Selected Redis Node:", tostring(redisToRead), ",host:", tostring(redisHost), ",port:", tostring(redisPort))
        ';
    }
--- timeout: 20s
--- request
GET /test2

--- response_body
127.0.0.1:12256 DOWN
127.0.0.1:12257 DOWN
127.0.0.1:12258 DOWN
Selected Redis Node:nil,host:nil,port:nil
--- no_error_log



=== TEST 5: test that healthy node is stored in shared_dict
--- http_config eval
"$::HttpConfig"
. q{
upstream cache_read_only_backend {
    server 127.0.0.1:6379;
}
}
--- config
    location = /test1 {
        access_log off;
        content_by_lua '
            ngx.sleep(5.52)

            local hc = require "resty.upstream.healthcheck"
            ngx.log(ngx.INFO,"[Test1]: Status is: \\n" .. hc.status_page())

            local HealthCheckCls = require "api-gateway.cache.status.remoteCacheStatus"
            local healthCheck = HealthCheckCls:new({shared_dict = "cachedkeys" })

            local redisUpstreamHealthResult = healthCheck:getStatus("cache_read_only_backend")

            local responseString = ""
            for key,value in ipairs(redisUpstreamHealthResult) do
                responseString = responseString .. value
            end

            ngx.log(ngx.INFO,"\\n responseString is ".. responseString)
            ngx.print(responseString)

            local redisToRead, redisHost, redisPort = healthCheck:getHealthyServer("cache_read_only_backend")
            ngx.log(ngx.INFO,"redis to read is ".. tostring(redisToRead))
            ngx.say("Selected Redis Node:", tostring(redisToRead), ",port:", tostring(redisPort))


            -- make sure it is saved in the dictionary too
            local dict_name = "cachedkeys"
            local dict = ngx.shared[dict_name]
            local health_upstream_key = "healthy_upstream:cache_read_only_backend"
            local upstreamRedis = dict:get(health_upstream_key)
            ngx.say("Selected Redis Node in shared_dict:", upstreamRedis)

            -- read the node again
            redisToRead, redisHost, redisPort = healthCheck:getHealthyServer("cache_read_only_backend")
            ngx.say("Selected Redis Node 2nd time:", tostring(redisToRead),",port:", tostring(redisPort))
        ';
    }
--- timeout: 20s
--- request
GET /test1

--- response_body
127.0.0.1:6379 up
Selected Redis Node:127.0.0.1:6379,port:6379
Selected Redis Node in shared_dict:127.0.0.1:6379
Selected Redis Node 2nd time:127.0.0.1:6379,port:6379
--- no_error_log
[error]
