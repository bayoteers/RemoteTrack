#!/usr/bin/perl -wT
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014-2017 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

=head1 NAME

track_all_bugs.pl - Script for cloning all bugs from remote bugzilla

=head1 SYNOPSIS

./extensions/RemoteTrack/track_all_bugs.pl [OPTIONS]

=head1 OPTIONS

    --source NAME     RemoteTrack source name to use. Required
    -s

    --product PRODUCT Filter bugs from remote bugzilla based on product.
    -p                Can be defiend multiple times to include bugs in all the
                      listed products.

    --help            Display this help.
    -h

=cut

use strict;
use warnings;

use Getopt::Long qw(:config bundling);
use Pod::Usage;

# Commandline params
our %opts;

GetOptions(\%opts, 'help|h', 'source|s=s', 'product|p=s@');
if ($opts{help} or !$opts{source}) {
    pod2usage({-verbose => 1, -exitval => 0});
}


use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::User;
use Bugzilla::Util;

use Term::ProgressBar;

###############
# Main Script #
###############

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

# Check that RemoteTrack is enabled
die "RemoteTrack extension is not enabled in Bugzilla"
    unless (grep($_->isa('Bugzilla::Extension::RemoteTrack'), @{Bugzilla->extensions}));

require Bugzilla::Extension::RemoteTrack::Source;
require Bugzilla::Extension::RemoteTrack::Url;

# Check that the user is set
die "RemoteTrack user not defined"
    unless (Bugzilla->params->{remotetrack_user});
Bugzilla->set_user(Bugzilla::User->check(Bugzilla->params->{remotetrack_user}));

my $source = Bugzilla::Extension::RemoteTrack::Source->check($opts{source});
die "$opts{source} is not a bugzilla remote source"
    unless $source->isa("Bugzilla::Extension::RemoteTrack::Source::Bugzilla");

my $params = {
    limit => 0,
    include_fields => ['id'],
};

if ($opts{product}) {
    $params->{product} = $opts{product};
}

my $result = $source->_rpc('Bug.search', $params);

my $total = scalar @{$result->{bugs}};
print "Total $total bugs to clone\n";

my $progress = Term::ProgressBar->new(
    {
        name  => 'Cloned',
        count => $total,
        ETA   => 'linear',
    }
);
my $count = 0;
my $next = 0;

for my $b (@{$result->{bugs}}) {
    $count ++;
    my $url = $source->options->{base_url} . "show_bug.cgi?id=" . $b->{id};
    #print "$url\n";
    if (@{Bugzilla::Extension::RemoteTrack::Url->match({value => $url})}) {
        print STDERR "$url already tracked, skipping\n";
        next;
    }
    my $bug = $source->create_tracking_bug($url);
    if (!defined $bug) {
        print STDERR "Cloning $url failed\n";
    }
    if ($count >= $next) {
        $next = $progress->update($count);
    }
}

exit;
