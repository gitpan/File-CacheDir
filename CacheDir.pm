#!/usr/bin/perl -w

package File::CacheDir; 

use strict;
use vars qw(@ISA @EXPORT_OK $VERSION);
use Exporter;
@ISA = ('Exporter');
@EXPORT_OK  = qw( cache_dir );
$VERSION = "0.13";

use File::Path qw(mkpath rmtree);

sub new {
  my $type = shift;
  my $hash_ref = $_[0];
  my @PASSED_ARGS = (ref $hash_ref eq 'HASH') ? %{$_[0]} : @_;
  my $cache_object;
  my @DEFAULT_ARGS = (
    filename => time . ".$$",
    ttl      => "1 day",
    base_dir => "/tmp/cache_dir",
  );
  my %ARGS = (@DEFAULT_ARGS, @PASSED_ARGS);
  $cache_object = bless \%ARGS, $type;

  $cache_object->{ttl_mkpath} = sub {
    my $_ttl_dir = shift;
    mkpath $_ttl_dir;
    die "couldn't mkpath '$_ttl_dir': $!" unless(-d $_ttl_dir);
  } unless(defined $cache_object->{ttl_mkpath} && ref $cache_object->{ttl_mkpath});

  $cache_object->{expired_check} = sub {
    my $_sub_dir = shift;
    my $diff = $cache_object->{int_time} - $_sub_dir;
    if($diff > 2) {
      return 1;
    } else {
      return 0;
    }
  } unless(defined $cache_object->{expired_check} && ref $cache_object->{expired_check});

  $cache_object->{cleanup} = sub {
    my $_dir = shift;
    File::Path::rmtree( $_dir );
  } unless(defined $cache_object->{cleanup} && ref $cache_object->{cleanup});

  $cache_object->{sub_mkdir} = sub {
    my $_dir = shift;
    mkdir $_dir, 0755;
    die "couldn't mkpath '$_dir': $!" unless(-d $_dir);
  } unless(defined $cache_object->{sub_mkdir} && ref $cache_object->{sub_mkdir});

  return $cache_object;
}

sub cache_dir {
  my $self = $_[0];
  unless(ref $self eq __PACKAGE__) {
    $self = new File::CacheDir(@_);
  }
  
  $self->{ttl} =~ s/^(\d+)\s*(\w+)$/$1/;
  $self->{ttl} =  $1 if defined $1;
  my $units = (defined $2) ? $2 : '';
  if(($units =~ /^s/i) || (!$units)) {
    $self->{ttl} = $self->{ttl};
  } elsif ($units =~ /^m/i) {
    $self->{ttl} *= 60;
  } elsif ($units =~ /^h/i) {
    $self->{ttl} *= 3600;
  } elsif ($units =~ /^d/i) {
    $self->{ttl} *= 86400;
  } elsif ($units =~ /^w/i) {
    $self->{ttl} *= 604800;
  } else {
     die "invalid ttl '$self->{ttl}', bad units '$units'";
  }

  $self->{base_dir} .= '/' unless($self->{base_dir} =~ m@/$@);
  my $ttl_dir = "$self->{base_dir}$self->{ttl}/";

  unless(-d $ttl_dir) {
    &{$self->{ttl_mkpath}}($ttl_dir);
  }

  $self->{int_time} ||= (int(time/$self->{ttl}));
  my $dir = "$ttl_dir$self->{int_time}/";

  if(-d $dir) {
    return "$dir$self->{filename}";
  } else {
    ### This is where the BACKGROUND will go
    opendir(DIR, $ttl_dir);
    while (my $sub_dir = readdir(DIR)) {
      next if($sub_dir =~ /^\.\.?$/);
      
      if($self->{expired_check} && &{$self->{expired_check}}($sub_dir)) {
    
        &{$self->{cleanup}}("$ttl_dir$sub_dir");
      }
    }
    closedir(DIR);
    &{$self->{sub_mkdir}}($dir);
    return "$dir$self->{filename}";
  }
}
