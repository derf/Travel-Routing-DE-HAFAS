package Travel::Routing::DE::HAFAS::Connection::Section;

# vim:foldmethod=marker

use strict;
use warnings;
use 5.014;

use parent 'Class::Accessor';
use DateTime::Duration;
use Travel::Routing::DE::HAFAS::Utils;

our $VERSION = '0.00';

Travel::Routing::DE::HAFAS::Connection::Section->mk_ro_accessors(
	qw(type schep_dep rt_dep sched_arr rt_arr dep_datetime arr_datetime arr_delay dep_delay journey distance duration transfer_duration dep_loc arr_loc
	  dep_platform arr_platform
	  operator id name category category_long class number line line_no load delay direction)
);

# {{{ Constructor

sub new {
	my ( $obj, %opt ) = @_;

	my $hafas = $opt{hafas};
	my $sec   = $opt{sec};
	my $date  = $opt{date};
	my $locs  = $opt{locL};
	my @prodL = @{ $opt{common}{prodL} // [] };

	# himL may only be present in departure monitor mode
	my @remL = @{ $opt{common}{remL} // [] };
	my @himL = @{ $opt{common}{himL} // [] };

	my @msgL = (
		@{ $sec->{dep}{msgL} // [] },
		@{ $sec->{arr}{msgL} // [] },
		@{ $sec->{jny}{msgL} // [] }
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

	my $sched_dep = $sec->{dep}{dTimeS};
	my $rt_dep    = $sec->{dep}{dTimeR};
	my $sched_arr = $sec->{arr}{aTimeS};
	my $rt_arr    = $sec->{arr}{aTimeR};

	for my $ts ( $sched_dep, $rt_dep, $sched_arr, $rt_arr ) {
		if ($ts) {
			$ts = handle_day_change(
				date     => $date,
				time     => $ts,
				strp_obj => $strptime,
			);
		}
	}

	my $ref = {
		type         => $sec->{type},
		sched_dep    => $sched_dep,
		rt_dep       => $rt_dep,
		sched_arr    => $sched_arr,
		rt_arr       => $rt_arr,
		dep_datetime => $rt_dep // $sched_dep,
		arr_datetime => $rt_arr // $sched_arr,
		dep_loc      => $locs->[ $sec->{dep}{locX} ],
		arr_loc      => $locs->[ $sec->{arr}{locX} ],
		dep_platform => $sec->{dep}{dplatfR} // $sec->{dep}{dPlatfS},
		arr_platform => $sec->{arr}{aplatfR} // $sec->{arr}{aPlatfS},
		messages     => \@messages,
	};

	if ( $sched_dep and $rt_dep ) {
		$ref->{dep_delay} = ( $rt_dep->epoch - $sched_dep->epoch ) / 60;
	}

	if ( $sched_arr and $rt_arr ) {
		$ref->{arr_delay} = ( $rt_arr->epoch - $sched_arr->epoch ) / 60;
	}

	if ( $sec->{type} eq 'JNY' ) {

		#operator id name type type_long class number line line_no load delay direction)
		my $journey = $sec->{jny};
		my $product = $prodL[ $journey->{prodX} ];
		$ref->{id}            = $journey->{jid};
		$ref->{direction}     = $journey->{dirTxt};
		$ref->{name}          = $product->{addName} // $product->{name};
		$ref->{category}      = $product->{prodCtx}{catOut};
		$ref->{category_long} = $product->{prodCtx}{catOutL};
		$ref->{class}         = $product->{cls};
		$ref->{number}        = $product->{prodCtx}{num};
		$ref->{line}          = $ref->{name};
		$ref->{line_no}       = $product->{prodCtx}{line};

		if (    $ref->{name}
			and $ref->{category}
			and $ref->{name} eq $ref->{category}
			and $product->{nameS} )
		{
			$ref->{name} .= ' ' . $product->{nameS};
		}
	}
	elsif ( $sec->{type} eq 'WALK' ) {
		$ref->{distance} = $sec->{gis}{dist};
		my $duration = $sec->{gis}{durS};
		$ref->{duration} = DateTime::Duration->new(
			hours   => substr( $duration, 0, 2 ),
			minutes => substr( $duration, 2, 2 ),
			seconds => substr( $duration, 4, 2 ),
		);
	}

	bless( $ref, $obj );

	return $ref;
}

# }}}

# {{{ Private

sub set_transfer_from_previous_section {
	my ( $self, $prev_sec ) = @_;

	my $delta = $self->dep_datetime - $prev_sec->arr_datetime;
	$self->{transfer_duration} = $delta;
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

# }}}

1;
