--[[
  Copyright [year] Adobe Systems Incorporated. All rights reserved.

  This file is licensed to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND, either express or implied.  See the License for the specific language governing permissions and limitations under the License.
  ]]

-- Copyright (c) 2015 Adobe Systems Incorporated. All rights reserved.
--
--   Permission is hereby granted, free of charge, to any person obtaining a
--   copy of this software and associated documentation files (the "Software"),
--   to deal in the Software without restriction, including without limitation
--   the rights to use, copy, modify, merge, publish, distribute, sublicense,
--   and/or sell copies of the Software, and to permit persons to whom the
--   Software is furnished to do so, subject to the following conditions:
--
--   The above copyright notice and this permission notice shall be included in
--   all copies or substantial portions of the Software.
--
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
--   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
--   DEALINGS IN THE SOFTWARE.

-- An initialization script on a per worker basis.
-- User: ddascal
-- Date: 07/12/14
-- Time: 16:44
--

local _M = {}

local function initRequestCaching(parentObject)
    local cache_cls = require "api-gateway.cache.cache"
    parentObject.request_cache = cache_cls:new()

    local local_cache_max_ttl = 1000
    local local_cache = require "api-gateway.cache.store.localCache":new({
        dict = "cachedkeys", -- defined in nginx conf as lua_shared_dict cachedkey 50m;
        ttl = function (value)
            return math.min(local_cache_max_ttl,(ngx.var.arg_exptime or local_cache_max_ttl))
        end
    })
    local redis_cache_max_ttl = 2000
    local redis_cache = require "api-gateway.cache.store.redisSetCache":new({
        ttl = function(value)
            -- ngx.var.arg_exptime is automatically set when
            --  /request-caching subrequest is called as:
            --  srcache_store PUT /request-caching <key>&exptime=<srcache_expire>;
            return math.min(redis_cache_max_ttl,(ngx.var.arg_exptime or redis_cache_max_ttl))
        end
    })

    -- NOTE: order is important
    parentObject.request_cache:addStore(local_cache)
    parentObject.request_cache:addStore(redis_cache)
end

initRequestCaching(_M)

ngx.apiGateway = _M

