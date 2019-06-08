# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

pkgcfgdir = $(prefix)/share/taler/config.d/

lib_LTLIBRARIES = \
  libtalerwire.la

libtalerwire_la_SOURCES = \
  payto.c \
  wire.c \
  wire_helper.c
libtalerwire_la_LIBADD = \
  -lgnunetutil \
  $(XLIB)
libtalerwire_la_LDFLAGS = \
  -version-info 1:0:0 \
  -export-dynamic -no-undefined
