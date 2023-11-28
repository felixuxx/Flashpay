#!/bin/bash
set -exuo pipefail

job_dir=$(dirname "${BASH_SOURCE[0]}")

codespell -I "${job_dir}"/dictionary.txt -S "*.bib,*.bst,*.cls,*.json,*.png,*.svg,*.wav,*.gz,*/templating/test?/**,**/auditor/*.sql,**/templating/mustach**,*.fees,*key,*.tag,*.info,*.latexmkrc,*.ecc,*.jpg,*.zkey,*.sqlite,*/contrib/hellos/**,*/vpn/tests/**,**/valgrind.h,*.priv,*.file,*.tgz,*.woff,*.gif,*.odt,*.fee,*.deflate,*.dat,*.jpeg,*.eps,*.odg,*/m4/ax_lib_postgresql.m4,*/m4/libgcrypt.m4,*.rpath,config.status,ABOUT-NLS,*/doc/texinfo.tex,*.PNG,*.??.json,*.docx,*.ods,*.doc,*.docx,*.xcf,*.xlsx,*.ecc,*.ttf,*.woff2,*.eot,*.ttf,*.eot,*.mp4,*.pptx,*.epgz,*.min.js,**/*.map,**/fonts/**,*.pack.js,*.po,*.bbl,*/afl-tests/*,*/.git/**,*.pdf,*.epub,**/signing-key.asc,**/pnpm-lock.yaml,**/*.svg,**/*.cls,**/rfc.bib,**/*.bst,*/cbdc-es.tex,*/cbdc-it.tex,**/ExchangeSelection/example.ts,*/testcurl/test_tricky.c,*/i18n/strings.ts,*/src/anastasis-data.ts,**/doc/flows/main.de.tex"
