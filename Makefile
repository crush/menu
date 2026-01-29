build:
	swift build -c release

install: build
	rm -rf /Applications/Menu.app
	mkdir -p /Applications/Menu.app/Contents/MacOS
	cp .build/release/menu /Applications/Menu.app/Contents/MacOS/
	cp Info.plist /Applications/Menu.app/Contents/

run: install
	open /Applications/Menu.app

uninstall:
	pkill -9 menu || true
	rm -rf /Applications/Menu.app

clean:
	rm -rf .build
