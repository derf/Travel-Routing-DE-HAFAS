package Travel::Routing::DE::HAFAS::Location;

use strict;
use warnings;
use 5.014;

use parent 'Class::Accessor';

our $VERSION = '0.00';

Travel::Routing::DE::HAFAS::Location->mk_ro_accessors(
	qw(lid type name eva state coordinate));

sub new {
	my ( $obj, %opt ) = @_;

	my $loc = $opt{loc};

	my $ref = {
		lid        => $loc->{lid},
		type       => $loc->{type},
		name       => $loc->{name},
		eva        => 0 + $loc->{extId},
		state      => $loc->{state},
		coordinate => $loc->{crd}
	};

	bless( $ref, $obj );

	return $ref;
}

1;
