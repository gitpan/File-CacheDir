#!/usr/bin/perl -w

package File::CacheDir; 

use strict;
use vars qw(@ISA @EXPORT_OK $VERSION);
use Exporter;
use CGI qw();
use File::Path qw(mkpath rmtree);
use File::Copy qw(mv);

@ISA = ('Exporter');
@EXPORT_OK  = qw( cache_dir );
$VERSION = "1.02";

sub new {
  my $type = shift;
  my $hash_ref = $_[0];
  my @PASSED_ARGS = (ref $hash_ref eq 'HASH') ? %{$_[0]} : @_;
  my $cache_object;
  my @DEFAULT_ARGS = (
    filename        => time . $$,
    ttl             => "1 day",
    base_dir        => "/tmp/cache_dir",
    carry_forward   => 1,
    cookie_name     => "cache_dir",
    cookie_path     => '/',
    set_cookie      => 0,
    periods_to_keep => 2,
  );
  my %ARGS = (@DEFAULT_ARGS, @PASSED_ARGS);
  $cache_object = bless \%ARGS, $type;

  # clean up a few blank things in the object
  unless($cache_object->{set_cookie}) {
    foreach(qw(set_cookie cookie_name cookie_path)) {
      delete $cache_object->{$_};
    }
  }
  foreach(qw(carry_forward)) {
    delete $cache_object->{$_} unless($cache_object->{$_});
  }

  return $cache_object;
}

sub ttl_mkpath {
  my $self = shift;
  my $_ttl_dir = shift;
  mkpath $_ttl_dir;
  die "couldn't mkpath '$_ttl_dir': $!" unless(-d $_ttl_dir);
}

sub expired_check {
  my $self = shift;
  my $_sub_dir = shift;
  my $diff = $self->{int_time} - $_sub_dir;
  if($diff > $self->{periods_to_keep}) {
    return 1;
  } else {
    return 0;
  }
}

sub cleanup {
  my $self = shift;
  my $_dir = shift;
  File::Path::rmtree( $_dir );
}

sub handle_ttl {
  my $self = shift;

  if($self->{ttl} =~ /^\d+$/) {
    # do nothing
  } elsif($self->{ttl} =~ s/^(\d+)\s*(\D+)$/$1/) {
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
  } else {
    die "invalid ttl '$self->{ttl}', not just number and couldn't find units";
  }
}

sub sub_mkdir {
  my $self = shift;
  my $_dir = shift;
  mkdir $_dir, 0755;
  die "couldn't mkpath '$_dir': $!" unless(-d $_dir);
}

sub cache_dir {
  my $self = $_[0];
  unless(UNIVERSAL::isa($self, __PACKAGE__)) {
    $self = File::CacheDir->new(@_);
  }

  delete $self->{carried_forward};

  $self->handle_ttl;
  
  $self->{base_dir} =~ s@/$@@;
  my $ttl_dir = "$self->{base_dir}/$self->{ttl}/";

  unless(-d $ttl_dir) {
    $self->ttl_mkpath($ttl_dir);
  }

  $self->{int_time} = (int(time/$self->{ttl}));
  $self->{full_dir} = "$ttl_dir$self->{int_time}/";

  if($self->{carry_forward}) {
    $self->{last_int_time} = $self->{int_time} - 1;
    $self->{last_int_dir} = "$ttl_dir$self->{last_int_time}/";
    $self->{carry_forward_filename} = "$self->{last_int_dir}$self->{filename}";
    if(-f $self->{carry_forward_filename}) {
      unless(-d $self->{full_dir}) {
        $self->sub_mkdir($self->{full_dir});
        die "couldn't mkpath '$self->{full_dir}': $!" unless(-d $self->{full_dir});
      }

      $self->{full_path} = "$self->{full_dir}$self->{filename}";

      mv $self->{carry_forward_filename}, $self->{full_path};
      die "couldn't mv $self->{carry_forward_filename}, $self->{full_path}: $!" unless(-e $self->{full_path});

      $self->{carried_forward} = 1;
      
      if($self->{set_cookie}) {
        ($self->{cookie_value}) = $self->{full_path} =~ /^$self->{base_dir}(.+)/;
        $self->set_cookie;
      }
      return $self->{full_path};

    }
  }

  if(-d $self->{full_dir}) {
    $self->{full_path} = "$self->{full_dir}$self->{filename}";
    if($self->{set_cookie}) {
      ($self->{cookie_value}) = $self->{full_path} =~ /^$self->{base_dir}(.+)/;
      $self->set_cookie;
    }
    return $self->{full_path};
  } else {
    opendir(DIR, $ttl_dir);
    while (my $sub_dir = readdir(DIR)) {
      next if($sub_dir =~ /^\.\.?$/);

      if($self->expired_check($sub_dir)) {
        $self->cleanup("$ttl_dir$sub_dir");
      }
    }
    closedir(DIR);
    $self->sub_mkdir($self->{full_dir});
    die "couldn't mkpath '$self->{full_dir}': $!" unless(-d $self->{full_dir});
    $self->{full_path} = "$self->{full_dir}$self->{filename}";
    if($self->{set_cookie}) {
      ($self->{cookie_value}) = $self->{full_path} =~ /^$self->{base_dir}(.+)/;
      $self->set_cookie;
    }
    return $self->{full_path};
  }
}

sub set_cookie {
  my $self = shift;
  return unless($self->{set_cookie});
  my $old_cookie = CGI::cookie( -name => $self->{cookie_name} );
  if(!$self->{cookie_brick_over} && defined $old_cookie) {
    $self->{cookie_value} = $old_cookie;
    return $old_cookie;
  }
  $self->{cookie_value} =~ m@$self->{base_dir}(.+)@;
  my $new_cookie = CGI::cookie
    (-name  => $self->{cookie_name},
     -value => $1,
     -path  => $self->{cookie_path},
     );
  if (exists $self->{content_typed}) {
    print qq{<meta http-equiv="Set-Cookie" content="$new_cookie">\n};
  } else {
    print "Set-Cookie: $new_cookie\n";
  }
  return;
}

__END__

=head1 NAME

File::CacheDir - Perl module to aid in keeping track and cleaning up files, quickly and without a cron
$Id: CacheDir.pm,v 1.3 2002/02/19 20:41:43 earl Exp $

=head1 DESCRIPTION

CacheDir attempts to keep files around for some ttl, while
quickly, automatically and cronlessly cleaning up files that are too old.

=head1 ARGUMENTS

The possible named arguments (which can be named or sent in a hash ref,
see below for an example) are,

base_dir        - the base directory
                  default is '/tmp/cache_dir'

carry_forward   - whether or not to move forward the file 
                  when time periods get crossed.  For example,
                  if your ttl is 3600, and you move from the 
                  278711 to the 278712 hour, if carry 
                  forward is set, it will refresh a cookie 
                  (if set_cookie is true) and move the file
                  to the new location, and 
                  set $self->{carried_forward} = 1
                  default is 1

content_typed   - whether or not you have printed a 
                  Content-type header
                  default is 0

cookie_name     - the name of your cookie
                  default is 'cache_dir'

cookie_path     - the path for your cookie
                  default is '/'

filename        - what you want the file to be named 
                  (not including the directory), 
                  like "storebuilder" . time . $$
                  I would suggest using a script 
                  specific word (like the name of the cgi), 
                  time and $$ (which is the pid number) 
                  in the filename, just so files 
                  are easy to track and the filenames 
                  are pretty unique
                  default is time . $$
           
periods_to_keep - how many old periods you would like to keep

set_cookie      - whether or not to set a cookie
                  default is 0

ttl             - how long you want the file to stick around
                  can be given in seconds (3600) or like 
                  "1 hour" or "1 day" or even "1 week"
                  default is '1 day'

=head1 COOOKIES

Since CacheDir fits in so nicely with cookies, I use a few CGI methods to automatically set cookies,
retrieve the cookies, and use the cookies when applicable.  The cookie methods make it near trivial
to handle session information.  Taking the advice of Rob Brown <rbrown@about-inc.com>, I use CGI.pm,
though it increases load time and nearly doubles out of the box memory required.

The cookie that gets set is the full path of the file with your base_dir swapped out.  This makes it nice
for users to not know full path to your files.  The filename that gets returned from a cache_dir call,
however is the full path.

=head1 METHOD OVERRIDES

Most of the time, the defaults will suffice, but using your own object
methods, you can override most everything CacheDir does.  To show
which methods are used, I walk through the code with a simple example.

my $cache_dir = File::CacheDir->new({
  base_dir => '/tmp/example',
  ttl      => '2 hours',
  filename => 'example.' . time . ".$$",
});

An object gets created, with the hash passed getting blessed in.

my $filename = $cache_dir->cache_dir;

The ttl gets converted to seconds, here 7200.  The 

$ttl_dir = $base_dir . $ttl;

In our example, $ttl_dir = "/tmp/example/7200"; 

$self->ttl_mkpath - if the ttl directory does not exist, it gets made

Next, the number of ttl units since epoch, here it is something like 137738.  This is

$self->{int_time} = int(time/$self->{ttl});

Now, the full directory can be formed

$self->{full_dir} = $ttl_dir . $self->{int_time};

If $self->{full_dir} exists, $self->{full_dir} . $self->{filename} gets returned.  Otherwise, I look through
the $ttl_dir, and for each directory that is too old (more than $self->{periods_to_keep}) I run

$self->cleanup - just deletes the old directory, but this is where a backup could take place,
or whatever you like.

Finally, I

$self->sub_mkdir - makes the new directory, $self->{full_dir}

and return the $filename

=head1 SYNOPSIS

  #!/usr/bin/perl -w

  use strict;
  use File::CacheDir qw(cache_dir);

  my $filename = cache_dir({
    base_dir => '/tmp',
    ttl      => '2 hours',
    filename => 'example.' . time . ".$$",
  });

  `touch $filename`;

=head1 THANKS

Thanks to Rob Brown <rbrown@about-inc.com> for discussing general concepts, helping me think through
things, offering suggestions and doing the most recent code review.  The idea for carry_forward was pretty
well all Rob.  I didn't see a need, but Rob convinced me of one.  Since Rob first introduced the idea to
me, I have seen CacheDir break three different programmers' code.  With carry_forward, no problems.  Finally,
Rob changed my non-CGI cookie stuff to use CGI, thus avoiding many a flame war.

Thanks to Paul T Seamons <paul@seamons.com> for listening to my ideas, offerings suggestions, using CacheDir
and giving feedback.  Using File::CacheDir was all Paul's idea.  Also, the case of CacheDir and cache_dir
I owe to Paul.  Finally, thanks to Paul for the idea of this THANKS section.

Thanks to Wes Cerny <wcerny@about-inc.com> for using CacheDir, and giving feedback.  Also, thanks to Wes
for a last minute code review.  Wes had me change the existence check on $self->{carry_forward_filename} to a
plain file check based on his experience with CacheDir.
