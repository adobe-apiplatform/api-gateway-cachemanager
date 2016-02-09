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
    self:__init(o)
    return o
end

---
-- Init method called from constructor
function _M:__init()
    local cache = ngx.apiGateway.request_cache
    local cache_key = ngx.var.escaped_key
    if (ngx.var.subrequest_method == "PUT") then
        ngx.req.read_body()
        -- value is nil if
        --
        --1. the request body has not been read,
        --2. the request body has been read into disk temporary files,
        --3. or the request body has zero size.
        -- If the request body has been read into disk files, try calling the ngx.req.get_body_file function instead.
        local value = ngx.req.get_body_data() or ngx.req.get_body_file()
        ngx.log(ngx.DEBUG, "Storing value=", tostring(value), " into key=", tostring(cache_key), " in cache")
        if (value ~= nil) then
            cache:put(tostring(cache_key),value)
            ngx.status = ngx.HTTP_OK
            ngx.log(ngx.DEBUG, "Stored value=", tostring(value), " with key=", tostring(cache_key), " in cache")
        end
    end

    if (ngx.var.subrequest_method == "GET") then
        local val = cache:get(tostring(cache_key))
        if (val ~= nil) then
            ngx.log(ngx.DEBUG, "Found value=", tostring(val), " with key=", tostring(cache_key), " stored in cache")
            ngx.status = ngx.HTTP_OK
        else
            ngx.log(ngx.DEBUG, "No value in cache found for key=", tostring(cache_key))
            ngx.status = ngx.HTTP_NOT_FOUND
        end
    end
end

return _M