package Travel::Routing::DE::HAFAS;

# vim:foldmethod=marker

use strict;
use warnings;
use 5.014;
use utf8;

use Carp qw(confess);
use DateTime;
use DateTime::Format::Strptime;
use Digest::MD5 qw(md5_hex);
use Encode      qw(decode encode);
use JSON;
use LWP::UserAgent;
use Travel::Routing::DE::HAFAS::Connection;
use Travel::Routing::DE::HAFAS::Location;
use Travel::Status::DE::HAFAS::Message;

our $VERSION = '0.00';

# {{{ Endpoint Definition

my %hafas_instance = (
	DB => {
		mgate       => 'https://reiseauskunft.bahn.de/bin/mgate.exe',
		name        => 'Deutsche Bahn',
		productbits => [qw[ice ic_ec d regio s bus ferry u tram ondemand]],
		salt        => 'bdI8UVj4' . '0K5fvxwf',
		languages   => [qw[de en fr es]],
		request     => {
			client => {
				id   => 'DB',
				v    => '20100000',
				type => 'IPH',
				name => 'DB Navigator',
			},
			ext  => 'DB.R21.12.a',
			ver  => '1.15',
			auth => {
				type => 'AID',
				aid  => 'n91dB8Z77' . 'MLdoR0K'
			},
		},
	},
	NAHSH => {
		mgate       => 'https://nah.sh.hafas.de/bin/mgate.exe',
		name        => 'Nahverkehrsverbund Schleswig-Holstein',
		productbits => [qw[ice ice ice regio s bus ferry u tram ondemand]],
		request     => {
			client => {
				id   => 'NAHSH',
				v    => '3000700',
				type => 'IPH',
				name => 'NAHSHPROD',
			},
			ver  => '1.16',
			auth => {
				type => 'AID',
				aid  => 'r0Ot9FLF' . 'NAFxijLW'
			},
		},
	},
	NASA => {
		mgate       => 'https://reiseauskunft.insa.de/bin/mgate.exe',
		name        => 'Nahverkehrsservice Sachsen-Anhalt',
		productbits => [qw[ice ice regio regio regio tram bus ondemand]],
		languages   => [qw[de en]],
		request     => {
			client => {
				id   => 'NASA',
				v    => '4000200',
				type => 'IPH',
				name => 'nasaPROD',
				os   => 'iPhone OS 13.1.2',
			},
			ver  => '1.18',
			auth => {
				type => 'AID',
				aid  => 'nasa-' . 'apps',
			},
			lang => 'deu',
		},
	},
	NVV => {
		mgate       => 'https://auskunft.nvv.de/auskunft/bin/app/mgate.exe',
		name        => 'Nordhessischer VerkehrsVerbund',
		productbits =>
		  [qw[ice ic_ec regio s u tram bus bus ferry ondemand regio regio]],
		request => {
			client => {
				id   => 'NVV',
				v    => '5000300',
				type => 'IPH',
				name => 'NVVMobilPROD_APPSTORE',
				os   => 'iOS 13.1.2',
			},
			ext  => 'NVV.6.0',
			ver  => '1.18',
			auth => {
				type => 'AID',
				aid  => 'Kt8eNOH7' . 'qjVeSxNA',
			},
			lang => 'deu',
		},
	},
	'ÖBB' => {
		mgate       => 'https://fahrplan.oebb.at/bin/mgate.exe',
		name        => 'Österreichische Bundesbahnen',
		productbits =>
		  [qw[ice ice ice regio regio s bus ferry u tram ice ondemand ice]],
		request => {
			client => {
				id   => 'OEBB',
				v    => '6030600',
				type => 'IPH',
				name => 'oebbPROD-ADHOC',
			},
			ver  => '1.41',
			auth => {
				type => 'AID',
				aid  => 'OWDL4fE4' . 'ixNiPBBm',
			},
			lang => 'deu',
		},
	},
	VBB => {
		mgate       => 'https://fahrinfo.vbb.de/bin/mgate.exe',
		name        => 'Verkehrsverbund Berlin-Brandenburg',
		productbits => [qw[s u tram bus ferry ice regio]],
		languages   => [qw[de en]],
		request     => {
			client => {
				id   => 'VBB',
				type => 'WEB',
				name => 'VBB WebApp',
				l    => 'vs_webapp_vbb',
			},
			ext  => 'VBB.1',
			ver  => '1.33',
			auth => {
				type => 'AID',
				aid  => 'hafas-vb' . 'b-webapp',
			},
			lang => 'deu',
		},
	},
	VBN => {
		mgate       => 'https://fahrplaner.vbn.de/bin/mgate.exe',
		name        => 'Verkehrsverbund Bremen/Niedersachsen',
		productbits => [qw[ice ice regio regio s bus ferry u tram ondemand]],
		salt        => 'SP31mBu' . 'fSyCLmNxp',
		micmac      => 1,
		languages   => [qw[de en]],
		request     => {
			client => {
				id   => 'VBN',
				v    => '6000000',
				type => 'IPH',
				name => 'vbn',
			},
			ver  => '1.42',
			auth => {
				type => 'AID',
				aid  => 'kaoxIXLn' . '03zCr2KR',
			},
			lang => 'deu',
		},
	},
);

# }}}
# {{{ Constructors

sub new {
	my ( $obj, %conf ) = @_;
	my $service = $conf{service};

	my $ua = $conf{user_agent};

	if ( not $ua ) {
		my %lwp_options = %{ $conf{lwp_options} // { timeout => 10 } };
		$ua = LWP::UserAgent->new(%lwp_options);
		$ua->env_proxy;
	}

	if ( not( $conf{from_stop} and $conf{to_stop} ) ) {
		confess('from_stop and to_stop must be specified');
	}

	if ( not defined $service ) {
		$service = $conf{service} = 'DB';
	}

	if ( defined $service and not exists $hafas_instance{$service} ) {
		confess("The service '$service' is not supported");
	}

	my $now  = DateTime->now( time_zone => 'Europe/Berlin' );
	my $self = {
		active_service => $service,
		cache          => $conf{cache},
		developer_mode => $conf{developer_mode},
		exclusive_mots => $conf{exclusive_mots},
		excluded_mots  => $conf{excluded_mots},
		messages       => [],
		results        => [],
		from_stop      => $conf{from_stop},
		to_stop        => $conf{to_stop},
		ua             => $ua,
		now            => $now,
	};

	bless( $self, $obj );

	my $req;

	if (0) {
	}
	else {
		my $date = ( $conf{datetime} // $now )->strftime('%Y%m%d');
		my $time = ( $conf{datetime} // $now )->strftime('%H%M%S');

		my ( $from_lid, $to_lid );
		if ( $self->{from_stop} =~ m{ ^ [0-9]+ $ }x ) {
			$from_lid = 'A=1@L=' . $self->{from_stop} . '@';
		}
		else {
			$from_lid = 'A=1@O=' . $self->{from_stop} . '@';
		}
		if ( $self->{to_stop} =~ m{ ^ [0-9]+ $ }x ) {
			$to_lid = 'A=1@L=' . $self->{to_stop} . '@';
		}
		else {
			$to_lid = 'A=1@O=' . $self->{to_stop} . '@';
		}

		$req = {
			svcReqL => [
				{
					meth => 'TripSearch',
					req  => {
						depLocL    => [ { lid => $from_lid } ],
						arrLocL    => [ { lid => $to_lid } ],
						numF       => 6,
						maxChg     => undef,
						minChgTime => undef,
						outFrwd    => undef,
						viaLocL    => undef,
						trfReq     => {
							cType    => 'PK',
							tvlrProf => [ { type => 'E' } ],
						},
						outDate  => $date,
						outTime  => $time,
						jnyFltrL => [
							{
								type  => "PROD",
								mode  => "INC",
								value => $self->mot_mask
							}
						]
					},
				},
			],
			%{ $hafas_instance{$service}{request} }
		};
	}

	if ( $conf{language} ) {
		$req->{lang} = $conf{language};
	}

	$self->{strptime_obj} //= DateTime::Format::Strptime->new(
		pattern   => '%Y%m%dT%H%M%S',
		time_zone => 'Europe/Berlin',
	);

	my $json = $self->{json} = JSON->new->utf8;

	# The JSON request is the cache key, so if we have a cache we must ensure
	# that JSON serialization is deterministic.
	if ( $self->{cache} ) {
		$json->canonical;
	}

	$req = $json->encode($req);
	$self->{post} = $req;

	my $url = $conf{url} // $hafas_instance{$service}{mgate};

	if ( my $salt = $hafas_instance{$service}{salt} ) {
		if ( $hafas_instance{$service}{micmac} ) {
			my $mic = md5_hex( $self->{post} );
			my $mac = md5_hex( $mic . $salt );
			$url .= "?mic=$mic&mac=$mac";
		}
		else {
			$url .= '?checksum=' . md5_hex( $self->{post} . $salt );
		}
	}

	if ( $conf{async} ) {
		$self->{url} = $url;
		return $self;
	}

	if ( $conf{json} ) {
		$self->{raw_json} = $conf{json};
	}
	else {
		if ( $self->{developer_mode} ) {
			say "requesting $req from $url";
		}

		my ( $content, $error ) = $self->post_with_cache($url);

		if ($error) {
			$self->{errstr} = $error;
			return $self;
		}

		if ( $self->{developer_mode} ) {
			say decode( 'utf-8', $content );
		}

		$self->{raw_json} = $json->decode($content);
	}

	$self->check_mgate;
	$self->parse_trips;

	return $self;
}

sub new_p {
	my ( $obj, %conf ) = @_;
	my $promise = $conf{promise}->new;

	if (
		not(   $conf{station}
			or $conf{journey}
			or $conf{geoSearch}
			or $conf{locationSearch} )
	  )
	{
		return $promise->reject('station or journey flag must be passed');
	}

	my $self = $obj->new( %conf, async => 1 );
	$self->{promise} = $conf{promise};

	$self->post_with_cache_p( $self->{url} )->then(
		sub {
			my ($content) = @_;
			$self->{raw_json} = $self->{json}->decode($content);
			$self->check_mgate;
			if ( $conf{journey} ) {
				$self->parse_journey;
			}
			elsif ( $conf{geoSearch} or $conf{locationSearch} ) {
				$self->parse_search;
			}
			else {
				$self->parse_board;
			}
			if ( $self->errstr ) {
				$promise->reject( $self->errstr, $self );
			}
			else {
				$promise->resolve($self);
			}
			return;
		}
	)->catch(
		sub {
			my ($err) = @_;
			$promise->reject($err);
			return;
		}
	)->wait;

	return $promise;
}

# }}}
# {{{ Internal Helpers

sub mot_mask {
	my ($self) = @_;

	my $service  = $self->{active_service};
	my $mot_mask = 2**@{ $hafas_instance{$service}{productbits} } - 1;

	my %mot_pos;
	for my $i ( 0 .. $#{ $hafas_instance{$service}{productbits} } ) {
		$mot_pos{ $hafas_instance{$service}{productbits}[$i] } = $i;
	}

	if ( my @mots = @{ $self->{exclusive_mots} // [] } ) {
		$mot_mask = 0;
		for my $mot (@mots) {
			$mot_mask |= 1 << $mot_pos{$mot};
		}
	}

	if ( my @mots = @{ $self->{excluded_mots} // [] } ) {
		for my $mot (@mots) {
			$mot_mask &= ~( 1 << $mot_pos{$mot} );
		}
	}

	return $mot_mask;
}

sub post_with_cache {
	my ( $self, $url ) = @_;
	my $cache = $self->{cache};

	if ( $self->{developer_mode} ) {
		say "POST $url";
	}

	if ($cache) {
		my $content = $cache->thaw( $self->{post} );
		if ($content) {
			if ( $self->{developer_mode} ) {
				say '  cache hit';
			}
			return ( ${$content}, undef );
		}
	}

	if ( $self->{developer_mode} ) {
		say '  cache miss';
	}

	my $reply = $self->{ua}->post(
		$url,
		'Content-Type' => 'application/json',
		Content        => $self->{post}
	);

	if ( $reply->is_error ) {
		return ( undef, $reply->status_line );
	}
	my $content = $reply->content;

	if ($cache) {
		say "freeeez";
		$cache->freeze( $self->{post}, \$content );
	}

	return ( $content, undef );
}

sub post_with_cache_p {
	my ( $self, $url ) = @_;
	my $cache = $self->{cache};

	if ( $self->{developer_mode} ) {
		say "POST $url";
	}

	my $promise = $self->{promise}->new;

	if ($cache) {
		my $content = $cache->thaw( $self->{post} );
		if ($content) {
			if ( $self->{developer_mode} ) {
				say '  cache hit';
			}
			return $promise->resolve( ${$content} );
		}
	}

	if ( $self->{developer_mode} ) {
		say '  cache miss';
	}

	$self->{ua}->post_p( $url, $self->{post} )->then(
		sub {
			my ($tx) = @_;
			if ( my $err = $tx->error ) {
				$promise->reject(
					"POST $url returned HTTP $err->{code} $err->{message}");
				return;
			}
			my $content = $tx->res->body;
			if ($cache) {
				$cache->freeze( $self->{post}, \$content );
			}
			$promise->resolve($content);
			return;
		}
	)->catch(
		sub {
			my ($err) = @_;
			$promise->reject($err);
			return;
		}
	)->wait;

	return $promise;
}

sub check_mgate {
	my ($self) = @_;

	if ( $self->{raw_json}{err} and $self->{raw_json}{err} ne 'OK' ) {
		$self->{errstr} = $self->{raw_json}{errTxt}
		  // 'error code is ' . $self->{raw_json}{err};
		$self->{errcode} = $self->{raw_json}{err};
	}
	elsif ( defined $self->{raw_json}{cInfo}{code}
		and $self->{raw_json}{cInfo}{code} ne 'OK'
		and $self->{raw_json}{cInfo}{code} ne 'VH' )
	{
		$self->{errstr}  = 'cInfo code is ' . $self->{raw_json}{cInfo}{code};
		$self->{errcode} = $self->{raw_json}{cInfo}{code};
	}
	elsif ( @{ $self->{raw_json}{svcResL} // [] } == 0 ) {
		$self->{errstr} = 'svcResL is empty';
	}
	elsif ( $self->{raw_json}{svcResL}[0]{err} ne 'OK' ) {
		$self->{errstr}
		  = 'svcResL[0].err is ' . $self->{raw_json}{svcResL}[0]{err};
		$self->{errcode} = $self->{raw_json}{svcResL}[0]{err};
	}

	return $self;
}

sub parse_trips {
	my ($self) = @_;

	my @locL = map { Travel::Routing::DE::HAFAS::Location->new( loc => $_ ) }
	  @{ $self->{raw_json}{svcResL}[0]{res}{common}{locL} // [] };

	my @conL = @{ $self->{raw_json}{svcResL}[0]{res}{outConL} // [] };
	for my $con (@conL) {
		push(
			@{ $self->{results} },
			Travel::Routing::DE::HAFAS::Connection->new(
				common     => $self->{raw_json}{svcResL}[0]{res}{common},
				locL       => \@locL,
				connection => $con,
				hafas      => $self,
			)
		);
	}
}

sub add_message {
	my ( $self, $json, $is_him ) = @_;

	my $text = $json->{txtN};
	my $code = $json->{code};

	if ($is_him) {
		$text = $json->{text};
		$code = $json->{hid};
	}

	# Some backends use remL for operator information. We don't want that.
	if ( $code eq 'OPERATOR' ) {
		return;
	}

	for my $message ( @{ $self->{messages} } ) {
		if ( $code eq $message->{code} and $text eq $message->{text} ) {
			$message->{ref_count}++;
			return $message;
		}
	}

	my $message = Travel::Status::DE::HAFAS::Message->new(
		json      => $json,
		ref_count => 1,
	);
	push( @{ $self->{messages} }, $message );
	return $message;
}

# }}}
# {{{ Public Functions

sub errcode {
	my ($self) = @_;

	return $self->{errcode};
}

sub errstr {
	my ($self) = @_;

	return $self->{errstr};
}

sub messages {
	my ($self) = @_;
	return @{ $self->{messages} };
}

sub connections {
	my ($self) = @_;
	return @{ $self->{results} };
}

# }}}
