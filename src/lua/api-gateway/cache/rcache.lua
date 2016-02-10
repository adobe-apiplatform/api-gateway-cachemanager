--[[
  Copyright 2016 Adobe Systems Incorporated. All rights reserved.

  This file is licensed to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND, either express or implied.  See the License for the specific language governing permissions and limitations under the License.
  ]]


--
-- Base class for implementing request caching
-- Cache backend request responses to redis and local cache
-- Subrequest methods "PUT" and "GET" will store respectivly retrieve backend responses from cache
--
-- User: stanciu
-- Date: 02/08/16
--

local _M = {}

function _M:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end


--- This method returns the request body using Lua functions.
--  There are 2 functions used:
--  1. ngx.req.get_body_data() - returning nil if
--      1. the request body has not been read,
--      2. the request body has been read into disk temporary files,
--      3. or the request body has zero size.
--  2. ngx.req.get_body_file()
--     If the request body has been read into disk files, ngx.req.get_body_file() function may be used instead.
--
local function readRequestBody()
    ngx.req.read_body()
    return ngx.req.get_body_data() or ngx.req.get_body_file()
end

--- The request body is either returned from an nginx variable $subrequest_body
-- or it's read from readRequestBody() method
--
local function getRequestBody()
    return ngx.var.subrequest_body or readRequestBody()
end

--- Stores the given key into the given cache instance.
-- The value of the key is read from the subrequest body
-- @param cache an instance of cache.lua
-- @param key the key to save
--
local function put(cache, key)
    local value = getRequestBody()
    --ngx.log(ngx.DEBUG, "Storing value=", tostring(value), " into key=", tostring(key), " in cache")
    ngx.log(ngx.DEBUG, "Storing key=", tostring(key), " in cache.")
    if (value ~= nil) then
        cache:put(tostring(key),value)
--        ngx.log(ngx.DEBUG, "Stored value=", tostring(value), " with key=", tostring(key), " in cache")
        ngx.log(ngx.DEBUG, "Stored key=", tostring(key), " in cache.")
        return ngx.HTTP_OK
    end
end

--- Returns a tuple <HTTP Status,value> found in cache, it any
-- @param cache an instance of cache.lua
-- @param key the key to lookup
--
local function get(cache, key)
    local val = cache:get(tostring(key))
    if (val ~= nil) then
--        ngx.log(ngx.DEBUG, "Found value=", tostring(val), " with key=", tostring(key), " stored in cache")
        ngx.log(ngx.DEBUG, "Found key=", tostring(key), " stored in cache.")
        return ngx.HTTP_OK, val
    end
    ngx.log(ngx.DEBUG, "No value in cache found for key=", tostring(key))
    return ngx.HTTP_NOT_FOUND, nil
end

---
-- Store/retrieve requests responses to/from cache
-- @param sr_method
-- @param cache 
-- @param key 
--
function _M:handleRequest(sr_method, cache, key)
    ngx.log(ngx.DEBUG , " Handling ", sr_method , " for key [", tostring(key), "]")
    if ("PUT" == sr_method) then
        local status = put(cache, key)
        ngx.status = status
        return
    end
    if ("GET" == sr_method) then
        local status, value = get(cache, key)
        ngx.status = status     -- print the status first
        ngx.print(value or "")  -- then append the body, if any
        return
    end
end

return _M