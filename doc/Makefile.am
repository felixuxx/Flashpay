# This Makefile.am is in the public domain

SUBDIRS = .

man_MANS = \
  taler-auditor.1 \
  taler-auditor-sign.1 \
  taler-config-generate.1 \
  taler-exchange-aggregator.1 \
  taler-exchange-dbinit.1 \
  taler-exchange-httpd.1 \
  taler-exchange-keyup.1 \
  taler-exchange-keycheck.1 \
  taler-exchange-reservemod.1 \
  taler-exchange-wire.1 \
  taler-exchange-wirewatch.1 \
  taler.conf.5

AM_MAKEINFOHTMLFLAGS = --no-split --css-ref=docstyle.css --css-ref=brown-paper.css

DISTCLEANFILES = \
  taler-exchange.cps \
  taler-exchange.dvi

info_TEXINFOS = \
  taler-exchange.texi
extra_TEXINFOS = \
  fdl-1.3.texi \
  agpl.texi \
  syntax.texi
EXTRA_DIST = \
  coding-style.txt \
  $(man_MANS) \
  $(extra_TEXINFOS) \
  docstyle.css \
  brown-paper.css

