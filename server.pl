#!/usr/bin/perl
# Hello from Perl, on Laravel Cloud's Go runtime.
#
# Laravel Cloud runs this binary because the branch carries a go.mod at its
# root, so the environment was detected as Go when it was created and Cloud
# starts whatever executable the build command left at ./app. Nothing Go is
# compiled: the build command downloads the binary GitHub Actions built from
# this commit.
#
# What ./app actually is: this script, Mojolicious, and the whole perl
# interpreter packed into one executable by PAR::Packer (`pp`). Debian 12 needs
# no perl installed for it to run.
#
# The shared template, the shared index URL and the OG card are compiled into
# Payload.pm by build.sh, so nothing is read from Cloud's ephemeral filesystem.
use strict;
use warnings;
use Mojolicious::Lite -signatures;
use Socket qw(AF_INET6 SOCK_STREAM SOMAXCONN SOL_SOCKET SO_REUSEADDR
    pack_sockaddr_in6 IN6ADDR_ANY);
use Payload qw(TEMPLATE INDEX_URL OG_PNG);

my $LANGUAGE = 'Perl';
my $BRANCH   = 'perl';
my $REPO_URL = 'https://github.com/artisan-build/hello_cloud';

# Mojolicious logs to STDERR at `info` by default, which is where Cloud's log
# collector reads from.
app->log->level('info');

get '/' => sub ($c) {
    # og:image and og:url have to be absolute, and the scheme is hard-coded:
    # Cloud terminates TLS upstream and then sends X-Forwarded-Proto: http on
    # an https request, so that header cannot be trusted.
    my $host = $c->req->headers->host // 'localhost';
    $host =~ s/[^A-Za-z0-9.:\[\]-]//g;
    my $base = "https://$host";

    my %v = (
        LANGUAGE   => $LANGUAGE,
        BRANCH     => $BRANCH,
        BRANCH_URL => "$REPO_URL/tree/$BRANCH",
        OG_IMAGE   => "$base/og.png",
        PAGE_URL   => "$base/",
        INDEX_URL  => INDEX_URL,
        EXTRA      => '',
    );

    my $body = TEMPLATE;
    $body =~ s/\{\{([A-Z_]+)\}\}/exists $v{$1} ? $v{$1} : ''/ge;

    $c->res->headers->content_type('text/html; charset=utf-8');
    $c->render(data => $body);
};

get '/og.png' => sub ($c) {
    $c->res->headers->content_type('image/png');
    $c->res->headers->cache_control('public, max-age=3600');
    $c->render(data => OG_PNG);
};

my $port = $ENV{PORT} || 3000;

# Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
# network, so the listening socket has to be the dual-stack IPv6 wildcard.
#
# It is created here, by hand, rather than by passing `-l http://[::]:$port`:
# Mojo binds through IO::Socket::IP, which resolves the address with
# getaddrinfo(), and getaddrinfo's default AI_ADDRCONFIG drops every IPv6
# result on a host that has no routable IPv6 address of its own. In a container
# without IPv6 -- which is both GitHub's runner and a plain `docker run` -- that
# turns `[::]` into "Address family for hostname not supported" and the daemon
# exits 22. socket()/bind() with in6addr_any asks the kernel directly, which
# has no such opinion, and IPV6_V6ONLY is left at the Linux default of off, so
# one socket answers both families.
socket(my $sock, AF_INET6, SOCK_STREAM, 0) or die "hello_cloud: socket: $!";
setsockopt($sock, SOL_SOCKET, SO_REUSEADDR, pack('l', 1))
    or die "hello_cloud: setsockopt: $!";
bind($sock, pack_sockaddr_in6($port, IN6ADDR_ANY)) or die "hello_cloud: bind: $!";
listen($sock, SOMAXCONN) or die "hello_cloud: listen: $!";

# Mojo::Server::Daemon takes an already-listening descriptor as ?fd=N; the host
# and port in the URL are then only what it prints.
my $fd = fileno $sock;
print "hello_cloud: hello from $LANGUAGE, serving on [::]:$port (fd $fd)\n";
app->start('daemon', '-l', "http://[::]:$port?fd=$fd", '-m', 'production');
