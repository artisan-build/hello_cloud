// Hello from aarch64 Assembly, on Laravel Cloud's Go runtime.
//
// Laravel Cloud runs this binary because the branch carries a `go.mod` at its
// root, so the environment was detected as Go when it was created and Cloud
// starts whatever executable the build command left at `./app`. No Go is
// compiled for this branch; the build command downloads the binary that GitHub
// Actions built from this commit.
//
// There is no framework, no HTTP library and no libc: `as` assembles this and
// `ld` links it with nothing, so every effect below is a raw Linux syscall and
// the entry point is _start rather than main. $PORT is read by walking the
// envp array off the initial stack, because getenv() is a libc function.
// The shared HTML template, the index URL and the OG card are `.incbin`-ed, so
// nothing is read from Cloud's ephemeral disk.
//
// One connection is served at a time: accept, read the request, write the
// response, close. Writes go through sendto() with MSG_NOSIGNAL -- with no libc
// there is no SIGPIPE handler, so a client that hangs up mid-write would
// otherwise kill the process.

    .equ SYS_read,       63
    .equ SYS_write,      64
    .equ SYS_close,      57
    .equ SYS_socket,    198
    .equ SYS_bind,      200
    .equ SYS_listen,    201
    .equ SYS_sendto,    206
    .equ SYS_setsockopt,208
    .equ SYS_accept4,   242
    .equ SYS_exit_group, 94

    .equ AF_INET6,      10
    .equ SOCK_STREAM,    1
    .equ SOL_SOCKET,     1
    .equ SO_REUSEADDR,   2
    .equ MSG_NOSIGNAL, 0x4000

    .equ REQ_CAP,    16384
    .equ OUT_CAP,    32768
    .equ HEAD_CAP,     512
    .equ URL_CAP,      512
    .equ DEFAULT_PORT, 3000

// ---------------------------------------------------------------- embedded data

    .section .rodata
    .balign 8
template:       .incbin "shared/page.html"
template_end:
index_url:      .incbin "shared/index-url.txt"
index_url_end:
og_png:         .incbin "og.png"
og_png_end:
    .balign 8
og_png_len:     .quad og_png_end - og_png

s_language:     .ascii "aarch64 Assembly"
s_language_end:
s_branch:       .ascii "asm-arm64"
s_branch_end:
s_branch_url:   .ascii "https://github.com/artisan-build/hello_cloud/tree/asm-arm64"
s_branch_url_end:
s_https:        .ascii "https://"
s_https_end:
s_og_path:      .ascii "/og.png"
s_og_path_end:
s_slash:        .ascii "/"

n_language:     .ascii "{{LANGUAGE}}"
n_language_end:
n_branch_url:   .ascii "{{BRANCH_URL}}"
n_branch_url_end:
n_branch:       .ascii "{{BRANCH}}"
n_branch_end:
n_og_image:     .ascii "{{OG_IMAGE}}"
n_og_image_end:
n_page_url:     .ascii "{{PAGE_URL}}"
n_page_url_end:
n_index_url:    .ascii "{{INDEX_URL}}"
n_index_url_end:
n_extra:        .ascii "{{EXTRA}}"
n_extra_end:

s_port_eq:      .ascii "PORT="
s_host_hdr:     .ascii "host:"
s_banner:       .ascii "hello_cloud: hello from aarch64 Assembly, serving on [::]:"
s_banner_end:
s_nl:           .ascii "\n"

s_head_200:     .ascii "HTTP/1.1 200 OK\r\ncontent-type: "
s_head_200_end:
s_ct_html:      .ascii "text/html; charset=utf-8"
s_ct_html_end:
s_ct_png:       .ascii "image/png\r\ncache-control: public, max-age=3600"
s_ct_png_end:
s_head_len:     .ascii "\r\ncontent-length: "
s_head_len_end:
s_head_tail:    .ascii "\r\nconnection: close\r\n\r\n"
s_head_tail_end:
s_404:          .ascii "HTTP/1.1 404 Not Found\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 10\r\nconnection: close\r\n\r\nnot found\n"
s_404_end:

// ------------------------------------------------------------------- mutable

    .section .data
    .balign 8
// One row per placeholder: needle pointer, needle length, and the ADDRESSES of
// the two words holding the current value pointer and length. The indirection
// is what lets {{OG_IMAGE}} and {{PAGE_URL}} change per request while the
// renderer stays a single table walk. A zero needle pointer ends the table.
subst_table:
    .quad n_language,   n_language_end - n_language,     v_language_ptr,  v_language_len
    .quad n_branch_url, n_branch_url_end - n_branch_url, v_branch_url_ptr, v_branch_url_len
    .quad n_branch,     n_branch_end - n_branch,         v_branch_ptr,    v_branch_len
    .quad n_og_image,   n_og_image_end - n_og_image,     v_og_image_ptr,  v_og_image_len
    .quad n_page_url,   n_page_url_end - n_page_url,     v_page_url_ptr,  v_page_url_len
    .quad n_index_url,  n_index_url_end - n_index_url,   v_index_url_ptr, v_index_url_len
    .quad n_extra,      n_extra_end - n_extra,           v_extra_ptr,     v_extra_len
    .quad 0, 0, 0, 0

v_language_ptr:   .quad s_language
v_language_len:   .quad s_language_end - s_language
v_branch_url_ptr: .quad s_branch_url
v_branch_url_len: .quad s_branch_url_end - s_branch_url
v_branch_ptr:     .quad s_branch
v_branch_len:     .quad s_branch_end - s_branch
v_og_image_ptr:   .quad og_image_buf
v_og_image_len:   .quad 0
v_page_url_ptr:   .quad page_url_buf
v_page_url_len:   .quad 0
v_index_url_ptr:  .quad index_url
v_index_url_len:  .quad 0
v_extra_ptr:      .quad s_slash
v_extra_len:      .quad 0

    .section .bss
    .balign 16
sockaddr:       .skip 28
    .balign 16
reuse_one:      .skip 4
    .balign 16
req_buf:        .skip REQ_CAP
out_buf:        .skip OUT_CAP
head_buf:       .skip HEAD_CAP
og_image_buf:   .skip URL_CAP
page_url_buf:   .skip URL_CAP
digits_buf:     .skip 32

// ---------------------------------------------------------------------- code

    .section .text
    .global _start

_start:
    // At process entry sp points at argc, argv follows, then a NULL, then envp.
    ldr     x19, [sp]                   // argc
    add     x20, sp, #8                 // argv
    add     x21, x20, x19, lsl #3
    add     x21, x21, #8                // envp

    mov     x0, x21
    bl      port_from_env
    mov     x22, x0                     // port

    // Trim the trailing newline off the embedded index URL once, up front.
    adrp    x0, index_url
    add     x0, x0, :lo12:index_url
    mov     x1, #(index_url_end - index_url)
    bl      trim_right
    adrp    x2, v_index_url_len
    add     x2, x2, :lo12:v_index_url_len
    str     x0, [x2]

    // socket(AF_INET6, SOCK_STREAM, 0)
    mov     x0, #AF_INET6
    mov     x1, #SOCK_STREAM
    mov     x2, #0
    mov     x8, #SYS_socket
    svc     #0
    cmp     x0, #0
    b.lt    fail
    mov     x23, x0                     // listening fd

    // setsockopt(SO_REUSEADDR, 1)
    adrp    x4, reuse_one
    add     x4, x4, :lo12:reuse_one
    mov     w5, #1
    str     w5, [x4]
    mov     x0, x23
    mov     x1, #SOL_SOCKET
    mov     x2, #SO_REUSEADDR
    mov     x3, x4
    mov     x4, #4
    mov     x8, #SYS_setsockopt
    svc     #0

    // struct sockaddr_in6 { u16 family; u16 port (big endian); u32 flowinfo;
    //                       u8 addr[16]; u32 scope_id; } -- all-zero address is
    // in6addr_any. The IPv6 wildcard is dual-stack on Linux (IPV6_V6ONLY is
    // left alone), which is what Cloud's nginx needs: it proxies to
    // 127.0.0.1:$PORT over an IPv6-only network.
    adrp    x24, sockaddr
    add     x24, x24, :lo12:sockaddr
    mov     x0, x24
    mov     x1, #28
    bl      bzero
    mov     w0, #AF_INET6
    strh    w0, [x24]
    rev16   w0, w22                     // htons(port)
    strh    w0, [x24, #2]

    mov     x0, x23
    mov     x1, x24
    mov     x2, #28
    mov     x8, #SYS_bind
    svc     #0
    cmp     x0, #0
    b.lt    fail

    mov     x0, x23
    mov     x1, #128
    mov     x8, #SYS_listen
    svc     #0
    cmp     x0, #0
    b.lt    fail

    // Log line on stdout, so a Cloud deploy log shows the bind. head_buf is
    // free at this point and is only scratch here.
    adrp    x26, head_buf
    add     x26, x26, :lo12:head_buf
    mov     x0, x26
    adrp    x1, s_banner
    add     x1, x1, :lo12:s_banner
    mov     x2, #(s_banner_end - s_banner)
    bl      append
    mov     x27, x0
    mov     x0, x22
    mov     x1, x27
    bl      utoa
    add     x0, x27, x0
    adrp    x1, s_nl
    add     x1, x1, :lo12:s_nl
    mov     x2, #1
    bl      append
    sub     x2, x0, x26
    mov     x1, x26
    mov     x0, #1
    mov     x8, #SYS_write
    svc     #0

accept_loop:
    mov     x0, x23
    mov     x1, #0
    mov     x2, #0
    mov     x3, #0
    mov     x8, #SYS_accept4
    svc     #0
    cmp     x0, #0
    b.lt    accept_loop                 // transient error: keep serving
    mov     x25, x0                     // client fd

    mov     x0, x25
    bl      serve

    mov     x0, x25
    mov     x8, #SYS_close
    svc     #0
    b       accept_loop

fail:
    mov     x0, #1
    mov     x8, #SYS_exit_group
    svc     #0

// ------------------------------------------------------- serve(x0 = client fd)

serve:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // fd
    adrp    x20, req_buf
    add     x20, x20, :lo12:req_buf
    mov     x21, #0                     // bytes held

serve_read:
    mov     x0, x19
    add     x1, x20, x21
    mov     x2, #REQ_CAP
    sub     x2, x2, x21
    cbz     x2, serve_parse
    mov     x8, #SYS_read
    svc     #0
    cmp     x0, #1
    b.lt    serve_parse
    add     x21, x21, x0
    // Stop once the request head is complete.
    mov     x0, x20
    mov     x1, x21
    bl      has_crlfcrlf
    cbz     x0, serve_read

serve_parse:
    cbz     x21, serve_done

    // "GET /path HTTP/1.1": the path starts after the first space.
    mov     x0, x20
    mov     x1, x21
    mov     w2, #0x20
    bl      index_byte
    cmp     x0, #0
    b.lt    serve_404
    add     x22, x20, x0
    add     x22, x22, #1                // path pointer
    sub     x23, x21, x0
    sub     x23, x23, #1                // bytes left after it
    cmp     x23, #1
    b.lt    serve_404

    // Both routes match the path, not the raw target, so the query string is
    // measured off before either comparison.
    mov     x0, x22
    mov     x1, x23
    bl      path_len
    mov     x23, x0                     // path length
    cbz     x23, serve_404

    // "/og.png"
    cmp     x23, #(s_og_path_end - s_og_path)
    b.ne    serve_check_root
    mov     x0, x22
    adrp    x1, s_og_path
    add     x1, x1, :lo12:s_og_path
    mov     x2, #(s_og_path_end - s_og_path)
    bl      memcmp_n
    cbz     x0, serve_og

serve_check_root:
    // exactly "/"
    cmp     x23, #1
    b.ne    serve_404
    ldrb    w0, [x22]
    cmp     w0, #'/'
    b.ne    serve_404

    // Render the page for this request's Host header.
    mov     x0, x20
    mov     x1, x21
    bl      find_host                   // x0 = ptr, x1 = len
    bl      set_absolute_urls
    bl      render_page                 // x0 = length in out_buf

    mov     x24, x0
    adrp    x0, s_ct_html
    add     x0, x0, :lo12:s_ct_html
    mov     x1, #(s_ct_html_end - s_ct_html)
    mov     x2, x24
    bl      build_head                  // x0 = head length
    mov     x1, x0
    adrp    x0, head_buf
    add     x0, x0, :lo12:head_buf
    mov     x2, x1
    mov     x1, x0
    mov     x0, x19
    bl      write_all
    mov     x0, x19
    adrp    x1, out_buf
    add     x1, x1, :lo12:out_buf
    mov     x2, x24
    bl      write_all
    b       serve_done

serve_og:
    adrp    x0, s_ct_png
    add     x0, x0, :lo12:s_ct_png
    mov     x1, #(s_ct_png_end - s_ct_png)
    adrp    x2, og_png_len
    add     x2, x2, :lo12:og_png_len
    ldr     x2, [x2]
    bl      build_head
    mov     x2, x0
    adrp    x1, head_buf
    add     x1, x1, :lo12:head_buf
    mov     x0, x19
    bl      write_all
    mov     x0, x19
    adrp    x1, og_png
    add     x1, x1, :lo12:og_png
    adrp    x2, og_png_len
    add     x2, x2, :lo12:og_png_len
    ldr     x2, [x2]
    bl      write_all
    b       serve_done

serve_404:
    mov     x0, x19
    adrp    x1, s_404
    add     x1, x1, :lo12:s_404
    mov     x2, #(s_404_end - s_404)
    bl      write_all

serve_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

// ---------------------------------------------- build_head(ct ptr, ct len, body len)
// Assembles the response head into head_buf; returns its length in x0.

build_head:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // content-type ptr
    mov     x20, x1                     // content-type len
    mov     x21, x2                     // body length

    adrp    x22, head_buf
    add     x22, x22, :lo12:head_buf

    mov     x0, x22
    adrp    x1, s_head_200
    add     x1, x1, :lo12:s_head_200
    mov     x2, #(s_head_200_end - s_head_200)
    bl      append
    mov     x22, x0

    mov     x0, x22
    mov     x1, x19
    mov     x2, x20
    bl      append
    mov     x22, x0

    mov     x0, x22
    adrp    x1, s_head_len
    add     x1, x1, :lo12:s_head_len
    mov     x2, #(s_head_len_end - s_head_len)
    bl      append
    mov     x22, x0

    mov     x0, x21
    mov     x1, x22
    bl      utoa                        // x0 = digits written
    add     x22, x22, x0

    mov     x0, x22
    adrp    x1, s_head_tail
    add     x1, x1, :lo12:s_head_tail
    mov     x2, #(s_head_tail_end - s_head_tail)
    bl      append
    mov     x22, x0

    adrp    x1, head_buf
    add     x1, x1, :lo12:head_buf
    sub     x0, x22, x1

    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

// ------------------------------------ set_absolute_urls(host ptr x0, host len x1)
// Builds "https://<host>/og.png" and "https://<host>/" and points the two
// dynamic table rows at them.
//
// og:image and og:url have to be absolute, and they are built from the
// request's Host header with a hard-coded https scheme: Cloud terminates TLS
// upstream and then sends `X-Forwarded-Proto: http` on an https request, so
// that header cannot be trusted.

set_absolute_urls:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // host ptr
    mov     x20, x1                     // host len
    // Keep the two URL buffers in range even for an absurd Host header.
    mov     x0, #(URL_CAP - 32)
    cmp     x20, x0
    csel    x20, x0, x20, hi

    adrp    x21, og_image_buf
    add     x21, x21, :lo12:og_image_buf
    mov     x0, x21
    adrp    x1, s_https
    add     x1, x1, :lo12:s_https
    mov     x2, #(s_https_end - s_https)
    bl      append
    mov     x1, x19
    mov     x2, x20
    bl      append
    adrp    x1, s_og_path
    add     x1, x1, :lo12:s_og_path
    mov     x2, #(s_og_path_end - s_og_path)
    bl      append
    sub     x0, x0, x21
    adrp    x1, v_og_image_len
    add     x1, x1, :lo12:v_og_image_len
    str     x0, [x1]

    adrp    x22, page_url_buf
    add     x22, x22, :lo12:page_url_buf
    mov     x0, x22
    adrp    x1, s_https
    add     x1, x1, :lo12:s_https
    mov     x2, #(s_https_end - s_https)
    bl      append
    mov     x1, x19
    mov     x2, x20
    bl      append
    adrp    x1, s_slash
    add     x1, x1, :lo12:s_slash
    mov     x2, #1
    bl      append
    sub     x0, x0, x22
    adrp    x1, v_page_url_len
    add     x1, x1, :lo12:v_page_url_len
    str     x0, [x1]

    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

// ------------------------------------------------------------------ render_page
// Copies the template into out_buf, swapping each {{PLACEHOLDER}} for the value
// its table row currently points at. Returns the length in x0.

render_page:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    adrp    x19, template
    add     x19, x19, :lo12:template    // cursor into the template
    mov     x20, #(template_end - template)
    add     x20, x19, x20               // template end
    adrp    x21, out_buf
    add     x21, x21, :lo12:out_buf     // write cursor
    adrp    x26, out_buf
    add     x26, x26, :lo12:out_buf     // out_buf start

render_loop:
    cmp     x19, x20
    b.hs    render_done

    // A placeholder always starts "{{"; anything else copies through.
    ldrb    w0, [x19]
    cmp     w0, #'{'
    b.ne    render_copy_byte
    add     x1, x19, #1
    cmp     x1, x20
    b.hs    render_copy_byte
    ldrb    w0, [x19, #1]
    cmp     w0, #'{'
    b.ne    render_copy_byte

    adrp    x22, subst_table
    add     x22, x22, :lo12:subst_table

render_try_row:
    ldr     x23, [x22]                  // needle ptr
    cbz     x23, render_copy_byte       // table exhausted: not a placeholder
    ldr     x24, [x22, #8]              // needle len
    sub     x0, x20, x19
    cmp     x0, x24
    b.lo    render_next_row
    mov     x0, x19
    mov     x1, x23
    mov     x2, x24
    bl      memcmp_n
    cbnz    x0, render_next_row

    ldr     x0, [x22, #16]              // &value ptr
    ldr     x1, [x0]
    ldr     x0, [x22, #24]              // &value len
    ldr     x2, [x0]
    mov     x0, x21
    bl      append
    mov     x21, x0
    add     x19, x19, x24
    b       render_loop

render_next_row:
    add     x22, x22, #32
    b       render_try_row

render_copy_byte:
    ldrb    w0, [x19], #1
    strb    w0, [x21], #1
    b       render_loop

render_done:
    sub     x0, x21, x26
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x25, x26, [sp, #64]
    ldp     x29, x30, [sp], #80
    ret

// ------------------------------------------- find_host(buf x0, len x1) -> ptr, len
// The Host header value, case-insensitively, or the literal "localhost" when
// the request carries none.

find_host:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // buf
    mov     x20, x1                     // len
    mov     x21, #0                     // index

find_host_loop:
    add     x0, x21, #5
    cmp     x0, x20
    b.hi    find_host_none
    cbz     x21, find_host_check        // the first line can be the header too
    sub     x0, x21, #1
    ldrb    w0, [x19, x0]
    cmp     w0, #10                     // only at the start of a line
    b.ne    find_host_next

find_host_check:
    add     x0, x19, x21
    adrp    x1, s_host_hdr
    add     x1, x1, :lo12:s_host_hdr
    mov     x2, #5
    bl      memcmp_fold
    cbz     x0, find_host_found

find_host_next:
    add     x21, x21, #1
    b       find_host_loop

find_host_found:
    add     x22, x21, #5                // past "host:"
find_host_skip_ws:
    cmp     x22, x20
    b.hs    find_host_none
    ldrb    w0, [x19, x22]
    cmp     w0, #0x20
    b.eq    find_host_skip_ws_step
    cmp     w0, #9
    b.ne    find_host_value
find_host_skip_ws_step:
    add     x22, x22, #1
    b       find_host_skip_ws

find_host_value:
    mov     x0, x22
find_host_scan:
    cmp     x0, x20
    b.hs    find_host_emit
    ldrb    w1, [x19, x0]
    cmp     w1, #13
    b.eq    find_host_emit
    cmp     w1, #10
    b.eq    find_host_emit
    add     x0, x0, #1
    b       find_host_scan

find_host_emit:
    sub     x1, x0, x22                 // value length
    cbz     x1, find_host_none
    add     x0, x19, x22
    b       find_host_ret

find_host_none:
    adrp    x0, s_localhost
    add     x0, x0, :lo12:s_localhost
    mov     x1, #(s_localhost_end - s_localhost)

find_host_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

    .section .rodata
s_localhost:    .ascii "localhost"
s_localhost_end:
    .section .text

// ------------------------------------------------- port_from_env(envp x0) -> port
// $PORT, or 3000. getenv() is libc, so this walks the envp array itself.

port_from_env:
    mov     x1, x0                      // cursor
port_loop:
    ldr     x2, [x1], #8
    cbz     x2, port_default
    mov     x3, #0
port_cmp:
    cmp     x3, #5
    b.eq    port_parse
    ldrb    w4, [x2, x3]
    adrp    x5, s_port_eq
    add     x5, x5, :lo12:s_port_eq
    ldrb    w5, [x5, x3]
    cmp     w4, w5
    b.ne    port_loop
    add     x3, x3, #1
    b       port_cmp

port_parse:
    add     x2, x2, #5
    mov     x0, #0
port_digit:
    ldrb    w4, [x2], #1
    sub     w4, w4, #'0'
    cmp     w4, #9
    b.hi    port_check
    mov     x5, #10
    mul     x0, x0, x5
    add     x0, x0, x4
    mov     x6, #65535                  // 65535 is not an encodable cmp immediate
    cmp     x0, x6
    b.hi    port_default
    b       port_digit

port_check:
    cbz     x0, port_default
    ret

port_default:
    mov     x0, #DEFAULT_PORT
    ret

// ---------------------------------- trim_right(ptr x0, len x1) -> trimmed len x0
// Drops trailing spaces, tabs, CRs and LFs. The embedded index URL has one.

trim_right:
    mov     x2, x1
trim_loop:
    cbz     x2, trim_done
    sub     x3, x2, #1
    ldrb    w4, [x0, x3]
    cmp     w4, #0x20
    b.eq    trim_step
    cmp     w4, #9
    b.eq    trim_step
    cmp     w4, #13
    b.eq    trim_step
    cmp     w4, #10
    b.eq    trim_step
    b       trim_done
trim_step:
    mov     x2, x3
    b       trim_loop
trim_done:
    mov     x0, x2
    ret

// ------------------------------------------ append(dst x0, src x1, len x2) -> dst
append:
    cbz     x2, append_done
append_loop:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    sub     x2, x2, #1
    cbnz    x2, append_loop
append_done:
    ret

// ------------------------------------------------------ bzero(ptr x0, len x1)
bzero:
    cbz     x1, bzero_done
    mov     x2, x0
bzero_loop:
    strb    wzr, [x2], #1
    sub     x1, x1, #1
    cbnz    x1, bzero_loop
bzero_done:
    ret

// ------------------------------- memcmp_n(a x0, b x1, len x2) -> 0 when equal
memcmp_n:
    cbz     x2, memcmp_equal
memcmp_loop:
    ldrb    w3, [x0], #1
    ldrb    w4, [x1], #1
    cmp     w3, w4
    b.ne    memcmp_diff
    sub     x2, x2, #1
    cbnz    x2, memcmp_loop
memcmp_equal:
    mov     x0, #0
    ret
memcmp_diff:
    mov     x0, #1
    ret

// ------------------- memcmp_fold(a x0, b x1, len x2) -> 0 when equal, ASCII-fold
// The ASCII fold is inline on purpose: memcmp_fold is a leaf, so a `bl` to a
// helper would overwrite the x30 it has to return through.
memcmp_fold:
    cbz     x2, fold_equal
fold_loop:
    ldrb    w3, [x0], #1
    ldrb    w4, [x1], #1
    sub     w5, w3, #'A'
    cmp     w5, #25
    b.hi    1f
    add     w3, w3, #32
1:  sub     w5, w4, #'A'
    cmp     w5, #25
    b.hi    2f
    add     w4, w4, #32
2:  cmp     w3, w4
    b.ne    fold_diff
    subs    x2, x2, #1
    b.ne    fold_loop
fold_equal:
    mov     x0, #0
    ret
fold_diff:
    mov     x0, #1
    ret

// -------------------------------------- path_len(ptr x0, max x1) -> length x0
// How many bytes of the request target are the path. The target ends at the
// space before "HTTP/1.1", and a query string is not part of the path: social
// sites append `?fbclid=...` and `?utm_source=...`, so `?` ends it too, as
// does `#` if a client ever sends a fragment. A leaf, so no frame.

path_len:
    mov     x2, #0
path_len_loop:
    cmp     x2, x1
    b.hs    path_len_done
    ldrb    w3, [x0, x2]
    cmp     w3, #0x20
    b.eq    path_len_done
    cmp     w3, #'?'
    b.eq    path_len_done
    cmp     w3, #'#'
    b.eq    path_len_done
    cmp     w3, #13
    b.eq    path_len_done
    cmp     w3, #10
    b.eq    path_len_done
    add     x2, x2, #1
    b       path_len_loop
path_len_done:
    mov     x0, x2
    ret

// ------------------------------- index_byte(buf x0, len x1, byte w2) -> index/-1
index_byte:
    mov     x3, #0
index_loop:
    cmp     x3, x1
    b.hs    index_missing
    ldrb    w4, [x0, x3]
    cmp     w4, w2
    b.eq    index_found
    add     x3, x3, #1
    b       index_loop
index_found:
    mov     x0, x3
    ret
index_missing:
    mov     x0, #-1
    ret

// ------------------------------ has_crlfcrlf(buf x0, len x1) -> 1 when present
has_crlfcrlf:
    cmp     x1, #4
    b.lo    crlf_no
    sub     x1, x1, #3
    mov     x2, #0
crlf_loop:
    cmp     x2, x1
    b.hs    crlf_no
    add     x3, x0, x2
    ldrb    w4, [x3]
    cmp     w4, #13
    b.ne    crlf_next
    ldrb    w4, [x3, #1]
    cmp     w4, #10
    b.ne    crlf_next
    ldrb    w4, [x3, #2]
    cmp     w4, #13
    b.ne    crlf_next
    ldrb    w4, [x3, #3]
    cmp     w4, #10
    b.eq    crlf_yes
crlf_next:
    add     x2, x2, #1
    b       crlf_loop
crlf_yes:
    mov     x0, #1
    ret
crlf_no:
    mov     x0, #0
    ret

// ----------------------------------- utoa(value x0, dst x1) -> digits written x0
utoa:
    adrp    x2, digits_buf
    add     x2, x2, :lo12:digits_buf
    add     x2, x2, #31                 // fill backwards from the end
    mov     x3, #0                      // count
    mov     x4, #10
    cbnz    x0, utoa_loop
    mov     w5, #'0'
    sub     x2, x2, #1
    strb    w5, [x2]
    mov     x3, #1
    b       utoa_copy
utoa_loop:
    cbz     x0, utoa_copy
    udiv    x5, x0, x4
    msub    x6, x5, x4, x0              // remainder
    add     w6, w6, #'0'
    sub     x2, x2, #1
    strb    w6, [x2]
    add     x3, x3, #1
    mov     x0, x5
    b       utoa_loop
utoa_copy:
    mov     x0, x1
    mov     x1, x2
    mov     x2, x3
    mov     x4, x3
    stp     x29, x30, [sp, #-16]!
    bl      append
    ldp     x29, x30, [sp], #16
    mov     x0, x4
    ret

// --------------------------------------- write_all(fd x0, buf x1, len x2)
// sendto() with MSG_NOSIGNAL: with no libc there is no SIGPIPE handler, so a
// bare write() to a hung-up client would terminate the process.

write_all:
    stp     x29, x30, [sp, #-32]!
    str     x0, [sp, #16]
write_loop:
    cbz     x2, write_done
    ldr     x0, [sp, #16]
    mov     x3, #MSG_NOSIGNAL
    mov     x4, #0
    mov     x5, #0
    mov     x8, #SYS_sendto
    svc     #0
    cmp     x0, #1
    b.lt    write_done                  // peer gone: drop this response
    add     x1, x1, x0
    sub     x2, x2, x0
    b       write_loop
write_done:
    ldp     x29, x30, [sp], #32
    ret
