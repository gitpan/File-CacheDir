#!/usr/bin/perl -w

package File::CacheDir; 

use strict;
use vars qw(@ISA @EXPORT_OK $VERSION);
use Exporter;
@ISA = ('Exporter');
@EXPORT_OK  = qw( cache_dir );
$VERSION = "0.11";

use Getopt::GetArgs;
use File::Path qw(mkpath rmtree);
use Carp qw(croak);

sub new {
  my $type = shift;
  my $hash_ref = $_[0];
  my @DEFAULT_ARGS = (
    filename => time . ".$$",
    ttl      => "1 day",
    base_dir => "/tmp/cache_dir",
  );
  my $cache_object = bless {GetArgs(@_, @DEFAULT_ARGS)}, $type;
  return $cache_object;
}

sub cache_dir {
  my $self = $_[0];
  if(!ref($self) || ref $self eq 'HASH') {
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
     croak "invalid ttl '$self->{ttl}', bad units '$units'";
  }

  $self->{base_dir} .= '/' unless $self->{base_dir} =~ m@/$@;
  my $ttl_dir = "$self->{base_dir}$self->{ttl}/";

  unless(-d $ttl_dir) {
    $self->{ttl_mkpath} = sub {
      mkpath $ttl_dir;
      die "couldn't mkpath '$ttl_dir': $!" unless(-d $ttl_dir);
    } unless(defined $self->{ttl_mkpath} && ref $self->{ttl_mkpath});

    &{$self->{ttl_mkpath}};
  }

  $self->{int_time} ||= (int(time/$self->{ttl}));
  my $dir = "$ttl_dir$self->{int_time}/";

  if(-d $dir) {
    return "$dir$self->{filename}";
  } else {
    ### This is where the BACKGROUND will go
    opendir(DIR, $ttl_dir);
    while (my $sub_dir = readdir(DIR)) {
      next if($sub_dir =~ /^..?$/);
      if($self->{int_time} - $sub_dir > 2) {
        $self->{cleanup} = sub {
          File::Path::rmtree( "$ttl_dir$sub_dir" );
        } unless(defined $self->{cleanup} && ref $self->{cleanup});
    
        &{$self->{cleanup}};
      }
    }
    closedir(DIR);
    $self->{sub_mkdir} = sub {
      mkdir $dir, 0755;
      die "couldn't mkpath '$dir': $!" unless(-d $dir);
    } unless(defined $self->{sub_mkdir} && ref $self->{sub_mkdir});
    &{$self->{sub_mkdir}};
    return "$dir$self->{filename}";
  }
}
