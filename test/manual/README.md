Test folder for manual testing
==============================


### Motivation
Test manually caching with an external HTTP Client ( Browser, JMeter, etc )

### Running the Gateway manually


```bash
make test-docker-manual
```

Then open the browser to `http://<docker_ip>/cache/favicon.ico` , `http://<docker_ip>/cache/index.html` and refresh the page to retrieve the content from cache. 