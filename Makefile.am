# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if DOC_ONLY
if ENABLE_DOC
  SUBDIRS = . doc
else
  SUBDIRS = .
endif
else
if ENABLE_DOC
  SUBDIRS = . src doc
else
  SUBDIRS = . src doc
endif
endif

@DX_RULES@

ACLOCAL_AMFLAGS = -I m4
EXTRA_DIST = \
  AUTHORS \
  contrib/coverage.sh \
  contrib/gnunet.tag \
  contrib/microhttpd.tag \
  Doxyfile
