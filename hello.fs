\ hello.fs -- the whole of hello_cloud's Forth branch.
\
\ Two routes, served straight off a BSD socket: "/" is the shared template with
\ its seven placeholders filled, "/og.png" is the generated card. The response
\ logic is Forth; the only C is gforth's own socket glue (unix/socket.fs), and
\ that is compiled once at BUILD time and travels in the bundle, so nothing is
\ compiled on Cloud -- debian:12 has no compiler.
\
\ gforth 0.7.3's create-server is PF_INET only, and Laravel Cloud's per-instance
\ nginx reaches the app over an IPv6-only network, so the listener below builds
\ its own sockaddr_in6 and binds the dual-stack wildcard instead.

require unix/socket.fs

\ ---------------------------------------------------------------- the listener

10 Constant PF_INET6
28 Constant /sockaddr_in6   \ family 2, port 2, flowinfo 4, addr 16, scope 4

Create sa6  /sockaddr_in6 allot

: create-server6 ( port -- lsocket )
    sa6 /sockaddr_in6 erase
    PF_INET6 sa6 w!             \ sin6_family
    htons sa6 2 + w!            \ sin6_port, network byte order
    \ sin6_addr stays all zeroes -- that is in6addr_any -- and Linux leaves
    \ IPV6_V6ONLY off, so this one socket answers v6 and v4 alike.
    PF_INET6 SOCK_STREAM 0 socket
    dup 0< abort" no free socket" >r
    r@ sa6 /sockaddr_in6 bind 0= IF  r>  EXIT  THEN
    r> drop true abort" bind [::] failed" ;

\ ------------------------------------------------------------- small utilities

: trim-right ( c-addr u -- c-addr u' )
    BEGIN  dup 0> IF  2dup + 1- c@ bl 1+ u<  ELSE  false  THEN
    WHILE  1-  REPEAT ;

\ A string accumulator with a movable destination: used for the two absolute
\ URLs, which cannot be known until a request arrives and names its Host.
Variable acc-a   Variable acc-u
: acc! ( c-addr -- ) acc-a !  0 acc-u ! ;
: acc+ ( c-addr u -- ) acc-a @ acc-u @ + swap dup >r move  r> acc-u +! ;
: acc@ ( -- c-addr u ) acc-a @ acc-u @ ;

\ ------------------------------------------------------------------- the pages

2Variable page-template
2Variable og-png
2Variable index-url

2Variable v-language
2Variable v-branch
2Variable v-branch-url
2Variable v-og-image
2Variable v-page-url

$100 Constant /url
Create page-url$  /url allot
Create og-url$    /url allot

\ The response body is built here: the page is about 5 KB, the card about 50 KB.
$20000 Constant /out
Create outbuf  /out allot
Variable outlen
: out-reset ( -- ) 0 outlen ! ;
: out@      ( -- c-addr u ) outbuf outlen @ ;
: out+      ( c-addr u -- )
    dup outlen @ + /out u> abort" response buffer overflow"
    outbuf outlen @ + swap dup >r move  r> outlen +! ;

\ The template walk keeps its cursor in plain variables: a BEGIN loop is not the
\ place to be juggling four cells of string on the stack.
Variable src-a  Variable src-u
Variable m-a    Variable m-u
: src!   ( c-addr u -- ) src-u ! src-a ! ;
: src@   ( -- c-addr u ) src-a @ src-u @ ;
: match! ( c-addr u -- ) m-u ! m-a ! ;
: prefix ( -- c-addr u ) src-a @  m-a @ over - ;      \ the text before a match
: skip2  ( -- )          m-a @ 2 + m-u @ 2 - src! ;   \ step over "{{" or "}}"

: key>val ( c-addr u -- c-addr2 u2 )
    2dup s" LANGUAGE"   compare 0= IF 2drop v-language   2@ EXIT THEN
    2dup s" BRANCH_URL" compare 0= IF 2drop v-branch-url 2@ EXIT THEN
    2dup s" BRANCH"     compare 0= IF 2drop v-branch     2@ EXIT THEN
    2dup s" OG_IMAGE"   compare 0= IF 2drop v-og-image   2@ EXIT THEN
    2dup s" PAGE_URL"   compare 0= IF 2drop v-page-url   2@ EXIT THEN
    2dup s" INDEX_URL"  compare 0= IF 2drop index-url    2@ EXIT THEN
    \ {{EXTRA}} is the index's own section; a language page leaves it empty.
    2drop s" " ;

: render ( c-addr u -- )        \ fill outbuf with the template, placeholders in
    out-reset src!
    BEGIN  src@ s" {{" search  WHILE
        match!  prefix out+  skip2
        src@ s" }}" search 0= abort" unterminated {{ in the template"
        match!  prefix key>val out+  skip2
    REPEAT
    out+ ;                      \ whatever follows the last placeholder

\ ------------------------------------------------------------------ the server

$2000 Constant /req
Create reqbuf  /req allot
Create lowbuf  /req allot
Variable reqlen

$400 Constant /hdr
Create hdrbuf  /hdr allot
Variable hdrlen
: hdr-reset ( -- ) 0 hdrlen ! ;
: hdr@      ( -- c-addr u ) hdrbuf hdrlen @ ;
: h+        ( c-addr u -- )
    dup hdrlen @ + /hdr u> abort" header buffer overflow"
    hdrbuf hdrlen @ + swap dup >r move  r> hdrlen +! ;
: h#        ( u -- ) 0 <# #s #> h+ ;

: lowercase-request ( -- )      \ a case-folded copy, for header matching
    reqlen @ 0 ?DO
        reqbuf I + c@
        dup [char] A >= over [char] Z <= and IF  $20 +  THEN
        lowbuf I + c!
    LOOP ;

\ Every absolute URL on the page is built from the request's Host header with
\ the scheme hard-coded to https: Cloud terminates TLS upstream and then sends
\ X-Forwarded-Proto: http on an https request, so that header cannot be used.
: request-host ( -- c-addr u )
    lowbuf reqlen @ s\" \r\nhost:" search 0= IF  2drop s" localhost" EXIT  THEN
    7 /string
    BEGIN  dup 0> IF  over c@ bl =  ELSE  false  THEN  WHILE  1 /string  REPEAT
    2dup 13 scan nip - ;

: request-path ( -- c-addr u )
    reqbuf reqlen @ 2dup 13 scan nip -          \ the request line
    bl scan dup 0= IF  2drop s" /" EXIT  THEN   \ skip the method
    1 /string
    2dup bl scan nip -                          \ up to the next space
    2dup [char] ? scan nip - ;                  \ and without any query string

: set-urls ( -- )
    page-url$ acc!  s" https://" acc+  request-host acc+  s" /" acc+
    acc@ v-page-url 2!
    og-url$   acc!  s" https://" acc+  request-host acc+  s" /og.png" acc+
    acc@ v-og-image 2! ;

2Variable r-body
2Variable r-ctype
Variable  r-cache

\ Sockets are handled as raw file descriptors throughout. gforth's own
\ accept-socket wraps the descriptor in a stdio FILE* that nothing ever
\ fcloses, and its read-socket spins for two seconds on a non-blocking
\ descriptor; accept(2), recv(2) and send(2) straight off socket.fs's C
\ bindings are both smaller and better behaved.
Create alen  /sockaddr_in6 ,

: accept-fd ( lsocket -- fd )
    /sockaddr_in6 alen !
    sa6 alen accept()  dup 0< abort" accept failed" ;

: close-fd ( fd -- ) closesocket drop ;

: send-all ( c-addr u fd -- )       \ send(2) may be short; keep going
    >r
    BEGIN  dup 0>  WHILE
        2dup r@ -rot 0 send         \ send(fd, c-addr, u, 0) -- n
        dup 0< IF  drop 2drop r> drop EXIT  THEN
        dup 0= IF  drop 2drop r> drop EXIT  THEN
        /string
    REPEAT
    2drop r> drop ;

: recv-request ( fd -- )
    reqbuf /req 0 recv  0 max  reqlen ! ;

: respond ( fd -- )
    >r
    hdr-reset
    s\" HTTP/1.1 200 OK\r\nContent-Type: " h+  r-ctype 2@ h+
    s\" \r\nContent-Length: " h+  r-body 2@ nip h#
    r-cache @ IF  s\" \r\nCache-Control: public, max-age=3600" h+  THEN
    s\" \r\nConnection: close\r\n\r\n" h+
    hdr@ r@ send-all
    r-body 2@ r@ send-all
    r> close-fd ;

: respond-404 ( fd -- )
    >r
    hdr-reset
    s\" HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" h+
    hdr@ r@ send-all
    r> close-fd ;

: handle ( lsocket -- )
    accept-fd >r
    r@ recv-request
    lowercase-request
    set-urls
    request-path
    2dup s" /og.png" compare 0= IF
        2drop
        og-png 2@ r-body 2!  s" image/png" r-ctype 2!  true r-cache !
        r> respond  EXIT
    THEN
    s" /" compare 0= IF
        page-template 2@ render
        out@ r-body 2!  s" text/html; charset=utf-8" r-ctype 2!  false r-cache !
        r> respond  EXIT
    THEN
    r> respond-404 ;

\ ------------------------------------------------------------------- start-up

: port# ( -- u )
    s" PORT" getenv dup 0= IF  2drop 3000 EXIT  THEN
    s>number? IF  d>s  ELSE  2drop 3000  THEN ;

\ The three assets travel inside ./app -- the self-extracting launcher unpacks
\ them next to this file -- so nothing is read from Cloud's ephemeral disk that
\ did not arrive in the binary.
: load-assets ( -- )
    s" assets/page.html"     slurp-file  page-template 2!
    s" assets/og.png"        slurp-file  og-png 2!
    s" assets/index-url.txt" slurp-file  trim-right index-url 2! ;

: main ( -- )
    load-assets
    s" Forth" v-language 2!
    s" forth" v-branch 2!
    s" https://github.com/artisan-build/hello_cloud/tree/forth" v-branch-url 2!
    port# create-server6  dup 64 listen
    ." hello_cloud: hello from Forth, serving on [::]:" port# . cr
    outfile-id flush-file drop
    BEGIN
        dup ['] handle catch
        ?dup IF  ." forth: request failed, throw " . cr  THEN
    AGAIN ;
