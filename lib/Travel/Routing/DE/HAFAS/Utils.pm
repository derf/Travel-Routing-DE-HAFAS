package Travel::Routing::DE::HAFAS::Utils;

# vim:foldmethod=marker

use strict;
use warnings;
use 5.014;

use parent 'Exporter';
our @EXPORT = qw(handle_day_change);

sub handle_day_change {
	my (%opt)       = @_;
	my $datestr     = $opt{date};
	my $timestr     = $opt{time};
	my $offset_days = 0;

	# timestr may include a day offset, resulting in DDHHMMSS
	if ( length($timestr) == 8 ) {
		$offset_days = substr( $timestr, 0, 2, q{} );
	}

	my $ts = $opt{strp_obj}->parse_datetime("${datestr}T${timestr}");

	if ($offset_days) {
		$ts->add( days => $offset_days );
	}

	return $ts;
}

1;
