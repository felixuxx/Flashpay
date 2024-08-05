# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if DOC_ONLY
if ENABLE_DOC
  SUBDIRS = . contrib doc po
else
  SUBDIRS = . contrib po
endif
else
if ENABLE_DOC
  SUBDIRS = . contrib src doc po
else
  SUBDIRS = . contrib src po
endif
endif

@DX_RULES@

TESTS = contrib/check-prebuilt

ACLOCAL_AMFLAGS = -I m4
EXTRA_DIST = build-aux/config.rpath   \
  AUTHORS \
  README.1st
