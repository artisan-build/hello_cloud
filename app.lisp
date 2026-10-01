;;;; Hello from Common Lisp, on Laravel Cloud's Go runtime.
;;;;
;;;; Laravel Cloud runs this binary because the branch carries a `go.mod` at its
;;;; root, so the environment was detected as Go when it was created and Cloud
;;;; starts whatever executable the build command left at `./app`. No Go is
;;;; compiled for this branch; the build command downloads the binary that
;;;; GitHub Actions built from this commit.
;;;;
;;;; The web layer is Hunchentoot. `./app` is a single self-contained SBCL
;;;; executable: `save-lisp-and-die :executable t` prepends the SBCL runtime to
;;;; a heap image that already holds Hunchentoot, the shared HTML template and
;;;; the OG card, so the host needs no Lisp of its own and nothing is read from
;;;; disk at run time -- Cloud's filesystem is ephemeral.
;;;;
;;;; This file is LOADED at build time (see build.lisp): the three
;;;; `defparameter` forms below read the assets then, and what they read is
;;;; what ends up frozen in the image.

(defpackage #:hello-cloud
  (:use #:cl)
  (:export #:main))

(in-package #:hello-cloud)

(defparameter +language+ "Common Lisp")
(defparameter +branch+ "common-lisp")
(defparameter +repo-url+ "https://github.com/artisan-build/hello_cloud")

(defun slurp-text (path)
  (with-open-file (in path :direction :input :external-format :utf-8)
    (let ((s (make-string (file-length in))))
      (subseq s 0 (read-sequence s in)))))

(defun slurp-octets (path)
  (with-open-file (in path :direction :input :element-type '(unsigned-byte 8))
    (let ((v (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence v in)
      v)))

;;; Baked in at build time, not read at run time.
(defparameter *page-template* (slurp-text "shared/page.html"))
(defparameter *index-url* (string-trim '(#\Space #\Tab #\Return #\Newline)
                                       (slurp-text "shared/index-url.txt")))
(defparameter *og-png* (slurp-octets "og.png"))

(defun replace-all (string part replacement)
  (with-output-to-string (out)
    (loop with part-length = (length part)
          for start = 0 then (+ index part-length)
          for index = (search part string :start2 start)
          do (write-string string out :start start :end (or index (length string)))
             (when index (write-string replacement out))
          while index)))

;;; Fills the shared template's seven placeholders.
;;;
;;; og:image and og:url have to be absolute, so they are built from the
;;; request's Host header with a hard-coded https scheme: Cloud terminates TLS
;;; upstream and then sends `X-Forwarded-Proto: http` on an https request, so
;;; that header cannot be trusted.
(defun render-page (host)
  (let ((out *page-template*))
    (loop for (placeholder value) in
          `(("{{LANGUAGE}}" ,+language+)
            ("{{BRANCH_URL}}" ,(format nil "~A/tree/~A" +repo-url+ +branch+))
            ("{{BRANCH}}" ,+branch+)
            ("{{OG_IMAGE}}" ,(format nil "https://~A/og.png" host))
            ("{{PAGE_URL}}" ,(format nil "https://~A/" host))
            ("{{INDEX_URL}}" ,*index-url*)
            ("{{EXTRA}}" ""))
          do (setf out (replace-all out placeholder value)))
    out))

(defun request-host ()
  (or (hunchentoot:header-in* :host) "localhost"))

(hunchentoot:define-easy-handler (home :uri "/") ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (render-page (request-host)))

(hunchentoot:define-easy-handler (og-card :uri "/og.png") ()
  (setf (hunchentoot:content-type*) "image/png")
  (setf (hunchentoot:header-out "Cache-Control") "public, max-age=3600")
  *og-png*)

(defun listen-port ()
  (let ((raw (sb-ext:posix-getenv "PORT")))
    (or (and raw (ignore-errors (parse-integer raw :junk-allowed nil))) 3000)))

;;; Cloud's per-instance nginx reaches the app over IPv6, so the listener has to
;;; be the IPv6 wildcard. Hunchentoot cannot be asked for one: it hands its
;;; :address to usocket:socket-listen, and usocket 0.8.9's SBCL backend resolves
;;; every host through sb-bsd-sockets:get-host-by-name -- an AF_INET getaddrinfo,
;;; which answers "::" with EAI_FAMILY ("Address family for hostname not
;;; supported"). usocket's own socket-listen can build an inet6-socket, but only
;;; from a 16-octet address it never manages to produce on SBCL.
;;;
;;; So this acceptor makes the listening socket itself and hands Hunchentoot the
;;; usocket wrapper it expects. Everything above the socket -- request parsing,
;;; dispatch, the taskmaster -- is still Hunchentoot's. On Linux an IPv6
;;; wildcard socket is dual-stack, so IPV6_V6ONLY is deliberately left alone.
(defclass ipv6-acceptor (hunchentoot:easy-acceptor) ())

(defmethod hunchentoot:start-listening ((acceptor ipv6-acceptor))
  (let ((socket (make-instance 'sb-bsd-sockets:inet6-socket
                               :type :stream :protocol :tcp)))
    (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
    (sb-bsd-sockets:socket-bind
     socket
     (make-array 16 :element-type '(unsigned-byte 8) :initial-element 0)
     (hunchentoot:acceptor-port acceptor))
    (sb-bsd-sockets:socket-listen
     socket (hunchentoot::acceptor-listen-backlog acceptor))
    (setf (hunchentoot::acceptor-listen-socket acceptor)
          (usocket::make-stream-server-socket socket
                                              :element-type '(unsigned-byte 8)))
    (values)))

(defun main ()
  (let ((port (listen-port)))
    (hunchentoot:start
     (make-instance 'ipv6-acceptor
                    :port port
                    :access-log-destination nil
                    :message-log-destination *error-output*))
    (format t "hello_cloud: hello from ~A, serving on [::]:~D~%" +language+ port)
    (finish-output)
    (loop (sleep 3600))))
