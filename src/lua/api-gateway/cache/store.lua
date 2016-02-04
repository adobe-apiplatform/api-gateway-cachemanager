--[[
  Copyright 2016 Adobe Systems Incorporated. All rights reserved.

  This file is licensed to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND, either express or implied.  See the License for the specific language governing permissions and limitations under the License.
  ]]


--
-- Base class for implementing a cache store Object.
-- Cache stores are responsible for putting and getting elements from a single location ( a shared dictionary in memory,
--  a remote Redis or others )
--
-- User: ddascal
-- Date: 31/01/16
--

local _M = {}

function _M:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    self:__init(o)
    return o
end

---
-- Init method called from constructor
function _M:__init()
end

---
--
function _M:getTTL()
    --1. if user has defined `ttl_function` return its value
    --2. if user has defined a static `ttl` return it
    --3. cache doesn't expire
end

---
-- Returns the name of the cache.
function _M:getName()
    error("getName method must be overwritten ")
end

function _M:get(key)
    error("get method must be overwritten ")
end

function _M:put(key, value)
    error("put method must be overwritten ")
end

function _M:evict(key)
    error("evict method must be overwritten ")
end

return _M