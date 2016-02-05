--[[
  Copyright 2016 Adobe Systems Incorporated. All rights reserved.

  This file is licensed to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND, either express or implied.  See the License for the specific language governing permissions and limitations under the License.
  ]]

--
--
-- User: ddascal
-- Date: 01/02/16
--

local redis_cache_cls = require "api-gateway.cache.store.redisCache"

local _M = redis_cache_cls:new()

-- Returns the name of this cache store.
function _M:getName()
    return "redis_set_cache"
end

--- The Redis command to execute in order to save an elements in the cache using set
-- @param redis the instance to the redis client
-- @param key Cache Key
-- @param value Cache Value
--
function _M:addPutCommand(redis, key, value)
    redis:set(key, value)
end

--- The Redis command to execute in order to get an element from the cache using set
-- @param redis the instance of the redis client
-- @param key Cache Key
--
function _M:addGetCommand(redis, key)
    return redis:get(key)
end

--- The Redis command to execute in order to delete an element from the cache using set
-- @param redis the instance of the redis client
-- @param key Cache Key
--
function _M:addDeleteCommand(redis, key)
    return redis:del(key)
end


return _M
