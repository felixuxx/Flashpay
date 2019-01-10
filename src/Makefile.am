# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include
if HAVE_POSTGRESQL
  PQ_DIR = pq
endif
if HAVE_LIBCURL
  BANK_LIB = bank-lib
else
if HAVE_LIBGNURL
  BANK_LIB = bank-lib
endif
endif

if WALLET_ONLY
SUBDIRS = include util
else

pkgcfgdir = $(prefix)/share/taler/config.d/
pkgcfg_DATA = \
  taler.conf

EXTRA_DIST = \
  taler.conf

SUBDIRS = include util wire json $(PQ_DIR) $(BANK_LIB) wire-plugins exchangedb exchange exchange-tools auditordb auditor 
if HAVE_LIBCURL
 SUBDIRS += auditor-lib exchange-lib benchmark
else
if HAVE_LIBGNURL
 SUBDIRS += auditor-lib exchange-lib benchmark
endif
endif

endif
