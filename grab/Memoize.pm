# Just some routines related to the Memoize module that are used in
# more than one place in XMLTV.  But not general enough to merge back
# into Memoize.
#

package XMLTV::Memoize;
use File::Basename;

# Use Log::TraceMessages if installed.
BEGIN {
    eval { require Log::TraceMessages };
    if ($@) {
	*t = sub {};
	*d = sub { '' };
    }
    else {
	*t = \&Log::TraceMessages::t;
	*d = \&Log::TraceMessages::d;
    }
}

# Add an undocumented option to cache things in a DB_File database.
# You need to decide which subroutines should be cached: LWP::Simple's
# get() is the most obvious candidate.  Call like this:
#
# if (check_argv('get', 'whatever')) {
#     # The subs get() and whatever() are now memoized.
# }
#
# If the user passed a --cache option to your program, this will be
# removed from @ARGV and caching will be turned on.  The optional
# argument to --cache gives the filename to use.
#
# Currently it is assumed that the function gives the same result in
# both scalar and list context.
#
# Note that the Memoize module is not loaded unless --cache options
# are found.
#
# Returns a ref to a list of code references for the memoized
# versions, if memoization happened (but does install the memoized
# versions under the original names too).  Returns undef if no
# memoization was wanted.
#
sub check_argv( @ ) {
    local $Log::TraceMessages::On = 1;
    my $yes = 0;
    my $filename;
    my @new_argv;
    while (@ARGV) {
	local $_ = shift @ARGV;
	if ($_ eq '--cache') {
	    t 'found arg --cache';
	    $yes = 1;
	    if (defined $ARGV[0]) {
		t 'next arg: ' . d $ARGV[0];
		if ($ARGV[0] !~ /^-/) {
		    $filename = shift @ARGV;
		    t "set cache filename to $filename";
		}
		else {
		    t "not a filename, it's the next option";
		}
	    }
	    else {
		t 'no further options, so no filename given';
	    }
	    last;
	}
	elsif (/^--cache=(.+)/) {
	    ($yes, $filename) = (1, $1);
	    last;
	}
	else {
	    push @new_argv, $_;
	    last if $_ eq '--';
	}
    }
    @ARGV = (@new_argv, @ARGV);
    t 'do we want to cache? ' . d $yes;
    return undef if not $yes;

    if (not defined $filename) {
	my $basename = File::Basename::basename($0);
	$filename = "$basename.cache";
    }
    print STDERR "using cache $filename\n";
    require POSIX;
    require Memoize;

    require DB_File;
    my @tie_args = ('DB_File', $filename,
		    POSIX::O_RDWR() | POSIX::O_CREAT(), 0666);

    # $from_caller is a sub which converts a function name into one
    # seen from the caller's namespace.  Namespaces do not nest, so if
    # it already has :: it should be left alone.
    #
    my $caller = caller();
    t "caller: $caller";
    my $from_caller = sub( $ ) {
	for (shift) {
	    return $_ if /::/;
	    return "${caller}::$_";
	}
    };

    my @r;
    if ($Memoize::VERSION > 0.62) {
	# Use HASH instead of deprecated TIE.
	my %cache;

	# Annoyingly tie(%cache, @tie_args) doesn't work
	tie %cache, 'DB_File', $filename,
	  POSIX::O_RDWR() | POSIX::O_CREAT(), 0666;
	foreach (@_) {
	    my $r = Memoize::memoize($from_caller->($_),
				     SCALAR_CACHE => [ HASH => \%cache ],
				     LIST_CACHE => 'MERGE');
	    die "could not memoize $_" if not $r;
	    push @r, $r;
	}
    }
    else {
	# Old version of Memoize.
	foreach (@_) {
	    my $r = Memoize::memoize($from_caller->($_),
				     SCALAR_CACHE => [ 'TIE', @tie_args ],
				     LIST_CACHE => 'MERGE');
	    die "could not memoize $_" if not $r;
	    push @r, $r;
	}
    }
    return \@r;
}

1;
