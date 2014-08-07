# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>


=head1 NAME

Bugzilla::Extension::RemoteSync::Source::Bugzilla

=head1 DESCRIPTION

Interface for Bugzilla Source

=cut

use strict;
use warnings;

package Bugzilla::Extension::RemoteSync::Source::Bugzilla;

use base qw(Bugzilla::Extension::RemoteSync::Source);

use Bugzilla::Error;

use constant see_also_class => "Bugzilla::BugUrl::Bugzilla";


sub check_options {
    my ($invocant, $options) = @_;
    for my $key (keys %$options) {
        if ($key eq 'base_url') {
            my $uri = URI->new($options->{base_url});
            ThrowUserError('invalid_parameter', {
                name => 'options->base_url',
                err => 'base_url has to be http(s)://...'}
            ) unless ($uri->scheme =~ /https?/);
            $options->{base_url} = $uri->scheme . ":" . $uri->opaque;
        } elsif ($key eq 'from_email') {
            my $value = $options->{from_email};
            unless ($value !~ /\P{ASCII}/
                && $value =~ /^${Email::Address::addr_spec}$/)
            {
                ThrowUserError('invalid_parameter', {
                    name => 'from email',
                    err => "'$value' is not a valid email address"
                });
            }
        } else {
            delete $options->{$key};
        }
    }
    if (!defined $options->{base_url}) {
        ThrowUserError('invalid_parameter', {
            name => 'options->base_url',
            err => 'base_url is required' });
    }
    return $options;
}

sub handle_mail_notification {
    my ($self, $email) = shift;
    my $bz_url = $email->header('X-Bugzilla-URL') || '';
    my $from = $email->header('From');
    return 0 if ($self->options->{base_url} ne $bz_url
                 || $self->options->{from_email} ne $from);

    my $msgid = $email->header('Message-ID');
    my ($id) = $msgid =~ /^<bug-(\d*)-/;
    if ($id) {
        #TODO process the mail here and trigger sync
        print("Bug#$id at ${bz_url}show_bug.cgi?id=$id "
            . $email->header('X-Bugzilla-Type'));
    } else {
        ThrowCodeError('remotesync_email_error', {
            err => "Failed to parse bug ID from message ID '$msgid'",
        });
    }
    return 1;
}

sub is_valid_url {
    my ($self, $url) = @_;
    return 0 unless $self->SUPER::is_valid_url($url);
    my $base = $self->options->{base_url};
    return ($url =~ /^$base/) ? 1 : 0;
}

1;
