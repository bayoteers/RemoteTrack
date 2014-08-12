#!/usr/bin/perl -wT
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Copyright (C) 2014 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

use strict;
use warnings;

# MTAs may call this script from any directory, but it should always run from
# the Bugzilla root dir so that it finds the modules
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use Getopt::Long qw(:config bundling);
use Pod::Usage;

# Commandline params
our %opts;

BEGIN {
    GetOptions(\%opts, 'help|h', 'verbose|v+', 'nomail|n', 'bugzilla|b=s');
    $opts{verbose} ||= 0;
    pod2usage({-verbose => 1, -exitval => 0}) if $opts{help};

    if ($opts{bugzilla}) {
        my ($a) = abs_path($opts{bugzilla}) =~ /^(.*)$/;
        chdir $a;
    }
}

use lib qw(. lib);

use Email::MIME;
use IO::Select;

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Hook;
use Bugzilla::Mailer;
use Bugzilla::User;
use Bugzilla::Util;

our $email_in;

####################
# Main Subroutines #
####################

sub die_handler {
    my ($msg) = @_;
    # If this is inside an eval, then we should just act like...we're
    # in an eval (instead of printing the error and exiting).
    die(@_) if $^S;

    print_log($msg);
    mail_admin("email_in_sync.pl died\n\n$msg");
    # We exit with a successful value, because we don't want the MTA to send a
    # failure notice.
    exit;
}

sub print_log {
    my ($msg, $level) = @_;
    $level ||= 0;
    if ($level >= $opts{verbose}) {
        print STDERR $msg."\n";
    }
}

sub mail_admin {
    return if $opts{nomail};
    my $msg = shift;
    my @parts;
    push @parts, Email::MIME->create(
        attributes => {
            content_type => 'text/plain',
            charset => 'UTF-8',
            encoding => 'quoted-printable'
        },
        body_str => $msg);
    if (defined $email_in) {
        push @parts, Email::MIME->create(
            attributes => {
                disposition => 'attachment',
                filename => 'received_message.txt',
                content_type => 'text/plain',
                charset => 'UTF-8',
                encoding => 'quoted-printable',
            },
            body_str => $email_in->as_string);
    }
    my $email = Email::MIME->create(
        header_str => [
            From => Bugzilla->params->{'mailfrom'},
            To => Bugzilla->params->{'maintainer'},
            Subject => "email_in_sync failure",
        ],
        parts => \@parts
    );
    MessageToMTA($email->as_string);
}

###############
# Main Script #
###############

$SIG{__DIE__} = \&die_handler;

Bugzilla->usage_mode(USAGE_MODE_EMAIL);
Bugzilla->set_user(Bugzilla::User->check(Bugzilla->params->{remotetrack_user}));

# Check that RemoteTrack is enabled
unless (grep($_->isa('Bugzilla::Extension::RemoteTrack'), @{Bugzilla->extensions}))
{
    die "RemoteTrack extension is not enabled in Bugzilla";
}
require Bugzilla::Extension::RemoteTrack::Source;

# Check that there is something to read from stdin
my $stdin_select = IO::Select->new(\*STDIN);
if (!$stdin_select->can_read(0)) {
    print_log("Nothing to read from STDIN");
    exit;
}

my $mail_text = join("", <STDIN>);
$email_in = Email::MIME->new($mail_text);

my $handled = 0;
for my $source (Bugzilla::Extension::RemoteTrack::Source->get_all) {
    next unless $source->can('handle_mail_notification');
    if ($source->handle_mail_notification($email_in)) {
        $handled = 1;
        last;
    }
}
if (!$handled) {
    my $msg = "Failed to handle email";
    print_log($msg);
    mail_admin($msg);
}

exit;

__END__

=head1 NAME

email_in_sync.pl - Email notification interface for triggering the sync

=head1 SYNOPSIS

./email_in_sync.pl [OPTIONS] < email.txt

Reads and processes an email from STDIN (the standard input).

=head1 OPTIONS

    --verbose (-v)  - Make the script print more to STDERR.
                      Specify multiple times to print even more.
    --nomail (-n)   - Do not send error notifications to admin
    --bugzilla (-b) - Path to Bugzilla installation.
                      The script needs to be run from Bugzilla dir. If that is
                      not possible, pass the full path to the installation with
                      this option.
    --help (-h)       Display this help. Use -hh to get more info


=head1 DESCRIPTION

This script processes inbound email notifications from remote tracking sources
to allow triggering any sync operations required.

The script will use the incoming email's From header to get configured
RemoteTrack::Source object from DB and if that source type has
handle_email_notification method, it will pass the incoming mail there for
further processing.

=head2 Errors

If the inbound email cannot be processed for some reason, an email will be sent
to the address specified as maintainer in Bugzilla params. Unless --nomail
parameter was given.
