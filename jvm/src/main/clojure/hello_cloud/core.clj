;; Two routes, a Ring handler served by http-kit. Laravel Cloud runs this
;; because the branch carries a go.mod at its root, so Cloud picked its Go
;; runtime and starts whatever executable it finds at ./app -- which here is a
;; self-extracting launcher wrapped around a jlink runtime image, the
;; dependency jars and this file.
(ns hello-cloud.core
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [org.httpkit.server :as http]
            [ring.util.response :as resp])
  (:import (java.io ByteArrayInputStream ByteArrayOutputStream)))

(def ^:private language "Clojure")
(def ^:private branch "clojure")
(def ^:private repo-url "https://github.com/artisan-build/hello_cloud")

;; Read off the classpath, which inside the bundle means out of the artifact
;; itself: Cloud's filesystem is ephemeral and holds none of this repo.
(defn- resource-bytes [name]
  (with-open [in (io/input-stream (io/resource name))
              out (ByteArrayOutputStream.)]
    (io/copy in out)
    (.toByteArray out)))

(def ^:private template (slurp (io/resource "page.html")))
(def ^:private index-url (str/trim (slurp (io/resource "index-url.txt"))))
(def ^:private og-png (resource-bytes "og.png"))

;; Fills the shared template's seven placeholders. Keep in step with main.go.
;; The absolute URLs come from the request's Host header with the scheme
;; hard-coded to https: Cloud terminates TLS upstream and then sends
;; X-Forwarded-Proto: http on an https request, so that header is unusable.
(defn- render [host]
  (let [base (str "https://" host)]
    (reduce (fn [acc [from to]] (str/replace acc from to))
            template
            [["{{LANGUAGE}}" language]
             ["{{BRANCH}}" branch]
             ["{{BRANCH_URL}}" (str repo-url "/tree/" branch)]
             ["{{OG_IMAGE}}" (str base "/og.png")]
             ["{{PAGE_URL}}" (str base "/")]
             ["{{INDEX_URL}}" index-url]
             ["{{EXTRA}}" ""]])))

(defn handler [request]
  (case (:uri request)
    "/" (-> (resp/response (render (get-in request [:headers "host"] "localhost")))
            (resp/content-type "text/html; charset=utf-8"))
    "/og.png" (-> (resp/response (ByteArrayInputStream. og-png))
                  (resp/content-type "image/png")
                  (resp/header "Cache-Control" "public, max-age=3600")
                  (resp/header "Content-Length" (str (alength og-png))))
    (-> (resp/not-found "not found")
        (resp/content-type "text/plain; charset=utf-8"))))

(defn -main [& _args]
  (let [port (Integer/parseInt (or (System/getenv "PORT") "3000"))]
    ;; "::" is the IPv6 wildcard, which on Linux is dual-stack: Cloud's
    ;; per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
    ;; network, so one socket has to answer both.
    (http/run-server handler {:ip "::" :port port :thread 4})
    (println (str "hello_cloud: hello from " language ", serving on [::]:" port))
    ;; run-server returns immediately; this process has nothing else to do.
    @(promise)))
