use strict;
use warnings;

package XPAN::Injector::VCS;

use Moose::Role;
with qw(XPAN::Helper XPAN::Injector);

use File::Temp ();
use File::pushd;

requires qw(export_to_dir);

sub url_to_file {
  my ($self, $url) = @_;

  my $export_dir = File::Temp::tempdir(CLEANUP => 1);

  $self->export_to_dir($url => $export_dir);

  my $dist;
  {
    my $dir = pushd($export_dir);

    my $builder = 
      -e 'Build.PL'    ? 'build_pl' :
      -e 'Makefile.PL' ? 'make_pl' :
      die "Can't find either Build.PL or Makefile.PL in $export_dir from $url";

    my $dist_dir = $self->$builder;
    my ($suffix) = grep { -e "$dist_dir$_" } qw(.tar.gz .tgz .zip)
      or die "Can't find dist in $export_dir from $url ($dist_dir)";
    $dist = "$dist_dir$suffix";
  }

  return Path::Class::dir($export_dir)->file($dist)->stringify;
}

sub perl_run {
  my $self = shift;
  system("$^X @_ >/dev/null") && die "Error running @_: nonzero exit $?";
}

sub build_pl {
  my ($self) = @_;
  $self->perl_run('Build.PL');
  my $out = `./Build dist`;
  my ($dist) = grep { $_ ne 'META.yml' }
    $out =~ m{^Creating (\S+)$}m;
  return $dist;
}

sub make_pl {
  my ($self) = @_;
  $self->perl_run('Makefile.PL');
  my $out = `make dist`;
  my ($dist) = $out =~ m{^mkdir ([^\n/]+)$}m;
  return $dist;
}

1;