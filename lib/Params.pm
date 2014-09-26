# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

package Bugzilla::Extension::RemoteTrack::Params;
use warnings;
use strict;

sub get_param_list {
    return (
        {
            name => 'remotetrack_user',
            type => 't',
            default => '',
            checker => \&_check_user,
        }, {
            name => 'remotetrack_manual_sync',
            type => 'b',
            default => 0,
        }, {
            name => 'remotetrack_status_change_tmpl',
            type => 'l',
            default => 'Our tracking [% terms.bug %] changed status: [% from %] -> [% to %]',
        }
    );
}

sub _check_user {
    my $value = shift;
    if ($value) {
        eval {Bugzilla::User->check($value);};
        return $@ || "";
    }
    return "";
}

1;
