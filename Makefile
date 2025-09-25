# Makefile
# Helper targets for Noema development tasks

PROJECT = Noema.xcodeproj
SCHEME = Noema
SIM_DEST = platform=iOS\ Simulator,name=iPhone\ 15
GENERIC_SIM = generic/platform=iOS\ Simulator
GENERIC_IOS = generic/platform=iOS
ARCHIVE_PATH = build/Noema.xcarchive

.PHONY: spm-refresh spm-reset resolve build build-debug build-release test analyze archive ci

# Remove .build cache and regenerate pins/resolved
spm-refresh:
	rm -rf .build
	rm -f Package.resolved
	swift package resolve

# Clean SPM artifacts and derived data (Xcode)
spm-reset:
	rm -rf .build
	rm -f Package.resolved
	rm -rf ~/Library/Developer/Xcode/DerivedData/*
	swift package reset

resolve:
	swift package resolve

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug clean build -destination '$(GENERIC_SIM)'
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release build -destination '$(GENERIC_IOS)'

build-debug:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug clean build -destination '$(GENERIC_SIM)'

build-release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release build -destination '$(GENERIC_IOS)'

test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(SIM_DEST)'

analyze:
	xcodebuild analyze -project $(PROJECT) -scheme $(SCHEME) -destination '$(GENERIC_SIM)'

archive:
	xcodebuild archive -project $(PROJECT) -scheme $(SCHEME) -destination '$(GENERIC_IOS)' -archivePath $(ARCHIVE_PATH)

ci:
	$(MAKE) build
	$(MAKE) test
	$(MAKE) analyze
	$(MAKE) archive
