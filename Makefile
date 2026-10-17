.PHONY: build build-debug app dmg clean run lint test inject-secret clean-secret relay-build relay-test relay-run

# Build universal release binary (arm64 + x86_64)
# CLIP_LICENSE_SECRET env var (if set) is injected at build time; without it
# the app is built fail-closed (no license verification possible).
build: inject-secret
	swift build -c release --arch arm64 --arch x86_64

# Debug build for development
build-debug: inject-secret
	swift build -c debug

# Assemble .app bundle (universal release)
app: build
	bash Scripts/build-app.sh release universal

# Build .app and package as DMG
dmg: app
	bash Scripts/create-dmg.sh

# Clean build artifacts
clean:
	rm -rf .build build

# Run in debug mode (no .app bundle — for development only)
run: inject-secret
	swift run --arch arm64

# SwiftLint (install with: brew install swiftlint)
lint:
	swiftlint --strict

# Unit tests (Swift core + golden serial roundtrip with the Python script)
test: inject-secret
	swift test

# License secret: inject $CLIP_LICENSE_SECRET into SecretConfig.swift
inject-secret:
	bash Scripts/inject-secret.sh

# License secret: reset SecretConfig.swift to the nil template
clean-secret:
	bash Scripts/inject-secret.sh --reset

# Relay service (TypeScript, zero runtime deps)
relay-build:
	cd relay && npm install && npm run build

relay-test:
	cd relay && npm install && npm test

relay-run:
	cd relay && npm run build && npm start
