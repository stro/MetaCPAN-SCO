package MetaCPAN::SCO;
use strict;
use warnings;

use Carp ();
use Cwd qw(abs_path);
use Data::Dumper qw(Dumper);
use File::Basename qw(dirname);
use JSON qw(from_json);
use List::MoreUtils qw(natatime);
use LWP::Simple qw(get);
use Path::Tiny qw(path);
use Plack::Builder;
use Plack::Request;
use Template;

our $VERSION = '0.01';

=head1 NAME

SCO - search.cpan.org clone

=cut

sub run {
	my $root = root();

	my $app = sub {
		my $env = shift;

		my $request = Plack::Request->new($env);
		if ($request->path_info eq '/') {
			return template('index', {front => 1});
		}
		if ($request->path_info eq '/feedback') {
			return template('feedback');
		}
		if ($request->path_info =~ m{^/author/?$}) {
			my $query_string = $request->query_string;
			return template('author', { letters => ['A' .. 'Z'] }) if not $query_string;
			my $lead = substr $query_string, 0, 1;
			my $authors = authors_starting_by(uc $lead);
			if (@$authors) {
				my $it = natatime 4, @$authors;
				my @table;
				while (my @vals = $it->()) {
					push @table, \@vals;
				}
				return template('author', {letters => ['A' .. 'Z'], authors => \@table});
			}
		}

		my $reply = template('404');
		return [ '404', [ 'Content-Type' => 'text/html' ], $reply->[2], ];
	};

	builder {
		enable 'Plack::Middleware::Static',
			path => qr{^/(favicon.ico|robots.txt)},
			root => "$root/static/";
		$app;
	};
}

sub authors_starting_by {
	my ($char) = @_;
	# curl http://api.metacpan.org/v0/author/_search?size=10
	# curl 'http://api.metacpan.org/v0/author/_search?q=author._id:S*&size=10'
	# curl 'http://api.metacpan.org/v0/author/_search?size=10&fields=name'
	# curl 'http://api.metacpan.org/v0/author/_search?q=author._id:S*&size=10&fields=name'
	# or maybe use fetch to download and keep the full list locally:
	# http://api.metacpan.org/v0/author/_search?pretty=true&q=*&size=100000 (from https://github.com/CPAN-API/cpan-api/wiki/API-docs )

	my @authors = [];
	if ($char =~ /[A-Z]/) {
		eval {
			my $json = get "http://api.metacpan.org/v0/author/_search?q=author._id:$char*&size=5000&fields=name";
			my $data = from_json $json;
			@authors =
				sort { $a->{id} cmp $b->{id} }
				map { { id => $_->{_id}, name => $_->{fields}{name} } } @{ $data->{hits}{hits} };
			1;
		} or do {
			my $err = $@  // 'Unknown error';
			warn $err if $err;
		};
	}
	return \@authors;
}


sub template {
	my ( $file, $vars ) = @_;
	$vars //= {};
	Carp::confess 'Need to pass HASH-ref to template()'
		if ref $vars ne 'HASH';

	my $root = root();

	eval {
		$vars->{totals} = from_json path("$root/totals.json")->slurp_utf8;
	};

	my $tt = Template->new(
		INCLUDE_PATH => "$root/tt",
		INTERPOLATE  => 0,
		POST_CHOMP   => 1,
		EVAL_PERL    => 1,
		START_TAG    => '<%',
		END_TAG      => '%>',
		PRE_PROCESS  => 'incl/header.tt',
		POST_PROCESS => 'incl/footer.tt',
	);
	my $out;
	$tt->process( "$file.tt", $vars, \$out )
		|| die $tt->error();
	return [ '200', [ 'Content-Type' => 'text/html' ], [$out], ];
}

sub root {
	return dirname(dirname(dirname( abs_path(__FILE__) )));
}

1;

