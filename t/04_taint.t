#!/usr/bin/perl -T -w
use strict;
use Test;

use File::CacheDir;
use IO::File;
use Carp;
$SIG{__WARN__} = \&cluck;
$SIG{__DIE__} = \&confess;

my $backoff = 5;
plan tests => $backoff+1;

my $cacher;
my $pause = 2;
for (1..$backoff) {
  $cacher = new File::CacheDir {
    carry_forward => 1,
    base_dir => "/tmp/make_test_file_cache_dir_dir",
    filename => "taint.$$",
    ttl      => "3 Seconds",
    periods_to_keep => 1,
  };
  ok (IO::File->new($cacher->cache_dir(), "w")->close());
} continue {
  sleep ($pause = int($pause*1.5));
}

$cacher->cleanup("/tmp/make_test_file_cache_dir_dir");
ok 1;
