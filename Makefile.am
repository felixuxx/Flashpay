# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include
SUBDIRS = src doc
ACLOCAL_AMFLAGS = -I m4

app:
	mkdir -p $(PACKAGE)-$(VERSION)-app
	tar cf - configure.ac AUTHORS README doc/*.1 doc/*.5 doc/Makefile.am Makefile.am `find src/ -name "*.c" -o -name "*.h" -o -name Makefile.am` | (cd $(PACKAGE)-$(VERSION)-app ; tar xf -)
	tar cf $(PACKAGE)-$(VERSION)-app.tgz $(PACKAGE)-$(VERSION)-app
	rm -rf $(PACKAGE)-$(VERSION)-app
