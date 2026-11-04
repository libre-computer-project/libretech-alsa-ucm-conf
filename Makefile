PREFIX ?= /usr/share/alsa

# The whole tree is the system UCM: upstream alsa-ucm-conf (the base this fork
# is rebased on), the compat pins (compat/), and the Libre Computer profiles.
install:
	mkdir -p $(DESTDIR)$(PREFIX)/init $(DESTDIR)$(PREFIX)/ucm $(DESTDIR)$(PREFIX)/ucm2
	cp -r init/* $(DESTDIR)$(PREFIX)/init/
	cp -r ucm/* $(DESTDIR)$(PREFIX)/ucm/
	cp -r ucm2/* $(DESTDIR)$(PREFIX)/ucm2/
	# as Debian's alsa-ucm-conf packaging does: no VCS placeholder, no exec bits
	rm -f $(DESTDIR)$(PREFIX)/ucm2/conf.virt.d/.gitignore
	find $(DESTDIR)$(PREFIX)/ucm $(DESTDIR)$(PREFIX)/ucm2 -type f -exec chmod 0644 {} +
