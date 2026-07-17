MAKEFLAGS += --no-print-directory
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := build
.DELETE_ON_ERROR:
.SUFFIXES:

-include .env.upload
export GH_TOKEN
export GITHUB_TOKEN
export GITHUB_TAG

INSTALL ?= install
PYTHON ?= python3
TAR ?= tar

UNAME := $(shell uname)
ARCH := $(shell uname -m)
SELECTOR := $(shell if test "$(UNAME)" = "Darwin" ; then echo "-f Makefile.OSX" ; fi)
PREFIX ?= /usr/local
DESTDIR ?= $(CURDIR)/build/root

DIST_DIR := dist
RELEASE_TAG := $(shell awk 'NR == 1 {print $$5}' NEWS)
VERSION := $(patsubst v%,%,$(RELEASE_TAG))
PACKAGE := $(DIST_DIR)/libfaketime-$(VERSION)-$(UNAME)-$(ARCH).tar.gz
GITHUB_REPOSITORY := chrisovalantise/libfaketime

.PHONY: all
all:
	$(MAKE) $(SELECTOR) -C src PREFIX="$(PREFIX)" all

.PHONY: test
test:
	$(MAKE) $(SELECTOR) -C src PREFIX="$(PREFIX)" all
	$(MAKE) $(SELECTOR) -C test all

.PHONY: install
install: all
	$(MAKE) $(SELECTOR) -C src DESTDIR="$(DESTDIR)" PREFIX="$(PREFIX)" INSTALL="$(INSTALL)" install
	$(MAKE) $(SELECTOR) -C man DESTDIR="$(DESTDIR)" PREFIX="$(PREFIX)" INSTALL="$(INSTALL)" install
	$(INSTALL) -dm0755 "$(DESTDIR)$(PREFIX)/share/doc/faketime/"
	$(INSTALL) -m0644 README "$(DESTDIR)$(PREFIX)/share/doc/faketime/README"
	$(INSTALL) -m0644 NEWS "$(DESTDIR)$(PREFIX)/share/doc/faketime/NEWS"

.PHONY: install-local
install-local:
	$(MAKE) install DESTDIR=

.PHONY: uninstall
uninstall:
	$(MAKE) $(SELECTOR) -C src DESTDIR="$(DESTDIR)" PREFIX="$(PREFIX)" uninstall
	$(MAKE) $(SELECTOR) -C man DESTDIR="$(DESTDIR)" PREFIX="$(PREFIX)" uninstall
	rm -f "$(DESTDIR)$(PREFIX)/share/doc/faketime/README"
	rm -f "$(DESTDIR)$(PREFIX)/share/doc/faketime/NEWS"
	rmdir "$(DESTDIR)$(PREFIX)/share/doc/faketime"

.PHONY: package
package:
	rm -rf "$(DESTDIR)" "$(DIST_DIR)"
	$(MAKE) install
	$(INSTALL) -dm0755 "$(DIST_DIR)"
	$(TAR) -C "$(DESTDIR)" -czf "$(PACKAGE)" .

.PHONY: build
build: package

.PHONY: push
push: build
	@test -n "$${GH_TOKEN:-$${GITHUB_TOKEN:-}}" || (echo "Set GH_TOKEN or GITHUB_TOKEN with repo write access" >&2; exit 1)
	@token="$${GH_TOKEN:-$${GITHUB_TOKEN:-}}"; \
	repo="$(GITHUB_REPOSITORY)"; \
	tag="$${GITHUB_TAG:-$(RELEASE_TAG)}"; \
	api="https://api.github.com/repos/$${repo}"; \
	upload_api="https://uploads.github.com/repos/$${repo}/releases"; \
	release_json=$$(curl -fsS \
		-H "Authorization: Bearer $${token}" \
		-H "Accept: application/vnd.github+json" \
		"$${api}/releases/tags/$${tag}" 2>/dev/null || true); \
	if [ -z "$${release_json}" ]; then \
		echo "Creating GitHub release $${repo}@$${tag}"; \
		release_json=$$(curl -fsS -X POST \
			-H "Authorization: Bearer $${token}" \
			-H "Accept: application/vnd.github+json" \
			"$${api}/releases" \
			-d "$$(printf '{"tag_name":"%s","name":"%s","body":"%s"}' "$${tag}" "$${tag}" "Built libfaketime artifacts for $${tag}")"); \
	else \
		echo "Using existing GitHub release $${repo}@$${tag}"; \
	fi; \
	release_id=$$(printf '%s' "$${release_json}" | $(PYTHON) -c 'import json,sys; print(json.load(sys.stdin)["id"])'); \
	for artifact in $(DIST_DIR)/*; do \
		name=$$(basename "$${artifact}"); \
		echo "Uploading $${name}"; \
		existing_asset_id=$$(curl -fsS \
				-H "Authorization: Bearer $${token}" \
				-H "Accept: application/vnd.github+json" \
				"$${api}/releases/$${release_id}/assets" | \
				ASSET_NAME="$${name}" $(PYTHON) -c 'import json,sys,os; name=os.environ["ASSET_NAME"]; print(next((str(a["id"]) for a in json.load(sys.stdin) if a["name"] == name), ""))'); \
		if [ -n "$${existing_asset_id}" ]; then \
			curl -fsS -X DELETE \
				-H "Authorization: Bearer $${token}" \
				-H "Accept: application/vnd.github+json" \
				"$${api}/releases/assets/$${existing_asset_id}" >/dev/null; \
		fi; \
		curl -fsS -X POST \
			-H "Authorization: Bearer $${token}" \
			-H "Accept: application/vnd.github+json" \
			-H "Content-Type: application/octet-stream" \
			--data-binary @"$${artifact}" \
			"$${upload_api}/$${release_id}/assets?name=$${name}" >/dev/null; \
	done

.PHONY: upload
upload: push

.PHONY: clean
clean:
	$(MAKE) $(SELECTOR) -C src clean
	$(MAKE) $(SELECTOR) -C test clean
	rm -rf build "$(DIST_DIR)"

.PHONY: distclean
distclean:
	$(MAKE) $(SELECTOR) -C src distclean
	$(MAKE) $(SELECTOR) -C test distclean
	rm -rf build "$(DIST_DIR)"
