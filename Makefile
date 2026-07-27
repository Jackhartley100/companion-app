.PHONY: build test lint xcodeproj clean check devices device

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
	@test -f Signing.xcconfig || { \
		cp Signing.example.xcconfig Signing.xcconfig; \
		echo "Created Signing.xcconfig — set DEVELOPMENT_TEAM in it to run on a device."; }
	xcodegen generate
	@echo "Generated Companion.xcodeproj — open it with Xcode."

clean:
	swift package clean
	rm -rf .build Companion.xcodeproj

# Lists iPhones this Mac can see. The device must be unlocked and trusted.
devices:
	@xcrun devicectl list devices 2>/dev/null || echo "No devices found."

# Builds and installs on a connected iPhone. Requires DEVELOPMENT_TEAM in
# Signing.xcconfig — see README "Running on your iPhone".
device: xcodeproj
	xcodebuild -scheme Companion -destination 'generic/platform=iOS' \
		-allowProvisioningUpdates build
