# This Makefile.am is in the public domain

SUBDIRS = . doxygen

AM_MAKEINFOHTMLFLAGS = $(TEXINFO_HTMLFLAGS)

infoimagedir = $(infodir)/images

man_MANS = \
  prebuilt/man/taler.conf.5            \
  prebuilt/man/taler-config.1            \
  prebuilt/man/taler-aggregator-benchmark.1   \
  prebuilt/man/taler-auditor.1             \
  prebuilt/man/taler-auditor-dbinit.1      \
  prebuilt/man/taler-auditor-httpd.1       \
  prebuilt/man/taler-auditor-offline.1    \
  prebuilt/man/taler-auditor-sign.1       \
  prebuilt/man/taler-auditor-sync.1       \
  prebuilt/man/taler-bank-benchmark.1   \
  prebuilt/man/taler-exchange-aggregator.1 \
  prebuilt/man/taler-exchange-benchmark.1  \
  prebuilt/man/taler-exchange-closer.1     \
  prebuilt/man/taler-exchange-dbconfig.1  \
  prebuilt/man/taler-exchange-dbinit.1  \
  prebuilt/man/taler-exchange-drain.1  \
  prebuilt/man/taler-exchange-expire.1  \
  prebuilt/man/taler-exchange-httpd.1       \
  prebuilt/man/taler-exchange-kyc-aml-pep-trigger.1 \
  prebuilt/man/taler-exchange-kyc-tester.1       \
  prebuilt/man/taler-exchange-offline.1    \
  prebuilt/man/taler-exchange-router.1\
  prebuilt/man/taler-exchange-secmod-cs.1\
  prebuilt/man/taler-exchange-secmod-eddsa.1\
  prebuilt/man/taler-exchange-secmod-rsa.1 \
  prebuilt/man/taler-exchange-transfer.1\
  prebuilt/man/taler-exchange-wire-gateway-client.1\
  prebuilt/man/taler-exchange-wirewatch.1   \
  prebuilt/man/taler-fakebank-run.1   \
  prebuilt/man/taler-helper-auditor-aggregation.1 \
  prebuilt/man/taler-helper-auditor-coins.1\
  prebuilt/man/taler-helper-auditor-deposits.1\
  prebuilt/man/taler-helper-auditor-purses.1\
  prebuilt/man/taler-helper-auditor-reserves.1\
  prebuilt/man/taler-helper-auditor-wire.1 \
  prebuilt/man/taler-terms-generator.1 \
  prebuilt/man/taler-unified-setup.1

info_TEXINFOS = \
  prebuilt/texinfo/taler-auditor.texi \
  prebuilt/texinfo/taler-developer-manual.texi \
  prebuilt/texinfo/taler-exchange.texi


EXTRA_DIST = \
  $(man_MANS) \
  doxygen/taler.doxy \
  $(info_TEXINFOS) \
  prebuilt/texinfo/taler-auditor-figures/auditor-db.png \
  prebuilt/texinfo/taler-auditor-figures/replication.png  \
  prebuilt/texinfo/taler-exchange-figures/kyc-process.png \
  prebuilt/texinfo/taler-exchange-figures/exchange-db.png
