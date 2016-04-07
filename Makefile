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
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/cache/request/
	$(INSTALL) src/lua/api-gateway/cache/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/cache/
	$(INSTALL) src/lua/api-gateway/cache/store/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/cache/store/
	$(INSTALL) src/lua/api-gateway/cache/request/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/cache/request/

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

.PHONY: pre-docker-test
pre-docker-test:
	echo "   pre-docker-test"
	echo "   cleaning up any test_redis docker image"
	docker ps | grep test_redis | awk '{print $$1}' | xargs docker stop | xargs docker rm
	rm -rf $(BUILD_DIR)/*
	rm -rf  ~/tmp/apiplatform/api-gateway-cachemanager/
	mkdir  -p $(BUILD_DIR)
	mkdir  -p $(BUILD_DIR)/test-logs
	cp -r test/resources/api-gateway $(BUILD_DIR)
	sed -i '' 's/127\.0\.0\.1/redis\.docker/g' $(BUILD_DIR)/api-gateway/redis-upstream.conf
	rm -f $(BUILD_DIR)/test-logs/*
	mkdir -p ~/tmp/apiplatform/api-gateway-cachemanager
	cp -r ./src ~/tmp/apiplatform/api-gateway-cachemanager/
	cp -r ./test ~/tmp/apiplatform/api-gateway-cachemanager/
	cp -r ./target ~/tmp/apiplatform/api-gateway-cachemanager/
	mkdir -p ~/tmp/apiplatform/api-gateway-cachemanager/target/test-logs
	ln -s ~/tmp/apiplatform/api-gateway-cachemanager/target/test-logs ./target/test-logs

.PHONY: get-redis-docker-ip
get-redis-docker-ip:
	$(eval $@_IP := $(shell docker run --entrypoint=ifconfig alpine eth0 | grep "inet addr" | cut -d: -f2 | awk '{ print $$1}'))
	@echo "Assuming the next IP for the docker container is:" $($@_IP)
	sed -i '' 's/127\.0\.0\.1\:6379/$($@_IP)\:6379/g' ~/tmp/apiplatform/api-gateway-cachemanager/test/perl/api-gateway/cache/status/remoteCacheStatus.t

post-docker-test:
	echo "    post-docker-test"
	cp -r ~/tmp/apiplatform/api-gateway-cachemanager/target/ ./target
	rm -rf  ~/tmp/apiplatform/api-gateway-cachemanager

run-docker-test:
	echo "   run-docker-test"
	- cd ./test && docker-compose up --force-recreate

test-docker: pre-docker-test get-redis-docker-ip run-docker-test post-docker-test
	echo "running tests with docker ..."

test-docker-manual: pre-docker-test
	echo "starting the docker images ..."
	cd ./test/manual && docker-compose up --force-recreate

package:
	git archive --format=tar --prefix=api-gateway-cachemanager-1.3.0/ -o api-gateway-cachemanager-1.3.0.tar.gz -v HEAD

clean: all
	rm -rf $(BUILD_DIR)
	