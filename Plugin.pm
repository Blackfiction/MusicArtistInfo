package Plugins::MusicArtistInfo::Plugin;

use strict;
use base qw(Slim::Plugin::Base);

use vars qw($VERSION);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);

use Plugins::MusicArtistInfo::AlbumInfo;
use Plugins::MusicArtistInfo::ArtistInfo;

use constant PLUGIN_TAG => 'musicartistinfo';

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.musicartistinfo',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_MUSICARTISTINFO',
} );

#my $prefs = preferences('plugin.musicartistinfo'); 

sub initPlugin {
	my $class = shift;
	
	$VERSION = $class->_pluginDataFor('version');
	
	Plugins::MusicArtistInfo::AlbumInfo->init($class);
	Plugins::MusicArtistInfo::ArtistInfo->init($class);

	# "Local Artwork" requires LMS 7.8+, as it's using its imageproxy.
	if (Slim::Utils::Versions->compareVersions($::VERSION, '7.8.0') >= 0) {
		require Plugins::MusicArtistInfo::LocalArtwork;
		Plugins::MusicArtistInfo::LocalArtwork->init();
		
		# use our skin, unless user has changed back already
		# XXX - skin files can be remove once we live with the Artists menu hijacking
#		preferences('server')->set('skin', 'MusicArtistInfo') unless $prefs->get('skinSet') || lc(preferences('server')->get('skin')) ne 'default';
#		$prefs->set('skinSet', 1);
		# revert skin pref from previous skinning exercise...
		my $prefs = preferences('server'); 
		$prefs->set('skin', 'Default') if lc($prefs->get('skin')) eq 'musicartistinfo';
	}
	else {
		# remove our HTML folder from the list of skins if we can't support it
		Slim::Web::HTTP->getSkinManager->{templateDirs} = [ 
			grep { $_ !~ m|Plugins/MusicArtistInfo| } @{Slim::Web::HTTP->getSkinManager->{templateDirs}}
		];
	}
	
	$class->SUPER::initPlugin(shift);
}

# don't add this plugin to the Extras menu
sub playerMenu {}

sub webPages {
	my $class = shift;
	
	my $url   = 'plugins/' . PLUGIN_TAG . '/index.html';
	
	Slim::Web::Pages->addPageLinks( 'plugins', { PLUGIN_MUSICARTISTINFO_ALBUMS_MISSING_ARTWORK => $url } );
	Slim::Web::Pages->addPageLinks( 'icons', { PLUGIN_MUSICARTISTINFO_ALBUMS_MISSING_ARTWORK => "html/images/cover.png" });

	Slim::Web::Pages->addPageFunction( $url, sub {
		my $client = $_[0];
		
		Slim::Web::XMLBrowser->handleWebIndex( {
			client  => $client,
			feed    => \&getMissingArtworkAlbums,
			type    => 'link',
			title   => cstring($client, 'PLUGIN_MUSICARTISTINFO_ALBUMS_MISSING_ARTWORK'),
			timeout => 35,
			args    => \@_
		} );
	} );
}

sub getMissingArtworkAlbums {
	my ($client, $cb, $params, $args) = @_;

	# Find distinct albums to check for artwork.
	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();
	my $rs = Slim::Schema->search('Genre', undef, { 'order_by' => "me.namesort $collate" });

	my $albums = Slim::Schema->search('Album', {
		'me.artwork' => { '='  => undef },
	},{
		'order_by' => "me.titlesort $collate",
	});
	
	my $items = [];
	while ( my $album = $albums->next ) {
		my $artist = $album->contributor->name;
		
		push @$items, {
			type => 'slideshow',
			name => $album->title . ' ' . cstring($client, 'BY') . " $artist",
			url  => \&Plugins::MusicArtistInfo::AlbumInfo::getAlbumCover,
			passthrough => [{ 
				album  => $album->title,
				artist => $artist,
			}]
		};
	}
	
	$cb->({
		items => $items,
	});
}

=pod
sub getSmallArtworkAlbums {
	my ($client, $cb, $params, $args) = @_;

	# Find distinct albums to check for artwork.
	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();
	my $rs = Slim::Schema->search('Genre', undef, { 'order_by' => "me.namesort $collate" });

	my $cache = Slim::Utils::ArtworkCache->new();
	my $sth = Slim::Schema->dbh->prepare("SELECT album, cover, coverid FROM tracks WHERE NOT coverid IS NULL GROUP BY album");
	$sth->execute();
	
	my $items = [];
	while ( my $track = $sth->fetchrow_hashref ) {
		my $size;
		$size = $track->{cover} if $track->{cover} =~ /^\d+$/;
		
		if ( !$size && -f $track->{cover} ) {
			$size = -s _;
		}
		
		# what's a reasonable threshold here? Doesn't make much sense with lossy jpg vs. lossless png etc.
		if ( $size && $size > 50000 ) {
			my $album = Slim::Schema->search('Album', {
				'me.id' => { '=' => $track->{album} }
			})->first;
			
			if ($album) {
				my $artist = $album->contributor->name;
				my $title  = $album->title;
				
				push @$items, {
					type => 'slideshow',
					image => '/music/' . $track->{coverid} . '/cover',
					name => $title . ' ' . cstring($client, 'BY') . " $artist",
					url  => \&Plugins::MusicArtistInfo::AlbumInfo::getAlbumCover,
					passthrough => [{ 
						album  => $title,
						artist => $artist,
					}]
				};
			}
		}
	}
	
	$items = [ sort { lc($a->{name}) cmp lc($b->{name}) } @$items ];
	
	$cb->({
		items => $items,
	});
}
=cut

1;