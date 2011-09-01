#!/usr/bin/perl -w

# Author          : Johan Vromans
# Created On      : Tue Aug 30 12:44:57 2011
# Last Modified By: Johan Vromans
# Last Modified On: Thu Sep  1 20:42:24 2011
# Update Count    : 108
# Status          : Unknown, Use with caution!

################ Common stuff ################

use strict;
use warnings;

# Package name.
my $my_package = 'SugarSync';
# Program name and version.
my ($my_name, $my_version) = qw( mirror_share 0.03 );

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
my $select;
my $resume;
my $verbose = 1;		# verbose processing
my $config = $ENV{HOME} . "/.config/sugarsync/config";
my $timestamps = 1;		# logging with timestamps
my $delete;			# delete local files not on share

# Development options (not shown with -help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test = 0;			# test mode.

# Process command line options.
app_options();

# Post-processing.
$trace |= ($debug || $test);

my @select = wc_compile($select) if $select;
my @resume = wc_compile($resume) if $resume;

if ( $timestamps ) {
    $SIG{__WARN__} = \&ts_warn;
    $SIG{__DIE__}  = \&ts_die;
}

################ Presets ################

use Data::Dumper;
my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';

################ The Process ################

use SugarSync::API;
use Config::Tiny;

warn("$my_name $my_version started\n") if $verbose;

my ( $f_total, $f_count, $f_ok, $f_ts, $f_dl ); # statistics
my ( $c_total, $c_count ); # statistics
my ( $d_count ); # statistics

# Load config data.
my $cfg = Config::Tiny->read($config);

my $so = SugarSync::API->new( $cfg->{auth}->{username},
			      $cfg->{auth}->{password} );

my $shares = $so->get_receivedShares;
foreach my $share ( @$shares ) {
    process_share($share);
}

if ( $verbose ) {
    warn("$my_name $my_version finished\n");
    my $st = sub {
	return unless $_[1];
	warn( sprintf( "%-30s %6d\n", $_[0], $_[1] ) );
    };
    $st->( "Total number of folders:"	  , $c_total );
    $st->( "Number of folders processed:" , $c_count );
    $st->( "Total number of files:"	  , $f_total );
    $st->( "Number of files processed:"	  , $f_count );
    $st->( "Number of files OK:"	  , $f_ok    );
    $st->( "Number of files utimed:"	  , $f_ts    );
    $st->( "Number of files downloaded:"  , $f_dl    );
    $st->( "Number of files ".($delete ? "deleteed" : "to delete").":",
	   $d_count );
}

################ Subroutines ################

use File::Basename;
use File::Path qw(make_path remove_tree);

sub process_share {
    my ( $share ) = @_;

    my $r = $so->get_receivedShare( $share->{sharedFolder} );
    warn Data::Dumper->Dump([$r],[qw(share)]) if $debug;

    warn( $r->{displayName}, "\n" ) if $verbose > 2;

    # Handle select/resume.
    return unless selectresume( $r->{displayName}, 0 );

#    my $f = $so->get_files( $r->{files} );
#    warn Data::Dumper->Dump([$f],[qw(files)]);

    my $c = $so->get_collections( $r->{collections} );
    warn Data::Dumper->Dump([$c],[qw(collections)]) if $debug;

    my $files = get_filelist( $r->{displayName} );

    foreach my $coll ( @$c ) {
	delete( $files->{$coll->{displayName}} );
	$c_total++;
	# Handle select/resume.
	next unless selectresume( $coll->{displayName}, 1 );
	$c_count++;

	process_collection( [ $r->{displayName} ], $coll );
    }

    delete_files( $files, $r->{displayName} );
}

sub process_collection {
    my ( $path, $r ) = @_;
    $path = [ @$path, $r->{displayName} ];
    warn( join( "/", @$path ), "\n" ) if $verbose > 2;
    my $depth = @$path;

    my $did;
    if ( $r->{type} eq 'folder' ) {
	# Folder. Get its contents.
	my $c = $so->get_url_xml( $r->{contents} );
	my $files = get_filelist( join( "/", @$path ) );

	# Folders can contain folders, and files. Process folders first.
	if ( $c->{collection} ) {
	    my $c = $c->{collection};
	    $c = [ $c ] unless UNIVERSAL::isa( $c, 'ARRAY' );
	    foreach my $coll ( @$c ) {
		delete( $files->{$coll->{displayName}} );
		$c_total++;
		# Handle select/resume.
		next unless selectresume( $coll->{displayName}, $depth );
		$c_count++;

		# Recurse.
		process_collection( $path, $coll );
	    }
	}

	if ( $c->{file} ) {
	    my $c = $c->{file};
	    $c = [ $c ] unless UNIVERSAL::isa( $c, 'ARRAY' );
	    foreach my $file ( @$c ) {
		delete( $files->{$file->{displayName}} );
		$f_total++;
		# Handle select/resume.
		next unless selectresume( $file->{displayName}, $depth );
		$f_count++;

		my $fn = join( "/", @$path, $file->{displayName} );
		warn( $fn, "\n" ) if $verbose > 1;
		my $mtime = $so->ts_deparse($file->{lastModified});

		# Depending on the file properties, update the local copy.

		if ( -e $fn ) {
		    my @st = stat(_);
		    if ( $st[7] == $file->{size} && $st[9] == $mtime ) {
			# Local file exists with the same size/mtime.
			warn( "    OK ", $mtime, " ", $file->{size}, "\n" )
			  if $verbose > 1;
			$f_ok++;
			next;
		    }
		    elsif ( 0 and $st[7] == $file->{size} ) {
			# Temporary facility to update timestamps of files
			# that have been added otherwise.
			utime( $mtime, $mtime, $fn ) or warn("utime($fn): $!\n");
			warn( "    Updated timestamp $st[9] -> ", $mtime, " ",
			      $file->{size}, "\n" ) if $verbose > 1;
			$f_ts++;
			next;
		    }
		    else {
			warn( "    Needs updating ", $mtime, " ",
			      $file->{size}, "\n" ) if $verbose > 1;
		    }
		}

		warn( $fn, "\n" ) if $verbose && $verbose <= 1;

		# Download the file.
		save_file( $fn, $file->{fileData}, $mtime );
		$f_dl++;
	    }
	}

	delete_files( $files, join( "/", @$path ) );
    }

    else {
	# Signal unhandled cases.
	warn Data::Dumper->Dump( [$r], [qw(unhandled)] ) unless $did;
    }

    #exit if @$path == 3;		# testing
}

sub save_file {
    my ( $fn, $url, $mtime ) = @_;

    my $dir = basename($fn);
    make_path( $dir, { verbose => $verbose>1 } ) unless -d $dir;

    # Download the file.
    print STDERR ( ts(), "    Downloading... ") if $verbose;
    my $data = $so->get_url_data($url);

    # Save to disk.
    open( my $fd, '>', $fn ) or croak("$fn: $!\n");
    print { $fd } $data;
    close($fd) or croak("$fn: $!\n");
    utime( $mtime, $mtime, $fn ) or warn("utime($fn): $!\n");
    print STDERR ("done ", $mtime, " ", length($data), "\n") if $verbose;
}

sub get_filelist {
    my ( $dir ) = @_;
    my %files;
    if ( opendir( D, $dir ) ) {
	while ( readdir(D) ) {
	    next if /^\.\.?$/;
	    $files{$_} = 1;
	}
	closedir(D);
    }
    \%files;
}

sub delete_files {
    my ( $files, $path ) = @_;
    foreach ( sort keys(%$files) ) {
	my $fn = join( "/", $path, $_ );
	warn("$fn\n");
	if ( $delete ) {
	    remove_tree( $fn, { verbose => $verbose>1 } )
	      ? warn("    Deleted\n")
	      : warn("    Cannot delete ($!)\n");
	}
	else {
	    warn("    Needs deleting\n");
	}
	$d_count++;
    }
}

sub ts {
    return '' unless $timestamps;
    my @tm = localtime;
    sprintf("%04d-%02d-%02d %02d:%02d:%02d ",
	    1900+$tm[5], 1+$tm[4], @tm[3,2,1,0] );
}

sub ts_warn {
    my $ts = ts();
    foreach ( split( /\n/, join('',@_) ) ) {
	CORE::warn( $ts, $_, "\n" );
    }
}

sub ts_die {
    my $ts = ts();
    foreach ( split( /\n/, join('',@_) ) ) {
	CORE::die( $ts, $_, "\n" );
    }
}

sub wc_compile {
    my ( $fnpat ) = @_;
    my @ret;
    foreach ( split( '/', $fnpat ) ) {
	my $p = quotemeta($_);
	$p =~ s/\\\*/.*/g;
	$p =~ s/\\\?/./g;
	push( @ret, qr/^(?:$p)$/i );
    }
    return @ret;
}

sub wc_match {
    my ( $fn, $pat ) = @_;
    return 1 if !defined($pat) || $pat eq '';
    $fn =~ $pat;
}

sub selectresume {
    my ( $fn, $depth ) = @_;
    return unless wc_match( $fn, $resume[$depth] );
    return unless wc_match( $fn, $select[$depth] );
    $resume[$depth] = '';
    return 1;
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
		   'select=s'	=> \$select,
		   'resume=s'	=> \$resume,
		   'config=s'	=> \$config,
		   'delete'	=> \$delete,
		   'verbose+'	=> \$verbose,
		   'quiet'	=> sub { $verbose = 0 },
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

mirror_sync -- sync a share to local disk

=head1 SYNOPSIS

mirror_sync [options]

 Options:
   --select XXX		select this path only
   --resume XXX		resume a sync run at this point
   --config XXX		alternate config file.
   --delete		delete local files not on the share
   --ident		show identification
   --help		brief help message
   --man                full documentation
   --verbose		verbose information
   --quiet		suppress informational messages

=head1 OPTIONS

=over 8

=item B<--select> I<path>

When processing a hierarchy of folders, only process the named folder.

The folder name should be a relative file name, starting at the top
level of the share. Shell wildcards C<*> and C<?> are allowed. Path
matching is case idenpendent.

=item B<--resume> I<path>

When processing a hierarchy of folders, start at the named folder.

The folder name should be a relative file name, starting at the top
level of the share. Shell wildcards C<*> and C<?> are allowed. Path
matching is case idenpendent.

=item B<--config> I<file>

Alternate config file.

Default config file is $HOME/.config/sugarsync/config .

This should contain the username and password for Sugarsync.

=item B<--delete>

Delete local files and folders that are not on the share.

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=item B<--ident>

Prints program identification.

=item B<--verbose>

More verbose information. Repeat for even more information.

=item B<--quiet>

Suppress informational messages.

=back

=head1 DESCRIPTION

B<mirror_share> will connect to the SugarSync cloud service and copy
all files of the received shared folders to local disk.

If a local file already exists, the size and modification date is
checked. If they match, the file is assumed to be up to date. On
mismatch, the file is overwritten with a new downloaded copy.

=head1 CONFIG FILE

A config file is required to store the username and password for
SugarSync access.

By default, the config file is C<.config/sugarsync/config> in the
users home directory. An alternative config file can be selected with
the B<--config> command line option.

The config file should contain:

  [auth]
  username = your_sugarsync_user_name
  password = your_sugarsync_password

=SEE ALSO

L<SugarSync::API>.

=head1 AUTHOR

Johan Vromans, C<< <jv at cpan.org> >>

=head1 BUGS & SUPPORT

See L<SugarSync::API>.

=head1 COPYRIGHT & LICENSE

Copyright 2011 Johan Vromans, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
