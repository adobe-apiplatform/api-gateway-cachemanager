# NOTE: Every line in a recipe must begin with a tab character.
BUILD_DIR ?= target
REDIS_VERSION ?= 2.8.6

PREFIX ?=          /usr/local
LUA_INCLUDE_DIR ?= $(PREFIX)/include
LUA_LIB_DIR ?=     $(PREFIX)/lib/lua/$(LUA_VERSION)
INSTALL ?= install
REDIS_SERVER ?= $(BUILD_DIR)/redis-$(REDIS_VERSION)/src/redis-server

.PHONY: all clean test install

all: ;

install: all
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/cache/
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/cache/store/
	$(INSTALL) src/lua/api-gateway/validation/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/cache/
	$(INSTALL) src/lua/api-gateway/validation/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/cache/store/

test: redis
	echo "Starting redis server on default port"
	# $(BUILD_DIR)/redis-$(REDIS_VERSION)/src/redis-server test/resources/redis/redis-test.conf
	$(REDIS_SERVER) test/resources/redis/redis-test.conf
	echo "updating git submodules ..."
	if [ ! -d "test/resources/test-nginx/lib" ]; then	git submodule update --init --recursive; fi
	echo "running tests ..."
	mkdir  -p $(BUILD_DIR)
	mkdir  -p $(BUILD_DIR)/test-logs
	cp -r test/resources/api-gateway $(BUILD_DIR)
	rm -f $(BUILD_DIR)/test-logs/*

	PATH=/usr/local/sbin:$$PATH TEST_NGINX_SERVROOT=`pwd`/$(BUILD_DIR)/servroot TEST_NGINX_PORT=1989 prove -I ./test/resources/test-nginx/lib -I ./test/resources/test-nginx/inc  -r ./test/perl
	cat $(BUILD_DIR)/redis-test.pid | xargs kill

redis: all
	mkdir -p $(BUILD_DIR)
	if [ "$(REDIS_SERVER)" = "$(BUILD_DIR)/redis-$(REDIS_VERSION)/src/redis-server" ]; then \
		tar -xf test/resources/redis/redis-$(REDIS_VERSION).tar.gz -C $(BUILD_DIR)/;\
		cd $(BUILD_DIR)/redis-$(REDIS_VERSION) && make; \
	fi
	echo " ... using REDIS_SERVER=$(REDIS_SERVER)"

test-docker:
	echo "running tests with docker ..."
	mkdir  -p $(BUILD_DIR)
	mkdir  -p $(BUILD_DIR)/test-logs
	cp -r test/resources/api-gateway $(BUILD_DIR)
	sed -i '' 's/127\.0\.0\.1/redis\.docker/g' $(BUILD_DIR)/api-gateway/redis-upstream.conf
	rm -f $(BUILD_DIR)/test-logs/*
	mkdir -p ~/tmp/apiplatform/api-gateway-cachemanager
	cp -r ./src ~/tmp/apiplatform/api-gateway-cachemanager/
	cp -r ./test ~/tmp/apiplatform/api-gateway-cachemanager/
	cp -r ./target ~/tmp/apiplatform/api-gateway-cachemanager/
	cd ./test && docker-compose up
	cp -r ~/tmp/apiplatform/api-gateway-cachemanager/target/ ./target
	rm -rf  ~/tmp/apiplatform/api-gateway-cachemanager

package:
	git archive --format=tar --prefix=api-gateway-cachemanager-1.3.0/ -o api-gateway-cachemanager-1.3.0.tar.gz -v HEAD

clean: all
	rm -rf $(BUILD_DIR)
	