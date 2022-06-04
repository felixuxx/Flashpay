FILES = taler_signatures.h

gana = ../gana


all: check $(FILES)
check: registry.rec
	recfix --check registry.rec
registry.rec:
	ln -s $(gana)/gnunet-signatures/registry.rec
distclean:
	rm -f *.tmp
clean:
	rm -f $(FILES) *.tmp registry.rec
taler_signatures.h.tmp: registry.rec h.template
	$(gana)/format.sh h.template 'Package = "GNU Taler"' < registry.rec > $@

taler_signatures.h: h.header taler_signatures.h.tmp h.footer
	cat h.header taler_signatures.h.tmp h.footer > $@

.PHONY: check clean distclean
