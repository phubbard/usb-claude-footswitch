APP_NAME = Claude Footswitch
APP      = build/$(APP_NAME).app
BUNDLE_ID = net.phfactor.ClaudeFootswitch

.PHONY: build icon run install uninstall clean reset-tcc debug

## Render the app icon into Resources/AppIcon.icns
icon:
	@bash scripts/make-icon.sh

## Build the .app bundle (release, ad-hoc signed)
build:
	@bash scripts/make-app.sh

## Build, then launch the menu-bar app
run: build
	@open "$(APP)"

## Copy the app into /Applications and launch it from there
install: build
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R "$(APP)" "/Applications/$(APP_NAME).app"
	@echo "✓ Installed to /Applications/$(APP_NAME).app"
	@open "/Applications/$(APP_NAME).app"

uninstall:
	@rm -rf "/Applications/$(APP_NAME).app"
	@echo "✓ Removed /Applications/$(APP_NAME).app"

## Run the bare binary in the terminal with live logs (TCC identity differs from the bundle)
debug:
	@swift build
	@.build/debug/ClaudeFootswitch

## Forget granted permissions for this app (useful after re-signing during development)
reset-tcc:
	-@tccutil reset ListenEvent $(BUNDLE_ID)
	-@tccutil reset Accessibility $(BUNDLE_ID)
	@echo "✓ Reset Input Monitoring + Accessibility grants for $(BUNDLE_ID)"

clean:
	@rm -rf .build build
	@echo "✓ Cleaned"
