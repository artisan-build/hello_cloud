#!/bin/sh
# Builds ./app: this branch's Mojolicious app, Mojolicious itself and the perl
# interpreter packed into one executable by PAR::Packer.
#
# Run by GitHub Actions inside the image lang.json names, at the repo root, as
# root. Nothing here runs on Laravel Cloud -- Cloud's build command only
# downloads the finished binary.
set -eux

# --notest keeps the install inside a few minutes; both distributions are
# heavily used and their test suites are not what is being proven here.
cpanm --quiet --notest Mojolicious PAR::Packer

# The three payloads become a module, so the packed binary reads nothing from
# the deployed tree.
perl genpayload.pl > Payload.pm
perl -c Payload.pm

# Mojolicious loads a lot of itself at run time -- Mojolicious::Lite alone pulls
# in the HeaderCondition, DefaultHelpers, TagHelpers, EPRenderer, EPLRenderer
# and Config plugins through a string eval, and the `daemon` command the same
# way. pp's static dependency scan finds none of that, and the first missing
# one aborts the packed binary at startup with
# `Plugin "HeaderCondition" missing`. So every .pm in the two distribution
# trees is named explicitly, which is ~150 modules and costs about 2 MB.
MOJO_LIB=$(perl -MMojolicious -e 'print $INC{"Mojolicious.pm"} =~ s{/Mojolicious\.pm$}{}r')
set -- -I . -M Payload
for m in $(cd "$MOJO_LIB" && find Mojo Mojolicious -name '*.pm' | sed 's|/|::|g; s|\.pm$||'); do
    set -- "$@" -M "$m"
done
# Mojolicious finds its own resources (the exception/not-found templates, the
# favicon) relative to Mojolicious.pm, which under PAR means the extracted
# cache directory -- so they have to travel inside the archive at that path.
set -- "$@" -a "$MOJO_LIB/Mojolicious/resources;lib/Mojolicious/resources"

pp "$@" -o app server.pl

ls -l app
