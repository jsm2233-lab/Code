.PHONY: project open test clean

project:
	@command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen not found. Install with: brew install xcodegen"; exit 1; }
	xcodegen generate

open: project
	open StreetCollector.xcodeproj

test: project
	xcodebuild test \
		-project StreetCollector.xcodeproj \
		-scheme StreetCollector \
		-destination 'platform=iOS Simulator,name=iPhone 15'

clean:
	rm -rf StreetCollector.xcodeproj build DerivedData
