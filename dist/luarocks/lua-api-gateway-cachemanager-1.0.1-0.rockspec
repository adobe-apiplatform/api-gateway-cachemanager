package = "lua-api-gateway-cachemanager"
version = "./-1"
source = {
   url = "*** please add URL for source tarball, zip or repository here ***"
}
description = {
   detailed = [[
Table of Contents
=================
* [Status](#status)
* [Synopsis] (#synopsis)
* [Motivation](#motivation)
* [Integration with other caching modules](#integration-with-other-caching-modules)
* [Features](#features)
* [Developer guide](#developer-guide)
 ]],
   homepage = "*** please enter a project homepage ***",
   license = "*** please specify a license ***"
}
dependencies = {}
build = {
   type = "builtin",
   modules = {
      ["lua.api-gateway.cache.cache"] = "src/lua/api-gateway/cache/cache.lua",
      ["lua.api-gateway.cache.request.rcache"] = "src/lua/api-gateway/cache/request/rcache.lua",
      ["lua.api-gateway.cache.status.remoteCacheStatus"] = "src/lua/api-gateway/cache/status/remoteCacheStatus.lua",
      ["lua.api-gateway.cache.store"] = "src/lua/api-gateway/cache/store.lua",
      ["lua.api-gateway.cache.store.localCache"] = "src/lua/api-gateway/cache/store/localCache.lua",
      ["lua.api-gateway.cache.store.redisCache"] = "src/lua/api-gateway/cache/store/redisCache.lua",
      ["lua.api-gateway.cache.store.redisHashCache"] = "src/lua/api-gateway/cache/store/redisHashCache.lua",
      ["lua.api-gateway.cache.store.redisSetCache"] = "src/lua/api-gateway/cache/store/redisSetCache.lua"
   }
}
