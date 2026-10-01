#lang racket/base
;; Hello from Racket, on Laravel Cloud's Go runtime.
;;
;; Laravel Cloud runs this binary because the branch carries a `go.mod` at its
;; root, so the environment was detected as Go when it was created and Cloud
;; starts whatever executable the build command left at `./app`. The build
;; command for this environment never compiles any Go: it downloads the binary
;; GitHub Actions built from this commit.
;;
;; The shared HTML template, the index URL and the OG card are read at EXPAND
;; time by the `embed-bytes` macro below and end up as literals inside the
;; `raco exe` image, so nothing on Cloud's ephemeral filesystem matters once
;; the process is up.

(require (for-syntax racket/base racket/file)
         net/url
         racket/string
         web-server/http
         web-server/servlet-env)

(define-syntax (embed-bytes stx)
  (syntax-case stx ()
    [(_ path)
     (with-syntax ([blob (file->bytes (syntax->datum #'path))])
       #'(quote blob))]))

(define language "Racket")
(define branch "racket")
(define repo-url "https://github.com/artisan-build/hello_cloud")

;; The shared template from `main`. Do not fork it per language.
(define template (bytes->string/utf-8 (embed-bytes "shared/page.html")))
;; The index URL, also shared from `main`.
(define index-url (string-trim (bytes->string/utf-8 (embed-bytes "shared/index-url.txt"))))
;; Written by `go run ./tools/ogen -language Racket -out og.png` before the build.
(define og-png (embed-bytes "og.png"))

;; Fills the shared template's seven placeholders.
;;
;; og:image and og:url have to be absolute, so they are built from the request's
;; Host header with a hard-coded https scheme: Cloud terminates TLS upstream and
;; then sends `X-Forwarded-Proto: http` on an https request, so that header
;; cannot be trusted.
(define (render host)
  (define base (string-append "https://" host))
  (for/fold ([page template])
            ([pair (in-list (list (cons "{{LANGUAGE}}" language)
                                  (cons "{{BRANCH}}" branch)
                                  (cons "{{BRANCH_URL}}" (string-append repo-url "/tree/" branch))
                                  (cons "{{OG_IMAGE}}" (string-append base "/og.png"))
                                  (cons "{{PAGE_URL}}" (string-append base "/"))
                                  (cons "{{INDEX_URL}}" index-url)
                                  (cons "{{EXTRA}}" "")))])
    (string-replace page (car pair) (cdr pair))))

(define (host-of req)
  (define h (headers-assq* #"host" (request-headers/raw req)))
  (if h (bytes->string/utf-8 (header-value h)) "localhost"))

(define (og-png? req)
  (equal? (map path/param-path (url-path (request-uri req))) '("og.png")))

(define (start req)
  (if (og-png? req)
      (response/full 200 #"OK" (current-seconds) #"image/png"
                     (list (make-header #"Cache-Control" #"public, max-age=3600"))
                     (list og-png))
      (response/full 200 #"OK" (current-seconds) #"text/html; charset=utf-8"
                     '()
                     (list (string->bytes/utf-8 (render (host-of req)))))))

(define port
  (let ([p (getenv "PORT")])
    (or (and p (string->number p)) 3000)))

(printf "hello_cloud: hello from ~a, serving on port ~a\n" language port)
(flush-output)

;; #:listen-ip #f makes the listener accept on every address of the machine,
;; which is what Cloud's per-instance nginx needs: it proxies to $PORT over an
;; IPv6-only network.
(serve/servlet start
               #:port port
               #:listen-ip #f
               #:servlet-path "/"
               #:servlet-regexp #rx""
               #:command-line? #t
               #:banner? #f)
