--  Hello from Ada, on Laravel Cloud's Go runtime.
--
--  Laravel Cloud runs this binary because the branch carries a `go.mod` at its
--  root, so the environment was detected as Go when it was created and Cloud
--  starts whatever executable the build command left at `./app`. No Go is
--  compiled for this branch; the build command downloads the binary that GitHub
--  Actions built from this commit.
--
--  No web framework: GNAT.Sockets is the whole web layer, which is also what
--  makes the IPv6 wildcard listener Cloud needs a one-liner (Any_Inet6_Addr).
--  The shared HTML template and the OG card are linked in as a relocatable
--  object produced by `ld -r -b binary`, and mapped in place with address
--  overlays -- nothing is read from disk, because Cloud's filesystem is
--  ephemeral and nothing is copied, because the overlays alias the data
--  already in the image.
--
--  The binary is linked fully static, which is not just belt and braces:
--  Debian's gnat links the Ada runtime as `libgnat-12.so`, which exists in the
--  toolchain image and not in Cloud's runtime image, so the default dynamic
--  build dies with `error while loading shared libraries: libgnat-12.so`. Note
--  that `-static` alone does not work either -- the link line asks for
--  `-lgnat-12` while the archive Debian ships is plain `libgnat.a` -- hence the
--  symlinks the build command makes before linking.

with Ada.Environment_Variables;
with Ada.Streams;              use Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Maps;
with Ada.Strings.Maps.Constants;
with Ada.Text_IO;              use Ada.Text_IO;
with GNAT.Sockets;             use GNAT.Sockets;
with Interfaces;
with System;
with System.Storage_Elements;  use System.Storage_Elements;

procedure App is

   Language : constant String := "Ada";
   Branch   : constant String := "ada";
   Repo_Url : constant String := "https://github.com/artisan-build/hello_cloud";

   --  The three build-time assets. `ld -r -b binary page.html index_url.txt
   --  og.png -o assets.o` gives each input a _start/_end symbol pair; the
   --  length is the gap between the two addresses.
   Page_Html_Start : aliased Interfaces.Unsigned_8;
   pragma Import (C, Page_Html_Start, "_binary_page_html_start");
   Page_Html_End   : aliased Interfaces.Unsigned_8;
   pragma Import (C, Page_Html_End, "_binary_page_html_end");
   Index_Url_Start : aliased Interfaces.Unsigned_8;
   pragma Import (C, Index_Url_Start, "_binary_index_url_txt_start");
   Index_Url_End   : aliased Interfaces.Unsigned_8;
   pragma Import (C, Index_Url_End, "_binary_index_url_txt_end");
   Og_Png_Start    : aliased Interfaces.Unsigned_8;
   pragma Import (C, Og_Png_Start, "_binary_og_png_start");
   Og_Png_End      : aliased Interfaces.Unsigned_8;
   pragma Import (C, Og_Png_End, "_binary_og_png_end");

   function Span (First, Last : System.Address) return Natural is
     (Natural (To_Integer (Last) - To_Integer (First)));

   Page_Len : constant Natural := Span (Page_Html_Start'Address, Page_Html_End'Address);
   Page_Template : String (1 .. Page_Len);
   for Page_Template'Address use Page_Html_Start'Address;
   pragma Import (Ada, Page_Template);

   Index_Len : constant Natural := Span (Index_Url_Start'Address, Index_Url_End'Address);
   Index_Url_Raw : String (1 .. Index_Len);
   for Index_Url_Raw'Address use Index_Url_Start'Address;
   pragma Import (Ada, Index_Url_Raw);

   Og_Len : constant Natural := Span (Og_Png_Start'Address, Og_Png_End'Address);
   Og_Data : Stream_Element_Array (1 .. Stream_Element_Offset (Og_Len));
   for Og_Data'Address use Og_Png_Start'Address;
   pragma Import (Ada, Og_Data);

   Index_Url : constant String :=
     Ada.Strings.Fixed.Trim (Index_Url_Raw, Ada.Strings.Both);

   function Replace (Source, Pattern, By : String) return String is
      Pos : constant Natural := Ada.Strings.Fixed.Index (Source, Pattern);
   begin
      if Pos = 0 then
         return Source;
      end if;
      return Source (Source'First .. Pos - 1) & By &
             Replace (Source (Pos + Pattern'Length .. Source'Last), Pattern, By);
   end Replace;

   --  Fills the shared template's seven placeholders.
   --
   --  og:image and og:url have to be absolute, so they are built from the
   --  request's Host header with a hard-coded https scheme: Cloud terminates
   --  TLS upstream and then sends `X-Forwarded-Proto: http` on an https
   --  request, so that header cannot be trusted.
   function Render_Page (Host : String) return String is
      S1 : constant String := Replace (Page_Template, "{{LANGUAGE}}", Language);
      S2 : constant String := Replace (S1, "{{BRANCH_URL}}", Repo_Url & "/tree/" & Branch);
      S3 : constant String := Replace (S2, "{{BRANCH}}", Branch);
      S4 : constant String := Replace (S3, "{{OG_IMAGE}}", "https://" & Host & "/og.png");
      S5 : constant String := Replace (S4, "{{PAGE_URL}}", "https://" & Host & "/");
      S6 : constant String := Replace (S5, "{{INDEX_URL}}", Index_Url);
   begin
      return Replace (S6, "{{EXTRA}}", "");
   end Render_Page;

   function To_SEA (S : String) return Stream_Element_Array is
      R : Stream_Element_Array (1 .. Stream_Element_Offset (S'Length));
   begin
      for I in S'Range loop
         R (Stream_Element_Offset (I - S'First + 1)) :=
           Stream_Element (Character'Pos (S (I)));
      end loop;
      return R;
   end To_SEA;

   procedure Send_All (Socket : Socket_Type; Data : Stream_Element_Array) is
      First : Stream_Element_Offset := Data'First;
      Last  : Stream_Element_Offset;
   begin
      while First <= Data'Last loop
         Send_Socket (Socket, Data (First .. Data'Last), Last);
         exit when Last < First;
         First := Last + 1;
      end loop;
   exception
      when others =>
         null;  --  client went away mid-response; nothing useful to do
   end Send_All;

   function Head (Status, Content_Type, Extra : String; Length : Natural) return String is
     ("HTTP/1.1 " & Status & ASCII.CR & ASCII.LF &
      "content-type: " & Content_Type & ASCII.CR & ASCII.LF &
      "content-length:" & Natural'Image (Length) & ASCII.CR & ASCII.LF &
      Extra &
      "connection: close" & ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF);

   procedure Respond_Text
     (Socket : Socket_Type; Status, Content_Type, Body_Text : String) is
   begin
      Send_All (Socket, To_SEA (Head (Status, Content_Type, "", Body_Text'Length)
                                & Body_Text));
   end Respond_Text;

   procedure Respond_Og (Socket : Socket_Type) is
      Extra : constant String :=
        "cache-control: public, max-age=3600" & ASCII.CR & ASCII.LF;
   begin
      Send_All (Socket, To_SEA (Head ("200 OK", "image/png", Extra, Og_Len)));
      Send_All (Socket, Og_Data);
   end Respond_Og;

   procedure Handle (Socket : Socket_Type) is
      Buffer : Stream_Element_Array (1 .. 8192);
      Filled : Stream_Element_Offset := 0;
      Got    : Stream_Element_Offset;
      Target : String (1 .. 512);
      Target_Last : Natural := 0;
      Host   : String (1 .. 256);
      Host_Last : Natural := 0;
   begin
      --  Read the request line and the headers. Neither route has a body, so
      --  anything past the blank line is ignored.
      loop
         Receive_Socket (Socket, Buffer (Filled + 1 .. Buffer'Last), Got);
         exit when Got <= Filled;  --  Receive_Socket returns the last index written
         Filled := Got;
         exit when Filled >= Buffer'Last;
         declare
            Text : String (1 .. Natural (Filled));
         begin
            for I in 1 .. Natural (Filled) loop
               Text (I) := Character'Val (Buffer (Stream_Element_Offset (I)));
            end loop;
            exit when Ada.Strings.Fixed.Index
              (Text, ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF) > 0;
         end;
      end loop;

      if Filled = 0 then
         Close_Socket (Socket);
         return;
      end if;

      declare
         Text    : String (1 .. Natural (Filled));
         Lowered : String (1 .. Natural (Filled));
         Eol, Sp1, Sp2, H : Natural;
      begin
         for I in 1 .. Natural (Filled) loop
            Text (I) := Character'Val (Buffer (Stream_Element_Offset (I)));
         end loop;
         Lowered := Ada.Strings.Fixed.Translate
           (Text, Ada.Strings.Maps.Constants.Lower_Case_Map);

         Eol := Ada.Strings.Fixed.Index (Text, ASCII.CR & ASCII.LF);
         if Eol = 0 then
            Eol := Text'Last + 1;
         end if;
         Sp1 := Ada.Strings.Fixed.Index (Text (1 .. Eol - 1), " ");
         if Sp1 > 0 then
            Sp2 := Ada.Strings.Fixed.Index (Text (Sp1 + 1 .. Eol - 1), " ");
            if Sp2 = 0 then
               Sp2 := Eol;
            end if;
            Target_Last := Sp2 - Sp1 - 1;
            if Target_Last > Target'Last then
               Target_Last := Target'Last;
            end if;
            Target (1 .. Target_Last) := Text (Sp1 + 1 .. Sp1 + Target_Last);
         end if;

         H := Ada.Strings.Fixed.Index (Lowered, ASCII.LF & "host:");
         if H > 0 then
            declare
               Value_First : constant Natural := H + 6;
               Value_Last  : Natural :=
                 Ada.Strings.Fixed.Index (Text (Value_First .. Text'Last), ASCII.CR & ASCII.LF);
            begin
               if Value_Last = 0 then
                  Value_Last := Text'Last;
               else
                  Value_Last := Value_Last - 1;
               end if;
               if Value_Last >= Value_First then
                  declare
                     Trimmed : constant String :=
                       Ada.Strings.Fixed.Trim (Text (Value_First .. Value_Last),
                                               Ada.Strings.Both);
                  begin
                     Host_Last := Trimmed'Length;
                     if Host_Last > Host'Last then
                        Host_Last := Host'Last;
                     end if;
                     Host (1 .. Host_Last) :=
                       Trimmed (Trimmed'First .. Trimmed'First + Host_Last - 1);
                  end;
               end if;
            end;
         end if;
      end;

      if Host_Last = 0 then
         Host (1 .. 9) := "localhost";
         Host_Last := 9;
      end if;

      --  Route on the path alone. Social sites append `?fbclid=...` and
      --  `?utm_source=...`, so the query string -- and a fragment, if a client
      --  ever sends one -- is cut off the target before it is compared.
      declare
         Cut : constant Natural :=
           Ada.Strings.Fixed.Index (Target (1 .. Target_Last),
                                    Ada.Strings.Maps.To_Set ("?#"));
      begin
         if Cut > 0 then
            Target_Last := Cut - 1;
         end if;
      end;

      if Target (1 .. Target_Last) = "/og.png" then
         Respond_Og (Socket);
      elsif Target (1 .. Target_Last) = "/" then
         Respond_Text (Socket, "200 OK", "text/html; charset=utf-8",
                       Render_Page (Host (1 .. Host_Last)));
      else
         Respond_Text (Socket, "404 Not Found", "text/plain; charset=utf-8",
                       "not found" & ASCII.LF);
      end if;

      Close_Socket (Socket);
   exception
      when others =>
         begin
            Close_Socket (Socket);
         exception
            when others => null;
         end;
   end Handle;

   function Listen_Port return Port_Type is
      Raw : constant String :=
        (if Ada.Environment_Variables.Exists ("PORT")
         then Ada.Environment_Variables.Value ("PORT") else "");
   begin
      if Raw = "" then
         return 3000;
      end if;
      return Port_Type'Value (Raw);
   exception
      when others =>
         return 3000;
   end Listen_Port;

   Server : Socket_Type;
   Client : Socket_Type;
   Peer   : Sock_Addr_Type;
   Port   : constant Port_Type := Listen_Port;

begin
   --  Cloud's per-instance nginx reaches the app over IPv6, so the listener is
   --  the IPv6 wildcard. On Linux that socket is dual-stack, which is why
   --  IPv6_Only is deliberately left at the system default.
   Create_Socket (Server, Family_Inet6, Socket_Stream);
   Set_Socket_Option (Server, Socket_Level, (Reuse_Address, True));
   Bind_Socket (Server, (Family => Family_Inet6,
                         Addr   => Any_Inet6_Addr,
                         Port   => Port));
   Listen_Socket (Server, 128);

   Put_Line ("hello_cloud: hello from " & Language & ", serving on [::]:"
             & Ada.Strings.Fixed.Trim (Port_Type'Image (Port), Ada.Strings.Both));
   Flush;

   loop
      begin
         Accept_Socket (Server, Client, Peer);
         --  One connection at a time: both routes answer from memory in
         --  microseconds, and a receive timeout keeps a silent client from
         --  parking the loop.
         Set_Socket_Option (Client, Socket_Level, (Receive_Timeout, 5.0));
         Handle (Client);
      exception
         when others =>
            null;
      end;
   end loop;
end App;
