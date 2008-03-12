use strict;
use warnings;

package XPAN::PinsetChange;

use Moose;
extends 'XPAN::Object';

has pinset => (
  is => 'ro',
  weak_ref => 1,
  isa => 'XPAN::Pinset',
);

has dists => (
  is => 'ro',
  isa => 'ArrayRef[XPAN::Dist]',
  auto_deref => 1,
);

has changes => (
  is => 'ro',
  isa => 'HashRef',
  lazy => 1,
  default => sub { shift->build_changes },
);

has conflicts => (
  is => 'ro',
  isa => 'HashRef',
  lazy => 1,
  default => sub { shift->build_conflicts },
);

use Module::CoreList;
use Sort::Versions;
use Carp;

sub build_changes {
  my ($self) = @_;

  my %changes;

  my @queue = $self->dists;

  my %seen;
  while (@queue) {
    my $dist = shift @queue;
    next if $seen{$dist->id}++;
    my ($pin) = $self->pinset->find_pins({ name => $dist->name });

    if ($pin) {
      next if $pin->version eq $dist->version;

      $changes{$dist->name} = {
        from => $pin,
        to   => $dist,
      };
    } else {
      $changes{$dist->name} = {
        to => $dist,
      };
    }

    for my $dep ($dist->dependencies) {

      next if Module::CoreList->first_release($dep->name);
      next if $dep->name eq 'perl';

      unless (($pin && $dep->matches($self->pinset))
        || grep { $dep->matches($_->{to}) } values %changes) {

        my ($module) = sort versioncmp $dep->matching_modules;

        unless ($module) {
          die "no module found to fulfill dependency " . $dep->as_string;
        }

        push @queue, $module->dist;
      }
    }
  }

  return \%changes;
}

sub build_conflicts {
  my ($self) = @_;
  my $changes = $self->changes;
  my $conflicts = {
    map {
      $_ => $changes->{$_}
    }
    grep {
      $changes->{$_}{from} &&
      $changes->{$_}{from}->reason
    } keys %$changes
  };
  return unless %$conflicts;
  return $conflicts;
}

sub table {
  my ($self, $data) = @_;
  require Text::Table;
  my $table = Text::Table->new("dist", "from", "to");

  for (keys %$data) {
    my $c = $data->{$_};
    $table->add(
      $_,
      $c->{from} && $c->{from}->version,
      $c->{to}->version,
    );
  }

  return $table->table;
}

sub apply {
  my ($self) = @_;
  my $changes = $self->changes;

  if ($self->conflicts) {
    Carp::confess "asked to apply changes, but conflicts are present";
  }

  $self->pinset->db->do_transaction(sub {
    for (keys %$changes) {
      my $dist = $changes->{$_}{to};
      if (my $pin = $changes->{$_}{from}) {
        $pin->version($dist->version);
        $pin->save;
      } else {
        $self->pinset->add_pins(
          {
            name => $dist->name,
            version => $dist->version,
          }
        );
      }
    }
    $self->pinset->save;
  });
}

1;