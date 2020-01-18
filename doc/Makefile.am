# This Makefile.am is in the public domain

SUBDIRS = . doxygen

man_MANS = \
  prebuilt/man/taler-auditor.1 \
  prebuilt/man/taler-auditor-exchange.1 \
  prebuilt/man/taler-auditor-sign.1 \
  prebuilt/man/taler-bank-transfer.1 \
  prebuilt/man/taler-config-generate.1 \
  prebuilt/man/taler-exchange-aggregator.1 \
  prebuilt/man/taler-exchange-dbinit.1 \
  prebuilt/man/taler-exchange-httpd.1 \
  prebuilt/man/taler-exchange-keyup.1 \
  prebuilt/man/taler-exchange-keycheck.1 \
  prebuilt/man/taler-exchange-wire.1 \
  prebuilt/man/taler-exchange-wirewatch.1 \
  prebuilt/man/taler-exchange-benchmark.1 \
  prebuilt/man/taler.conf.5

info_TEXINFOS = \
  prebuilt/texinfo/taler-exchange.texi \
  prebuilt/texinfo/taler-bank.texi \
  prebuilt/texinfo/onboarding.texi

EXTRA_DIST = \
  $(man_MANS) \
  doxygen/taler.doxy \
  $(info_TEXINFOS) \
  prebuilt/texinfo/onboarding-figures/exchange-db.png \
  prebuilt/texinfo/onboarding-figures/arch-api.png \
  prebuilt/texinfo/taler-exchange-figures/exchange-db.png \
  prebuilt/texinfo/taler-bank-figures/exchange-db.png \
  prebuilt/texinfo/taler-bank-figures/arch-api.png
