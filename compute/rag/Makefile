.PHONY: build push deploy redeploy bulk-index logs test

IMAGE := gitea.mati-lab.online/gooral/rag-watcher
TAG   := latest
NAS   := truenas_admin@192.168.1.65

# ── Local dev ────────────────────────────────────────────────────────────────

test:
	.venv/bin/pytest tests/ -v

# ── Image build + push ───────────────────────────────────────────────────────

build:
	docker buildx build --platform linux/amd64 -t $(IMAGE):$(TAG) --load .

push: build
	docker push $(IMAGE):$(TAG)

# ── NAS Custom App lifecycle ─────────────────────────────────────────────────

deploy:
	scp deploy/rag-watcher-create.json $(NAS):/tmp/
	ssh $(NAS) 'midclt call -j app.create "$$(cat /tmp/rag-watcher-create.json)"'

redeploy:
	ssh $(NAS) 'midclt call app.redeploy rag-watcher'

bulk-index:
	ssh $(NAS) 'cid=$$(docker ps --format "{{.Names}}" | grep rag-watcher | head -1); \
	  docker exec $$cid python -m watcher.bulk_index'

logs:
	ssh $(NAS) 'cid=$$(docker ps --format "{{.Names}}" | grep rag-watcher | head -1); \
	  docker logs --tail 100 -f $$cid'
