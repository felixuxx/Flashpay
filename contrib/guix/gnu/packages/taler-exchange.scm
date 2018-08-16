;;; This file is part of GNU Taler.
;;; Copyright (C) 2018 GNUnet e.V.
;;;
;;; GNU Taler is free software: you can redistribute it and/or modify it
;;; under the terms of the GNU Affero General Public License as published
;;; by the Free Software Foundation, either version 3 of the License,
;;; or (at your option) any later version.
;;;
;;; GNU Taler is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Affero General Public License for more details.
;;;
;;; You should have received a copy of the GNU Affero General Public License
;;; along with this program.  If not, see <http://www.gnu.org/licenses/>.


(define-module (gnu packages taler-exchange)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (gnu packages)
  #:use-module (gnu packages file)
  #:use-module (gnu packages base)
  #:use-module (gnu packages texinfo)
  #:use-module (gnu packages aidc)
  #:use-module (gnu packages autotools)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages curl)
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages gnunet)
  #:use-module (gnu packages gnupg)
  #:use-module (gnu packages groff)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages gstreamer)
  #:use-module (gnu packages libidn)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages image)
  #:use-module (gnu packages libunistring)
  #:use-module (gnu packages maths)
  #:use-module (gnu packages multiprecision)
  #:use-module (gnu packages music)
  #:use-module (gnu packages ncurses)
  #:use-module (gnu packages package-management)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages pulseaudio)
  #:use-module (gnu packages python)
  #:use-module (gnu packages databases)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages video)
  #:use-module (gnu packages web)
  #:use-module (gnu packages xiph)
  #:use-module (gnu packages backup)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module ((guix build utils) #:prefix build-utils:)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix utils)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix build-system gnu))

(define (repeat f n)
  (if (= n 1)
      f
      (lambda (x) (f ((repeat f (- n 1)) x)))))

(define %source-dir ((repeat dirname 5) (current-filename)))

(define (git-output . args)
  "Execute 'git ARGS ...' command and return its output without trailing
newspace."
  (build-utils:with-directory-excursion %source-dir
    (let* ((port   (apply open-pipe* OPEN_READ "git" args))
           (output (read-string port)))
      (close-port port)
      (string-trim-right output #\newline))))

(define (current-git-version)
  (git-output "describe" "--tags"))

(define (git-sources)
  (local-file %source-dir
	      #:recursive? #t
	      #:select? (git-predicate %source-dir)))

(define-public taler-exchange
  (package
   (name "taler-exchange")
   (version (current-git-version))
   (source (git-sources))
   (build-system gnu-build-system)
   (inputs
    `(("gnurl" ,gnurl)
      ("libgcrypt" ,libgcrypt)
      ("libmicrohttpd" ,libmicrohttpd)
      ("libltdl" ,libltdl)
      ("jansson" ,jansson)
      ("gnunet" ,gnunet)
      ("zlib" ,zlib)
      ("perl" ,perl)
      ("postgresql" ,postgresql)))
   (native-inputs
    `(("pkg-config" ,pkg-config)
      ("autoconf" ,autoconf)
      ("automake" ,automake)
      ("gnu-gettext" ,gnu-gettext)
      ("which" ,which)
      ("texinfo" ,texinfo-5) ; Debian stable: 5.2
      ("libtool" ,libtool)))
   (arguments
    '(#:parallel-tests? #f
      #:tests? #f
      #:phases
      (modify-phases %standard-phases
        (add-after 'unpack 'patch-bin-sh
          (lambda _
            (for-each (lambda (f) (chmod f #o755))
                      (find-files "po" ""))
            #t))
        (add-after 'install 'check
          (assoc-ref %standard-phases 'check))
        (delete 'check))))
   (synopsis "GNU Taler exchange")
   (description "GNU Taler is an electronic payment system")
   (license license:agpl3+)
   (home-page "https://taler.net/")))
