#!/usr/bin/perl -w
use strict;
use Test;

BEGIN { plan tests => 2}
use File::CacheDir qw(cache_dir);

my $filename = cache_dir({
  ttl      => '3 hours',
  filename => 'example.' . time . ".$$",
});

`touch $filename`;
ok(-e $filename);
ok(unlink $filename);
