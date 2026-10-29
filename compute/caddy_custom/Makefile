.PHONY: build clean

# Plain Caddy (standard modules only) for the amd64 LXCs. The cloudsmith apt
# build lags Go security releases (2.11.7 apt = go1.26.8, short of the
# CVE-2026-111943 fix), so we build it ourselves on the same builder digest
# network/caddy/Dockerfile pins. Bump both together.
CADDY_VERSION := v2.11.7
BUILDER       := caddy:2-builder@sha256:bf6a7d38add2508b7d2e3e3f40cf2af399214f143c0fa3daa51f254e01f8d293
OUT           := $(CURDIR)/dist

build: $(OUT)/caddy-linux-amd64

$(OUT)/caddy-linux-amd64: Makefile
	mkdir -p $(OUT)
	docker run --rm -u $$(id -u):$$(id -g) -e HOME=/tmp -e GOCACHE=/tmp/gc \
	  -e GOMODCACHE=/tmp/gm -e GOOS=linux -e GOARCH=amd64 -e CGO_ENABLED=0 -e XCADDY_SETCAP=0 \
	  -v $(OUT):/out -w /tmp $(BUILDER) \
	  xcaddy build $(CADDY_VERSION) --output /out/caddy-linux-amd64
	go version $@

clean:
	rm -rf $(OUT)
