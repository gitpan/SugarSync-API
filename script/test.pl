#!/usr/bin/perl -w

# Author          : Johan Vromans
# Created On      : Tue Aug 30 12:44:57 2011
# Last Modified By: Johan Vromans
# Last Modified On: Thu Sep  1 08:38:10 2011
# Update Count    : 31
# Status          : Unknown, Use with caution!

################ Common stuff ################

use strict;
use warnings;

# Package name.
my $my_package = 'SugarSync';
# Program name and version.
my ($my_name, $my_version) = qw( test 0.01 );

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
my $verbose = 0;		# verbose processing
my $show_location = 0;

# Development options (not shown with -help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test = 0;			# test mode.

# Process command line options.
app_options();

# Post-processing.
$trace |= ($debug || $test);

################ Presets ################

my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';

################ The Process ################

use SugarSync::API;

my $username = 'xxxxxxxxxxxx';
my $password = 'yyyyyyyyyyyy';

die("Nothing to test -- spcify URLs on the command line\n")
  unless @ARGV || $show_location;

my $so = SugarSync::API->new( $username, $password );
warn("Location: ", $so->{_auth}, "\n") if $show_location;

foreach ( @ARGV ) {
    $so->get_url_xml( $_, 1 );
}

################ Subroutines ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally
    my $man = 0;		# handled locally

    my $pod2usage = sub {
        # Load Pod::Usage only if needed.
        require Pod::Usage;
        Pod::Usage->import;
        &pod2usage;
    };

    # Process options.
    if ( @ARGV > 0 ) {
	GetOptions('ident'	=> \$ident,
		   'show-location' => \$show_location,
		   'verbose'	=> \$verbose,
		   'trace'	=> \$trace,
		   'help|?'	=> \$help,
		   'man'	=> \$man,
		   'debug'	=> \$debug)
	  or $pod2usage->(2);
    }
    if ( $ident or $help or $man ) {
	print STDERR ("This is $my_package [$my_name $my_version]\n");
    }
    if ( $man or $help ) {
	$pod2usage->(1) if $help;
	$pod2usage->(VERBOSE => 2) if $man;
    }
}

__END__

################ Documentation ################

=head1 NAME

sample - skeleton for GetOpt::Long and Pod::Usage

=head1 SYNOPSIS

sample [options] [file ...]

 Options:
   -ident		show identification
   -help		brief help message
   -man                 full documentation
   -verbose		verbose information

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-ident>

Prints program identification.

=item B<-verbose>

More verbose information.

=item I<file>

Input file(s).

=back

=head1 DESCRIPTION

B<This program> will read the given input file(s) and do someting
useful with the contents thereof.

=cut
