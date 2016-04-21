TEMPORARY_FOLDER?=/tmp/Cake.dst
PREFIX?=/usr/local
BUILD_TOOL?=xcodebuild

XCODEFLAGS=-project 'Cake.xcodeproj' -scheme 'cake' -configuration Release DSTROOT=$(TEMPORARY_FOLDER)

BUILT_BUNDLE=$(TEMPORARY_FOLDER)/Applications/cake.app
EXECUTABLE=$(BUILT_BUNDLE)/Contents/MacOS/cake
FRAMEWORKS=$(BUILT_BUNDLE)/Contents/Frameworks

FRAMEWORKS_FOLDER=/Library/Frameworks/Cake
BINARIES_FOLDER=/usr/local/bin

OUTPUT_PACKAGE=Cake.pkg

VERSION_STRING=$(shell agvtool what-marketing-version -terse1)

clean:
	rm -f "$(OUTPUT_PACKAGE)"
	rm -rf "$(TEMPORARY_FOLDER)"
	$(BUILD_TOOL) $(XCODEFLAGS) clean

installables: clean 
	$(BUILD_TOOL) $(XCODEFLAGS) install

	mkdir -p "$(TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)" "$(TEMPORARY_FOLDER)$(BINARIES_FOLDER)"
	
	mkdir -p "$(TEMPORARY_FOLDER)/cake"
	cp "$(EXECUTABLE)" "$(TEMPORARY_FOLDER)/cake"
	cp $(FRAMEWORKS)/*.dylib "$(TEMPORARY_FOLDER)/cake"
	cp -r $(FRAMEWORKS)/*.framework "$(TEMPORARY_FOLDER)/cake"
	zip -r "./cake.zip" "$(TEMPORARY_FOLDER)/cake" 
	rm -rf "$(TEMPORARY_FOLDER)/cake"
	mv -f "$(EXECUTABLE)" "$(TEMPORARY_FOLDER)$(BINARIES_FOLDER)/cake"
	mv "$(FRAMEWORKS)" "$(TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)"
	install_name_tool -rpath "@executable_path" "$(FRAMEWORKS_FOLDER)/Frameworks" "$(TEMPORARY_FOLDER)$(BINARIES_FOLDER)/cake"
	rm -rf "$(BUILT_BUNDLE)"

package: installables
	pkgbuild \
		--identifier "com.prolificinteractive.cake" \
		--install-location "/" \
		--root "$(TEMPORARY_FOLDER)" \
		--version "$(VERSION_STRING)" \
		"$(OUTPUT_PACKAGE)"
