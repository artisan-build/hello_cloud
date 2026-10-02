! Hello from Fortran, on Laravel Cloud's Go runtime.
!
! Laravel Cloud runs this binary because the branch carries a `go.mod` at its
! root, so the environment was detected as Go when it was created and Cloud
! starts whatever executable the build command left at `./app`. No Go is
! compiled for this branch; the build command downloads the binary that GitHub
! Actions built from this commit.
!
! There is no Fortran web framework to reach for, so the web layer is libc: the
! BSD socket calls are bound straight through ISO_C_BINDING and the HTTP is
! parsed and written here. `sockaddr_in6` has no Fortran equivalent either, so
! it is laid out byte by byte -- which is the whole reason the structure's field
! offsets are spelled out below.
!
! The binary is linked fully static, so Cloud's glibc version is moot, and the
! shared template plus the OG card are compiled in as hex (see genassets.f90).

module hc_libc
   use iso_c_binding
   implicit none

   ! Linux/aarch64 values.
   integer(c_int), parameter :: AF_INET6 = 10
   integer(c_int), parameter :: SOCK_STREAM = 1
   integer(c_int), parameter :: SOL_SOCKET = 1
   integer(c_int), parameter :: SO_REUSEADDR = 2
   integer(c_int), parameter :: SO_RCVTIMEO = 20
   integer(c_int), parameter :: MSG_NOSIGNAL = 16384   ! 0x4000
   integer(c_int), parameter :: SHUT_WR = 1

   interface
      function c_socket(domain, stype, protocol) bind(C, name='socket') result(fd)
         import :: c_int
         integer(c_int), value :: domain, stype, protocol
         integer(c_int) :: fd
      end function c_socket

      function c_bind(fd, addr, addrlen) bind(C, name='bind') result(rc)
         import :: c_int, c_char
         integer(c_int), value :: fd
         character(kind=c_char), intent(in) :: addr(*)
         integer(c_int), value :: addrlen
         integer(c_int) :: rc
      end function c_bind

      function c_listen(fd, backlog) bind(C, name='listen') result(rc)
         import :: c_int
         integer(c_int), value :: fd, backlog
         integer(c_int) :: rc
      end function c_listen

      function c_accept(fd, addr, addrlen) bind(C, name='accept') result(client)
         import :: c_int, c_ptr
         integer(c_int), value :: fd
         type(c_ptr), value :: addr, addrlen
         integer(c_int) :: client
      end function c_accept

      function c_setsockopt(fd, level, optname, optval, optlen) &
         bind(C, name='setsockopt') result(rc)
         import :: c_int, c_char
         integer(c_int), value :: fd, level, optname
         character(kind=c_char), intent(in) :: optval(*)
         integer(c_int), value :: optlen
         integer(c_int) :: rc
      end function c_setsockopt

      function c_recv(fd, buf, nbytes, flags) bind(C, name='recv') result(got)
         import :: c_int, c_char, c_size_t, c_ptrdiff_t
         integer(c_int), value :: fd
         character(kind=c_char) :: buf(*)
         integer(c_size_t), value :: nbytes
         integer(c_int), value :: flags
         integer(c_ptrdiff_t) :: got
      end function c_recv

      function c_send(fd, buf, nbytes, flags) bind(C, name='send') result(sent)
         import :: c_int, c_char, c_size_t, c_ptrdiff_t
         integer(c_int), value :: fd
         character(kind=c_char), intent(in) :: buf(*)
         integer(c_size_t), value :: nbytes
         integer(c_int), value :: flags
         integer(c_ptrdiff_t) :: sent
      end function c_send

      function c_shutdown(fd, how) bind(C, name='shutdown') result(rc)
         import :: c_int
         integer(c_int), value :: fd, how
         integer(c_int) :: rc
      end function c_shutdown

      function c_close(fd) bind(C, name='close') result(rc)
         import :: c_int
         integer(c_int), value :: fd
         integer(c_int) :: rc
      end function c_close
   end interface
end module hc_libc

module hc_page
   use assets
   implicit none

   character(len=*), parameter :: language = 'Fortran'
   character(len=*), parameter :: branch = 'fortran'
   character(len=*), parameter :: repo_url = 'https://github.com/artisan-build/hello_cloud'

contains

   ! Turns one of the generated hex chunk arrays back into the bytes it came from.
   function unhex(chunks, nchunks, nbytes) result(out)
      character(len=asset_chunk), intent(in) :: chunks(*)
      integer, intent(in) :: nchunks, nbytes
      character(len=:), allocatable :: out
      character(len=:), allocatable :: hex
      integer :: i, hi, lo

      allocate (character(len=nchunks*asset_chunk) :: hex)
      do i = 1, nchunks
         hex((i - 1)*asset_chunk + 1:i*asset_chunk) = chunks(i)
      end do

      allocate (character(len=nbytes) :: out)
      do i = 1, nbytes
         hi = nibble(hex(2*i - 1:2*i - 1))
         lo = nibble(hex(2*i:2*i))
         out(i:i) = achar(16*hi + lo)
      end do
   end function unhex

   integer function nibble(c)
      character(len=1), intent(in) :: c
      if (c >= '0' .and. c <= '9') then
         nibble = iachar(c) - iachar('0')
      else
         nibble = iachar(c) - iachar('a') + 10
      end if
   end function nibble

   function replace_all(source, pattern, by) result(out)
      character(len=*), intent(in) :: source, pattern, by
      character(len=:), allocatable :: out
      integer :: pos, from

      out = ''
      from = 1
      do
         pos = index(source(from:), pattern)
         if (pos == 0) exit
         out = out//source(from:from + pos - 2)//by
         from = from + pos - 1 + len(pattern)
      end do
      out = out//source(from:)
   end function replace_all

   ! Fills the shared template's seven placeholders.
   !
   ! og:image and og:url have to be absolute, so they are built from the
   ! request's Host header with a hard-coded https scheme: Cloud terminates TLS
   ! upstream and then sends `X-Forwarded-Proto: http` on an https request, so
   ! that header cannot be trusted.
   function render_page(template, index_url, host) result(out)
      character(len=*), intent(in) :: template, index_url, host
      character(len=:), allocatable :: out

      out = replace_all(template, '{{LANGUAGE}}', language)
      out = replace_all(out, '{{BRANCH_URL}}', repo_url//'/tree/'//branch)
      out = replace_all(out, '{{BRANCH}}', branch)
      out = replace_all(out, '{{OG_IMAGE}}', 'https://'//host//'/og.png')
      out = replace_all(out, '{{PAGE_URL}}', 'https://'//host//'/')
      out = replace_all(out, '{{INDEX_URL}}', index_url)
      out = replace_all(out, '{{EXTRA}}', '')
   end function render_page

end module hc_page

program app
   use iso_c_binding
   use iso_fortran_env, only: output_unit, error_unit
   use hc_libc
   use hc_page
   use assets
   implicit none

   character(len=2), parameter :: crlf = achar(13)//achar(10)
   character(len=:), allocatable :: template, index_url, og, body, head, host, target
   character(kind=c_char) :: sa(28), yes(4), tv(16)
   character(kind=c_char) :: buf(16384)
   integer(c_int) :: listener, client, rc
   integer(c_ptrdiff_t) :: got
   integer :: port, used, blank, eol, sp1, sp2, hpos, i, qpos
   character(len=:), allocatable :: text, lowered

   template = unhex(page_html_hex, page_html_chunks, page_html_bytes)
   index_url = chomp(unhex(index_url_hex, index_url_chunks, index_url_bytes))
   og = unhex(og_png_hex, og_png_chunks, og_png_bytes)
   port = listen_port()

   listener = c_socket(AF_INET6, SOCK_STREAM, 0_c_int)
   if (listener < 0) then
      write (error_unit, '(a)') 'hello_cloud: socket() failed'
      stop 1
   end if

   yes = [achar(1), achar(0), achar(0), achar(0)]
   rc = c_setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, yes, 4_c_int)

   ! struct sockaddr_in6, laid out by hand: family (2 bytes, host order),
   ! port (2 bytes, network order), flowinfo (4), addr (16, all zero for
   ! in6addr_any), scope_id (4). Cloud's per-instance nginx reaches the app over
   ! IPv6, and an IPv6 wildcard socket is dual-stack on Linux, so IPV6_V6ONLY is
   ! deliberately left alone.
   do i = 1, 28
      sa(i) = achar(0)
   end do
   sa(1) = achar(AF_INET6)
   sa(3) = achar(port/256)
   sa(4) = achar(modulo(port, 256))

   if (c_bind(listener, sa, 28_c_int) /= 0) then
      write (error_unit, '(a)') 'hello_cloud: bind([::]) failed'
      stop 1
   end if
   if (c_listen(listener, 128_c_int) /= 0) then
      write (error_unit, '(a)') 'hello_cloud: listen() failed'
      stop 1
   end if

   write (output_unit, '(a,i0)') 'hello_cloud: hello from '//language//', serving on [::]:', port
   flush (output_unit)

   do
      client = c_accept(listener, c_null_ptr, c_null_ptr)
      if (client < 0) cycle

      ! One connection at a time: both routes answer from memory. A five second
      ! receive timeout (struct timeval, 8 bytes of seconds then 8 of
      ! microseconds) keeps a client that connects and says nothing from parking
      ! the loop for good.
      do i = 1, 16
         tv(i) = achar(0)
      end do
      tv(1) = achar(5)
      rc = c_setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, tv, 16_c_int)

      used = 0
      do
         got = c_recv(client, buf(used + 1), int(size(buf) - used, c_size_t), 0_c_int)
         if (got <= 0) exit
         used = used + int(got)
         if (used >= size(buf)) exit
         if (index(bytes_to_string(buf, used), crlf//crlf) > 0) exit
      end do

      if (used == 0) then
         rc = c_close(client)
         cycle
      end if

      text = bytes_to_string(buf, used)
      lowered = lower(text)

      eol = index(text, crlf)
      if (eol == 0) eol = len(text) + 1
      target = ''
      sp1 = index(text(1:eol - 1), ' ')
      if (sp1 > 0) then
         sp2 = index(text(sp1 + 1:eol - 1), ' ')
         if (sp2 == 0) then
            target = text(sp1 + 1:eol - 1)
         else
            target = text(sp1 + 1:sp1 + sp2 - 1)
         end if
      end if

      ! Shared links arrive with ?fbclid=... or #frag appended. Route on the
      ! path alone, so /?x=1 is still the page and /og.png?x=1 still the card.
      qpos = scan(target, '?#')
      if (qpos > 0) target = target(1:qpos - 1)

      host = 'localhost'
      hpos = index(lowered, achar(10)//'host:')
      if (hpos > 0) then
         i = index(text(hpos + 6:), crlf)
         if (i == 0) then
            host = trim(adjustl(text(hpos + 6:)))
         else
            host = trim(adjustl(text(hpos + 6:hpos + 4 + i)))
         end if
         if (len(host) == 0) host = 'localhost'
      end if

      if (target == '/og.png') then
         head = 'HTTP/1.1 200 OK'//crlf//'content-type: image/png'//crlf// &
                'content-length: '//itoa(len(og))//crlf// &
                'cache-control: public, max-age=3600'//crlf// &
                'connection: close'//crlf//crlf
         call send_all(client, head)
         call send_all(client, og)
      else if (target == '/') then
         body = render_page(template, index_url, host)
         head = 'HTTP/1.1 200 OK'//crlf//'content-type: text/html; charset=utf-8'//crlf// &
                'content-length: '//itoa(len(body))//crlf// &
                'connection: close'//crlf//crlf
         call send_all(client, head//body)
      else
         body = 'not found'//achar(10)
         head = 'HTTP/1.1 404 Not Found'//crlf//'content-type: text/plain; charset=utf-8'//crlf// &
                'content-length: '//itoa(len(body))//crlf// &
                'connection: close'//crlf//crlf
         call send_all(client, head//body)
      end if

      rc = c_shutdown(client, SHUT_WR)
      rc = c_close(client)
   end do

contains

   ! trim() only strips blanks, and shared/index-url.txt ends in a newline.
   function chomp(s) result(out)
      character(len=*), intent(in) :: s
      character(len=:), allocatable :: out
      integer :: first, last
      first = 1
      last = len(s)
      do while (first <= last)
         if (iachar(s(first:first)) > 32) exit
         first = first + 1
      end do
      do while (last >= first)
         if (iachar(s(last:last)) > 32) exit
         last = last - 1
      end do
      out = s(first:last)
   end function chomp

   function bytes_to_string(b, n) result(s)
      character(kind=c_char), intent(in) :: b(*)
      integer, intent(in) :: n
      character(len=:), allocatable :: s
      integer :: k
      allocate (character(len=n) :: s)
      do k = 1, n
         s(k:k) = b(k)
      end do
   end function bytes_to_string

   function lower(s) result(out)
      character(len=*), intent(in) :: s
      character(len=:), allocatable :: out
      integer :: k, c
      out = s
      do k = 1, len(s)
         c = iachar(s(k:k))
         if (c >= 65 .and. c <= 90) out(k:k) = achar(c + 32)
      end do
   end function lower

   function itoa(n) result(s)
      integer, intent(in) :: n
      character(len=:), allocatable :: s
      character(len=16) :: tmp
      write (tmp, '(i0)') n
      s = trim(tmp)
   end function itoa

   subroutine send_all(fd, data)
      integer(c_int), intent(in) :: fd
      character(len=*), intent(in) :: data
      character(kind=c_char), allocatable :: raw(:)
      integer(c_ptrdiff_t) :: sent
      integer :: total, k

      allocate (raw(len(data)))
      do k = 1, len(data)
         raw(k) = data(k:k)
      end do
      total = 0
      do while (total < len(data))
         sent = c_send(fd, raw(total + 1), int(len(data) - total, c_size_t), MSG_NOSIGNAL)
         if (sent <= 0) exit
         total = total + int(sent)
      end do
   end subroutine send_all

   integer function listen_port()
      character(len=32) :: raw
      integer :: status, value
      listen_port = 3000
      call get_environment_variable('PORT', raw, status=status)
      if (status /= 0) return
      read (raw, *, iostat=status) value
      if (status == 0 .and. value > 0 .and. value < 65536) listen_port = value
   end function listen_port

end program app
