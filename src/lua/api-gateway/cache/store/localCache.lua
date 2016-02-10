--[[
  Copyright 2016 Adobe Systems Incorporated. All rights reserved.

  This file is licensed to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND, either express or implied.  See the License for the specific language governing permissions and limitations under the License.
  ]]



-- Local cache stores the elements into a Lua Shared Cache dictionary: https://github.com/openresty/lua-nginx-module#ngxshareddict.
--
-- User: ddascal
-- Date: 31/01/16
--

local cache_store_cls = require "api-gateway.cache.store"

local _M = cache_store_cls:new()

local function throwIfDictIsNil(init_obj)
    if (init_obj.dict == nil) then
        error("Please provide the lua shared dictionary name.")
    end
end

---
-- Init method called from constructor
function _M:__init(init_obj)
    throwIfDictIsNil(init_obj)
end

--- Returns the dictionary name as set in the constructor ini object with "dict"
--
function _M:getDict()
    return self.dict
end

function _M:getDictInstance()
    local dict = ngx.shared[self:getDict()] -- cachedkeys is defined in conf.d/api_gateway_init.conf
    if dict == nil then
        ngx.log(ngx.WARN, "dict `", tostring(self:getDict()), "` not defined. Please define it with 'lua_shared_dict ", tostring(self:getDict()), " 50m'")
        return nil
    end
    return dict
end

--- Returns the name of the cache.
--
function _M:getName()
    return "local_cache"
end


function _M:get(key)
    local d = self:getDictInstance()
    if (d ~= nil) then
        return d:get(key)
    end
    return nil
end

function _M:put(key, value)
    if (type(value) ~= "string") then
        ngx.log(ngx.WARN,".Could not save key=", tostring(key), " into ", tostring(self:getName()), ". Invalid value of type=", type(value))
    end
    local d = self:getDictInstance()
    if (d ~= nil) then
        local expires_in = self:getTTL(key, value) or 0
        local succ, err, forcible = d:set(key, value, expires_in)
        if (err) then
            ngx.log(ngx.WARN, "Could not save key=", tostring(key), " into ", tostring(self:getName()), ".", err)
        end
        if (forcible) then
            ngx.log(ngx.INFO, "shared dict=", tostring(self:getDict()) " has removed other items from memory when adding key:", tostring(key))
        end
        return succ, err, forcible
    end
    return nil
end

function _M:evict(key)
    local d = self:getDictInstance()
    if (d ~= nil) then
        return d:delete(key)
    end
    return nil
end



return _M