*> Hello from COBOL, on Laravel Cloud's Go runtime.
*>
*> Laravel Cloud runs this binary because the branch carries a `go.mod` at its
*> root, so the environment was detected as Go when it was created and Cloud
*> starts whatever executable the build command left at `./app`. No Go is
*> compiled for this branch; the build command downloads the binary that GitHub
*> Actions built from this commit.
*>
*> There is no C shim here. GnuCOBOL's CALL "name" resolves straight to a C
*> symbol, and BY VALUE on a COMP-5 item matches the C ABI, so the BSD socket
*> calls are made from COBOL and `struct sockaddr_in6` is laid out as a group
*> item, field by field. Everything above the socket -- parsing the request,
*> filling the template, writing the response -- is COBOL too.
*>
*> The template and the OG card are compiled in as hexadecimal literals; see
*> genassets.sh. Cloud's filesystem is ephemeral, so nothing is read from disk.
IDENTIFICATION DIVISION.
PROGRAM-ID. app.

DATA DIVISION.
WORKING-STORAGE SECTION.

COPY "assets.cpy".

*> libc and Linux/aarch64 constants. COMP-5 is native binary, which is what
*> BY VALUE has to pass for the C prototypes to line up.
01  K-AF-INET6      PIC S9(9) COMP-5 VALUE 10.
01  K-SOCK-STREAM   PIC S9(9) COMP-5 VALUE 1.
01  K-SOL-SOCKET    PIC S9(9) COMP-5 VALUE 1.
01  K-SO-REUSEADDR  PIC S9(9) COMP-5 VALUE 2.
01  K-SO-RCVTIMEO   PIC S9(9) COMP-5 VALUE 20.
01  K-MSG-NOSIGNAL  PIC S9(9) COMP-5 VALUE 16384.
01  K-SHUT-WR       PIC S9(9) COMP-5 VALUE 1.
01  K-BACKLOG       PIC S9(9) COMP-5 VALUE 128.
01  K-ZERO          PIC S9(9) COMP-5 VALUE 0.
01  K-FOUR          PIC S9(9) COMP-5 VALUE 4.
01  K-SIXTEEN       PIC S9(9) COMP-5 VALUE 16.
01  K-ADDRLEN       PIC S9(9) COMP-5 VALUE 28.

01  LISTEN-SOCK     PIC S9(9) COMP-5.
01  CLIENT-SOCK     PIC S9(9) COMP-5.
01  CALL-RC         PIC S9(9) COMP-5.
01  N-GOT           PIC S9(9) COMP-5.
01  N-SENT          PIC S9(9) COMP-5.
01  LEN-ARG         PIC S9(18) COMP-5.
01  OPT-ONE         PIC S9(9) COMP-5 VALUE 1.

*> struct sockaddr_in6: family (2 bytes, host order), port (2, network order),
*> flowinfo (4), address (16), scope id (4).
01  SOCK-ADDR.
    05  SA-FAMILY   PIC X(2).
    05  SA-PORT     PIC X(2).
    05  SA-FLOW     PIC X(4).
    05  SA-HOST     PIC X(16).
    05  SA-SCOPE    PIC X(4).
01  PEER-ADDR       PIC X(28).
01  PEER-LEN        PIC S9(9) COMP-5 VALUE 28.
*> struct timeval: 8 bytes of seconds then 8 of microseconds.
01  TIMEOUT-VAL     PIC X(16).

01  PORT-NUM        PIC S9(9) COMP-5 VALUE 3000.
01  PORT-HI         PIC S9(9) COMP-5.
01  PORT-LO         PIC S9(9) COMP-5.
01  PORT-TEXT       PIC X(16).
01  NUM-EDIT        PIC Z(9).

01  REQ-BUF         PIC X(16384).
01  REQ-LOWER       PIC X(16384).
01  REQ-LEN         PIC S9(9) COMP-5.
01  HEADERS-DONE    PIC S9(9) COMP-5.
01  W-METHOD        PIC X(16).
01  W-TARGET        PIC X(256).
01  W-TARGET-LEN    PIC S9(9) COMP-5.
01  W-HOST          PIC X(256).
01  W-HOST-LEN      PIC S9(9) COMP-5.
01  FOUND-POS       PIC S9(9) COMP-5.
01  SCAN-I          PIC S9(9) COMP-5.
01  SCAN-J          PIC S9(9) COMP-5.
01  SCAN-K          PIC S9(9) COMP-5.

01  OUT-BODY        PIC X(8192).
01  OUT-LEN         PIC S9(9) COMP-5.
01  TPL-POS         PIC S9(9) COMP-5.
01  PH-IDX          PIC S9(9) COMP-5.
01  PH-HIT          PIC S9(9) COMP-5.

01  PH-COUNT        PIC S9(9) COMP-5 VALUE 7.
01  PH-TABLE.
    05  PH-ENTRY OCCURS 7 TIMES.
        10  PH-KEY      PIC X(16).
        10  PH-KEY-LEN  PIC S9(9) COMP-5.
        10  PH-VAL      PIC X(256).
        10  PH-VAL-LEN  PIC S9(9) COMP-5.

01  RESP-HEAD       PIC X(512).
01  RESP-HEAD-LEN   PIC S9(9) COMP-5.
01  STR-PTR         PIC S9(9) COMP-5.
01  SEND-BUF        PIC X(131072).
01  SEND-LEN        PIC S9(9) COMP-5.
01  SEND-POS        PIC S9(9) COMP-5.

01  CRLF            PIC X(2).
01  WS-INDEX-URL    PIC X(256).
01  WS-INDEX-LEN    PIC S9(9) COMP-5.

PROCEDURE DIVISION.

MAIN-PARA.
    MOVE X"0D0A" TO CRLF
    PERFORM READ-PORT
    PERFORM TRIM-INDEX-URL
    PERFORM OPEN-LISTENER
    MOVE PORT-NUM TO NUM-EDIT
    DISPLAY "hello_cloud: hello from COBOL, serving on [::]:"
        FUNCTION TRIM(NUM-EDIT) UPON SYSOUT
    PERFORM SERVE-LOOP
    STOP RUN.

READ-PORT.
    MOVE SPACES TO PORT-TEXT
    ACCEPT PORT-TEXT FROM ENVIRONMENT "PORT"
    IF PORT-TEXT NOT = SPACES
        COMPUTE PORT-NUM = FUNCTION NUMVAL(PORT-TEXT)
    END-IF
    IF PORT-NUM < 1 OR PORT-NUM > 65535
        MOVE 3000 TO PORT-NUM
    END-IF.

TRIM-INDEX-URL.
    MOVE INDEX-URL-DATA(1:INDEX-URL-LEN) TO WS-INDEX-URL
    MOVE FUNCTION TRIM(WS-INDEX-URL) TO WS-INDEX-URL
    MOVE 0 TO WS-INDEX-LEN
    PERFORM VARYING SCAN-I FROM 1 BY 1 UNTIL SCAN-I > 256
        IF WS-INDEX-URL(SCAN-I:1) NOT = SPACE
           AND WS-INDEX-URL(SCAN-I:1) NOT = X"0A"
           AND WS-INDEX-URL(SCAN-I:1) NOT = X"0D"
            MOVE SCAN-I TO WS-INDEX-LEN
        END-IF
    END-PERFORM.

OPEN-LISTENER.
    CALL "socket" USING BY VALUE K-AF-INET6 K-SOCK-STREAM K-ZERO
        RETURNING LISTEN-SOCK
    END-CALL
    IF LISTEN-SOCK < 0
        DISPLAY "hello_cloud: socket() failed" UPON SYSERR
        STOP RUN
    END-IF

    CALL "setsockopt" USING BY VALUE LISTEN-SOCK K-SOL-SOCKET
        K-SO-REUSEADDR BY REFERENCE OPT-ONE BY VALUE K-FOUR
        RETURNING CALL-RC
    END-CALL

    *> in6addr_any is all zeroes, and an IPv6 wildcard socket is dual-stack on
    *> Linux, which is what Cloud's per-instance nginx needs; IPV6_V6ONLY is
    *> deliberately left at the system default.
    MOVE LOW-VALUES TO SOCK-ADDR
    MOVE X"0A00" TO SA-FAMILY
    DIVIDE PORT-NUM BY 256 GIVING PORT-HI REMAINDER PORT-LO
    MOVE FUNCTION CHAR(PORT-HI + 1) TO SA-PORT(1:1)
    MOVE FUNCTION CHAR(PORT-LO + 1) TO SA-PORT(2:1)

    CALL "bind" USING BY VALUE LISTEN-SOCK BY REFERENCE SOCK-ADDR
        BY VALUE K-ADDRLEN RETURNING CALL-RC
    END-CALL
    IF CALL-RC NOT = 0
        DISPLAY "hello_cloud: bind([::]) failed" UPON SYSERR
        STOP RUN
    END-IF

    CALL "listen" USING BY VALUE LISTEN-SOCK K-BACKLOG RETURNING CALL-RC
    END-CALL
    IF CALL-RC NOT = 0
        DISPLAY "hello_cloud: listen() failed" UPON SYSERR
        STOP RUN
    END-IF.

SERVE-LOOP.
    PERFORM FOREVER
        MOVE 28 TO PEER-LEN
        CALL "accept" USING BY VALUE LISTEN-SOCK BY REFERENCE PEER-ADDR
            BY REFERENCE PEER-LEN RETURNING CLIENT-SOCK
        END-CALL
        IF CLIENT-SOCK >= 0
            PERFORM HANDLE-CLIENT
        END-IF
    END-PERFORM.

HANDLE-CLIENT.
    *> One connection at a time: both routes answer from memory. A five second
    *> receive timeout keeps a client that connects and says nothing from
    *> parking the loop for good.
    MOVE LOW-VALUES TO TIMEOUT-VAL
    MOVE FUNCTION CHAR(6) TO TIMEOUT-VAL(1:1)
    CALL "setsockopt" USING BY VALUE CLIENT-SOCK K-SOL-SOCKET K-SO-RCVTIMEO
        BY REFERENCE TIMEOUT-VAL BY VALUE K-SIXTEEN RETURNING CALL-RC
    END-CALL

    PERFORM READ-REQUEST
    IF REQ-LEN > 0
        PERFORM PARSE-REQUEST
        PERFORM ROUTE-REQUEST
    END-IF
    CALL "shutdown" USING BY VALUE CLIENT-SOCK K-SHUT-WR RETURNING CALL-RC
    END-CALL
    CALL "close" USING BY VALUE CLIENT-SOCK RETURNING CALL-RC
    END-CALL.

READ-REQUEST.
    MOVE 0 TO REQ-LEN
    MOVE 0 TO HEADERS-DONE
    PERFORM UNTIL HEADERS-DONE = 1
        COMPUTE LEN-ARG = 16384 - REQ-LEN
        IF LEN-ARG < 1
            MOVE 1 TO HEADERS-DONE
            EXIT PERFORM
        END-IF
        CALL "recv" USING BY VALUE CLIENT-SOCK
            BY REFERENCE REQ-BUF(REQ-LEN + 1:LEN-ARG)
            BY VALUE LEN-ARG K-ZERO
            RETURNING N-GOT
        END-CALL
        IF N-GOT <= 0
            MOVE 1 TO HEADERS-DONE
            EXIT PERFORM
        END-IF
        ADD N-GOT TO REQ-LEN
        MOVE 0 TO FOUND-POS
        IF REQ-LEN >= 4
            PERFORM VARYING SCAN-I FROM 1 BY 1
                UNTIL SCAN-I > REQ-LEN - 3 OR FOUND-POS > 0
                IF REQ-BUF(SCAN-I:4) = X"0D0A0D0A"
                    MOVE SCAN-I TO FOUND-POS
                END-IF
            END-PERFORM
        END-IF
        IF FOUND-POS > 0
            MOVE 1 TO HEADERS-DONE
        END-IF
    END-PERFORM.

PARSE-REQUEST.
    MOVE SPACES TO W-METHOD
    MOVE SPACES TO W-TARGET
    UNSTRING REQ-BUF(1:REQ-LEN) DELIMITED BY ALL SPACE
        INTO W-METHOD W-TARGET
    END-UNSTRING
    MOVE 0 TO W-TARGET-LEN
    PERFORM VARYING SCAN-I FROM 1 BY 1 UNTIL SCAN-I > 256
        IF W-TARGET(SCAN-I:1) NOT = SPACE
            MOVE SCAN-I TO W-TARGET-LEN
        END-IF
    END-PERFORM

    MOVE "localhost" TO W-HOST
    MOVE 9 TO W-HOST-LEN
    MOVE SPACES TO REQ-LOWER
    MOVE FUNCTION LOWER-CASE(REQ-BUF(1:REQ-LEN)) TO REQ-LOWER(1:REQ-LEN)
    MOVE 0 TO FOUND-POS
    PERFORM VARYING SCAN-I FROM 1 BY 1
        UNTIL SCAN-I > REQ-LEN - 6 OR FOUND-POS > 0
        IF REQ-LOWER(SCAN-I:1) = X"0A"
           AND REQ-LOWER(SCAN-I + 1:5) = "host:"
            MOVE SCAN-I TO FOUND-POS
        END-IF
    END-PERFORM
    IF FOUND-POS > 0
        MOVE 0 TO SCAN-J
        COMPUTE SCAN-K = FOUND-POS + 6
        PERFORM VARYING SCAN-I FROM SCAN-K BY 1 UNTIL SCAN-I > REQ-LEN
            IF REQ-BUF(SCAN-I:1) = X"0D" OR REQ-BUF(SCAN-I:1) = X"0A"
                EXIT PERFORM
            END-IF
            ADD 1 TO SCAN-J
        END-PERFORM
        IF SCAN-J > 0 AND SCAN-J < 257
            MOVE SPACES TO W-HOST
            MOVE REQ-BUF(FOUND-POS + 6:SCAN-J) TO W-HOST
            MOVE FUNCTION TRIM(W-HOST) TO W-HOST
            MOVE 0 TO W-HOST-LEN
            PERFORM VARYING SCAN-I FROM 1 BY 1 UNTIL SCAN-I > 256
                IF W-HOST(SCAN-I:1) NOT = SPACE
                    MOVE SCAN-I TO W-HOST-LEN
                END-IF
            END-PERFORM
            IF W-HOST-LEN = 0
                MOVE "localhost" TO W-HOST
                MOVE 9 TO W-HOST-LEN
            END-IF
        END-IF
    END-IF.

ROUTE-REQUEST.
    EVALUATE TRUE
        WHEN W-TARGET(1:W-TARGET-LEN) = "/og.png"
            PERFORM SERVE-OG-CARD
        WHEN W-TARGET(1:W-TARGET-LEN) = "/"
            PERFORM SERVE-PAGE
        WHEN OTHER
            PERFORM SERVE-NOT-FOUND
    END-EVALUATE.

SERVE-PAGE.
    PERFORM BUILD-PLACEHOLDERS
    PERFORM RENDER-TEMPLATE
    MOVE OUT-LEN TO NUM-EDIT
    MOVE 1 TO STR-PTR
    MOVE SPACES TO RESP-HEAD
    STRING "HTTP/1.1 200 OK" CRLF
           "content-type: text/html; charset=utf-8" CRLF
           "content-length: " FUNCTION TRIM(NUM-EDIT) CRLF
           "connection: close" CRLF CRLF
        DELIMITED BY SIZE INTO RESP-HEAD WITH POINTER STR-PTR
    END-STRING
    COMPUTE RESP-HEAD-LEN = STR-PTR - 1
    MOVE RESP-HEAD(1:RESP-HEAD-LEN) TO SEND-BUF(1:RESP-HEAD-LEN)
    MOVE OUT-BODY(1:OUT-LEN) TO SEND-BUF(RESP-HEAD-LEN + 1:OUT-LEN)
    COMPUTE SEND-LEN = RESP-HEAD-LEN + OUT-LEN
    PERFORM SEND-RESPONSE.

SERVE-OG-CARD.
    MOVE OG-PNG-LEN TO NUM-EDIT
    MOVE 1 TO STR-PTR
    MOVE SPACES TO RESP-HEAD
    STRING "HTTP/1.1 200 OK" CRLF
           "content-type: image/png" CRLF
           "content-length: " FUNCTION TRIM(NUM-EDIT) CRLF
           "cache-control: public, max-age=3600" CRLF
           "connection: close" CRLF CRLF
        DELIMITED BY SIZE INTO RESP-HEAD WITH POINTER STR-PTR
    END-STRING
    COMPUTE RESP-HEAD-LEN = STR-PTR - 1
    MOVE RESP-HEAD(1:RESP-HEAD-LEN) TO SEND-BUF(1:RESP-HEAD-LEN)
    MOVE OG-PNG-DATA(1:OG-PNG-LEN) TO SEND-BUF(RESP-HEAD-LEN + 1:OG-PNG-LEN)
    COMPUTE SEND-LEN = RESP-HEAD-LEN + OG-PNG-LEN
    PERFORM SEND-RESPONSE.

SERVE-NOT-FOUND.
    MOVE 1 TO STR-PTR
    MOVE SPACES TO RESP-HEAD
    STRING "HTTP/1.1 404 Not Found" CRLF
           "content-type: text/plain; charset=utf-8" CRLF
           "content-length: 10" CRLF
           "connection: close" CRLF CRLF
           "not found" X"0A"
        DELIMITED BY SIZE INTO RESP-HEAD WITH POINTER STR-PTR
    END-STRING
    COMPUTE SEND-LEN = STR-PTR - 1
    MOVE RESP-HEAD(1:SEND-LEN) TO SEND-BUF(1:SEND-LEN)
    PERFORM SEND-RESPONSE.

SEND-RESPONSE.
    MOVE 1 TO SEND-POS
    PERFORM UNTIL SEND-POS > SEND-LEN
        COMPUTE LEN-ARG = SEND-LEN - SEND-POS + 1
        CALL "send" USING BY VALUE CLIENT-SOCK
            BY REFERENCE SEND-BUF(SEND-POS:LEN-ARG)
            BY VALUE LEN-ARG K-MSG-NOSIGNAL
            RETURNING N-SENT
        END-CALL
        IF N-SENT <= 0
            EXIT PERFORM
        END-IF
        ADD N-SENT TO SEND-POS
    END-PERFORM.

*> og:image and og:url have to be absolute, so they are built from the request's
*> Host header with a hard-coded https scheme: Cloud terminates TLS upstream and
*> then sends `X-Forwarded-Proto: http` on an https request, so that header
*> cannot be trusted.
*>
*> {{BRANCH_URL}} is listed before {{BRANCH}} on purpose: the renderer takes the
*> first entry that matches at the current position, and "{{BRANCH}}" is not a
*> prefix of "{{BRANCH_URL}}" -- but a shorter key that WERE a prefix would win
*> and leave a tail behind, so the longer key goes first.
BUILD-PLACEHOLDERS.
    MOVE SPACES TO PH-TABLE

    MOVE "{{LANGUAGE}}" TO PH-KEY(1)
    MOVE 12 TO PH-KEY-LEN(1)
    MOVE "COBOL" TO PH-VAL(1)
    MOVE 5 TO PH-VAL-LEN(1)

    MOVE "{{BRANCH_URL}}" TO PH-KEY(2)
    MOVE 14 TO PH-KEY-LEN(2)
    MOVE "https://github.com/artisan-build/hello_cloud/tree/cobol"
        TO PH-VAL(2)
    MOVE 55 TO PH-VAL-LEN(2)

    MOVE "{{BRANCH}}" TO PH-KEY(3)
    MOVE 10 TO PH-KEY-LEN(3)
    MOVE "cobol" TO PH-VAL(3)
    MOVE 5 TO PH-VAL-LEN(3)

    MOVE "{{OG_IMAGE}}" TO PH-KEY(4)
    MOVE 12 TO PH-KEY-LEN(4)
    MOVE SPACES TO PH-VAL(4)
    MOVE 1 TO STR-PTR
    STRING "https://" W-HOST(1:W-HOST-LEN) "/og.png"
        DELIMITED BY SIZE INTO PH-VAL(4) WITH POINTER STR-PTR
    END-STRING
    COMPUTE PH-VAL-LEN(4) = STR-PTR - 1

    MOVE "{{PAGE_URL}}" TO PH-KEY(5)
    MOVE 12 TO PH-KEY-LEN(5)
    MOVE SPACES TO PH-VAL(5)
    MOVE 1 TO STR-PTR
    STRING "https://" W-HOST(1:W-HOST-LEN) "/"
        DELIMITED BY SIZE INTO PH-VAL(5) WITH POINTER STR-PTR
    END-STRING
    COMPUTE PH-VAL-LEN(5) = STR-PTR - 1

    MOVE "{{INDEX_URL}}" TO PH-KEY(6)
    MOVE 13 TO PH-KEY-LEN(6)
    MOVE WS-INDEX-URL(1:WS-INDEX-LEN) TO PH-VAL(6)
    MOVE WS-INDEX-LEN TO PH-VAL-LEN(6)

    MOVE "{{EXTRA}}" TO PH-KEY(7)
    MOVE 9 TO PH-KEY-LEN(7)
    MOVE SPACES TO PH-VAL(7)
    MOVE 0 TO PH-VAL-LEN(7).

RENDER-TEMPLATE.
    MOVE SPACES TO OUT-BODY
    MOVE 0 TO OUT-LEN
    MOVE 1 TO TPL-POS
    PERFORM UNTIL TPL-POS > PAGE-HTML-LEN
        MOVE 0 TO PH-HIT
        PERFORM VARYING PH-IDX FROM 1 BY 1
            UNTIL PH-IDX > PH-COUNT OR PH-HIT = 1
            IF TPL-POS + PH-KEY-LEN(PH-IDX) - 1 <= PAGE-HTML-LEN
               AND PAGE-HTML-DATA(TPL-POS:PH-KEY-LEN(PH-IDX)) =
                   PH-KEY(PH-IDX)(1:PH-KEY-LEN(PH-IDX))
                MOVE 1 TO PH-HIT
                IF PH-VAL-LEN(PH-IDX) > 0
                    MOVE PH-VAL(PH-IDX)(1:PH-VAL-LEN(PH-IDX))
                        TO OUT-BODY(OUT-LEN + 1:PH-VAL-LEN(PH-IDX))
                    ADD PH-VAL-LEN(PH-IDX) TO OUT-LEN
                END-IF
                ADD PH-KEY-LEN(PH-IDX) TO TPL-POS
            END-IF
        END-PERFORM
        IF PH-HIT = 0
            ADD 1 TO OUT-LEN
            MOVE PAGE-HTML-DATA(TPL-POS:1) TO OUT-BODY(OUT-LEN:1)
            ADD 1 TO TPL-POS
        END-IF
    END-PERFORM.

END PROGRAM app.
