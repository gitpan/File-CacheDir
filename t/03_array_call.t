#!/usr/bin/perl -w
use strict;
use Test;

BEGIN { plan tests => 3}
use File::CacheDir qw(cache_dir);

my $filename = cache_dir(
  base_dir => '/tmp/make_test_file_cache_dir_dir',
  filename => 'example.' . time . ".$$",
  ttl      => '3 hours',
);

`touch $filename`;
ok(-e $filename);
ok(unlink $filename);
ok(!system("rm -rf /tmp/make_test_file_cache_dir_dir"));
