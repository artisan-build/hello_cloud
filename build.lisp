;;;; Build script for the `app` executable. Run as
;;;; `sbcl --non-interactive --load build.lisp` at the repo root.
;;;;
;;;; 1. bootstrap Quicklisp into /qlocal (idempotent, so a warm container reuses it)
;;;; 2. load Hunchentoot
;;;; 3. load app.lisp -- which reads shared/page.html, shared/index-url.txt and
;;;;    og.png off disk AS IT LOADS, so they end up inside the heap image
;;;; 4. dump a single self-contained executable: SBCL runtime + that heap
(if (probe-file "/qlocal/setup.lisp")
    (load "/qlocal/setup.lisp")
    (progn
      (load "/tmp/quicklisp.lisp")
      (funcall (read-from-string "quicklisp-quickstart:install") :path "/qlocal/")))

(funcall (read-from-string "ql:quickload") :hunchentoot :silent t)
(load (compile-file "app.lisp"))

;;; Hunchentoot depends on cl+ssl, which dlopens libssl/libcrypto as it loads.
;;; SBCL remembers every dlopened object in the image and re-opens them all on
;;; start-up, so an image saved this way dies on Cloud's runtime image (Debian
;;; 12 without libssl3) before `main` ever runs -- with a backtrace about
;;; `libcrypto.so.3`, which looks nothing like a Lisp problem. Cloud terminates
;;; TLS upstream and this app never serves it, so the handles are dropped before
;;; the dump and the image starts with no foreign libraries at all.
(when (find-package :cffi)
  (dolist (lib (funcall (read-from-string "cffi:list-foreign-libraries")))
    (ignore-errors (funcall (read-from-string "cffi:close-foreign-library") lib))))
(dolist (so (copy-seq sb-sys:*shared-objects*))
  (ignore-errors
   (sb-alien:unload-shared-object (sb-alien::shared-object-pathname so))))
(format t "~&build: shared objects remembered in the image: ~S~%"
        sb-sys:*shared-objects*)

(sb-ext:disable-debugger)
(sb-ext:save-lisp-and-die
 "app"
 :executable t
 :toplevel (read-from-string "hello-cloud:main")
 ;; Compressed when this SBCL was built with core compression, plain otherwise.
 :compression (if (member :sb-core-compression *features*) t nil))
