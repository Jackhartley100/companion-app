.PHONY: build test lint xcodeproj clean check

# Builds and tests the domain and UI packages for the host platform.
# This is what runs without Xcode installed — see README.md.
build:
	swift build

test:
	swift test

# Fails on any warning, so "no warnings" stays true rather than aspirational.
check:
	@echo "Building with warnings treated as errors…"
	@swift build -Xswiftc -warnings-as-errors
	@echo "Running tests…"
	@swift test
	@echo "OK"

# Generates Companion.xcodeproj for the iOS app target.
# Requires: brew install xcodegen
xcodeproj:
	@command -v xcodegen >/dev/null 2>&1 || { \
		echo "xcodegen is not installed. Run: brew install xcodegen"; exit 1; }
	xcodegen generate
	@echo "Generated Companion.xcodeproj — open it with Xcode."

clean:
	swift package clean
	rm -rf .build Companion.xcodeproj
