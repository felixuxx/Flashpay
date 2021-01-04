# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

SUBDIRS = . contrib src doc

BUILT_SOURCES = src/include/taler_error_codes.h

src/include/taler_error_codes.h: contrib/gana/gnu-taler-error-codes/registry.rec
	contrib/gana-update.sh

@DX_RULES@

ACLOCAL_AMFLAGS = -I m4
EXTRA_DIST =  \
  AUTHORS
