--[[
  Copyright 2016 Adobe Systems Incorporated. All rights reserved.

  This file is licensed to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND, either express or implied.  See the License for the specific language governing permissions and limitations under the License.
  ]]
--
-- Module for selecting a healthy server from an upstream.
--   It's best to be used with health-checks so that a peer is maked UP or DOWN
-- User: nramaswa
-- Date: 4/17/14
-- Time: 7:38 PM

local _M = {}
local DEFAULT_SHARED_DICT = "cachedkeys"

function _M:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if ( o ~= nil ) then
        self.shared_dict = o.shared_dict or DEFAULT_SHARED_DICT
    end
    return o
end

--- Reused from the "resty.upstream.healthcheck" module to get the
-- status of the upstream servers
local function gen_peers_status_info(peers, bits, idx)
    local npeers = #peers
    for i = 1, npeers do
        local peer = peers[i]
        bits[idx] = peer.name
        if peer.down then
            bits[idx + 1] = " DOWN\n"
        else
            bits[idx + 1] = " up\n"
        end
        idx = idx + 2
    end
    return idx
end

--- Returns the results of the health checks for the provided upstream_name
-- as found in the "resty.upstream.healthcheck" module.
-- @param upstream_name
--
local function get_health_check_for_upstream(upstream_name)
    local ok, upstream = pcall(require, "ngx.upstream")
    if not ok then
        error("ngx_upstream_lua module required")
    end

    local get_primary_peers = upstream.get_primary_peers
    local get_backup_peers = upstream.get_backup_peers

    local ok, new_tab = pcall(require, "table.new")
    if not ok or type(new_tab) ~= "function" then
        new_tab = function (narr, nrec) return {} end
    end

    local n = 1
    local bits = new_tab(n * 20, 0)
    local idx = 1

        local peers, err = get_primary_peers(upstream_name)
        if not peers then
            return "failed to get primary peers in upstream " .. upstream_name .. ": "
                    .. err
        end

        idx = gen_peers_status_info(peers, bits, idx)

        peers, err = get_backup_peers(upstream_name)
        if not peers then
            return "failed to get backup peers in upstream " .. upstream_name .. ": "
                    .. err
        end

        idx = gen_peers_status_info(peers, bits, idx)

    return bits
end

--- Returns a cached healthy upstream.
-- @param dict_name  shared dict name
-- @param upstream_name  the name of the upstream as defined in the config
--
local function get_healthy_upstream_from_cache(dict_name, upstream_name)
    local dict = ngx.shared[dict_name]
    local healthy_upstream
    local health_upstream_key = "healthy_upstream:" .. tostring(upstream_name)
    if (nil ~= dict) then
        healthy_upstream = dict:get(health_upstream_key)
    end
    return healthy_upstream
end

local function update_healthy_upstream_in_cache(dict_name, upstream_name, healthy_upstream)
    local dict = ngx.shared[dict_name];
    if (nil ~= dict) then
        ngx.log(ngx.DEBUG, "Saving a healthy upstream:", healthy_upstream, " in cache:", dict_name, " for upstream:", upstream_name)
        local exp_time_in_seconds = 5
        local health_upstream_key = "healthy_upstream:" .. tostring(upstream_name)
        dict:set(health_upstream_key, healthy_upstream, exp_time_in_seconds)
        return
    end

    ngx.log(ngx.WARN, "Dictionary ", dict_name,  " doesn't seem to be set. Did you define one ? ")
end

--- Returns the host and port from an upstream like host:port
-- @param upstream_host
--
local function get_host_and_port_in_upstream(upstream_host)
    local p = {}
    p.host = upstream_host

    local idx = string.find(upstream_host, ":", 1, true)
    if idx then
        p.host = string.sub(upstream_host, 1, idx - 1)
        p.port = tonumber(string.sub(upstream_host, idx + 1))
    end
    return p.host, p.port
end


function _M:getStatus(upstream_name)
    return get_health_check_for_upstream(upstream_name)
end

--- Returns the first healthy server found in the upstream_name
-- Returns 3 values: <upstreamName , host, port >
-- The difference between upstream and <host,port> is that the upstream may be just a string containing host:port
-- @param upstream_name
--
function _M:getHealthyServer(upstream_name)

    -- get the host and port from the local cache first
    local healthy_host = get_healthy_upstream_from_cache(self.shared_dict, upstream_name)
    if ( nil ~= healthy_host) then
        local host, port = get_host_and_port_in_upstream(healthy_host)
        return healthy_host, host, port
    end

    -- if the host is not in the local cache get it from the upstream configuration
    ngx.log(ngx.DEBUG, "Looking up for a healthy peer in upstream:", upstream_name)
    local upstream_health_result = get_health_check_for_upstream(upstream_name)

    if(upstream_health_result == nil) then
        ngx.log(ngx.ERR, "\n No upstream results!")
        return nil
    end

    for key,value in ipairs(upstream_health_result) do
        -- return the first peer found to be up.
        -- TODO: save all the peers that are up and return them using round-robin alg
        if(value == " up\n") then
            healthy_host = upstream_health_result[key-1]
            update_healthy_upstream_in_cache(self.shared_dict, upstream_name, healthy_host)
            local host, port = get_host_and_port_in_upstream(healthy_host)
            return healthy_host, host, port
        end
        if(value == " DOWN\n" and upstream_health_result[key-1] ~= nil ) then
            ngx.log(ngx.WARN, "Peer ", tostring(upstream_health_result[key-1]), " is down! Checking for backup peers.")
        end
    end

    ngx.log(ngx.ERR, "All peers are down!")
    return nil -- No peers are up
end

return _M