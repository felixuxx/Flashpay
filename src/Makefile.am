# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include
if HAVE_POSTGRESQL
  PQ_DIR = pq
endif
SUBDIRS = include util $(PQ_DIR) mintdb mint mint-tools 
if HAVE_LIBCURL
 SUBDIRS += mint-lib
endif
