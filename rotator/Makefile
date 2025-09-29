SHELL := /bin/bash

APP := rotator
PKG := github.com/tapasyadubey/log-rotate-util/rotator
IMAGE ?= rotator:dev

.PHONY: build test docker helm-lint

build:
	go build ./...

test:
	go test ./...

docker:
	docker build -t $(IMAGE) -f Dockerfile .

# Local kind-based E2E
.PHONY: local-kind local-load local-install local-demo local-clean

local-kind:
	kind create cluster || true
	kubectl cluster-info

local-load: docker
	kind load docker-image $(IMAGE)

local-install:
	helm upgrade --install rotator ../helm/rotator \
	  --set rotator.image.repository=$(shell echo $(IMAGE) | cut -d: -f1) \
	  --set rotator.image.tag=$(shell echo $(IMAGE) | cut -d: -f2) \
	  --set serviceMonitor.enabled=false \
	  --set priorityClass.create=false

local-demo:
	kubectl create ns payments || true
	kubectl create ns checkout || true
	kubectl create ns transportation || true
	kubectl -n payments apply -f ../hack/log-writer-daemonset.yaml
	kubectl -n checkout apply -f ../hack/log-writer-daemonset.yaml
	kubectl -n transportation apply -f ../hack/log-writer-daemonset.yaml

local-clean:
	kubectl delete -n payments -f ../hack/log-writer-daemonset.yaml || true
	kubectl delete -n checkout -f ../hack/log-writer-daemonset.yaml || true
	kubectl delete -n transportation -f ../hack/log-writer-daemonset.yaml || true
	helm uninstall rotator || true
	kubectl delete ns payments checkout transportation || true

helm-lint:
	helm lint ../helm/rotator


