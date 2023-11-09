package Travel::Routing::DE::HAFAS::Connection;

# vim:foldmethod=marker

use strict;
use warnings;
use 5.014;

use parent 'Class::Accessor';
use DateTime::Duration;
use Travel::Routing::DE::HAFAS::Utils;
use Travel::Routing::DE::HAFAS::Connection::Section;

our $VERSION = '0.00';

Travel::Routing::DE::HAFAS::Connection->mk_ro_accessors(
	qw(changes duration sched_dep rt_dep sched_arr rt_arr dep_datetime arr_datetime dep_platform arr_platform dep_loc arr_loc dep_cancelled arr_cancelled is_cancelled load)
);

# {{{ Constructor

sub new {
	my ( $obj, %opt ) = @_;

	my $hafas      = $opt{hafas};
	my $connection = $opt{connection};
	my $locs       = $opt{locL};

	# himL may only be present in departure monitor mode
	my @remL = @{ $opt{common}{remL} // [] };
	my @himL = @{ $opt{common}{himL} // [] };

	my @msgL = @{ $connection->{msgL} // [] };
	my @secL = @{ $connection->{secL} // [] };

	my $date     = $connection->{date};
	my $duration = $connection->{dur};

	$duration = DateTime::Duration->new(
		hours   => substr( $duration, 0, 2 ),
		minutes => substr( $duration, 2, 2 ),
		seconds => substr( $duration, 4, 2 ),
	);

	my @messages;
	for my $msg (@msgL) {
		if ( $msg->{type} eq 'REM' and defined $msg->{remX} ) {
			push( @messages, $hafas->add_message( $remL[ $msg->{remX} ] ) );
		}
		elsif ( $msg->{type} eq 'HIM' and defined $msg->{himX} ) {
			push( @messages, $hafas->add_message( $himL[ $msg->{himX} ], 1 ) );
		}
		else {
			say "Unknown message type $msg->{type}";
		}
	}

	my $strptime = DateTime::Format::Strptime->new(
		pattern   => '%Y%m%dT%H%M%S',
		time_zone => 'Europe/Berlin'
	);

	my $sched_dep = $connection->{dep}{dTimeS};
	my $rt_dep    = $connection->{dep}{dTimeR};
	my $sched_arr = $connection->{arr}{aTimeS};
	my $rt_arr    = $connection->{arr}{aTimeR};

	for my $ts ( $sched_dep, $rt_dep, $sched_arr, $rt_arr ) {
		if ($ts) {
			$ts = handle_day_change(
				date     => $date,
				time     => $ts,
				strp_obj => $strptime,
			);
		}
	}

	my @sections;
	for my $sec (@secL) {
		push(
			@sections,
			Travel::Routing::DE::HAFAS::Connection::Section->new(
				common => $opt{common},
				date   => $date,
				locL   => $locs,
				sec    => $sec,
				hafas  => $hafas,
			)
		);
	}

	my $tco = {};
	for my $tco_id ( @{ $connection->{dTrnCmpSX}{tcocX} // [] } ) {
		my $tco_kv = $opt{common}{tcocL}[$tco_id];
		$tco->{ $tco_kv->{c} } = $tco_kv->{r};
	}

	my $dep_cancelled = $connection->{dep}{dCncl} ? 1 : 0;
	my $arr_cancelled = $connection->{arr}{aCncl} ? 1 : 0;
	my $is_cancelled  = $dep_cancelled || $arr_cancelled;

	my $ref = {
		duration      => $duration,
		changes       => $connection->{chg},
		sched_dep     => $sched_dep,
		rt_dep        => $rt_dep,
		sched_arr     => $sched_arr,
		rt_arr        => $rt_arr,
		dep_cancelled => $dep_cancelled,
		arr_cancelled => $arr_cancelled,
		is_cancelled  => $is_cancelled,
		dep_datetime  => $rt_dep // $sched_dep,
		arr_datetime  => $rt_arr // $sched_arr,
		dep_platform  => $connection->{dep}{dPlatfR}
		  // $connection->{dep}{dPlatfS},
		arr_platform => $connection->{arr}{aPlatfR}
		  // $connection->{arr}{aPlatfS},
		dep_loc  => $locs->[ $connection->{dep}{locX} ],
		arr_loc  => $locs->[ $connection->{arr}{locX} ],
		load     => $tco,
		messages => \@messages,
		sections => \@sections,
	};

	bless( $ref, $obj );

	return $ref;
}

# }}}

# {{{ Accessors

sub messages {
	my ($self) = @_;

	if ( $self->{messages} ) {
		return @{ $self->{messages} };
	}
	return;
}

sub sections {
	my ($self) = @_;

	if ( $self->{sections} ) {
		return @{ $self->{sections} };
	}
	return;
}

# }}}

1;
