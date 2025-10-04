# Makefile
# Simple Makefile helpers for Noema

.PHONY: spm-refresh spm-reset resolve

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