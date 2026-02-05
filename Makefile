PREFIX ?= /usr/share/alsa
STAGING ?= /usr/share/libretech-alsa-ucm-conf

install:
	mkdir -p $(DESTDIR)$(PREFIX)/init $(DESTDIR)$(PREFIX)/ucm $(DESTDIR)$(PREFIX)/ucm2
	mkdir -p $(DESTDIR)$(STAGING)/ucm2/Amlogic
	cp -r init/* $(DESTDIR)$(PREFIX)/init/
	cp -r ucm/* $(DESTDIR)$(PREFIX)/ucm/
	cp -r ucm2/* $(DESTDIR)$(PREFIX)/ucm2/
	# Move p241 to staging for conditional install via postinst
	rm -rf $(DESTDIR)$(PREFIX)/ucm2/Amlogic/p241
	cp -r ucm2/Amlogic/p241 $(DESTDIR)$(STAGING)/ucm2/Amlogic/
