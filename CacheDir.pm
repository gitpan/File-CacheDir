#!/usr/bin/perl -w

package File::CacheDir; 

use strict;
use vars qw(@ISA @EXPORT_OK $VERSION);
use Exporter;
@ISA = ('Exporter');
@EXPORT_OK  = qw( cache_dir );
$VERSION = "0.14";

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

__END__

=head1 NAME

File::CacheDir - Perl module to aid in keeping track and cleaning up files, quickly and without a cron
$Id: CacheDir.pod,v 1.2 2001/06/11 17:01:36 earl Exp $

=head1 SYNOPSIS

CacheDir takes up to three parameters and returns a fully qualified filename.
Cool part is that it quickly and automatically cleans up files that are too old.

=head1 ARGUMENTS

The possible named arguments (which can be named or sent in a hash ref,
 see below for an example) are,

filename - which is what you want the file 
           without the directory to be named, 
           like "storebuilder" . time . $$
           I would suggest using a script 
           specific word (like the name of the cgi), 
           time and $$ (which is the pid number) 
           in the filename, just so files 
           are easy to track and the filenames 
           are pretty unique
           
ttl      - how long you want the file to stick around
           can be given in seconds (3600) or like "1 hour" 
           or "1 day" or even "1 week"
           
base_dir - the base directory, like /tmp

=head1 CODE REF OVERRIDES

Most of the time, the defaults will suffice, but by having code refs
in your object, you can override most everything CacheDir does.  To
how the code refs are used, I walk through the code with a simple example.

my $cache_dir = new File::CacheDir({
  base_dir => '/tmp/example',
  ttl      => '2 hours',
  filename => 'example.' . time . ".$$",
});

An object gets created, with the hash passed getting blessed in.

my $filename = $cache_dir->cache_dir;

The ttl gets converted to seconds, here 7200.  The 

$ttl_dir = $base_dir . $ttl;

In our example, $ttl_dir = "/tmp/example/7200"; 

$self->{ttl_mkpath} - if the ttl directory doesn't exist, it gets made with this code ref 

Next, the number of ttl units since epoch, here it is something like 137738.  This is

$self->{int_time} = int(time/$self->{ttl});

Now, the full directory can be formed

$dir = $ttl_dir . $self->{int_time};

If $dir exists, $dir . $self->{filename} gets returned.  Otherwise, I look through
the $ttl_dir, and for each directory that is too old (more than two units away) I run

$self->{cleanup} - just deletes the old directory, but this is where a backup could take place,
or whatever you like

Finally, I

$self->{sub_mkdir} - makes the new directory, $dir

and return the $filename

=head1 SIMPLE EXAMPLE

  #!/usr/bin/perl -w

  use strict;
  use File::CacheDir qw(cache_dir);

  my $filename = cache_dir({
    base_dir => '/tmp',
    ttl      => '2 hours',
    filename => 'example.' . time . ".$$",
  });

  `touch $filename`;
