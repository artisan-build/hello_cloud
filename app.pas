{ Hello from Pascal, on Laravel Cloud's Go runtime.

  Laravel Cloud runs this binary because the branch carries a `go.mod` at its
  root, so the environment was detected as Go when it was created and Cloud
  starts whatever executable the build command left at `./app`. No Go is
  compiled for this branch; the build command downloads the binary that GitHub
  Actions built from this commit.

  Free Pascal 3.2.2 ships a real HTTP server (`fphttpserver`), and this program
  deliberately does NOT use it: that unit listens through `ssockets.TInetServer`,
  which creates its socket with `AF_INET` and keeps a `TInetSockAddr` -- IPv4
  only -- and `TFPCustomHttpServer.FServer` is in a `private` section, so the
  listening socket cannot be substituted from another unit. Cloud's per-instance
  nginx reaches the app over IPv6, so the listener has to be the dual-stack
  IPv6 wildcard. Hence the whole web layer here is the RTL `Sockets` unit plus
  about a hundred lines of HTTP.

  Both the shared HTML template and the OG card are linked in as an object file
  (`ld -r -b binary`), so nothing is read from disk: Cloud's filesystem is
  ephemeral. }
program app;

{$mode objfpc}
{$H+}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, Sockets;

{ The three build-time assets, turned into one relocatable object by
  `ld -r -b binary page.html index_url.txt og.png -o assets.o`. Each input
  gives ld a _start/_end pair of symbols; the length is the gap between them. }
{$L assets.o}
var
  page_html_start: Byte; external name '_binary_page_html_start';
  page_html_end: Byte; external name '_binary_page_html_end';
  index_url_start: Byte; external name '_binary_index_url_txt_start';
  index_url_end: Byte; external name '_binary_index_url_txt_end';
  og_png_start: Byte; external name '_binary_og_png_start';
  og_png_end: Byte; external name '_binary_og_png_end';

const
  Language = 'Pascal';
  BranchName = 'pascal';
  RepoUrl = 'https://github.com/artisan-build/hello_cloud';

  { Linux/aarch64 values. Spelled out rather than imported so the program does
    not depend on which platform include defines them. }
  AfInet6 = 10;
  SolSocket = 1;
  SoReuseAddr = 2;
  SockStream = 1;
  EIntr = 4;

var
  PageTemplate: AnsiString;
  IndexUrl: AnsiString;
  OgPng: AnsiString;

function BlobToString(First, Last: Pointer): AnsiString;
var
  Len: PtrUInt;
begin
  Len := PtrUInt(Last) - PtrUInt(First);
  SetLength(Result, Len);
  if Len > 0 then
    Move(First^, Result[1], Len);
end;

function ListenPort: Word;
var
  Raw: string;
  Value: LongInt;
begin
  Raw := GetEnvironmentVariable('PORT');
  if (Raw = '') or not TryStrToInt(Raw, Value) or (Value <= 0) or (Value > 65535) then
    Result := 3000
  else
    Result := Word(Value);
end;

{ Fills the shared template's seven placeholders.

  og:image and og:url have to be absolute, so they are built from the request's
  Host header with a hard-coded https scheme: Cloud terminates TLS upstream and
  then sends `X-Forwarded-Proto: http` on an https request, so that header
  cannot be trusted. }
function RenderPage(const Host: AnsiString): AnsiString;
begin
  Result := PageTemplate;
  Result := StringReplace(Result, '{{LANGUAGE}}', Language, [rfReplaceAll]);
  Result := StringReplace(Result, '{{BRANCH_URL}}', RepoUrl + '/tree/' + BranchName, [rfReplaceAll]);
  Result := StringReplace(Result, '{{BRANCH}}', BranchName, [rfReplaceAll]);
  Result := StringReplace(Result, '{{OG_IMAGE}}', 'https://' + Host + '/og.png', [rfReplaceAll]);
  Result := StringReplace(Result, '{{PAGE_URL}}', 'https://' + Host + '/', [rfReplaceAll]);
  Result := StringReplace(Result, '{{INDEX_URL}}', IndexUrl, [rfReplaceAll]);
  Result := StringReplace(Result, '{{EXTRA}}', '', [rfReplaceAll]);
end;

procedure SendAll(Sock: LongInt; const Data: AnsiString);
var
  Sent, Total, Len: PtrInt;
begin
  Total := 0;
  Len := Length(Data);
  while Total < Len do
  begin
    Sent := fpSend(Sock, @Data[Total + 1], Len - Total, 0);
    if Sent <= 0 then
      Exit;
    Total := Total + Sent;
  end;
end;

procedure Respond(Sock: LongInt; const Status, ContentType, ExtraHeaders, Body: AnsiString);
begin
  SendAll(Sock,
    'HTTP/1.1 ' + Status + #13#10 +
    'content-type: ' + ContentType + #13#10 +
    'content-length: ' + IntToStr(Length(Body)) + #13#10 +
    ExtraHeaders +
    'connection: close' + #13#10#13#10 + Body);
end;

{ Reads the request line and headers (never the body: neither route has one),
  then answers. }
function HandleConnection(Parameter: Pointer): PtrInt;
var
  Sock: LongInt;
  Buf: array[0..8191] of Byte;
  Got, Used: PtrInt;
  Head, Line, Target, Host, Lowered: AnsiString;
  Blank, Space1, Space2, Colon, Eol: SizeInt;
begin
  Result := 0;
  Sock := LongInt(PtrUInt(Parameter));
  Used := 0;
  Blank := 0;
  { Read until the end of the headers, or until the buffer is full. }
  while Used < SizeOf(Buf) do
  begin
    Got := fpRecv(Sock, @Buf[Used], SizeOf(Buf) - Used, 0);
    if Got <= 0 then
      Break;
    Used := Used + Got;
    SetLength(Head, Used);
    Move(Buf[0], Head[1], Used);
    Blank := Pos(#13#10#13#10, Head);
    if Blank > 0 then
      Break;
  end;
  if Used = 0 then
  begin
    CloseSocket(Sock);
    Exit;
  end;
  SetLength(Head, Used);
  Move(Buf[0], Head[1], Used);

  Eol := Pos(#13#10, Head);
  if Eol = 0 then
    Eol := Length(Head) + 1;
  Line := Copy(Head, 1, Eol - 1);
  Space1 := Pos(' ', Line);
  Target := '';
  if Space1 > 0 then
  begin
    Target := Copy(Line, Space1 + 1, Length(Line));
    Space2 := Pos(' ', Target);
    if Space2 > 0 then
      Target := Copy(Target, 1, Space2 - 1);
  end;

  Host := 'localhost';
  Lowered := LowerCase(Head);
  Colon := Pos(#10'host:', Lowered);
  if Colon > 0 then
  begin
    Host := Copy(Head, Colon + 6, Length(Head));
    Eol := Pos(#13#10, Host);
    if Eol > 0 then
      Host := Copy(Host, 1, Eol - 1);
    Host := Trim(Host);
    if Host = '' then
      Host := 'localhost';
  end;

  if Target = '/og.png' then
    Respond(Sock, '200 OK', 'image/png', 'cache-control: public, max-age=3600'#13#10, OgPng)
  else if Target = '/' then
    Respond(Sock, '200 OK', 'text/html; charset=utf-8', '', RenderPage(Host))
  else
    Respond(Sock, '404 Not Found', 'text/plain; charset=utf-8', '', 'not found'#10);

  fpShutdown(Sock, 1);
  CloseSocket(Sock);
end;

var
  Listener, Client: LongInt;
  Addr: TInetSockAddr6;
  Peer: TInetSockAddr6;
  PeerLen: TSockLen;
  One: LongInt;
  Port: Word;
begin
  PageTemplate := BlobToString(@page_html_start, @page_html_end);
  IndexUrl := Trim(BlobToString(@index_url_start, @index_url_end));
  OgPng := BlobToString(@og_png_start, @og_png_end);

  Port := ListenPort;

  { Cloud's per-instance nginx proxies to the app over an IPv6 loopback.
    Binding the IPv6 wildcard is dual-stack on Linux, so this one listener
    answers IPv4 and IPv6 both; IPV6_V6ONLY is deliberately left alone. }
  Listener := fpSocket(AfInet6, SockStream, 0);
  if Listener < 0 then
  begin
    WriteLn(StdErr, 'hello_cloud: socket() failed: ', SocketError);
    Halt(1);
  end;
  One := 1;
  fpSetSockOpt(Listener, SolSocket, SoReuseAddr, @One, SizeOf(One));

  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin6_family := AfInet6;
  Addr.sin6_port := htons(Port);   { sin6_addr all zeroes == in6addr_any }
  if fpBind(Listener, psockaddr(@Addr), SizeOf(Addr)) <> 0 then
  begin
    WriteLn(StdErr, 'hello_cloud: bind([::]:', Port, ') failed: ', SocketError);
    Halt(1);
  end;
  if fpListen(Listener, 128) <> 0 then
  begin
    WriteLn(StdErr, 'hello_cloud: listen() failed: ', SocketError);
    Halt(1);
  end;

  WriteLn('hello_cloud: hello from ', Language, ', serving on [::]:', Port);
  Flush(Output);

  while True do
  begin
    PeerLen := SizeOf(Peer);
    Client := fpAccept(Listener, psockaddr(@Peer), @PeerLen);
    if Client < 0 then
    begin
      if SocketError = EIntr then
        Continue;
      WriteLn(StdErr, 'hello_cloud: accept() failed: ', SocketError);
      Continue;
    end;
    BeginThread(@HandleConnection, Pointer(PtrUInt(Client)));
  end;
end.
