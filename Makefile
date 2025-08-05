PREFIX ?= /usr/share/alsa

install:
	mkdir -p $(DESTDIR)$(PREFIX)/init $(DESTDIR)$(PREFIX)/ucm $(DESTDIR)$(PREFIX)/ucm2
	cp -r init/* $(DESTDIR)$(PREFIX)/init/
	cp -r ucm/* $(DESTDIR)$(PREFIX)/ucm/
	cp -r ucm2/* $(DESTDIR)$(PREFIX)/ucm2/
