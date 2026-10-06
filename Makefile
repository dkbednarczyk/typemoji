.PHONY: build test bundle run stop emoji format lint clean

build:
	swift build

test:
	swift test

bundle:
	scripts/bundle.sh

run: bundle stop
	open build/typemoji.app

stop:
	-pkill -x typemoji

# Regenerates Resources/emoji.json. Needs bun; not required for a normal build.
emoji:
	cd tools && bun install --frozen-lockfile && bun run generate

format:
	swift format --in-place --recursive Package.swift Sources Tests

lint:
	swift format lint --strict --recursive Package.swift Sources Tests

clean:
	rm -rf .build build
