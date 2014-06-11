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

sub handle_mail_notification {
    my ($self, $email) = shift;
    my $bz_url = $email->header('X-Bugzilla-URL') || '';
    if ($self->base_url ne $bz_url) {
        ThrowCodeError('remotesync_email_error', {
            err => "X-Bugzilla-URL '$bz_url' does not match source base url "
                   . $self->base_url
        });
    }
    my ($id) = $email->header('Subject') =~ /\[.+ (\d+)\]/;
    if ($id) {
        #TODO process the mail here and trigger sync
        print("Bug#$id at ${bz_url}show_bug.cgi?id=$id "
            . $email->header('X-Bugzilla-Type'));
    } else {
        ThrowCodeError('remotesync_email_error', {
            err => "Failed to parse bug ID from subject '"
                   . $email->header('Subject') . "'"
        });
    }
}

1;
