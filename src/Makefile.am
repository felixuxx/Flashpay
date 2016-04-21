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

SUBDIRS = include util json $(PQ_DIR) $(BANK_LIB) wire exchangedb exchange exchange-tools
if HAVE_LIBCURL
 SUBDIRS += exchange-lib
else
if HAVE_LIBGNURL
 SUBDIRS += exchange-lib
endif
endif

endif
